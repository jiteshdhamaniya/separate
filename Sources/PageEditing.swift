import AppKit
import PDFKit
import UniformTypeIdentifiers

struct PageEditError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// Keep the actual pages so undo restores their contents and original order.
final class PageEditor {
    let document: PDFDocument
    private struct Change {
        let inserting: Bool
        let pages: [(index: Int, page: PDFPage)]
        let before: UUID
        let after = UUID()
    }
    private var past: [Change] = [], future: [Change] = []
    private var revision: UUID, saved: UUID
    init(_ document: PDFDocument) {
        self.document = document
        let start = UUID()
        revision = start
        saved = start
    }
    var editable: Bool { !document.isEncrypted && !document.isLocked && document.allowsDocumentAssembly }
    var dirty: Bool { revision != saved }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    func markSaved() { saved = revision }

    private func apply(_ change: Change, forward: Bool) -> Int {
        if change.inserting == forward {
            for entry in change.pages { document.insert(entry.page, at: entry.index) }
        } else {
            for entry in change.pages.reversed() { document.removePage(at: entry.index) }
        }
        revision = forward ? change.after : change.before
        return min(change.pages[0].index, document.pageCount - 1)
    }
    private func record(_ change: Change) -> Int {
        future.removeAll()
        past.append(change)
        return apply(change, forward: true)
    }
    func undo() -> Int? {
        guard let change = past.popLast() else { return nil }
        future.append(change)
        return apply(change, forward: false)
    }
    func redo() -> Int? {
        guard let change = future.popLast() else { return nil }
        past.append(change)
        return apply(change, forward: true)
    }
    func remove(_ indexes: IndexSet) throws -> Int {
        guard editable, !indexes.isEmpty, indexes.count < document.pageCount,
              indexes.last! < document.pageCount else { throw PageEditError("Keep at least one page in the PDF.") }
        let pages = try indexes.map { index -> (Int, PDFPage) in
            guard let page = document.page(at: index) else { throw PageEditError("Page unavailable.") }
            return (index, page)
        }
        return record(Change(inserting: false, pages: pages, before: revision))
    }
    private func insert(_ pages: [PDFPage], at index: Int) throws -> Int {
        guard editable, !pages.isEmpty, (0...document.pageCount).contains(index) else {
            throw PageEditError("Pages can’t be inserted here.")
        }
        return record(Change(inserting: true, pages: pages.enumerated().map { (index + $0.offset, $0.element) }, before: revision))
    }
    func insertBlank(at index: Int) throws -> Int {
        let page = PDFPage()
        if let neighbor = document.page(at: max(0, index - 1)) {
            page.setBounds(neighbor.bounds(for: .mediaBox), for: .mediaBox)
            page.setBounds(neighbor.bounds(for: .cropBox), for: .cropBox)
            page.rotation = neighbor.rotation
        }
        return try insert([page], at: index)
    }
    func insertFiles(_ urls: [URL], at index: Int) throws -> Int {
        // Validate and copy the entire batch before touching the destination.
        var pages: [PDFPage] = []
        for url in urls {
            guard let source = PDFDocument(url: url), !source.isLocked, !source.isEncrypted,
                  source.allowsCopying, source.pageCount > 0 else {
                throw PageEditError("Couldn’t import \(url.lastPathComponent). Choose a readable, unprotected PDF.")
            }
            for i in 0..<source.pageCount {
                guard let page = source.page(at: i)?.copy() as? PDFPage else {
                    throw PageEditError("Couldn’t copy page \(i + 1) of \(url.lastPathComponent).")
                }
                pages.append(page)
            }
        }
        return try insert(pages, at: index)
    }
}

