import AppKit
import UniformTypeIdentifiers

extension DocType {
    static let pptx = "org.openxmlformats.presentationml.presentation"
}

fileprivate struct SlideEditingState {
    var current:Int
    var slides:IndexSet
    var shapes:Set<Int>
    var primary:Int?
    var slideFocus:Bool
}

@objc(SlideDocument)
final class SlideDocument: NSDocument {
    var pres = Presentation.blank()
    private var inPlaceSaveConfirmed = false

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { [DocType.pptx] }
    override class var writableTypes: [String] { [DocType.pptx, DocType.pdf] }
    override class func isNativeType(_ type: String) -> Bool { type == DocType.pptx }

    override func makeWindowControllers() { addWindowController(SlideWindowController(document: self)) }

    override func read(from url: URL, ofType typeName: String) throws {
        do { pres = try SlidesIO.load(url: url) } catch let e as FormatError {
            throw NSError(domain: "HanWord", code: 1, userInfo: [NSLocalizedDescriptionKey: "문서를 열 수 없습니다", NSLocalizedFailureReasonErrorKey: e.description])
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        windowControllers.compactMap { $0 as? SlideWindowController }.forEach { $0.commitTextEditing() }
        return typeName == DocType.pdf ? SlideRenderer.pdf(pres) : PPTXWriter.write(pres)
    }

    override func save(_ sender: Any?) {
        if fileURL != nil && !inPlaceSaveConfirmed { saveAs(sender) } else { super.save(sender) }
    }

    override func save(to url: URL, ofType typeName: String, for op: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: op) { [weak self] e in
            if e == nil && op != .saveToOperation { self?.inPlaceSaveConfirmed = true }
            completionHandler(e)
        }
    }

    override var shouldRunSavePanelWithAccessoryView: Bool { true }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        typeName == DocType.pdf ? "pdf" : typeName == DocType.pptx ? "pptx" : super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
    }

    private struct Snapshot {
        var slides:[Slide],images:[String:ImageData],width:Double,height:Double
        var selections:[ObjectIdentifier:SlideEditingState]
    }
    private func snapshot()->Snapshot {
        let states=windowControllers.compactMap { $0 as? SlideWindowController }.map { (ObjectIdentifier($0),$0.editingState) }
        return Snapshot(slides:pres.slides,images:pres.images,width:pres.width,height:pres.height,selections:Dictionary(uniqueKeysWithValues:states))
    }
    private func restore(_ saved:Snapshot,name:String) {
        let inverse=snapshot()
        pres.slides=saved.slides; pres.images=saved.images; pres.width=saved.width; pres.height=saved.height
        undoManager?.registerUndo(withTarget:self) { $0.restore(inverse,name:name) }
        undoManager?.setActionName(name)
        NotificationCenter.default.post(name:.slidesChanged,object:self,userInfo:["selections":saved.selections])
    }
    /// Preserve both editing data and the selected slide/object through undo.
    func edit(_ name: String, _ change: (Presentation) -> Void) {
        let before=snapshot()
        change(pres)
        undoManager?.registerUndo(withTarget:self) { $0.restore(before,name:name) }
        undoManager?.setActionName(name)
        NotificationCenter.default.post(name: .slidesChanged, object: self)
    }
}

extension Notification.Name { static let slidesChanged = Notification.Name("HanWordSlidesChanged") }

// MARK: - Canvas

protocol SlideCanvasDelegate: AnyObject {
    func canvasDidChange(_ name: String, _ change: (inout Slide) -> Void)
    func canvasPaste(_ source: Presentation)
    func canvasEditTable(_ id:Int)
    func canvasSelectionChanged()
}

/// Editing surface. Its bounds are in slide points, so text editors placed
/// inside scale together with the slide.
final class SlideCanvasView: NSView, NSTextViewDelegate, NSMenuItemValidation {
    weak var delegate: SlideCanvasDelegate?
    var pres: Presentation
    var slide = Slide() { didSet { needsDisplay = true } }
    private var primaryID: Int?
    var selectedIDs: Set<Int> = [] { didSet { needsDisplay=true; delegate?.canvasSelectionChanged() } }
    var selectedID: Int? {
        get { primaryID }
        set { primaryID=newValue; selectedIDs=Set(newValue.map { [$0] } ?? []) }
    }
    func select(_ ids: Set<Int>, primary: Int? = nil) { primaryID=primary.flatMap { ids.contains($0) ? $0 : nil } ?? ids.sorted().first; selectedIDs=ids }
    private var originals: [Int: SlideShape] = [:]
    private var originalRotation: Double = 0
    private var marquee: NSRect?
    private var dragStart: NSPoint?
    private var originalFrame: Frame?
    private var handle: Int?          // 0…7 resize handle, nil = move
    private(set) var editor: NSTextView?
    private var editingID: Int?
    private var initialEditorText: NSAttributedString?
    var onCommand:((String)->Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(pres: Presentation) {
        self.pres = pres
        super.init(frame: NSRect(x: 0, y: 0, width: pres.width, height: pres.height))
        wantsLayer = true
        layer?.shadowOpacity = 0.14; layer?.shadowRadius = 8
    }

    required init?(coder: NSCoder) { fatalError() }

    func fit(in size: NSSize) {
        let s = max(0.05, min((size.width - 60) / CGFloat(pres.width), (size.height - 60) / CGFloat(pres.height)))
        setFrameSize(NSSize(width: CGFloat(pres.width) * s, height: CGFloat(pres.height) * s))
        bounds = NSRect(x: 0, y: 0, width: pres.width, height: pres.height)
        needsDisplay = true
    }

    var selected: SlideShape? { slide.shapes.first { $0.id == selectedID } }

    var showAnimationBadges = true

    override func draw(_ dirtyRect: NSRect) {
        SlideRenderer.draw(slide, pres, hideTextOf: editingID)
        for s in slide.shapes where !s.locked && !s.hasText && s.placeholder != nil && s.id != editingID {
            let r=SlideRenderer.cg(s.frame).insetBy(dx:1,dy:1)
            NSColor.tertiaryLabelColor.setStroke(); let p=NSBezierPath(rect:r); p.lineWidth=scaleFactor; p.setLineDash([5*scaleFactor,4*scaleFactor],count:2,phase:0); p.stroke()
            let hint=s.placeholder == "body" ? "내용을 입력하려면 두 번 클릭하세요" : s.placeholder == "subTitle" ? "부제목을 입력하려면 두 번 클릭하세요" : "제목을 입력하려면 두 번 클릭하세요"
            let text=NSAttributedString(string:hint,attributes:[.font:NSFont.systemFont(ofSize:s.placeholder == "body" ? 20 : 26),.foregroundColor:NSColor.placeholderTextColor])
            text.draw(in:SlideRenderer.textRect(s))
        }
        if showAnimationBadges { drawBadges() }
        for s in slide.shapes where selectedIDs.contains(s.id) {
            let r=SlideRenderer.cg(s.frame)
            NSGraphicsContext.saveGraphicsState()
            let t=NSAffineTransform(); t.translateX(by:r.midX,yBy:r.midY); t.rotate(byDegrees:s.rotation); t.translateX(by:-r.midX,yBy:-r.midY); t.concat()
            NSColor.controlAccentColor.setStroke()
            let p=NSBezierPath(rect:r); p.lineWidth=1.5*scaleFactor; p.stroke()
            if selectedIDs.count == 1 {
                let stem=NSBezierPath(); stem.move(to:NSPoint(x:r.midX,y:r.minY)); stem.line(to:NSPoint(x:r.midX,y:r.minY-28*scaleFactor)); stem.stroke()
                for h in handles(r) {
                    NSColor.white.setFill(); NSColor.controlAccentColor.setStroke()
                    let hp=NSBezierPath(ovalIn:h); hp.fill(); hp.lineWidth=scaleFactor; hp.stroke()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if let r=marquee { NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); r.fill(); NSColor.controlAccentColor.setStroke(); NSBezierPath(rect:r).stroke() }
    }

    private var scaleFactor: CGFloat { bounds.width / max(1, frame.width) }

    /// Numbered tags beside animated shapes, like PowerPoint's animation view.
    private func drawBadges() {
        var step = 0
        var placed: [Int: Int] = [:]
        for a in slide.animations {
            if a.trigger == .onClick { step += 1 }
            guard let s = slide.shapes.first(where: { $0.id == a.shapeID }) else { continue }
            let n = placed[a.shapeID, default: 0]
            placed[a.shapeID] = n + 1
            let k = scaleFactor
            let r = NSRect(x: s.frame.x - 20 * k, y: s.frame.y + Double(n) * 18 * k, width: 17 * k, height: 15 * k)
            NSColor(white: 0.25, alpha: 0.85).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3 * k, yRadius: 3 * k).fill()
            let t = NSAttributedString(string: "\(max(step, 0))", attributes: [.font: NSFont.systemFont(ofSize: 10 * k, weight: .bold), .foregroundColor: NSColor.white])
            let sz = t.size()
            t.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
        }
    }

    private func handles(_ r: NSRect) -> [NSRect] {
        let d = 8 * scaleFactor
        let pts = [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.midX, y: r.minY), NSPoint(x: r.maxX, y: r.minY), NSPoint(x: r.maxX, y: r.midY),
                   NSPoint(x: r.maxX, y: r.maxY), NSPoint(x: r.midX, y: r.maxY), NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.minX, y: r.midY)]
        return (pts + [NSPoint(x:r.midX,y:r.minY-28*scaleFactor)]).map { NSRect(x: $0.x - d / 2, y: $0.y - d / 2, width: d, height: d) }
    }

