import AppKit
import PDFKit
import VisionKit
import UniformTypeIdentifiers

enum ViewerError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self { case .unreadable(let name): return "Couldn’t open \(name). Choose a readable PDF or image." }
    }
}

// Each open request owns a new window. Never consult the system tab preference.
final class FileWindow: NSWindow {
    var onZoomGesture: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        // Route pinch events before PDFKit's nested views can consume them.
        // Returning early also prevents applying the same zoom twice.
        if (event.type == .magnify || event.type == .smartMagnify), onZoomGesture?(event) == true { return }
        super.sendEvent(event)
    }
    override func mergeAllWindows(_ sender: Any?) {}
    override func toggleTabBar(_ sender: Any?) {}
}

final class DropSurface: NSView {
    var onOpen: (([URL]) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onOpen?(urls)
        return true
    }
}

final class ImageCanvas: NSImageView {
    let textOverlay = ImageAnalysisOverlayView(frame: .zero)
    var onAnalysisChanged: (() -> Void)?
    private(set) var textStatus = ""
    private(set) var isAnalyzing = false
    private var analysisTask: Task<Void, Never>?

    init(image: NSImage) {
        super.init(frame: .zero)
        self.image = image
        imageScaling = .scaleAxesIndependently
        isEditable = false
        allowsCutCopyPaste = false
        textOverlay.frame = bounds
        textOverlay.autoresizingMask = [.width, .height]
        textOverlay.trackingImageView = self
        textOverlay.preferredInteractionTypes = .textSelection
        addSubview(textOverlay)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { analysisTask?.cancel() }

    func analyzeText() {
        guard analysisTask == nil, let image else { return }
        guard ImageAnalyzer.isSupported else {
            textStatus = "Live Text unavailable on this Mac"
            onAnalysisChanged?()
            return
        }
        isAnalyzing = true
        textStatus = "Recognizing text…"
        onAnalysisChanged?()
        // Analyze the displayed image once. Resizing only updates the overlay geometry.
        analysisTask = Task { @MainActor [weak self, image] in
            do {
                let analysis = try await ImageAnalyzer().analyze(image, orientation: .up, configuration: .init(.text))
                guard !Task.isCancelled, let self else { return }
                self.textOverlay.analysis = analysis
                self.textStatus = analysis.hasResults(for: .text) ? "Select text to copy" : "No text found"
                self.isAnalyzing = false
                self.onAnalysisChanged?()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.textStatus = "Text recognition unavailable"
                self.isAnalyzing = false
                self.onAnalysisChanged?()
            }
        }
    }
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }
}

final class CenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        if let documentView {
            if documentView.frame.width < result.width { result.origin.x = (documentView.frame.width - result.width) / 2 }
            if documentView.frame.height < result.height { result.origin.y = (documentView.frame.height - result.height) / 2 }
        }
        return result
    }
}

