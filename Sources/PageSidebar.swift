import AppKit
import PDFKit

final class PageTable: NSTableView {
    var deleteSelection: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if [51, 117].contains(event.keyCode), event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty {
            deleteSelection?()
        } else { super.keyDown(with: event) }
    }
}

final class PageSidebar: NSScrollView, NSTableViewDelegate, NSTableViewDataSource {
    weak var viewer: ViewerController?
    let table = PageTable()
    var syncing = false
    init(viewer: ViewerController) {
        self.viewer = viewer
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        let column = NSTableColumn(identifier: .init("page"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 115
        table.allowsMultipleSelection = true
        table.delegate = self
        table.dataSource = self
        table.registerForDraggedTypes([.fileURL])
        table.setAccessibilityLabel("PDF pages")
        table.toolTip = "Drop a PDF between pages or below the last page to insert it."
        table.deleteSelection = { [weak viewer] in
            guard let viewer, viewer.editor?.editable == true, !viewer.selectedPages.isEmpty else { return }
            viewer.deletePages(nil)
        }
        documentView = table
        table.reloadData()
    }
    required init?(coder: NSCoder) { fatalError() }
    func numberOfRows(in tableView: NSTableView) -> Int { viewer?.editor?.document.pageCount ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let page = viewer?.editor?.document.page(at: row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("pageThumbnail")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView { cell = reused }
        else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView(), label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 11)
            image.imageScaling = .scaleProportionallyUpOrDown
            for child in [image as NSView, label] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
            cell.imageView = image
            cell.textField = label
            NSLayoutConstraint.activate([
                image.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
                image.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3),
                image.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -3),
                label.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2)
            ])
        }
        cell.imageView?.image = page.thumbnail(of: NSSize(width: 88, height: 92), for: .cropBox)
        cell.textField?.stringValue = String(row + 1)
        cell.setAccessibilityLabel("Page \(row + 1)")
        return cell
    }
    func select(_ row: Int) {
        guard !syncing, (0..<table.numberOfRows).contains(row) else { return }
        syncing = true
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        syncing = false
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let viewer, let index = table.selectedRowIndexes.first,
              let page = viewer.editor?.document.page(at: index) else { return }
        syncing = true
        viewer.pdfView?.go(to: page)
        syncing = false
    }
    static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf" ||
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) == true
    }
    func pdfURLs(_ board: NSPasteboard) -> [URL]? {
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty, urls.allSatisfy(Self.isPDF) else { return nil }
        return urls
    }
    func insertionRow(_ row: Int, _ op: NSTableView.DropOperation) -> Int {
        if row < 0 { return table.numberOfRows }
        return min(table.numberOfRows, row + (op == .on ? 1 : 0))
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard viewer?.editor?.editable == true, pdfURLs(info.draggingPasteboard) != nil else { return [] }
        tableView.setDropRow(insertionRow(row, op), dropOperation: .above)
        return .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation op: NSTableView.DropOperation) -> Bool {
        acceptFiles(info.draggingPasteboard, row: row, operation: op)
    }
    func acceptFiles(_ pasteboard: NSPasteboard, row: Int, operation op: NSTableView.DropOperation) -> Bool {
        guard let urls = pdfURLs(pasteboard) else { return false }
        return viewer?.importPDFs(urls, at: insertionRow(row, op)) == true
    }
}