    private func hit(_ p: NSPoint) -> SlideShape? {
        slide.shapes.reversed().first { s in
            guard !s.locked else { return false }
            let q=ShapeGeometry.local(x:p.x,y:p.y,frame:s.frame,rotation:s.rotation)
            return SlideRenderer.cg(s.frame).insetBy(dx:-4*scaleFactor,dy:-4*scaleFactor).contains(NSPoint(x:q.0,y:q.1))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        endEditing(); window?.makeFirstResponder(self)
        handle=nil; originals=[:]; marquee=nil
        if let s=selected, selectedIDs.count == 1 {
            let q=ShapeGeometry.local(x:p.x,y:p.y,frame:s.frame,rotation:s.rotation)
            handle=handles(SlideRenderer.cg(s.frame)).firstIndex { $0.insetBy(dx:-3*scaleFactor,dy:-3*scaleFactor).contains(NSPoint(x:q.0,y:q.1)) }
        }
        if handle == nil {
            if let s=hit(p) {
                if event.modifierFlags.contains(.shift) {
                    var ids=selectedIDs; if ids.contains(s.id) { ids.remove(s.id) } else { ids.insert(s.id) }; select(ids,primary:ids.contains(s.id) ? s.id : nil)
                } else if !selectedIDs.contains(s.id) { selectedID=s.id }
                if event.clickCount == 2 && s.kind == .table { selectedID=s.id; delegate?.canvasEditTable(s.id); return }
                if event.clickCount == 2 && ![.image,.line,.table].contains(s.kind) { selectedID=s.id; beginEditing(s); return }
            } else { if !event.modifierFlags.contains(.shift) { selectedID=nil }; marquee=NSRect(origin:p,size:.zero) }
        }
        dragStart=p; originalFrame=selected?.frame; originalRotation=selected?.rotation ?? 0
        originals=Dictionary(uniqueKeysWithValues:slide.shapes.filter { selectedIDs.contains($0.id) }.map { ($0.id,$0) })
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start=dragStart else { return }
        let p=convert(event.locationInWindow,from:nil), dx=p.x-start.x, dy=p.y-start.y
        if marquee != nil {
            marquee=NSRect(x:min(start.x,p.x),y:min(start.y,p.y),width:abs(dx),height:abs(dy)); needsDisplay=true; return
        }
        for i in slide.shapes.indices {
            guard let old=originals[slide.shapes[i].id] else { continue }
            if handle == 8 {
                let c=NSPoint(x:old.frame.x+old.frame.w/2,y:old.frame.y+old.frame.h/2)
                let delta=(atan2(p.y-c.y,p.x-c.x)-atan2(start.y-c.y,start.x-c.x))*180 / .pi
                var angle=originalRotation+delta
                if event.modifierFlags.contains(.shift) { angle=(angle/15).rounded()*15 }
                slide.shapes[i].rotation=angle.truncatingRemainder(dividingBy:360)
            } else if let h=handle {
                slide.shapes[i].frame=ShapeGeometry.resized(old.frame,rotation:old.rotation,handle:h,dx:dx,dy:dy,preserveAspect:old.lockAspect || event.modifierFlags.contains(.shift))
            } else {
                var f=old.frame
                if event.modifierFlags.contains(.shift) { f.x += abs(dx)>abs(dy) ? dx : 0; f.y += abs(dy)>=abs(dx) ? dy : 0 }
                else { f.x += dx; f.y += dy }
                slide.shapes[i].frame=f
            }
        }
        needsDisplay=true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart=nil; originals=[:]; marquee=nil; needsDisplay=true }
        guard dragStart != nil else { return }
        if let r=marquee {
            let ids=Set(slide.shapes.filter { !$0.locked && r.intersects(SlideRenderer.cg(ShapeGeometry.bounds($0))) }.map(\.id))
            select(event.modifierFlags.contains(.shift) ? selectedIDs.union(ids) : ids); return
        }
        let changes=slide.shapes.filter { sh in originals[sh.id].map { $0.frame != sh.frame || $0.rotation != sh.rotation } ?? false }
        guard !changes.isEmpty else { return }
        for i in slide.shapes.indices { if let old=originals[slide.shapes[i].id] { slide.shapes[i]=old } }
        delegate?.canvasDidChange(handle == 8 ? "회전" : handle == nil ? "이동" : "크기 조절") { sl in
            for sh in changes { if let i=sl.shapes.firstIndex(where:{$0.id == sh.id}) { sl.shapes[i].frame=sh.frame; sl.shapes[i].rotation=sh.rotation } }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { endEditing(); selectedID=nil; return }
        if event.keyCode == 48 {
            let ids=slide.shapes.filter { !$0.locked }.map(\.id)
            if !ids.isEmpty { let old=selectedID.flatMap { ids.firstIndex(of:$0) } ?? (event.modifierFlags.contains(.shift) ? 0 : -1); selectedID=ids[(old+(event.modifierFlags.contains(.shift) ? -1 : 1)+ids.count)%ids.count] }
            return
        }
        if selected == nil,[123,124,125,126].contains(event.keyCode) { onCommand?([123,126].contains(event.keyCode) ? "previousSlide" : "nextSlide"); return }
        guard let s = selected else { super.keyDown(with: event); return }
        let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        var d: (Double, Double)?
        switch event.keyCode {
        case 51, 117: deleteSelection(nil); return
        case 123: d = (-step, 0)
        case 124: d = (step, 0)
        case 125: d = (0, step)
        case 126: d = (0, -step)
        case 36, 76: if s.kind == .table { delegate?.canvasEditTable(s.id); return }; if s.kind != .image && s.kind != .line && s.kind != .table { beginEditing(s) }; return
        default: super.keyDown(with: event); return
        }
        if let d {
            let ids=selectedIDs
            delegate?.canvasDidChange("이동") { sl in
                for i in sl.shapes.indices where ids.contains(sl.shapes[i].id) { sl.shapes[i].frame.x += d.0; sl.shapes[i].frame.y += d.1 }
            }
        }
    }

    @objc func deleteSelection(_ sender: Any?) {
        endEditing()
        let ids=selectedIDs
        guard !ids.isEmpty else { return }
        delegate?.canvasDidChange("삭제") { sl in sl.shapes.removeAll { ids.contains($0.id) }; sl.animations.removeAll { ids.contains($0.shapeID) } }
        selectedID = nil
    }

    @objc func delete(_ sender: Any?) { deleteSelection(sender) }

    override func selectAll(_ sender: Any?) { endEditing(); select(Set(slide.shapes.filter { !$0.locked }.map(\.id))) }
    static let shapePasteboardType=NSPasteboard.PasteboardType("org.hanword.slide-shapes")
    private func selectionPresentation()->Presentation? {
        endEditing(); guard !selectedIDs.isEmpty else { return nil }
        let p=Presentation(); p.width=pres.width; p.height=pres.height; p.images=pres.images
        var s=Slide(); s.shapes=slide.shapes.filter { selectedIDs.contains($0.id) }; s.animations=slide.animations.filter { selectedIDs.contains($0.shapeID) }; p.slides=[s]
        return p
    }
    @objc func copy(_ sender: Any?) {
        _=copySelection()
    }
    private func copySelection()->Bool {
        guard let p=selectionPresentation(),let data=try? SlideClipboard.encode(p) else { return false }
        NSPasteboard.general.clearContents(); return NSPasteboard.general.setData(data,forType:Self.shapePasteboardType)
    }
    @objc func cut(_ sender: Any?) { if copySelection() { deleteSelection(sender) } }
    @objc func paste(_ sender: Any?) {
        endEditing()
        let board=NSPasteboard.general
        if let data=board.data(forType:Self.shapePasteboardType),let source=SlideClipboard.decode(data) { delegate?.canvasPaste(source); return }
        if board.data(forType:SlideWindowController.slidePasteboardType) != nil { onCommand?("pasteSlides"); return }
        let source=Presentation(); source.width=pres.width; source.height=pres.height
        var shape:SlideShape
        if let image=NSImage(pasteboard:board),image.size.width>0,image.size.height>0,let data=board.data(forType:.png) ?? image.tiffRepresentation {
            let png=board.data(forType:.png) != nil
            let id="clipboard/\(UUID().uuidString)",name=png ? "clipboard.png" : "clipboard.tiff"
            source.images[id]=ImageData(name:name,data:data)
            let k=min(1,pres.width*0.6/image.size.width,pres.height*0.6/image.size.height)
            let w=image.size.width*k,h=image.size.height*k
            shape=SlideShape(id:2,name:"붙여넣은 그림",kind:.image,frame:Frame(x:(pres.width-w)/2,y:(pres.height-h)/2,w:w,h:h)); shape.imageID=id; shape.lockAspect=true
        } else {
            var paragraphs:[Paragraph]?
            if let data=board.data(forType:.rtf),let attributed=try? NSAttributedString(data:data,options:[.documentType:NSAttributedString.DocumentType.rtf],documentAttributes:nil) { paragraphs=SlideText.paragraphs(attributed) }
            if paragraphs == nil,let text=board.string(forType:.string),!text.isEmpty { paragraphs=text.components(separatedBy:"\n").map { Presentation.textParagraph($0,size:24) } }
            guard let paragraphs else { return }
            shape=SlideShape(id:2,name:"붙여넣은 텍스트",kind:.text,frame:Frame(x:pres.width*0.2,y:pres.height*0.3,w:pres.width*0.6,h:pres.height*0.4)); shape.paragraphs=paragraphs
        }
        source.slides=[Slide(shapes:[shape])]; delegate?.canvasPaste(source)
    }
    @objc func duplicateSelection(_ sender: Any?) { if let source=selectionPresentation() { delegate?.canvasPaste(source) } }
    @objc func duplicate(_ sender:Any?) { duplicateSelection(sender) }
    @objc func toggleBoldface(_ sender:Any?) { onCommand?("bold") }
    @objc func toggleItalics(_ sender:Any?) { onCommand?("italic") }
    @objc func underline(_ sender:Any?) { onCommand?("underline") }
    static var canPaste:Bool {
        let types=NSPasteboard.general.types ?? []
        return types.contains(shapePasteboardType) || types.contains(SlideWindowController.slidePasteboardType) || types.contains(.string) || types.contains(.rtf) || NSImage.canInit(with:NSPasteboard.general)
    }

    override func menu(for event:NSEvent)->NSMenu? {
        endEditing(); window?.makeFirstResponder(self)
        if let shape=hit(convert(event.locationInWindow,from:nil)) { if !selectedIDs.contains(shape.id) { selectedID=shape.id } }
        else { selectedID=nil }
        let menu=NSMenu(title:"개체")
        for (title,action,key) in [("잘라내기",#selector(cut(_:)),"x"),("복사",#selector(copy(_:)),"c"),("붙여넣기",#selector(paste(_:)),"v"),("복제",#selector(duplicate(_:)),"d"),("삭제",#selector(delete(_:)),"")] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:key); item.target=self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let all=NSMenuItem(title:"모든 개체 선택",action:#selector(selectAll(_:)),keyEquivalent:"a"); all.target=self; menu.addItem(all)
        return menu
    }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if item.action == #selector(duplicate(_:)) { item.title="복제" }
        if item.action == #selector(paste(_:)) { return Self.canPaste }
        if item.action == #selector(selectAll(_:)) { return slide.shapes.contains { !$0.locked } }
        return !selectedIDs.isEmpty
    }

    // MARK: Text editing

    func beginEditing(_ s: SlideShape) {
        endEditing()
        let r = SlideRenderer.textRect(s)
        let tv = NSTextView(frame: r)
        tv.isRichText = true
        tv.allowsUndo = true
        tv.usesFontPanel = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.delegate = self
        var paras = s.paragraphs
        if paras.isEmpty { paras = [Presentation.textParagraph("", size: 18)] }
        let text = SlideText.attributed(paras, scale: s.autofitScale)
        tv.textStorage?.setAttributedString(text)
        if text.length == 0 { tv.typingAttributes = AttributedBridge.charAttributes(paras[0].markProps, eastAsian: true) }
        initialEditorText=NSAttributedString(attributedString:tv.textStorage ?? NSTextStorage())
        addSubview(tv)
        editor = tv
        editingID = s.id
        window?.makeFirstResponder(tv)
        tv.selectAll(nil)
        needsDisplay = true
    }

    func endEditing() {
        guard let tv = editor, let id = editingID else { return }
        editor = nil; editingID = nil
        let changed = !(initialEditorText?.isEqual(to:tv.textStorage ?? NSTextStorage()) ?? false)
        initialEditorText=nil
        let paras = SlideText.paragraphs(tv.textStorage ?? NSTextStorage())
        tv.removeFromSuperview()
        if !changed { needsDisplay=true; return }
        delegate?.canvasDidChange("텍스트 편집") { sl in
            if let i = sl.shapes.firstIndex(where: { $0.id == id }) { sl.shapes[i].paragraphs = paras; sl.shapes[i].autofitScale = 1 }
        }
        needsDisplay = true
    }

    fileprivate func discardTextEditing() {
        let old=editor; editor=nil; editingID=nil; initialEditorText=nil
        if window?.firstResponder === old { window?.makeFirstResponder(self) }
        old?.removeFromSuperview(); needsDisplay=true
    }

    func textDidEndEditing(_ notification: Notification) { endEditing() }
    func textViewDidChangeSelection(_ notification: Notification) { delegate?.canvasSelectionChanged() }

    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { endEditing(); window?.makeFirstResponder(self); return true }
        return false
    }
}

final class SlideShowWindow: NSWindow {
    var onKey: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func mouseDown(with event: NSEvent) { onKey?(event) }
    override func rightMouseDown(with event: NSEvent) { onKey?(event) }
}

// MARK: - Window

final class SlideWindowController: NSWindowController, SlideCanvasDelegate, SlideInspectorHost, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate, NSWindowDelegate, NSMenuItemValidation {
    private unowned let doc: SlideDocument
    private let list = SlideNavigatorView()
    private var canvas: SlideCanvasView!
    private let stage = HWSurfaceView()
    private var current = 0
    private var show: SlideShowWindow?
    private let notes = HWTextField()
    private var ribbon: OfficeRibbon!
    private var tableEditor:SlideTableEditor?
    private let inspector = SlideInspector(frame: .zero)
    private var slideSelection=IndexSet(integer:0)
    private var reloading=false
    private var slideFocus=true
    private var transitionPreview:NSView?