final class ViewerController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let fileURL: URL
    var pdfView: PDFView?
    var imageScroll: NSScrollView?
    var imageCanvas: ImageCanvas?
    var thumbnailView: PDFThumbnailView?
    var splitView: NSSplitView?
    var originalImageSize = NSSize.zero
    var imageScale: CGFloat = 1
    var fitsImage = true
    let status = NSTextField(labelWithString: "")
    var onClose: (() -> Void)?
    private var observations: [NSObjectProtocol] = []
    private var smartZoomReturn: (scale: CGFloat, fits: Bool)?

    init(url: URL, analyzeImages: Bool = true) throws {
        fileURL = url
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            throw ViewerError.unreadable(url.lastPathComponent)
        }
        let isPDF = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) == true || url.pathExtension.lowercased() == "pdf"
        let pdf = isPDF ? PDFDocument(url: url) : nil
        let image = isPDF ? nil : NSImage(contentsOf: url)
        guard (pdf?.pageCount ?? 0) > 0 || pdf?.isLocked == true || (image?.isValid == true) else {
            throw ViewerError.unreadable(url.lastPathComponent)
        }
        let window = FileWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 740),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.tabbingMode = .disallowed
        window.tabbingIdentifier = UUID().uuidString
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.title = url.lastPathComponent
        window.representedURL = url
        window.minSize = NSSize(width: 480, height: 360)
        super.init(window: window)
        window.delegate = self
        window.onZoomGesture = { [weak self] event in
            guard let self else { return false }
            return event.type == .smartMagnify ? self.smartMagnify(with: event) : self.magnify(with: event)
        }

        let root = DropSurface(frame: window.contentView!.bounds)
        root.onOpen = { urls in (NSApp.delegate as? AppDelegate)?.openURLs(urls) }
        window.contentView = root
        let content: NSView
        if let pdf {
            let view = PDFView()
            view.document = pdf
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.autoScales = true
            view.backgroundColor = .underPageBackgroundColor
            view.minScaleFactor = 0.1
            view.maxScaleFactor = 8
            pdfView = view
            let thumbnails = PDFThumbnailView()
            thumbnails.pdfView = view
            thumbnails.thumbnailSize = NSSize(width: 88, height: 120)
            thumbnailView = thumbnails
            let split = NSSplitView()
            split.isVertical = true
            split.dividerStyle = .thin
            split.addArrangedSubview(thumbnails)
            split.addArrangedSubview(view)
            splitView = split
            content = split
            for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged, .PDFDocumentDidUnlock] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.updateStatus() })
            }
        } else if let image {
            let representation = image.representations.max { $0.pixelsWide < $1.pixelsWide }
            originalImageSize = NSSize(width: max(1, representation?.pixelsWide ?? Int(image.size.width)), height: max(1, representation?.pixelsHigh ?? Int(image.size.height)))
            let canvas = ImageCanvas(image: image)
            imageCanvas = canvas
            canvas.onAnalysisChanged = { [weak self] in self?.updateStatus() }
            let scroll = NSScrollView()
            scroll.contentView = CenteredClipView()
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            scroll.backgroundColor = .underPageBackgroundColor
            scroll.documentView = canvas
            imageScroll = scroll
            content = scroll
        } else { fatalError("Unreachable: validated content") }
        content.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addSubview(content)
        root.addSubview(status)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -7),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -7),
            status.heightAnchor.constraint(equalToConstant: 15)
        ])
        let toolbar = NSToolbar(identifier: "SeparateViewerToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        root.layoutSubtreeIfNeeded()
        splitView?.setPosition(124, ofDividerAt: 0)
        fit(nil)
        if analyzeImages { imageCanvas?.analyzeText() }
        updateStatus()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { observations.forEach(NotificationCenter.default.removeObserver) }

    func windowWillClose(_ notification: Notification) { imageCanvas?.cancelAnalysis(); onClose?() }
    func windowDidResize(_ notification: Notification) { if fitsImage { fit(nil) } }

    @objc func zoomIn(_ sender: Any?) {
        smartZoomReturn = nil
        if let pdfView { pdfView.autoScales = false; pdfView.zoomIn(sender) }
        else { setImageScale(imageScale * 1.25) }
        updateStatus()
    }
    @objc func zoomOut(_ sender: Any?) {
        smartZoomReturn = nil
        if let pdfView { pdfView.autoScales = false; pdfView.zoomOut(sender) }
        else { setImageScale(imageScale / 1.25) }
        updateStatus()
    }
    @objc func fit(_ sender: Any?) {
        smartZoomReturn = nil
        if let pdfView { pdfView.autoScales = true }
        if let scroll = imageScroll {
            let size = scroll.contentSize
            setImageScale(min(size.width / originalImageSize.width, size.height / originalImageSize.height, 1))
            fitsImage = true
        }
        updateStatus()
    }
    @objc func actualSize(_ sender: Any?) {
        smartZoomReturn = nil
        if let pdfView { pdfView.autoScales = false; pdfView.scaleFactor = 1 }
        else { setImageScale(1) }
        updateStatus()
    }
    func magnify(with event: NSEvent) -> Bool {
        guard let content = (imageScroll as NSView?) ?? pdfView,
              content.bounds.contains(content.convert(event.locationInWindow, from: nil)) else { return false }
        let delta = event.magnification
        guard delta.isFinite, delta != 0 else { return true }
        let factor = max(0.01, 1 + delta)
        if imageScroll != nil {
            setImageScale(imageScale * factor, anchorInWindow: event.locationInWindow)
        } else if let pdfView {
            setPDFScale(pdfView.scaleFactor * factor, anchorInWindow: event.locationInWindow)
        }
        return true
    }
    func smartMagnify(with event: NSEvent) -> Bool {
        guard let content = (imageScroll as NSView?) ?? pdfView,
              content.bounds.contains(content.convert(event.locationInWindow, from: nil)) else { return false }
        if let saved = smartZoomReturn {
            if saved.fits { fit(nil) }
            else if pdfView != nil { setPDFScale(saved.scale, anchorInWindow: event.locationInWindow) }
            else { setImageScale(saved.scale, anchorInWindow: event.locationInWindow) }
        } else {
            let current = pdfView?.scaleFactor ?? imageScale
            let maximum = pdfView?.maxScaleFactor ?? 16
            if current >= maximum { fit(nil); return true }
            let saved = (scale: current, fits: pdfView?.autoScales ?? fitsImage)
            let target = min(max(current * 2, 1), maximum)
            if pdfView != nil { setPDFScale(target, anchorInWindow: event.locationInWindow) }
            else { setImageScale(target, anchorInWindow: event.locationInWindow) }
            smartZoomReturn = saved
        }
        return true
    }
    private func setPDFScale(_ scale: CGFloat, anchorInWindow: NSPoint) {
        guard scale.isFinite, let pdfView else { return }
        smartZoomReturn = nil
        // Keep the point on the PDF under the pointer stationary when possible.
        let point = pdfView.convert(anchorInWindow, from: nil)
        let page = pdfView.page(for: point, nearest: true)
        let pagePoint = page.map { pdfView.convert(point, to: $0) }
        let clip = pdfView.documentView?.enclosingScrollView?.contentView
        let oldClipSize = clip?.bounds.size
        let oldPoint = pdfView.documentView?.convert(anchorInWindow, from: nil)
        let offset = oldPoint.flatMap { p in clip.map { NSPoint(x: p.x - $0.bounds.minX, y: p.y - $0.bounds.minY) } }
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(scale, pdfView.minScaleFactor), pdfView.maxScaleFactor)
        pdfView.layoutDocumentView()
        if let page, let pagePoint, let clip, let offset, let oldClipSize,
           oldClipSize.width > 0, oldClipSize.height > 0, let document = pdfView.documentView {
            let newPoint = document.convert(pdfView.convert(pagePoint, from: page), from: pdfView)
            // PDFKit also scales the clip view's coordinate system.
            let adjustedOffset = NSPoint(x: offset.x * clip.bounds.width / oldClipSize.width,
                                         y: offset.y * clip.bounds.height / oldClipSize.height)
            scroll(clip, to: NSPoint(x: newPoint.x - adjustedOffset.x, y: newPoint.y - adjustedOffset.y))
        }
        updateStatus()
    }
    private func scroll(_ clip: NSClipView, to origin: NSPoint) {
        let proposed = NSRect(origin: origin, size: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        clip.enclosingScrollView?.reflectScrolledClipView(clip)
    }
    func setImageScale(_ scale: CGFloat, anchorInWindow: NSPoint? = nil) {
        guard scale.isFinite, let canvas = imageCanvas, let clip = imageScroll?.contentView else { return }
        smartZoomReturn = nil
        let anchor = anchorInWindow.map { canvas.convert($0, from: nil) }
            ?? NSPoint(x: clip.bounds.midX, y: clip.bounds.midY)
        let offset = NSPoint(x: anchor.x - clip.bounds.minX, y: anchor.y - clip.bounds.minY)
        let previousScale = imageScale
        fitsImage = false
        imageScale = min(max(scale, 0.01), 16)
        canvas.setFrameSize(NSSize(width: originalImageSize.width * imageScale, height: originalImageSize.height * imageScale))
        let ratio = imageScale / previousScale
        scroll(clip, to: NSPoint(x: anchor.x * ratio - offset.x, y: anchor.y * ratio - offset.y))
        canvas.textOverlay.setContentsRectNeedsUpdate()
        canvas.needsDisplay = true
        updateStatus()
    }
    @objc func previousPage(_ sender: Any?) { pdfView?.goToPreviousPage(sender) }
    @objc func nextPage(_ sender: Any?) { pdfView?.goToNextPage(sender) }
    @objc func toggleSidebar(_ sender: Any?) {
        guard let thumbnails = thumbnailView, let split = splitView else { return }
        thumbnails.isHidden.toggle()
        split.adjustSubviews()
        if !thumbnails.isHidden { split.setPosition(124, ofDividerAt: 0) }
    }
    func updateStatus() {
        if let pdfView, let document = pdfView.document {
            if document.isLocked { status.stringValue = "Password-protected PDF"; return }
            let page = pdfView.currentPage.map { document.index(for: $0) + 1 } ?? 1
            status.stringValue = "Page \(page) of \(document.pageCount)  ·  \(Int(pdfView.scaleFactor * 100))%"
        } else {
            status.stringValue = "\(Int(originalImageSize.width)) × \(Int(originalImageSize.height)) pixels  ·  \(Int(imageScale * 100))%"
            if let textStatus = imageCanvas?.textStatus, !textStatus.isEmpty { status.stringValue += "  ·  " + textStatus }
        }
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let names = pdfView == nil ? ["open", "space", "minus", "fit", "actual", "plus"] : ["open", "sidebar", "space", "previous", "next", "minus", "fit", "actual", "plus"]
        return names.map { $0 == "space" ? .flexibleSpace : NSToolbarItem.Identifier($0) }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        let configuration: (String, String, Selector)
        switch id.rawValue {
        case "open": configuration = ("Open files", "folder", #selector(AppDelegate.openPanel(_:)))
        case "sidebar": configuration = ("Show or hide thumbnails", "sidebar.left", #selector(toggleSidebar(_:)))
        case "previous": configuration = ("Previous page", "chevron.up", #selector(previousPage(_:)))
        case "next": configuration = ("Next page", "chevron.down", #selector(nextPage(_:)))
        case "minus": configuration = ("Zoom out", "minus.magnifyingglass", #selector(zoomOut(_:)))
        case "plus": configuration = ("Zoom in", "plus.magnifyingglass", #selector(zoomIn(_:)))
        case "fit": configuration = ("Fit to window", "arrow.up.left.and.arrow.down.right", #selector(fit(_:)))
        case "actual": configuration = ("Actual size", "1.magnifyingglass", #selector(actualSize(_:)))
        default: return nil
        }
        item.label = configuration.0
        item.toolTip = configuration.0
        item.image = NSImage(systemSymbolName: configuration.1, accessibilityDescription: configuration.0)
        item.target = id.rawValue == "open" ? NSApp.delegate : self
        item.action = configuration.2
        return item
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewers: [UUID: ViewerController] = [:]
    var welcome: NSWindow?
    var cascadePoint = NSPoint(x: 130, y: 850)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        makeMenu()
        if viewers.isEmpty { showWelcome() }
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) { openURLs(urls) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }
    func openURLs(_ urls: [URL]) {
        var errors: [String] = []
        for url in urls {
            do {
                let controller = try ViewerController(url: url)
                let id = UUID()
                viewers[id] = controller
                controller.onClose = { [weak self] in self?.viewers.removeValue(forKey: id) }
                if let window = controller.window {
                    cascadePoint = window.cascadeTopLeft(from: cascadePoint)
                    controller.showWindow(nil)
                    window.makeKeyAndOrderFront(nil)
                }
                welcome?.orderOut(nil)
            } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some files couldn’t be opened"
            alert.informativeText = errors.prefix(5).joined(separator: "\n")
            alert.runModal()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Each file opens in its own window."
        if panel.runModal() == .OK { openURLs(panel.urls) }
    }
    func showWelcome() {
        if let welcome { welcome.makeKeyAndOrderFront(nil); return }
        let window = FileWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 390), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Separate"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        let root = DropSurface(frame: window.contentView!.bounds)
        root.onOpen = { [weak self] urls in self?.openURLs(urls) }
        window.contentView = root
        let iconImage = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Separate windows")!
        let icon = NSImageView(image: iconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Separate app icon")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let heading = NSTextField(labelWithString: "One file. One window.")
        heading.font = .systemFont(ofSize: 26, weight: .semibold)
        let detail = NSTextField(labelWithString: "Drop PDFs or images here to get started.")
        detail.textColor = .secondaryLabelColor
        let button = NSButton(title: "Open Files…", target: self, action: #selector(openPanel(_:)))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        let stack = NSStackView(views: [icon, heading, detail, button])
        stack.orientation = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: root.centerXAnchor), stack.centerYAnchor.constraint(equalTo: root.centerYAnchor)])
        welcome = window
        window.makeKeyAndOrderFront(nil)
    }
    func makeMenu() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title)
            item.submenu = child
            menu.addItem(item)
            return child
        }
        let appMenu = submenu("Separate")
        appMenu.addItem(withTitle: "About Separate", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Separate", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Separate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("File")
        let open = file.addItem(withTitle: "Open…", action: #selector(openPanel(_:)), keyEquivalent: "o")
        open.target = self
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = submenu("Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let view = submenu("View")
        view.addItem(withTitle: "Zoom In", action: #selector(ViewerController.zoomIn(_:)), keyEquivalent: "+")
        view.addItem(withTitle: "Zoom Out", action: #selector(ViewerController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Fit to Window", action: #selector(ViewerController.fit(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Actual Size", action: #selector(ViewerController.actualSize(_:)), keyEquivalent: "1")
        view.addItem(withTitle: "Show or Hide Thumbnails", action: #selector(ViewerController.toggleSidebar(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Previous Page", action: #selector(ViewerController.previousPage(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Next Page", action: #selector(ViewerController.nextPage(_:)), keyEquivalent: "")
        let windows = submenu("Window")
        windows.addItem(withTitle: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windows
        NSApp.mainMenu = menu
    }
}

// Synthetic AppKit events exercise the same window dispatch path as a trackpad.
final class TestMagnifyEvent: NSEvent {
    var delta: CGFloat = 0
    var point = NSPoint.zero
    var eventType: NSEvent.EventType = .magnify
    override var type: NSEvent.EventType { eventType }
    override var magnification: CGFloat { delta }
    override var locationInWindow: NSPoint { point }
}

func testPinch(_ controller: ViewerController) {
    let content: NSView = controller.imageScroll ?? controller.pdfView!
    let event = TestMagnifyEvent()
    event.point = content.convert(NSPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil)
    func scale() -> CGFloat { controller.pdfView?.scaleFactor ?? controller.imageScale }
    func pinch(_ delta: CGFloat) {
        event.delta = delta
        controller.window!.sendEvent(event)
    }
    controller.fit(nil)
    pinch(0)
    precondition(controller.pdfView?.autoScales ?? controller.fitsImage, "Zero-delta events must preserve fit mode")
    controller.actualSize(nil)
    pinch(0.25)
    precondition(abs(scale() - 1.25) < 0.001, "Pinch out must zoom in exactly once")
    pinch(-0.2)
    precondition(abs(scale() - 1) < 0.001, "Pinch in must zoom out")
    precondition(!(controller.pdfView?.autoScales ?? controller.fitsImage))
    pinch(.nan)
    precondition(abs(scale() - 1) < 0.001)
    pinch(1000)
    precondition(abs(scale() - (controller.pdfView?.maxScaleFactor ?? 16)) < 0.001)
    pinch(-10)
    pinch(-10)
    precondition(abs(scale() - (controller.pdfView?.minScaleFactor ?? 0.01)) < 0.001)
    event.point = NSPoint(x: -100, y: -100)
    precondition(!controller.magnify(with: event), "Gestures outside the document must not zoom")
    event.point = content.convert(NSPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil)
    controller.fit(nil)
    precondition(controller.pdfView?.autoScales ?? controller.fitsImage)
    if let canvas = controller.imageCanvas, let clip = controller.imageScroll?.contentView {
        controller.setImageScale(4)
        event.point = canvas.convert(NSPoint(x: clip.bounds.midX + 20, y: clip.bounds.midY + 10), to: nil)
        let before = canvas.convert(event.point, from: nil)
        pinch(0.25)
        let after = canvas.convert(event.point, from: nil)
        precondition(abs(before.x / 4 - after.x / 5) < 1 && abs(before.y / 4 - after.y / 5) < 1,
                     "Pinch must keep the image point under the pointer")
        precondition(controller.status.stringValue.contains("500%"))
    } else if let pdf = controller.pdfView {
        controller.actualSize(nil)
        pinch(3)
        let point = pdf.convert(event.point, from: nil)
        let page = pdf.page(for: point, nearest: true)!
        let before = pdf.convert(point, to: page)
        pinch(0.25)
        let after = pdf.convert(pdf.convert(event.point, from: nil), to: page)
        precondition(abs(before.x - after.x) < 1 && abs(before.y - after.y) < 1,
                     "Pinch must keep the PDF point under the pointer")
        precondition(controller.status.stringValue.contains("500%"))
    }
}

func testSmartZoom(_ controller: ViewerController) {
    let content: NSView = controller.imageScroll ?? controller.pdfView!
    let event = TestMagnifyEvent()
    event.eventType = .smartMagnify
    event.point = content.convert(NSPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil)
    func scale() -> CGFloat { controller.pdfView?.scaleFactor ?? controller.imageScale }
    controller.fit(nil)
    let fitted = scale()
    controller.window!.sendEvent(event)
    precondition(scale() > fitted, "Two-finger double tap must zoom in")
    controller.window!.sendEvent(event)
    precondition(abs(scale() - fitted) < 0.001)
    precondition(controller.pdfView?.autoScales ?? controller.fitsImage, "Second double tap must restore Fit")
    controller.actualSize(nil)
    controller.window!.sendEvent(event)
    precondition(abs(scale() - 2) < 0.001)
    controller.window!.sendEvent(event)
    precondition(abs(scale() - 1) < 0.001, "Double tap must restore a custom zoom too")
    controller.window!.sendEvent(event)
    controller.zoomOut(nil)
    let manuallyAdjusted = scale()
    controller.window!.sendEvent(event)
    precondition(scale() > manuallyAdjusted, "Manual zoom must reset the smart-zoom toggle")
    event.point = NSPoint(x: -100, y: -100)
    precondition(!controller.smartMagnify(with: event))
}

@MainActor func testLiveText(_ base: URL) throws {
    guard ImageAnalyzer.isSupported else { print("SKIP: Live Text unsupported on this Mac"); return }
    let controller = try ViewerController(url: base.appendingPathComponent("text-image.png"))
    let canvas = controller.imageCanvas!
    let deadline = Date().addingTimeInterval(45)
    while canvas.isAnalyzing && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    precondition(!canvas.isAnalyzing, "Text recognition timed out")
    let transcript = canvas.textOverlay.analysis?.transcript ?? ""
    precondition(transcript.contains("Separate reads this text") && transcript.contains("One file"),
                 "Live Text must recognize the synthetic image")
    precondition(canvas.textOverlay.preferredInteractionTypes == .textSelection)
    controller.setImageScale(2)
    precondition(canvas.textOverlay.frame == canvas.bounds, "Text overlay must follow image zoom")
    if #available(macOS 14.0, *) {
        let text = canvas.textOverlay.text
        canvas.textOverlay.selectedRanges = [text.startIndex..<text.endIndex]
        precondition(canvas.textOverlay.selectedText.contains("Separate reads this text"), "Recognized text must be selectable")
    }
    controller.close()
    precondition(!canvas.isAnalyzing)
    print("PASS: Live Text recognition, selectable text and overlay zoom geometry")
}

@MainActor func selfTest(_ directory: String) throws {
    NSWindow.allowsAutomaticWindowTabbing = false
    let base = URL(fileURLWithPath: directory)
    let names = ["window-one.pdf", "window-two.pdf", "image-one.png", "image-two.png"]
    var controllers: [ViewerController] = []
    for index in 0..<24 {
        let controller = try ViewerController(url: base.appendingPathComponent(names[index % names.count]), analyzeImages: false)
        controllers.append(controller)
        precondition(controller.window?.tabbingMode == .disallowed)
        precondition(controller.window?.tabbedWindows == nil || controller.window?.tabbedWindows?.count == 1)
        precondition((controller.pdfView?.document?.pageCount ?? 0) > 0 || controller.imageCanvas != nil)
        if controller.imageCanvas != nil {
            controller.actualSize(nil)
            precondition(controller.imageScale == 1)
            controller.zoomIn(nil)
            precondition(controller.imageScale > 1)
            controller.fit(nil)
            precondition(controller.fitsImage)
        } else {
            controller.actualSize(nil)
            precondition(abs(controller.pdfView!.scaleFactor - 1) < 0.01)
            controller.nextPage(nil)
            precondition(controller.pdfView?.currentPage == controller.pdfView?.document?.page(at: 1))
        }
        testPinch(controller)
        testSmartZoom(controller)
    }
    precondition(Set(controllers.map { ObjectIdentifier($0.window!) }).count == 24)
    precondition(Set(controllers.compactMap { $0.window?.tabbingIdentifier }).count == 24)
    precondition(!NSWindow.allowsAutomaticWindowTabbing)
    do {
        _ = try ViewerController(url: base.appendingPathComponent("missing.pdf"))
        fatalError("Missing file must fail")
    } catch is ViewerError {}
    do {
        _ = try ViewerController(url: base.appendingPathComponent("invalid.pdf"))
        fatalError("Invalid file must fail")
    } catch is ViewerError {}
    controllers.forEach { $0.close() }
    try testLiveText(base)
    print("PASS: 24 independent PDF/image windows, tabs disabled, duplicate opens independent, pinch in/out and limits, zoom anchoring, zoom/fit/page navigation, invalid and missing file handling.")
}

let application = NSApplication.shared
NSWindow.allowsAutomaticWindowTabbing = false
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--self-test" {
    do { try MainActor.assumeIsolated { try selfTest(CommandLine.arguments[2]) }; exit(0) }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
