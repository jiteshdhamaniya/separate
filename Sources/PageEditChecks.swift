import AppKit
import PDFKit

@MainActor func testPageEdits(_ directory: URL) throws {
    let original = directory.appendingPathComponent("window-one.pdf")
    let source = directory.appendingPathComponent("window-two.pdf")
    let working = directory.appendingPathComponent("editing.pdf")
    try FileManager.default.copyItem(at: original, to: working)
    let viewer = try ViewerController(url: working), second = try ViewerController(url: working)
    defer { viewer.close(); second.close() }
    let editor = viewer.editor!, sidebar = viewer.thumbnailView!
    viewer.window!.contentView!.layoutSubtreeIfNeeded()
    precondition(sidebar.table.bounds.width > 40 && sidebar.table.rect(ofRow: 0).width > 40,
                 "Sidebar must provide a visible drop target")
    let root = viewer.window!.contentView as! DropSurface
    precondition(root.onDrop?([source]) == true && editor.document.pageCount == 4)
    viewer.undoPages(nil)
    func pages(_ doc: PDFDocument) -> [String] {
        (0..<doc.pageCount).map { doc.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    }
    let first = pages(editor.document), other = pages(PDFDocument(url: source)!)
    precondition(first == ["File 1 page 1", "File 1 page 2"] && other == ["File 2 page 1", "File 2 page 2"])
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.writeObjects([source as NSURL])
    precondition(sidebar.acceptFiles(board, row: 0, operation: .on))
    let combined = [first[0]] + other + [first[1]]
    precondition(pages(editor.document) == combined && viewer.window!.isDocumentEdited)
    viewer.undoPages(nil)
    precondition(pages(editor.document) == first && !editor.dirty)
    viewer.redoPages(nil)
    precondition(pages(editor.document) == combined)
    sidebar.table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
    viewer.deletePages(nil)
    precondition(pages(editor.document) == [other[0], first[1]])
    viewer.undoPages(nil)
    precondition(pages(editor.document) == combined)
    precondition(sidebar.acceptFiles(board, row: 4, operation: .above))
    precondition(pages(editor.document) == combined + other)
    viewer.undoPages(nil)
    viewer.addBlankPage(nil)
    precondition(editor.document.pageCount == 5)
    viewer.undoPages(nil)
    do {
        _ = try editor.remove(IndexSet(0..<4))
        fatalError("Must keep one page")
    } catch is PageEditError {}
    do {
        _ = try editor.insertFiles([source, directory.appendingPathComponent("invalid.pdf")], at: 1)
        fatalError("Partial import must fail")
    } catch is PageEditError {}
    precondition(pages(editor.document) == combined && pages(PDFDocument(url: working)!) == first)
    try viewer.savePDF(to: working)
    precondition(!editor.dirty && pages(PDFDocument(url: working)!) == combined)
    second.addBlankPage(nil)
    do { try second.savePDF(to: working); fatalError("Stale window overwrote newer edits") } catch is PageEditError {}
    let copy = directory.appendingPathComponent("edited-copy.pdf")
    try second.savePDF(to: copy)
    precondition(PDFDocument(url: copy)?.pageCount == 3 && pages(PDFDocument(url: working)!) == combined)
    print("PASS: sidebar PDF drop between pages and at end, ordered content, multi-delete, blank insertion, undo/redo, atomic import, explicit save/reopen and stale-window protection.")
}