    init(document: SlideDocument) {
        doc = document
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 700, height: 480)
        w.tabbingMode = .preferred
        HWTheme.style(w)
        super.init(window: w)
        w.delegate = self
        build()
        w.center()
        NotificationCenter.default.addObserver(self, selector: #selector(reload(_:)), name: .slidesChanged, object: document)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String { "\(displayName)  프레젠테이션" }

    private func build() {
        guard let content = window?.contentView else { return }
        let W = content.bounds.width, H = content.bounds.height - OfficeRibbon.height, side: CGFloat = 200, notesH: CGFloat = 60, inspW: CGFloat = 272

        buildRibbon(in:content)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: side, height: H))
        scroll.autoresizingMask = [.height]
        scroll.hasVerticalScroller = true
        let col = NSTableColumn(identifier: .init("slide"))
        col.width = side - 20
        list.addTableColumn(col)
        list.headerView = nil
        list.rowHeight = (side - 50) * CGFloat(doc.pres.height / doc.pres.width) + 16
        list.dataSource = self
        list.delegate = self
        list.allowsMultipleSelection=true
        list.registerForDraggedTypes([Self.slideReorderType])
        list.onFocus={ [weak self] in self?.slideFocus=true; self?.canvas?.endEditing(); self?.canvas?.selectedID=nil }
        list.onCommand={ [weak self] command in self?.slideCommand(command) }
        list.canCommand={ [weak self] _ in (self?.canPasteSlides ?? false) || SlideCanvasView.canPaste }
        list.contextMenu={ [weak self] _ in self?.slideContextMenu() }
        list.style = .plain
        list.backgroundColor=HWTheme.toolbar
        list.selectionHighlightStyle = .regular
        list.intercellSpacing=NSSize(width:0,height:8)
        scroll.documentView = list
        content.addSubview(scroll)

