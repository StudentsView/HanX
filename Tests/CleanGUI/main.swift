import AppKit

// Exercise actual document windows and NSAlert sheets without activating the app
// or using the user's documents, preferences, recent history or clipboard.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HanX-CleanGUI-" + UUID().uuidString)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("PASS \(message)") } else { failures += 1; print("FAIL \(message)") }
}
func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
func makeEditor(_ doc: HWDocument) -> EditorWindowController {
    doc.makeWindowControllers()
    let editor = doc.windowControllers.first as! EditorWindowController
    editor.window!.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    return editor
}
func dismiss(_ window: NSWindow) {
    if let sheet = window.attachedSheet { window.endSheet(sheet); sheet.orderOut(nil); settle() }
}
let clean = HWDocument()
let cleanEditor = makeEditor(clean)
cleanEditor.showWindow(nil); settle()
check(cleanEditor.window!.attachedSheet == nil, "new clean document opens without a notice")
cleanEditor.close()

let source = HWDocument()
source.textStorage.setAttributedString(NSAttributedString(string: "HanX PDF fixture", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
let pdf = folder.appendingPathComponent("fixture.pdf")
try source.pdfData().write(to: pdf)
let imported = HWDocument()
try imported.read(from: pdf, ofType: DocType.pdf)
imported.model.warnings.append("Fixture compatibility detail")
let editor = makeEditor(imported)
editor.showWindow(nil); settle()
let window = editor.window!
check(window.attachedSheet != nil, "PDF import warning opens as an alert sheet")
if let content = window.attachedSheet?.contentView {
    let text = descendants(content).compactMap { $0 as? NSTextField }.map(\.stringValue).joined(separator: "\n")
    check(text.contains("OCR") && text.contains("Fixture compatibility detail"), "alert preserves extraction limits and other import warnings")
}
dismiss(window)
editor.pages.firstTextView.insertText(" Edited", replacementRange: NSRange(location: imported.textStorage.length, length: 0))
editor.updateStatus()
editor.showWindow(nil); settle()
check(window.attachedSheet == nil, "editing and showing the same document do not repeat the alert")
let secondEditor = EditorWindowController(document: imported)
imported.addWindowController(secondEditor)
secondEditor.window!.setFrameOrigin(NSPoint(x: -10000, y: -10000))
secondEditor.showWindow(nil); settle()
check(secondEditor.window!.attachedSheet == nil, "another window for the same document does not repeat the alert")
secondEditor.close()
let labels = descendants(window.contentView!).compactMap { $0 as? NSTextField }
check(!labels.contains { $0.stringValue.contains("OCR") || ($0.toolTip?.contains("OCR") ?? false) }, "import warning does not persist in editor status or tooltips")
editor.close()

let reopened = HWDocument()
try reopened.read(from: pdf, ofType: DocType.pdf)
let reopenedEditor = makeEditor(reopened)
reopenedEditor.showWindow(nil); settle()
check(reopenedEditor.window!.attachedSheet != nil, "opening the file as a new document shows its notice again")
dismiss(reopenedEditor.window!)
reopenedEditor.close()

let queued = HWDocument()
try queued.read(from: pdf, ofType: DocType.pdf)
let queuedEditor = makeEditor(queued)
let existing = NSAlert()
existing.messageText = "Existing operation"
existing.beginSheetModal(for: queuedEditor.window!)
queuedEditor.showWindow(nil); settle()
dismiss(queuedEditor.window!)
check(queuedEditor.window!.attachedSheet != nil, "an existing dialog does not discard the import warning")
dismiss(queuedEditor.window!)
queuedEditor.close()

let manyWarnings = HWDocument()
try manyWarnings.read(from: pdf, ofType: DocType.pdf)
let lastWarning = "Final warning: " + String(repeating: "Full compatibility details remain available. ", count: 60)
manyWarnings.model.warnings += (1...30).map { "Warning \($0): " + String(repeating: "Unsupported imported property. ", count: 8) }
manyWarnings.model.warnings.append(lastWarning)
let manyEditor = makeEditor(manyWarnings)
manyEditor.showWindow(nil); settle()
if let content = manyEditor.window!.attachedSheet?.contentView {
    let views = descendants(content)
    let summary = views.compactMap { $0 as? NSTextField }.map(\.stringValue).joined(separator: "\n")
    check(summary.count < 1200, "many import warnings keep the alert summary concise")
    let details = views.compactMap { $0 as? NSTextView }.first { $0.enclosingScrollView != nil }
    check(details?.string.contains(lastWarning) == true, "scrollable import details preserve the complete final warning")
    check(details?.isEditable == false && details?.isSelectable == true && details?.enclosingScrollView?.hasVerticalScroller == true,
          "large warning details are read-only, selectable and scrollable")
    if let details {
        details.scrollRangeToVisible(NSRange(location: (details.string as NSString).length - 1, length: 1))
        check((details.enclosingScrollView?.contentView.bounds.origin.y ?? 0) > 0,
              "the final import warning can actually be scrolled into view")
    }
} else { check(false, "many import warnings still open an alert") }
dismiss(manyEditor.window!)
manyEditor.close()
exit(failures == 0 ? 0 : 1)
