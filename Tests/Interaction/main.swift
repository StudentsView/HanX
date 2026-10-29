import AppKit
import QuartzCore

let app=NSApplication.shared
app.setActivationPolicy(.regular)
let dc=HWDocumentController()
app.mainMenu=MainMenu.build()
app.finishLaunching()
FontResolver.shared.registerBundledFonts()
let clipboard=NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
func restoreClipboard() {
    NSPasteboard.general.clearContents()
    let items=clipboard.map { pairs -> NSPasteboardItem in let item=NSPasteboardItem(); for (type,data) in pairs { item.setData(data,forType:type) }; return item }
    NSPasteboard.general.writeObjects(items)
}
var failures=0
func check(_ condition:@autoclosure ()->Bool,_ label:String) { if condition() { print("PASS \(label)") } else { failures += 1; print("FAIL \(label)") } }
func spin(_ seconds:Double=0.08) {
    let end=Date(timeIntervalSinceNow:seconds)
    while Date()<end {
        if let e=app.nextEvent(matching:.any,until:Date(timeIntervalSinceNow:0.01),inMode:.default,dequeue:true) { app.sendEvent(e) }
        app.updateWindows()
    }
}
func runChecks() {
let doc=SlideDocument(); dc.addDocument(doc); doc.undoManager?.groupsByEvent=false; doc.makeWindowControllers()
let wc=doc.windowControllers.first as! SlideWindowController
let window=wc.window!, list=wc.debugSlideList, canvas=wc.debugCanvas
window.title="한워드 동작 검사"
window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true); spin()
func reset(_ selection:IndexSet=IndexSet(integer:1)) {
    action { canvas.endEditing() }
    doc.pres.slides=(0..<3).map { i in var s=Slide(); s.background=i == 0 ? RGB(r:200,g:40,b:40) : RGB(r:40,g:70,b:200); s.notes="slide-\(i)"; var shape=SlideShape(id:2,kind:.rect,frame:Frame(x:100,y:100,w:150,h:90)); shape.fill=RGB(r:50,g:180,b:80); shape.paragraphs=[Presentation.textParagraph("slide-\(i)",size:20)]; s.shapes=[shape]; return s }
    doc.undoManager?.removeAllActions(); wc.reload()
    list.selectRowIndexes(selection,byExtendingSelection:false)
    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(list); spin()
}
func action(_ body:()->Void) { doc.undoManager?.beginUndoGrouping(); body(); doc.undoManager?.endUndoGrouping() }
func key(_ value:String,_ code:UInt16,_ modifiers:NSEvent.ModifierFlags = .command) {
    if !window.isKeyWindow || !app.isActive { app.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil); spin(0.1) }
    check(window.isKeyWindow && app.isActive,"keyboard test window owns input")
    let e=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:modifiers.contains(.shift) ? value.uppercased() : value,charactersIgnoringModifiers:modifiers.contains(.shift) ? value.uppercased() : value,isARepeat:false,keyCode:code)!
    print("KEY before value=\(value) mods=\(modifiers.rawValue) key=\(window.isKeyWindow) responder=\(String(describing:window.firstResponder)) count=\(doc.pres.slides.count) rows=\(list.selectedRowIndexes) notes=\(wc.inspectedSlide.notes) shapes=\(canvas.selectedIDs)")
    if code == 6 && modifiers.contains(.command) { app.sendEvent(e) } else { action { app.sendEvent(e) } }; spin()
    print("KEY after count=\(doc.pres.slides.count) rows=\(list.selectedRowIndexes) notes=\(wc.inspectedSlide.notes) pb=\(String(describing:NSPasteboard.general.types))")
}
func rightEvent(_ view:NSView)->NSEvent {
    let point=view.convert(NSPoint(x:40,y: view is NSTableView ? list.rect(ofRow:1).midY : 140),to:nil)
    return NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
}
reset()
print("keyWindow=\(String(describing:app.keyWindow)) isKey=\(window.isKeyWindow)")
print("firstResponder=\(String(describing:window.firstResponder)) duplicateTarget=\(String(describing:app.target(forAction:#selector(SlideWindowController.duplicateSlide(_:)))))")
key("d",2)
check(doc.pres.slides.count == 4 && doc.pres.slides[2].notes == "slide-1","Cmd+D duplicates selected slide in thumbnail list")
reset()
key("c",8); key("v",9)
check(doc.pres.slides.count == 4 && doc.pres.slides[2].notes == "slide-1","Cmd+C/V copies and pastes selected slide")
reset()
key("\u{7f}",51,[])
check(doc.pres.slides.map(\.notes) == ["slide-0","slide-2"],"Delete removes selected slide from thumbnail list")
reset(IndexSet([0,2]))
check(list.selectedRowIndexes == IndexSet([0,2]),"thumbnail list retains multiple selected slides")
let menu=list.menu(for:rightEvent(list))
check(menu?.items.contains(where:{$0.title.contains("복제")}) == true && menu?.items.contains(where:{$0.title.contains("삭제")}) == true,"thumbnail right-click offers slide commands")
reset()
canvas.selectedID=2; window.makeFirstResponder(canvas)
let shapeMenu=canvas.menu(for:rightEvent(canvas))
check(shapeMenu?.items.contains(where:{$0.title.contains("복사")}) == true,"canvas right-click offers object commands")
NSPasteboard.general.clearContents(); NSPasteboard.general.setString("clipboard must survive duplicate",forType:.string)
action { canvas.duplicateSelection(nil) }
check(NSPasteboard.general.string(forType:.string) == "clipboard must survive duplicate","duplicating object preserves existing clipboard")
reset()
canvas.selectedID=2; window.makeFirstResponder(canvas)
key("d",2)
check(doc.pres.slides.count == 3 && wc.inspectedSlide.shapes.count == 2,"Cmd+D duplicates object when canvas has focus")
reset()
wc.debugRibbon.showTab("전환")
action { wc.ribbonCommand("transition","1"); wc.ribbonCommand("duration","1.0"); wc.previewTransition() }
let overlays=canvas.superview!.subviews.filter {$0 !== canvas}
if let host=overlays.last?.layer,let layers=host.sublayers,let incoming=layers.last {
    print("preview.contents=\(incoming.contents.map {String(describing:type(of:$0))} ?? "nil")")
    check(incoming.contents != nil,"live transition has rendered slide contents")
    spin(0.12); let early=incoming.presentation()?.opacity ?? -1
    spin(0.45); let later=incoming.presentation()?.opacity ?? -1
    print("live preview opacity early=\(early) later=\(later)")
    check(early>=0 && early<later && later<1,"visible preview progresses between different intermediate frames")
} else { check(false,"transition preview creates visible animation layer") }
spin(1.0)
reset()
key("n",45,[.command,.shift])
print("new-slide count after Shift shortcut=\(doc.pres.slides.count)")
check(doc.pres.slides.count == 4,"Cmd+Shift+N inserts a new slide")
key("z",6); check(doc.pres.slides.count == 3,"Cmd+Z undoes slide insertion")
key("z",6,[.command,.shift]); check(doc.pres.slides.count == 4,"Cmd+Shift+Z redoes slide insertion")
func menuItems(_ menu:NSMenu)->[NSMenuItem] { menu.items.flatMap { item in [item]+(item.submenu.map(menuItems) ?? []) } }
reset(IndexSet([0,2])); key("c",8); key("v",9)
check(doc.pres.slides.count == 5 && doc.pres.slides[3].notes == "slide-0" && doc.pres.slides[4].notes == "slide-2","copy/paste retains discontiguous slide order and notes")
check(list.selectedRowIndexes == IndexSet([3,4]),"pasted slides remain selected together")
key("z",6); check(doc.pres.slides.count == 3,"undo removes pasted slides as one action")
reset(); key("a",0); key("\u{7f}",51,[])
check(doc.pres.slides.isEmpty,"Delete can remove all slides")
if doc.pres.slides.isEmpty {
    do { let back=try PPTXReader(zip:ZipReader(data:doc.data(ofType:DocType.pptx))).read(); check(back.slides.isEmpty,"empty document saves and reopens without ghost slide") } catch { check(false,"empty document saves and reopens") }
}
key("v",9); check(!doc.pres.slides.isEmpty,"slides can be pasted into an empty presentation")
reset(); canvas.selectedID=2; window.makeFirstResponder(canvas); canvas.beginEditing(canvas.selected!)
canvas.editor?.setSelectedRange(NSRange(location:0,length:5)); key("c",8)
check(NSPasteboard.general.string(forType:.string) == "slide","Cmd+C in text editing copies text instead of slide")
key("\u{7f}",51,[])
check(doc.pres.slides.count == 3 && canvas.editor?.string == "-1","Delete in text editing changes text instead of slide")
action { canvas.endEditing() }
reset(); doc.pres.slides[1].transition.kind = .fade; doc.pres.slides[1].transition.duration=1.5; wc.reload()
wc.previewTransition(); wc.previewTransition()
check(canvas.superview!.subviews.filter {$0 !== canvas}.count == 1,"repeated preview replaces previous playback")
action { wc.ribbonCommand("transition","0") }
check(canvas.superview!.subviews.filter {$0 !== canvas}.isEmpty,"choosing None cancels active preview immediately")
action { wc.ribbonCommand("transition","1") }; list.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
check(canvas.superview!.subviews.filter {$0 !== canvas}.isEmpty && wc.inspectedSlide.notes == "slide-2","changing slide cancels obsolete transition preview")
// Select through the actual ribbon control, then sample the live presentation tree.
func descendants(_ v:NSView)->[NSView] { [v]+v.subviews.flatMap(descendants) }
reset(); wc.debugRibbon.showTab("전환")
let effectControl=descendants(wc.debugRibbon).first {$0.identifier?.rawValue == "transition"} as! NSPopUpButton
let durationControl=descendants(wc.debugRibbon).first {$0.identifier?.rawValue == "duration"} as! NSComboBox
func selectEffect(_ kind:TransitionKind) {
    effectControl.selectItem(at:TransitionKind.allCases.firstIndex(of:kind)!)
    action { _=effectControl.sendAction(effectControl.action,to:effectControl.target) }
}
durationControl.stringValue="0.6"; action { _=durationControl.sendAction(durationControl.action,to:durationControl.target) }
func liveFrame(_ layer:CALayer)->CGImage? {
    let w=480,h=270
    let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x:CGFloat(w)/layer.bounds.width,y:CGFloat(h)/layer.bounds.height)
    (layer.presentation() ?? layer).render(in:ctx)
    return ctx.makeImage()
}
let strip=CGContext(data:nil,width:480*2,height:270*3,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
var frameRow=0
for kind in TransitionKind.allCases {
    selectEffect(kind)
    check(wc.inspectedSlide.transition.kind == kind,"ribbon selects \(kind.title)")
    if kind == .none {
        check(canvas.superview!.subviews.filter {$0 !== canvas}.isEmpty,"None leaves current slide visible")
        continue
    }
    if kind == .cut {
        if let host=canvas.superview!.subviews.last(where:{$0 !== canvas})?.layer,let incoming=host.sublayers?.last {
            spin(0.04); let a=liveFrame(host)
            check(incoming.isHidden,"Cut preview first displays outgoing slide")
            spin(0.16); let b=liveFrame(host)
            print("Cut preview incomingHidden=\(incoming.isHidden) framesDiffer=\(a?.dataProvider?.data != b?.dataProvider?.data) animations=\(incoming.animationKeys() ?? [])")
            check(!incoming.isHidden && (incoming.animationKeys() ?? []).isEmpty && a?.dataProvider?.data != b?.dataProvider?.data,"Cut preview switches to current slide without blending")
        } else { check(false,"Cut preview visibly switches between previous and current slide") }
        continue
    }
    if let host=canvas.superview!.subviews.last(where:{$0 !== canvas})?.layer {
        spin(0.12); let a=liveFrame(host)
        spin(0.30); let b=liveFrame(host)
        check(a?.dataProvider?.data != b?.dataProvider?.data,"\(kind.title) produces distinct live frames")
        if [.fade,.push,.wipe].contains(kind),let a,let b {
            strip.draw(a,in:CGRect(x:0,y:frameRow*270,width:480,height:270)); strip.draw(b,in:CGRect(x:480,y:frameRow*270,width:480,height:270)); frameRow += 1
        }
    } else { check(false,"\(kind.title) creates playback layer") }
}
if let picture=strip.makeImage(),let data=NSBitmapImageRep(cgImage:picture).representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:"build/interaction-transition.png")) }
selectEffect(.cut)
NSPasteboard.general.clearContents(); NSPasteboard.general.setData(Data("invalid".utf8),forType:SlideWindowController.slidePasteboardType)
window.makeFirstResponder(list); key("v",9)
check(doc.pres.slides.count == 3,"invalid slide clipboard is ignored without recursion")
NSPasteboard.general.setData(try! SlideClipboard.encode(Presentation()),forType:SlideWindowController.slidePasteboardType); key("v",9)
check(doc.pres.slides.count == 3,"empty slide clipboard is ignored without recursion")
let cutShow=Presentation(); cutShow.slides=[Slide(),Slide(),Slide()]
cutShow.slides[1].transition=SlideTransition(kind:.cut,duration:3,advanceAfter:0.1)
let cutPlayer=SlideShowController(pres:cutShow,screen:NSScreen.main!); _=cutPlayer.transitionProbe(from:0)
spin(0.25); check(cutPlayer.index == 2,"Cut auto advance ignores non-existent transition duration"); cutPlayer.end()
let timed=Presentation(); timed.slides=[Slide(),Slide(),Slide()]
timed.slides[1].transition=SlideTransition(kind:.fade,duration:0.7,advanceAfter:0.1)
var effectShape=SlideShape(id:2,kind:.rect,frame:Frame(x:100,y:100,w:100,h:100)); effectShape.fill = .black
timed.slides[1].shapes=[effectShape]; timed.slides[1].animations=[SlideAnimation(shapeID:2,effect:.fade,trigger:.withPrevious,duration:0.3)]
let player=SlideShowController(pres:timed,screen:NSScreen.main!)
_ = player.transitionProbe(from:0)
spin(0.25); check(player.index == 1,"automatic advance waits for transition")
spin(0.55); check(player.index == 1,"automatic advance waits for entrance animation")
spin(0.45); check(player.index == 2,"automatic advance continues after playback and configured delay")
player.end()
let manual=Presentation(); manual.slides=[Slide(),Slide(),Slide()]; manual.slides[1].transition=SlideTransition(kind:.push,duration:0.5)
let manualPlayer=SlideShowController(pres:manual,screen:NSScreen.main!); _=manualPlayer.transitionProbe(from:0); manualPlayer.next()
spin(0.1); check(manualPlayer.index == 1,"next command does not interrupt running transition")
spin(0.55); check(manualPlayer.index == 2,"queued next command runs after transition")
manualPlayer.end()
reset(); doc.pres.slides[1].shapes[0].locked=true; doc.pres.slides[1].shapes[0].sourceIDs=[10,99]; doc.pres.slides[1].shapes[0].wrap=false; wc.reload(); key("c",8); key("v",9)
check(doc.pres.slides[2].shapes[0].locked && doc.pres.slides[2].shapes[0].sourceIDs == [10,99] && !doc.pres.slides[2].shapes[0].wrap,"slide clipboard preserves decoration locks and native shape metadata")
reset(IndexSet(integer:2)); key(String(UnicodeScalar(NSUpArrowFunctionKey)!),126)
check(wc.inspectedSlide.notes == "slide-2" && list.selectedRow == 1,"Cmd+Up moves selected slide and retains selection")
key("z",6); check(wc.inspectedSlide.notes == "slide-2" && list.selectedRow == 2,"undo restores reordered slide selection by identity")
key("z",6,[.command,.shift]); check(wc.inspectedSlide.notes == "slide-2" && list.selectedRow == 1,"redo restores reordered slide selection by identity")
reset(IndexSet([0,2])); key("c",8); key("v",9); key("z",6)
check(list.selectedRowIndexes == IndexSet([0,2]),"undo paste restores original multi-selection")
key("z",6,[.command,.shift]); check(list.selectedRowIndexes == IndexSet([3,4]),"redo paste selects restored pasted slides")
reset(); canvas.selectedID=2; window.makeFirstResponder(canvas)
NSPasteboard.general.clearContents(); NSPasteboard.general.setString("붙여넣은 문장\n두 번째 줄",forType:.string); key("v",9)
check(wc.inspectedSlide.shapes.contains { $0.paragraphs.map(\.plainText).joined(separator:"\n") == "붙여넣은 문장\n두 번째 줄" },"Cmd+V pastes external plain text as a text object")
let png=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX24AAAAASUVORK5CYII=")!
NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png,forType:.png); key("v",9)
check(wc.inspectedSlide.shapes.contains {$0.kind == .image && $0.imageID.flatMap {doc.pres.images[$0]} != nil},"Cmd+V pastes external clipboard image")
reset(); canvas.selectedID=2; window.makeFirstResponder(canvas); key("b",11)
check(wc.inspectedShape?.paragraphs.first?.markProps.bold == true,"Cmd+B formats selected object's text")
key("i",34); check(wc.inspectedShape?.paragraphs.first?.markProps.italic == true,"Cmd+I formats selected object's text")
key("u",32); check(wc.inspectedShape?.paragraphs.first?.markProps.underline == .single,"Cmd+U formats selected object's text")
let backward=Presentation(); backward.slides=[Slide(),Slide(),Slide()]; backward.slides[0].shapes=[effectShape]; backward.slides[0].animations=[SlideAnimation(shapeID:2,effect:.fade,trigger:.withPrevious,duration:0.6)]; backward.slides[0].transition.advanceAfter=0.1
let backwardPlayer=SlideShowController(pres:backward,screen:NSScreen.main!); _=backwardPlayer.transitionProbe(from:0); backwardPlayer.previous()
spin(0.22); check(backwardPlayer.index == 1,"backward navigation schedules one fresh automatic advance")
spin(0.62); check(backwardPlayer.index == 1,"cancelled entrance timer cannot advance a later slide")
backwardPlayer.end()
let sheetDoc=SheetDocument(); dc.addDocument(sheetDoc); sheetDoc.makeWindowControllers(); let sheetWC=sheetDoc.windowControllers.first as! SheetWindowController
let sw=sheetWC.window!,grid=sheetWC.debugGrid
sw.makeKeyAndOrderFront(nil); sw.makeFirstResponder(grid); spin()
let cellPoint=grid.convert(NSPoint(x:grid.rect(CellRef(row:1,col:1)).midX,y:grid.rect(CellRef(row:1,col:1)).midY),to:nil)
let cellEvent=NSEvent.mouseEvent(with:.rightMouseDown,location:cellPoint,modifierFlags:[],timestamp:0,windowNumber:sw.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
let cellMenu=grid.menu(for:cellEvent)
check(cellMenu?.items.contains(where:{$0.title.contains("복사")}) == true && cellMenu?.items.contains(where:{$0.title.contains("행 삽입")}) == true,"spreadsheet cell right-click exposes editing and row commands")
func otherKey(_ w:NSWindow,_ d:NSDocument,_ value:String,_ code:UInt16) {
    app.activate(ignoringOtherApps:true); w.makeKeyAndOrderFront(nil); spin(0.1)
    let e=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:w.windowNumber,context:nil,characters:value,charactersIgnoringModifiers:value,isARepeat:false,keyCode:code)!
    d.undoManager?.beginUndoGrouping(); app.sendEvent(e); d.undoManager?.endUndoGrouping(); spin()
}
sheetDoc.undoManager?.groupsByEvent=false
otherKey(sw,sheetDoc,"b",11); otherKey(sw,sheetDoc,"i",34); otherKey(sw,sheetDoc,"u",32)
let cellStyle=grid.sheet.cells[grid.cursor]?.style
check(cellStyle?.bold == true && cellStyle?.italic == true && cellStyle?.underline == true,"spreadsheet Cmd+B/I/U changes selected cell formatting")
grid.sheet.cells[CellRef(row:0,col:0)]=SheetCell(input:"123")
grid.anchor=CellRef(row:0,col:0); grid.cursor=CellRef(row:1,col:0)
otherKey(sw,sheetDoc,"d",2)
check(grid.sheet.cells[CellRef(row:1,col:0)]?.input == "123","spreadsheet Cmd+D retains fill-down command")
let textDoc=HWDocument(); dc.addDocument(textDoc); textDoc.undoManager?.groupsByEvent=false; textDoc.makeWindowControllers()
let textWC=textDoc.windowControllers.first as! EditorWindowController,tw=textWC.window!,tv=textWC.pages.firstTextView
textDoc.undoManager?.beginUndoGrouping(); tv.insertText("서식 검사",replacementRange:NSRange(location:0,length:0)); textDoc.undoManager?.endUndoGrouping()
tw.makeKeyAndOrderFront(nil); tw.makeFirstResponder(tv); tv.setSelectedRange(NSRange(location:0,length:2))
otherKey(tw,textDoc,"b",11); check(AttributedBridge.charProps(textDoc.textStorage.attributes(at:0,effectiveRange:nil)).bold,"document Cmd+B formats selected text")
otherKey(tw,textDoc,"i",34); check(AttributedBridge.charProps(textDoc.textStorage.attributes(at:0,effectiveRange:nil)).italic,"document Cmd+I formats selected text")
otherKey(tw,textDoc,"u",32); check(AttributedBridge.charProps(textDoc.textStorage.attributes(at:0,effectiveRange:nil)).underline == .single,"document Cmd+U formats selected text")
tw.orderOut(nil)
sw.orderOut(nil)
restoreClipboard()
for w in app.windows { w.orderOut(nil) }
print("RESULT failures=\(failures)")
exit(failures == 0 ? 0 : 1)

}
// Start outside a GCD main-queue block: nested event pumping must allow
// the application's asynchronous preview callbacks to execute.
Timer.scheduledTimer(withTimeInterval:0,repeats:false) { _ in runChecks() }
app.run()