        stage.frame = NSRect(x: side, y: notesH, width: W - side - inspW, height: H - notesH)
        stage.autoresizingMask = [.width, .height]
        stage.wantsLayer = true
        stage.fill=HWTheme.canvas
        content.addSubview(stage)
        canvas = SlideCanvasView(pres: doc.pres)
        canvas.delegate = self
        canvas.onCommand={ [weak self] command in self?.slideCommand(command) }
        stage.addSubview(canvas)
        stage.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(layoutCanvas), name: NSView.frameDidChangeNotification, object: stage)

        inspector.frame = NSRect(x: W - inspW, y: 0, width: inspW, height: H)
        inspector.autoresizingMask = [.minXMargin, .height]
        inspector.host = self
        content.addSubview(inspector)

        notes.frame = NSRect(x: side + 8, y: 6, width: W - side - inspW - 16, height: notesH - 12)
        notes.autoresizingMask = [.width]
        notes.placeholderString = "슬라이드 노트"
        notes.target = self
        notes.action = #selector(notesChanged(_:))
        content.addSubview(notes)

        let tb = NSToolbar(identifier: "SlidesToolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        window?.toolbar = tb
        window?.toolbarStyle = .unifiedCompact
        reload()
    }

    @objc private func layoutCanvas() {
        cancelTransitionPreview()
        canvas.fit(in: stage.bounds.size)
        canvas.setFrameOrigin(NSPoint(x: (stage.bounds.width - canvas.frame.width) / 2, y: (stage.bounds.height - canvas.frame.height) / 2))
    }

    fileprivate var editingState:SlideEditingState {
        let focus=window?.firstResponder === list ? true : window?.firstResponder === canvas || canvas.editor != nil ? false : slideFocus
        return SlideEditingState(current:current,slides:slideSelection,shapes:canvas.selectedIDs,primary:canvas.selectedID,slideFocus:focus)
    }
    @objc func reload(_ notification:Notification?=nil) {
        guard !reloading else { return }; reloading=true; defer { reloading=false }
        let saved=(notification?.userInfo?["selections"] as? [ObjectIdentifier:SlideEditingState])?[ObjectIdentifier(self)]
        if let saved {
            canvas.discardTextEditing(); current=saved.current; slideSelection=saved.slides; slideFocus=saved.slideFocus
        }
        cancelTransitionPreview()
        current = max(0, min(current, doc.pres.slides.count - 1))
        canvas.pres = doc.pres
        canvas.slide = doc.pres.slides.indices.contains(current) ? doc.pres.slides[current] : Slide()
        canvas.isHidden=doc.pres.slides.isEmpty
        if let id = canvas.selectedID, !canvas.slide.shapes.contains(where: { $0.id == id }) { canvas.selectedID = nil }
        notes.stringValue = canvas.slide.notes
        list.reloadData()
        slideSelection=IndexSet(slideSelection.filter { doc.pres.slides.indices.contains($0) })
        if slideSelection.isEmpty,!doc.pres.slides.isEmpty { slideSelection=IndexSet(integer:current) }
        list.selectRowIndexes(slideSelection, byExtendingSelection: false)
        notes.isEnabled = !doc.pres.slides.isEmpty
        if let saved {
            canvas.select(saved.shapes.intersection(Set(canvas.slide.shapes.filter { !$0.locked }.map(\.id))),primary:saved.primary)
            window?.makeFirstResponder(saved.slideFocus ? list : canvas)
        }
        layoutCanvas()
        inspector.refresh(); reflectRibbon()
    }

    // MARK: Canvas delegate

    func canvasDidChange(_ name: String, _ change: (inout Slide) -> Void) {
        let idx = current
        guard doc.pres.slides.indices.contains(idx) else { return }
        var s = doc.pres.slides[idx]
        change(&s)
        doc.edit(name) { $0.slides[idx] = s }
    }

    func canvasPaste(_ source: Presentation) {
        canvas.endEditing()
        guard let slide=source.slides.first else { return }
        if doc.pres.slides.isEmpty { newSlide(nil) }
        var incoming=slide.shapes, mapping:[Int:Int]=[:], next=doc.pres.nextID(inspectedSlide)
        var images:[String:ImageData]=[:], imageMap:[String:String]=[:]
        for (key,image) in source.images { let target="paste/\(UUID().uuidString)/\(image.name)"; images[target]=image; imageMap[key]=target }
        incoming=SlideClipboard.remappingMedia([slide],ids:imageMap)[0].shapes
        for i in incoming.indices { mapping[incoming[i].id]=next; incoming[i].id=next; next += 1; incoming[i].frame.x += 18; incoming[i].frame.y += 18 }
        let animations=slide.animations.compactMap { a -> SlideAnimation? in guard let id=mapping[a.shapeID] else { return nil }; var b=a; b.shapeID=id; return b }
        let index=current
        doc.edit("붙이기") { p in
            p.images.merge(images) { _,new in new }; p.slides[index].shapes += incoming; p.slides[index].animations += animations
        }
        canvas.select(Set(incoming.map(\.id))); window?.makeFirstResponder(canvas)
    }
    func canvasEditTable(_ id:Int) {
        canvas.endEditing()
        guard let window,let shape=inspectedSlide.shapes.first(where:{$0.id == id}),let table=shape.table else { return }
        let index=current
        let editor=SlideTableEditor(table:table,parent:window) { [weak self] result in
            guard let self else { return }; self.tableEditor=nil
            if let result { self.doc.edit("표 내용") { p in if p.slides.indices.contains(index),let i=p.slides[index].shapes.firstIndex(where:{$0.id == id}) { p.slides[index].shapes[i].table=result } } }
        }
        tableEditor=editor; editor.present()
    }
    func canvasSelectionChanged() { if window?.firstResponder === canvas { slideFocus=false }; inspector.refresh(); reflectRibbon() }

    // MARK: Inspector host

    var inspectedSlide: Slide { doc.pres.slides.indices.contains(current) ? doc.pres.slides[current] : Slide() }
    var inspectedShape: SlideShape? { canvas.selected }
    var activeTextView: NSTextView? { canvas.editor }
    var presentation: Presentation { doc.pres }
    func resizePresentation(width: Double, height: Double) {
        canvas.endEditing(); let sx=width/doc.pres.width, sy=height/doc.pres.height
        doc.edit("슬라이드 크기") { p in
            p.width=width; p.height=height
            for i in p.slides.indices { for j in p.slides[i].shapes.indices { let f=p.slides[i].shapes[j].frame; p.slides[i].shapes[j].frame=Frame(x:f.x*sx,y:f.y*sy,w:f.w*sx,h:f.h*sy) } }
        }
    }

    func modifyShape(_ name: String, _ change: (inout SlideShape) -> Void) {
        let ids=canvas.selectedIDs
        guard !ids.isEmpty else { return }
        canvasDidChange(name) { sl in
            for i in sl.shapes.indices where ids.contains(sl.shapes[i].id) { change(&sl.shapes[i]) }
        }
    }

    func modifySlide(_ name: String, _ change: (inout Slide) -> Void) { canvasDidChange(name, change) }

    func modifyAllSlides(_ name: String, _ change: (inout Slide) -> Void) {
        var slides = doc.pres.slides
        for i in slides.indices { change(&slides[i]) }
        doc.edit(name) { $0.slides = slides }
    }

    func selectShape(_ id: Int) { canvas.endEditing(); canvas.selectedID = id }
    func previewFromCurrent() { playFromCurrent(nil) }
    func commitTextEditing() { canvas.endEditing() }

