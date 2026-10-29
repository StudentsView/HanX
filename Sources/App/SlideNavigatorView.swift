import AppKit

/// The thumbnail pane owns slide commands; canvas and text retain their own
/// responder-chain commands. Native table tracking handles Shift/Cmd selection.
final class SlideNavigatorView:NSTableView,NSMenuItemValidation {
    var onCommand:((String)->Void)?
    var onFocus:(()->Void)?
    var contextMenu:((NSEvent)->NSMenu?)?
    var canCommand:((String)->Bool)?
    override func becomeFirstResponder()->Bool {
        let result=super.becomeFirstResponder(); if result { onFocus?() }; return result
    }
    override func mouseDown(with event:NSEvent) { onFocus?(); super.mouseDown(with:event) }
    override func menu(for event:NSEvent)->NSMenu? {
        let row=row(at:convert(event.locationInWindow,from:nil))
        if row>=0,!selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }
        window?.makeFirstResponder(self); onFocus?()
        return contextMenu?(event)
    }
    override func keyDown(with event:NSEvent) {
        switch event.keyCode {
        case 51,117: delete(nil)
        case 36,76: onCommand?("new")
        case 126,125:
            if event.modifierFlags.contains(.command) { onCommand?(event.keyCode == 126 ? (event.modifierFlags.contains(.shift) ? "firstMove" : "up") : (event.modifierFlags.contains(.shift) ? "lastMove" : "down")) }
            else { super.keyDown(with:event) }
        case 48: onCommand?("canvasFocus")
        default: super.keyDown(with:event)
        }
    }
    @objc func copy(_ sender:Any?) { onCommand?("copySlides") }
    @objc func cut(_ sender:Any?) { onCommand?("cutSlides") }
    @objc func paste(_ sender:Any?) { onCommand?("pasteSlides") }
    @objc func duplicate(_ sender:Any?) { onCommand?("duplicateSlide") }
    @objc func delete(_ sender:Any?) { onCommand?("deleteSlide") }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if item.action == #selector(duplicate(_:)) { item.title="복제" }
        guard let action=item.action else { return true }
        let name=NSStringFromSelector(action)
        if ["copy:","cut:","duplicate:","delete:"].contains(name) { return numberOfSelectedRows>0 }
        if name == "paste:" { return canCommand?("pasteSlides") ?? false }
        return true
    }
}