extension ViewerController: NSMenuItemValidation {
    var selectedPages: IndexSet {
        if let rows = thumbnailView?.table.selectedRowIndexes, !rows.isEmpty { return rows }
        if let doc = editor?.document, let page = pdfView?.currentPage {
            let i = doc.index(for: page)
            if i < doc.pageCount { return IndexSet(integer: i) }
        }
        return []
    }
    var insertionIndex: Int { selectedPages.last.map { $0 + 1 } ?? editor?.document.pageCount ?? 0 }
    func refreshEdit(_ index: Int?) {
        guard let index, let editor, let view = pdfView else { return }
        let fitted = view.autoScales, scale = view.scaleFactor
        thumbnailView?.syncing = true
        view.document = nil
        view.document = editor.document
        if fitted { view.autoScales = true } else { view.scaleFactor = scale }
        thumbnailView?.table.reloadData()
        if let page = editor.document.page(at: index) { view.go(to: page) }
        thumbnailView?.syncing = false
        thumbnailView?.select(index)
        window?.isDocumentEdited = editor.dirty
        updateStatus()
    }
    func reportEditError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t change the PDF"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
    @discardableResult func importPDFs(_ urls: [URL], at row: Int) -> Bool {
        guard let editor, editor.editable else { return false }
        do { refreshEdit(try editor.insertFiles(urls, at: row)); return true }
        catch { reportEditError(error); return false }
    }
    @objc func insertPDF(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.prompt = "Insert"
        if panel.runModal() == .OK { importPDFs(panel.urls, at: insertionIndex) }
    }
    @objc func addBlankPage(_ sender: Any?) {
        do { refreshEdit(try editor?.insertBlank(at: insertionIndex)) } catch { reportEditError(error) }
    }
    @objc func deletePages(_ sender: Any?) {
        do { refreshEdit(try editor?.remove(selectedPages)) } catch { reportEditError(error) }
    }
    @objc func undoPages(_ sender: Any?) { refreshEdit(editor?.undo()) }
    @objc func redoPages(_ sender: Any?) { refreshEdit(editor?.redo()) }

    func savePDF(to url: URL) throws {
        guard let editor, editor.editable, let data = editor.document.dataRepresentation(),
              PDFDocument(data: data)?.pageCount == editor.document.pageCount else {
            throw PageEditError("Couldn’t prepare the edited PDF for saving.")
        }
        let target = url.resolvingSymlinksInPath()
        var coordinationError: NSError?, writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { destination in
            do {
                if target.standardizedFileURL == fileURL.resolvingSymlinksInPath().standardizedFileURL {
                    guard (try? Data(contentsOf: destination)) == savedBytes else {
                        throw PageEditError("The original file changed or moved. Use File → Save As… to keep your edits in another file.")
                    }
                }
                try data.write(to: destination, options: .atomic)
            } catch { writeError = error }
        }
        if let error = writeError ?? coordinationError { throw error }
        savedBytes = data
        editor.markSaved()
        fileURL = url
        window?.representedURL = url
        window?.title = url.lastPathComponent
        window?.isDocumentEdited = false
    }
    @objc func savePages(_ sender: Any?) {
        do { try savePDF(to: fileURL) } catch { reportEditError(error) }
    }
    @objc func savePagesAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = fileURL.deletingLastPathComponent()
        panel.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + " copy.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do { try savePDF(to: url) } catch { reportEditError(error) }
        }
    }
    func confirmClose() -> Bool {
        guard editor?.dirty == true else { return true }
        window?.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        alert.messageText = "Save changes to \(fileURL.lastPathComponent)?"
        alert.informativeText = "Your page edits will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: savePages(nil); return editor?.dirty != true
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmClose() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoPages(_:)): return editor?.canUndo == true
        case #selector(redoPages(_:)): return editor?.canRedo == true
        case #selector(savePages(_:)): return editor?.dirty == true
        case #selector(insertPDF(_:)), #selector(addBlankPage(_:)), #selector(savePagesAs(_:)): return editor?.editable == true
        case #selector(deletePages(_:)): return editor?.editable == true && !selectedPages.isEmpty && selectedPages.count < (editor?.document.pageCount ?? 0)
        default: return true
        }
    }
}