    /// Plays the current slide's transition over the canvas, from the
    /// previous slide (or black for the first), like PowerPoint's preview.
    func previewTransition() {
        cancelTransitionPreview()
        guard doc.pres.slides.indices.contains(current) else { return }
        let slide = doc.pres.slides[current]
        guard slide.transition.kind != .none else { return }
        let size = canvas.frame.size
        let overlay = NSView(frame: canvas.frame)
        overlay.identifier=NSUserInterfaceItemIdentifier("transitionPreview")
        transitionPreview=overlay
        let host = CALayer()
        host.frame = CGRect(origin: .zero, size: size)
        host.masksToBounds = true
        host.backgroundColor = NSColor.black.cgColor
        overlay.layer = host
        overlay.wantsLayer = true
        stage.addSubview(overlay)
        func layer(_ s: Slide?) -> CALayer {
            let l = CALayer()
            l.frame = host.bounds
            if let s { l.contents = SlideRenderer.cgImage(s, doc.pres, width: size.width * 2) }
            else { l.backgroundColor = NSColor.black.cgColor }
            l.contentsGravity = .resize
            return l
        }
        let old = layer(current > 0 ? doc.pres.slides[current - 1] : nil)
        let new = layer(slide)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.addSublayer(old)
        host.addSublayer(new)
        if slide.transition.kind == .cut { new.isHidden=true }
        CATransaction.commit()
        if slide.transition.kind == .cut {
            // A cut has no animated frames. Briefly show its source in the
            // editor so replaying an already selected slide is still visible.
            DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { [weak self,weak overlay] in
                guard let self,let overlay,self.transitionPreview === overlay else { return }
                CATransaction.begin(); CATransaction.setDisableActions(true)
                new.isHidden=false
                CATransaction.commit()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { [weak self,weak overlay] in
                    guard let self,let overlay,self.transitionPreview === overlay else { return }
                    overlay.removeFromSuperview(); self.transitionPreview=nil
                }
            }
            return
        }
        TransitionAnimator.animate(slide.transition, from: old, to: new, in: host, bounds: host.bounds) { [weak self,weak overlay] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self,weak overlay] in
                guard let overlay else { return }; overlay.removeFromSuperview()
                if self?.transitionPreview === overlay { self?.transitionPreview=nil }
            }
        }
    }

    private func cancelTransitionPreview() {
        func stop(_ layer:CALayer) { layer.removeAllAnimations(); if let mask=layer.mask { stop(mask) }; layer.sublayers?.forEach(stop) }
        if let layer=transitionPreview?.layer { stop(layer) }
        transitionPreview?.removeFromSuperview(); transitionPreview=nil
    }

    func addImageBackground() {
        guard !doc.pres.slides.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window!) { [weak self] r in
            guard r == .OK, let url = panel.url, let data = try? Data(contentsOf: url), let self else { return }
            let key = "background/\(UUID().uuidString)/\(url.lastPathComponent)"
            let idx = self.current
            self.doc.edit("배경 그림") { p in p.images[key] = ImageData(name: url.lastPathComponent, data: data); p.slides[idx].backgroundImage = key }
        }
    }

    @objc func showAnimations(_ s: Any?) { inspector.showAnimationTab() }

    /// Snapshot/test hook: select slide/shape and inspector tab.
    func debugSelect(slide: Int, shape: Int, animationTab: Bool) {
        current = slide; slideSelection=IndexSet(integer:slide); reload()
        let editable = doc.pres.slides[slide].shapes.filter { !$0.locked }
        if shape < editable.count { canvas.selectedID = editable[shape].id }
        if animationTab { inspector.showAnimationTab() }
    }

    @objc private func notesChanged(_ f: NSTextField) {
        let v = f.stringValue
        canvasDidChange("노트") { $0.notes = v }
    }

    // MARK: Slide list

    func numberOfRows(in tableView: NSTableView) -> Int { doc.pres.slides.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let v = NSView()
        let num = NSTextField(labelWithString: "\(row + 1)")
        num.frame = NSRect(x: 2, y: 4, width: 22, height: 16)
        num.font = .systemFont(ofSize: 11)
        num.textColor = .secondaryLabelColor
        let w = (tableColumn?.width ?? 180) - 30
        let iv = NSImageView(image: SlideRenderer.image(doc.pres.slides[row], doc.pres, width: w * 2))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.frame = NSRect(x: 26, y: 6, width: w, height: tableView.rowHeight - 12)
        iv.wantsLayer = true
        iv.layer?.borderWidth = 0.5
        iv.layer?.borderColor = NSColor.gray.cgColor
        v.addSubview(num); v.addSubview(iv)
        let slide = doc.pres.slides[row]
        if slide.transition.kind != .none || !slide.animations.isEmpty {
            // ✦ marks slides with transitions or animations, as in PowerPoint.
            let mark = NSImageView(image: NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "효과")!)
            mark.contentTintColor = .secondaryLabelColor
            mark.frame = NSRect(x: 4, y: 24, width: 16, height: 16)
            mark.toolTip = [slide.transition.kind != .none ? "전환: \(slide.transition.kind.title)" : nil,
                            slide.animations.isEmpty ? nil : "애니메이션 \(slide.animations.count)개"].compactMap { $0 }.joined(separator: ", ")
            v.addSubview(mark)
        }
        return v
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading else { return }
        let selected=list.selectedRowIndexes
        guard let first=selected.first else { return }
        let target=selected.contains(list.clickedRow) ? list.clickedRow : selected.contains(current) ? current : first
        canvas.endEditing()
        current = target
        slideSelection=selected; slideFocus=true
        canvas.selectedID = nil
        reload()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item=NSPasteboardItem(); item.setString(String(row),forType:Self.slideReorderType); return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        op == .above && info.draggingSource as AnyObject? === list && (0...doc.pres.slides.count).contains(row) ? .move : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard dropOperation == .above,info.draggingSource as AnyObject? === list,(0...doc.pres.slides.count).contains(row) else { return false }
        let indices=Set((info.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType:Self.slideReorderType).flatMap(Int.init) })
        guard !indices.isEmpty,indices.allSatisfy({doc.pres.slides.indices.contains($0)}) else { return false }
        canvas.endEditing()
        let slides=indices.sorted().map { doc.pres.slides[$0] },to=row-indices.filter { $0<row }.count
        doc.edit("슬라이드 이동") { p in
            for i in indices.sorted().reversed() { p.slides.remove(at:i) }
            p.slides.insert(contentsOf:slides,at:to)
        }
        selectSlides(IndexSet(integersIn:to..<(to+slides.count)))
        return true
    }

    // MARK: Commands

    @objc func newSlide(_ s: Any?) {
        canvas.endEditing()
        let at = doc.pres.slides.isEmpty ? 0 : (slideSelection.last ?? current)+1
        doc.edit("새 슬라이드") { p in p.slides.insert(p.contentSlide(), at: min(at, p.slides.count)) }
        selectSlides(IndexSet(integer:at))
    }

    @objc func duplicateSlide(_ s: Any?) {
        canvas.endEditing()
        let indices=selectedSlides, copies=indices.map { doc.pres.slides[$0] }
        guard let last=indices.last else { return }; let at=last+1
        doc.edit("슬라이드 복제") { p in p.slides.insert(contentsOf:copies,at:at) }
        selectSlides(IndexSet(integersIn:at..<(at+copies.count)))
    }

    @objc func deleteSlide(_ s: Any?) {
        canvas.endEditing()
        let indices=selectedSlides; guard let first=indices.first else { return }
        doc.edit("슬라이드 삭제") { p in for i in indices.reversed() { p.slides.remove(at:i) } }
        selectSlides(doc.pres.slides.isEmpty ? [] : IndexSet(integer:min(first,doc.pres.slides.count-1)))
    }

    private func add(_ shape: SlideShape, edit: Bool = false) {
        canvas.endEditing()
        if doc.pres.slides.isEmpty { newSlide(nil) }
        var sh = shape
        sh.id = doc.pres.nextID(doc.pres.slides[current])
        canvasDidChange("삽입") { $0.shapes.append(sh) }
        canvas.selectedID = sh.id
        if edit, let s = canvas.selected { canvas.beginEditing(s) }
    }

    private var center: (Double, Double) { (doc.pres.width / 2, doc.pres.height / 2) }

    @objc func insertTextBox(_ s: Any?) {
        var sh = SlideShape(name: "텍스트 상자", kind: .text, frame: Frame(x: center.0 - 200, y: center.1 - 40, w: 400, h: 80))
        sh.paragraphs = [Presentation.textParagraph("", size: 24)]
        add(sh, edit: true)
    }

    private func shape(_ kind: ShapeKind, _ name: String) {
        var sh = SlideShape(name: name, kind: kind, frame: Frame(x: center.0 - 120, y: center.1 - 80, w: 240, h: 160))
        sh.fill = RGB(r: 68, g: 114, b: 196)
        sh.line = RGB(r: 47, g: 82, b: 143)
        sh.anchor = .center
        sh.paragraphs = [Presentation.textParagraph("", size: 18, align: .center, color: RGB(r: 255, g: 255, b: 255))]
        add(sh)
    }

    @objc func insertRect(_ s: Any?) { shape(.rect, "사각형") }
    @objc func insertRoundRect(_ s: Any?) { shape(.roundRect, "둥근 사각형") }
    @objc func insertEllipse(_ s: Any?) { shape(.ellipse, "타원") }
    @objc func insertTriangle(_ s: Any?) { shape(.triangle, "삼각형") }
    @objc func insertArrow(_ s: Any?) { shape(.rightArrow, "화살표") }
    @objc func insertLine(_ s: Any?) {
        var sh = SlideShape(name: "선", kind: .line, frame: Frame(x: center.0 - 150, y: center.1, w: 300, h: 0.01))
        sh.line = .black; sh.lineWidth = 2
        add(sh)
    }

    @objc func insertTable(_ s: Any?) {
        var t = Table()
        t.columnWidths = [160, 160, 160]
        t.rows = (0..<3).map { r in (0..<3).map { _ in TableCell(blocks: [.paragraph(Presentation.textParagraph("", size: 16, bold: r == 0))]) } }
        var sh = SlideShape(name: "표", kind: .table, frame: Frame(x: center.0 - 240, y: center.1 - 60, w: 480, h: 120))
        sh.table = t
        sh.tableRowHeights = [40, 40, 40]
        add(sh)
    }

    @objc func insertImage(_ s: Any?) {
        if doc.pres.slides.isEmpty { newSlide(nil) }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window!) { [weak self] r in
            guard r == .OK, let url = panel.url, let data = try? Data(contentsOf: url), let self, let img = NSImage(data: data) else { return }
            let key = "insert/\(UUID().uuidString)/\(url.lastPathComponent)"
            var w = Double(img.size.width), h = Double(img.size.height)
            let maxW = self.doc.pres.width * 0.6, maxH = self.doc.pres.height * 0.6
            let k = min(1, maxW / w, maxH / h); w *= k; h *= k
            var sh = SlideShape(name: url.lastPathComponent, kind: .image, frame: Frame(x: self.center.0 - w / 2, y: self.center.1 - h / 2, w: w, h: h))
            sh.imageID = key
            sh.lockAspect=true
            self.canvas.endEditing()
            sh.id = self.doc.pres.nextID(self.doc.pres.slides[self.current])
            let idx = self.current
            self.doc.edit("그림 넣기") { p in p.images[key] = ImageData(name: url.lastPathComponent, data: data); p.slides[idx].shapes.append(sh) }
            self.canvas.selectedID = sh.id
        }
    }

    @objc func bringForward(_ s: Any?) {
        guard let id = canvas.selectedID else { return }
        canvasDidChange("앞으로") { sl in
            if let i = sl.shapes.firstIndex(where: { $0.id == id }), i < sl.shapes.count - 1 { sl.shapes.swapAt(i, i + 1) }
        }
    }

    @objc func sendBackward(_ s: Any?) {
        guard let id = canvas.selectedID else { return }
        canvasDidChange("뒤로") { sl in
            if let i = sl.shapes.firstIndex(where: { $0.id == id }), i > 0, !sl.shapes[i - 1].locked { sl.shapes.swapAt(i, i - 1) }
        }
    }

    @objc func fillColor(_ s: Any?) {
        NSColorPanel.shared.setTarget(self); NSColorPanel.shared.setAction(#selector(applyColor(_:)))
        NSColorPanel.shared.orderFront(nil)
    }

    @objc private func applyColor(_ p: NSColorPanel) {
        guard let id = canvas.selectedID else {
            let c = p.color.usingColorSpace(.sRGB) ?? p.color
            let rgb = RGB(r: UInt8(c.redComponent * 255), g: UInt8(c.greenComponent * 255), b: UInt8(c.blueComponent * 255))
            canvasDidChange("배경") { $0.background = rgb; $0.backgroundImage = nil }
            return
        }
        let c = p.color.usingColorSpace(.sRGB) ?? p.color
        let rgb = RGB(r: UInt8(c.redComponent * 255), g: UInt8(c.greenComponent * 255), b: UInt8(c.blueComponent * 255))
        canvasDidChange("색") { sl in
            guard let i = sl.shapes.firstIndex(where: { $0.id == id }) else { return }
            if sl.shapes[i].kind == .line { sl.shapes[i].line = rgb }
            else { sl.shapes[i].fill = rgb; if sl.shapes[i].kind == .text { sl.shapes[i].kind = .rect } }
        }
    }

    // MARK: Slide show

    private var showController: SlideShowController?

    override func selectAll(_ sender:Any?) { if slideFocus { list.selectAll(sender) } else { canvas.selectAll(sender) } }

    @objc func playSlideShow(_ s: Any?) { startShow(at: 0) }
    @objc func playFromCurrent(_ s: Any?) { startShow(at: current) }

    private func startShow(at index: Int) {
        canvas.endEditing()
        cancelTransitionPreview()
        guard doc.pres.slides.indices.contains(index) else { return }
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let c = SlideShowController(pres: doc.pres, screen: screen)
        c.onEnd = { [weak self] last in
            self?.current = last
            self?.showController = nil
            self?.reload()
        }
        showController = c
        c.start(at: index)
    }

    // MARK: Toolbar

    private let toolItems: [(String, String, String, Selector)] = [
        ("newslide", "새 슬라이드", "plus.rectangle.on.rectangle", #selector(newSlide(_:))),
        ("text", "텍스트", "textbox", #selector(insertTextBox(_:))),
        ("rect", "사각형", "rectangle", #selector(insertRect(_:))),
        ("ellipse", "타원", "circle", #selector(insertEllipse(_:))),
        ("arrow", "화살표", "arrow.right", #selector(insertArrow(_:))),
        ("line", "선", "line.diagonal", #selector(insertLine(_:))),
        ("table", "표", "tablecells", #selector(insertTable(_:))),
        ("image", "그림", "photo", #selector(insertImage(_:))),
        ("color", "색", "paintpalette", #selector(fillColor(_:))),
        ("front", "앞으로", "square.2.layers.3d.top.filled", #selector(bringForward(_:))),
        ("back", "뒤로", "square.2.layers.3d.bottom.filled", #selector(sendBackward(_:))),
        ("delete", "삭제", "trash", #selector(SlideCanvasView.deleteSelection(_:))),
        ("anim", "애니메이션", "rectangle.stack", #selector(showAnimations(_:))),
        ("play", "슬라이드 쇼", "play.rectangle.fill", #selector(playSlideShow(_:))),
    ]

    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.init("newslide"),.flexibleSpace,.init("anim"),.init("play")]
    }

    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolItems.map { NSToolbarItem.Identifier($0.0) } + [.space, .flexibleSpace]
    }

    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let spec = toolItems.first(where: { $0.0 == id.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = spec.1
        item.image = NSImage(systemSymbolName: spec.2, accessibilityDescription: spec.1)
        item.target = spec.0 == "delete" ? canvas : self
        item.action = spec.3
        return item
    }
}

extension SlideWindowController {
    private func buildRibbon(in content:NSView) {
        typealias R=OfficeRibbon
        let tabs:[R.Tab]=[
            .init(title:"홈",groups:[R.clipboard,R.text,.init(title:"문단",items:[.button("left","왼쪽","text.alignleft"),.button("center","가운데","text.aligncenter"),.button("right","오른쪽","text.alignright"),.menu("bullets","글머리",["글머리 없음","• 글머리표","1. 번호"]),.menu("spacing","줄 간격",["줄 간격 1.0","줄 간격 1.15","줄 간격 1.5","줄 간격 2.0"])]),.init(title:"글자 색",items:[.menu("textColor","글자 색",R.colors),.menu("highlight","형광펜",["형광펜 없음"]+R.colors),.button("strike","취소선","strikethrough")])]),
            .init(title:"삽입",groups:[.init(title:"슬라이드",items:[.button("new","새 슬라이드","plus.rectangle"),.button("duplicateSlide","슬라이드 복제","rectangle.on.rectangle"),.button("deleteSlide","슬라이드 삭제","trash")]),.init(title:"개체",items:[.menu("shape","도형",SlideInspector.kinds.map(\.1)),.button("image","그림","photo"),.button("table","표","tablecells"),.button("editTable","표 편집","square.and.pencil"),.button("line","선","line.diagonal")])]),
            .init(title:"배치",groups:[.init(title:"크기와 회전",items:[.menu("rotate","회전",["회전 선택…","오른쪽 90°","왼쪽 90°","180°","회전 초기화","좌우 뒤집기","상하 뒤집기"]),.button("aspect","비율 고정","lock.rectangle"),.menu("scale","크기 비율",["크기 선택…","50%","75%","125%","150%","200%"]),.button("geometry","크기 위치","ruler")]),.init(title:"정렬과 순서",items:[.menu("align","맞춤",["맞춤 선택…","왼쪽 맞춤","가운데 맞춤","오른쪽 맞춤","위쪽 맞춤","중간 맞춤","아래쪽 맞춤","가로 간격 같게","세로 간격 같게"]),.button("front","맨 앞으로","square.2.layers.3d.top.filled"),.button("back","맨 뒤로","square.2.layers.3d.bottom.filled"),.button("duplicate","복제","plus.square.on.square")]),.init(title:"도형 서식",items:[.menu("fill","채우기",["채우기 없음"]+R.colors),.menu("lineColor","윤곽선",["윤곽선 없음"]+R.colors),.menu("lineWidth","선 굵기",["0.5 pt","1 pt","2 pt","3 pt","4.5 pt","6 pt"])])]),
            .init(title:"전환",groups:[.init(title:"화면 전환",items:[.menu("transition","전환 효과",TransitionKind.allCases.map(\.title)),.field("duration","전환 시간 (초)",["0.7","0.3","0.5","1.0","1.5","2.0","3.0"]),.button("preview","미리 보기","play.fill"),.button("applyAll","모두 적용","rectangle.stack"),.button("transitionOptions","효과 넘김 설정","slider.horizontal.3")]),.init(title:"애니메이션",items:[.button("animations","애니메이션 창","rectangle.stack"),.button("show","현재부터 재생","play.rectangle")])]),
            .init(title:"보기",groups:[.init(title:"선택",items:[.button("selectAll","모두 선택","checkmark.rectangle.stack"),.button("delete","개체 삭제","trash")]),.init(title:"슬라이드 쇼",items:[.button("showAll","처음부터","play.rectangle.fill"),.button("show","현재부터","play.fill")])])]
        ribbon=OfficeRibbon(tabs:tabs,width:content.bounds.width); ribbon.frame.origin.y=content.bounds.height-OfficeRibbon.height
        ribbon.onCommand={ [weak self] id,value in self?.ribbonCommand(id,value) }; ribbon.onRefresh={ [weak self] in self?.reflectRibbon() }; content.addSubview(ribbon)
    }
    var debugTableWindow:NSWindow? { tableEditor?.window }
    var debugCanvas: SlideCanvasView { canvas }
    var debugRibbon:OfficeRibbon { ribbon }
    var debugSlideList:NSTableView { list }
    private func reflectRibbon() {
        guard ribbon != nil else { return }
        let t=inspectedSlide.transition
        ribbon.reflectChoice("transition",index:TransitionKind.allCases.firstIndex(of:t.kind) ?? 0)
        ribbon.reflectText("duration",value:String(format:"%.2f",t.duration))
        ribbon.isCommandEnabled("editTable",canvas.selected?.kind == .table)
        if let shape=canvas.selected {
            let p=shape.paragraphs.first?.props ?? ParaProps()
            ribbon.reflectChoice("bullets",index:p.listLabel == nil ? 0 : p.listLabel == "#" ? 2 : 1)
            var spacing = -1
            if case .multiple(let n)=p.lineSpacing { spacing=[1.0,1.15,1.5,2].firstIndex(where:{abs($0-n)<0.01}) ?? -1 }
            ribbon.reflectChoice("spacing",index:spacing)
            ribbon.reflectChoice("fill",index:shape.fill.flatMap { OfficeRibbon.palette.firstIndex(of:$0).map { $0+1 } } ?? (shape.fill == nil ? 0 : -1))
        }
        let c=inspector.currentChar
        ribbon.reflect(font:c?.eastAsianFontName ?? c?.fontName,size:c?.size,bold:c?.bold ?? false,italic:c?.italic ?? false,underline:c?.underline != nil && c?.underline != UnderlineStyle.none)
    }
    func ribbonCommand(_ id:String,_ value:String) {
        if OfficeRibbon.clipboardCommand(id) { return }
        let n=Int(value) ?? 0
        switch id {
        case "font": inspector.changeText("글꼴") { $0.fontName=value; $0.eastAsianFontName=value }
        case "size": if let v=Double(value),v.isFinite,v>0 { inspector.changeText("글자 크기") { $0.size=min(400,v) } }
        case "bold": let v = !(inspector.currentChar?.bold ?? false); inspector.changeText("굵게") { $0.bold=v }
        case "italic": let v = !(inspector.currentChar?.italic ?? false); inspector.changeText("기울임") { $0.italic=v }
        case "underline": let v=inspector.currentChar?.underline == UnderlineStyle.none; inspector.changeText("밑줄") { $0.underline=v ? .single : .none }
        case "strike": let v = !(inspector.currentChar?.strike ?? false); inspector.changeText("취소선") { $0.strike=v }
        case "textColor": inspector.changeText("글자 색") { $0.color=OfficeRibbon.palette[n] }
        case "highlight": inspector.changeText("형광펜") { $0.highlight=n == 0 ? nil : OfficeRibbon.palette[n-1] }
        case "left","center","right": inspector.changeParagraphs("정렬") { $0.alignment = id == "left" ? .left : id == "center" ? .center : .right }
        case "spacing": inspector.changeParagraphs("줄 간격") { $0.lineSpacing = .multiple([1,1.15,1.5,2][n]) }
        case "bullets": inspector.changeParagraphs("글머리") { $0.listLabel=[nil,"•","#"][n]; $0.indentLeft=n == 0 ? 0 : 27; $0.firstLine=n == 0 ? 0 : -27 }
        case "new": newSlide(nil)
        case "duplicateSlide": duplicateSlide(nil)
        case "deleteSlide": deleteSlide(nil)
        case "shape": let k=SlideInspector.kinds[n].0; if k == .text { insertTextBox(nil) } else { shape(k,k.title) }
        case "image": insertImage(nil)
        case "table": insertTable(nil)
        case "editTable": if let id=canvas.selectedID { canvasEditTable(id) }
        case "line": insertLine(nil)
        case "geometry": inspector.showFormatTab()
        case "aspect": let v = !(canvas.selected?.lockAspect ?? false); modifyShape("비율 고정") { $0.lockAspect=v }
        case "scale": if n>0 { let k=[1.0,0.5,0.75,1.25,1.5,2][n]; canvas.endEditing(); modifyShape("크기 비율") { s in let c=(s.frame.x+s.frame.w/2,s.frame.y+s.frame.h/2); s.frame.w *= k; s.frame.h *= k; s.frame.x=c.0-s.frame.w/2; s.frame.y=c.1-s.frame.h/2 } }
        case "rotate": canvas.endEditing(); modifyShape("회전 뒤집기") { s in switch n { case 1:s.rotation += 90; case 2:s.rotation -= 90; case 3:s.rotation += 180; case 4:s.rotation=0; case 5:s.flipH.toggle(); case 6:s.flipV.toggle(); default:break } }
        case "align": arrangeSelection(n)
        case "front","back":
            canvas.endEditing(); let ids=canvas.selectedIDs
            canvasDidChange(id == "front" ? "맨 앞으로" : "맨 뒤로") { sl in let chosen=sl.shapes.filter { ids.contains($0.id) }; sl.shapes.removeAll { ids.contains($0.id) }; if id == "front" { sl.shapes += chosen } else { let at=sl.shapes.prefix { $0.locked }.count; sl.shapes.insert(contentsOf:chosen,at:at) } }
        case "duplicate": canvas.duplicateSelection(nil)
        case "fill": modifyShape("채우기") { $0.fill=n == 0 ? nil : OfficeRibbon.palette[n-1] }
        case "lineColor": modifyShape("윤곽선") { $0.line=n == 0 ? nil : OfficeRibbon.palette[n-1] }
        case "lineWidth": modifyShape("선 굵기") { $0.lineWidth=[0.5,1,2,3,4.5,6][n]; if $0.line == nil { $0.line = .black } }
        case "transition": canvas.endEditing(); modifySlide("화면 전환") { $0.transition.kind=TransitionKind.allCases[n] }; previewTransition()
        case "duration": if let d=Double(value),d.isFinite,d>0 { modifySlide("전환 시간") { $0.transition.duration=min(60,d) } }
        case "preview": canvas.endEditing(); previewTransition()
        case "applyAll": let t=inspectedSlide.transition; modifyAllSlides("모두 적용") { $0.transition=t }
        case "transitionOptions": inspector.showTransitionTab()
        case "animations": inspector.showAnimationTab()
        case "show": playFromCurrent(nil)
        case "showAll": playSlideShow(nil)
        case "selectAll": canvas.selectAll(nil)
        case "delete": canvas.deleteSelection(nil)
        default: break
        }
        reflectRibbon()
    }
    private func arrangeSelection(_ mode:Int) {
        canvas.endEditing(); let ids=canvas.selectedIDs
        let chosen=inspectedSlide.shapes.filter { ids.contains($0.id) }
        guard mode>0,!chosen.isEmpty else { return }
        let boxes=chosen.map(ShapeGeometry.bounds), minX=boxes.map(\.x).min()!, minY=boxes.map(\.y).min()!, maxX=boxes.map(\.maxX).max()!, maxY=boxes.map(\.maxY).max()!
        let target=chosen.count == 1 ? Frame(x:0,y:0,w:doc.pres.width,h:doc.pres.height) : Frame(x:minX,y:minY,w:maxX-minX,h:maxY-minY)
        if mode<7 {
            canvasDidChange("맞춤") { sl in for i in sl.shapes.indices where ids.contains(sl.shapes[i].id) {
                let b=ShapeGeometry.bounds(sl.shapes[i])
                switch mode { case 1:sl.shapes[i].frame.x += target.x-b.x; case 2:sl.shapes[i].frame.x += target.x+target.w/2-b.x-b.w/2; case 3:sl.shapes[i].frame.x += target.maxX-b.maxX; case 4:sl.shapes[i].frame.y += target.y-b.y; case 5:sl.shapes[i].frame.y += target.y+target.h/2-b.y-b.h/2; case 6:sl.shapes[i].frame.y += target.maxY-b.maxY; default:break }
            } }
        } else if chosen.count>=3 {
            let horizontal=mode == 7
            let sorted=chosen.sorted { let a=ShapeGeometry.bounds($0),b=ShapeGeometry.bounds($1); return horizontal ? a.x<b.x : a.y<b.y }
            let total=boxes.reduce(0) { $0+(horizontal ? $1.w : $1.h) }, gap=((horizontal ? target.w : target.h)-total)/Double(chosen.count-1)
            var pos=horizontal ? target.x : target.y
            canvasDidChange("간격 같게") { sl in for s in sorted { let b=ShapeGeometry.bounds(s); if let i=sl.shapes.firstIndex(where:{$0.id == s.id}) { if horizontal { sl.shapes[i].frame.x += pos-b.x } else { sl.shapes[i].frame.y += pos-b.y } }; pos += (horizontal ? b.w : b.h)+gap } }
        }
    }
}

extension SlideWindowController {
    static let slidePasteboardType=NSPasteboard.PasteboardType("org.hanword.slides")
    static let slideReorderType=NSPasteboard.PasteboardType("org.hanword.slide-reorder")
    private var selectedSlides:[Int] { slideSelection.filter { doc.pres.slides.indices.contains($0) } }
    private var canPasteSlides:Bool { NSPasteboard.general.data(forType:Self.slidePasteboardType) != nil }
    private func selectSlides(_ indices:IndexSet) {
        slideSelection=indices
        current=indices.first ?? 0
        canvas.selectedID=nil; slideFocus=true; reload()
        if let row=indices.first { list.scrollRowToVisible(row) }
        window?.makeFirstResponder(list)
    }
    private func copySlides()->Bool {
        canvas.endEditing()
        let indices=selectedSlides; guard !indices.isEmpty else { return false }
        let source=Presentation(); source.width=doc.pres.width; source.height=doc.pres.height
        source.images=doc.pres.images; source.slides=indices.map { doc.pres.slides[$0] }
        guard let data=try? SlideClipboard.encode(source) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setData(data,forType:Self.slidePasteboardType)
    }
    private func pasteSlides() {
        canvas.endEditing()
        guard let data=NSPasteboard.general.data(forType:Self.slidePasteboardType) else { canvas.paste(nil); return }
        guard let source=SlideClipboard.decode(data),!source.slides.isEmpty else { return }
        var slides=source.slides,images:[String:ImageData]=[:],mapping:[String:String]=[:]
        for (key,image) in source.images { let id="paste/\(UUID().uuidString)/\(image.name)"; images[id]=image; mapping[key]=id }
        let sx=doc.pres.width/source.width,sy=doc.pres.height/source.height
        slides=SlideClipboard.remappingMedia(slides,ids:mapping)
        for i in slides.indices {
            for j in slides[i].shapes.indices {
                let f=slides[i].shapes[j].frame
                slides[i].shapes[j].frame=Frame(x:f.x*sx,y:f.y*sy,w:f.w*sx,h:f.h*sy)
            }
        }
        let at=doc.pres.slides.isEmpty ? 0 : (selectedSlides.last ?? current)+1
        doc.edit("슬라이드 붙여넣기") { p in p.images.merge(images) { _,new in new }; p.slides.insert(contentsOf:slides,at:at) }
        selectSlides(IndexSet(integersIn:at..<(at+slides.count)))
    }
    private func slideCommand(_ command:String) {
        switch command {
        case "copySlides": _=copySlides()
        case "cutSlides": if copySlides() { deleteSlide(nil) }
        case "pasteSlides": pasteSlides()
        case "duplicateSlide": duplicateSlide(nil)
        case "deleteSlide": deleteSlide(nil)
        case "new": newSlide(nil)
        case "bold","italic","underline": ribbonCommand(command,"")
        case "up","down","firstMove","lastMove": moveSlides(command)
        case "canvasFocus": window?.makeFirstResponder(canvas); slideFocus=false
        case "previousSlide","nextSlide": if !doc.pres.slides.isEmpty { selectSlides(IndexSet(integer:max(0,min(doc.pres.slides.count-1,current+(command == "nextSlide" ? 1 : -1))))); window?.makeFirstResponder(canvas); slideFocus=false }
        default: break
        }
    }
    private func moveSlides(_ direction:String) {
        canvas.endEditing()
        let selection=Set(selectedSlides); guard !selection.isEmpty else { return }
        var order=Array(doc.pres.slides.indices)
        if direction == "firstMove" { order=order.filter { selection.contains($0) }+order.filter { !selection.contains($0) } }
        else if direction == "lastMove" { order=order.filter { !selection.contains($0) }+order.filter { selection.contains($0) } }
        else if direction == "up" {
            for i in order.indices.dropFirst() where selection.contains(order[i]) && !selection.contains(order[i-1]) { order.swapAt(i,i-1) }
        } else if order.count>1 {
            for i in (0..<(order.count-1)).reversed() where selection.contains(order[i]) && !selection.contains(order[i+1]) { order.swapAt(i,i+1) }
        }
        guard order != Array(doc.pres.slides.indices) else { return }
        let slides=order.map { doc.pres.slides[$0] }
        doc.edit("슬라이드 이동") { $0.slides=slides }
        selectSlides(IndexSet(order.indices.filter { selection.contains(order[$0]) }))
    }
    private func slideContextMenu()->NSMenu {
        let menu=NSMenu(title:"슬라이드")
        for (title,selector,key) in [("새 슬라이드",#selector(newSlide(_:)),""),("슬라이드 복제",#selector(duplicateSlide(_:)),"d"),("슬라이드 삭제",#selector(deleteSlide(_:)),""),("잘라내기",#selector(cut(_:)),"x"),("복사",#selector(copy(_:)),"c"),("붙여넣기",#selector(paste(_:)),"v")] {
            let item=NSMenuItem(title:title,action:selector,keyEquivalent:key); item.target=self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let preview=NSMenuItem(title:"전환 미리 보기",action:#selector(previewSelectedTransition(_:)),keyEquivalent:""); preview.target=self; menu.addItem(preview)
        let play=NSMenuItem(title:"현재 슬라이드부터 쇼",action:#selector(playFromCurrent(_:)),keyEquivalent:""); play.target=self; menu.addItem(play)
        return menu
    }
    @objc func previewSelectedTransition(_ sender:Any?) { canvas.endEditing(); previewTransition() }
    @objc func showTransitions(_ sender:Any?) { ribbon.showTab("전환"); inspector.showTransitionTab() }
    @objc func duplicate(_ sender:Any?) { if slideFocus { duplicateSlide(sender) } else { canvas.duplicateSelection(sender) } }
    @objc func copy(_ sender:Any?) { if let tv=canvas.editor { tv.copy(sender) } else if slideFocus { _=copySlides() } else { canvas.copy(sender) } }
    @objc func cut(_ sender:Any?) { if let tv=canvas.editor { tv.cut(sender) } else if slideFocus { if copySlides() { deleteSlide(sender) } } else { canvas.cut(sender) } }
    @objc func paste(_ sender:Any?) { if let tv=canvas.editor { tv.paste(sender) } else if slideFocus { pasteSlides() } else { canvas.paste(sender) } }
    @objc func delete(_ sender:Any?) { if slideFocus { deleteSlide(sender) } else { canvas.deleteSelection(sender) } }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if item.action == #selector(duplicate(_:)) { item.title="복제" }
        if item.action == #selector(paste(_:)) { return canPasteSlides || SlideCanvasView.canPaste }
        if item.action == #selector(newSlide(_:)) { return true }
        if [#selector(duplicateSlide(_:)),#selector(deleteSlide(_:))].contains(item.action) { return !selectedSlides.isEmpty }
        if [#selector(copy(_:)),#selector(cut(_:)),#selector(delete(_:)),#selector(duplicate(_:))].contains(item.action) { return slideFocus ? !selectedSlides.isEmpty : !canvas.selectedIDs.isEmpty }
        return !doc.pres.slides.isEmpty
    }
}
