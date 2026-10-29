import AppKit

/// Shared, horizontally scrollable native ribbon. Every control dispatches an
/// implemented editor command; narrow windows retain access to every group.
final class OfficeRibbon: NSView, NSComboBoxDelegate {
    struct Item {
        let id: String, title: String
        var symbol: String? = nil
        var options: [String] = []
        var editable = false
        static func button(_ id:String,_ title:String,_ symbol:String?=nil) -> Item { Item(id:id,title:title,symbol:symbol) }
        static func menu(_ id:String,_ title:String,_ options:[String]) -> Item { Item(id:id,title:title,options:options) }
        static func field(_ id:String,_ title:String,_ options:[String]) -> Item { Item(id:id,title:title,options:options,editable:true) }
    }
    struct Group { let title:String; let items:[Item] }
    struct Tab { let title:String; let groups:[Group] }
    static let height: CGFloat=110
    var onRefresh: (() -> Void)?
    var onCommand: ((String,String)->Void)?
    private let tabs: [Tab]
    private let selector=HWTabControl()
    private let scroll=NSScrollView()
    private let row=NSStackView()
    private var controls:[String:NSControl]=[:]
    private var reflecting=false

    init(tabs:[Tab], width:CGFloat) {
        self.tabs=tabs
        super.init(frame:NSRect(x:0,y:0,width:width,height:Self.height))
        autoresizingMask=[.width,.minYMargin]
        selector.segmentCount=tabs.count; selector.trackingMode = .selectOne
        for (i,tab) in tabs.enumerated() { selector.setLabel(tab.title,forSegment:i); selector.setWidth(80,forSegment:i) }
        selector.selectedSegment=0; selector.segmentStyle = .texturedRounded; selector.target=self; selector.action=#selector(tabChanged(_:))
        selector.frame=NSRect(x:12,y:78,width:CGFloat(tabs.count)*80,height:31); addSubview(selector)
        scroll.frame=NSRect(x:0,y:1,width:width,height:76); scroll.autoresizingMask=[.width]
        scroll.drawsBackground=false; scroll.hasHorizontalScroller=true; scroll.autohidesScrollers=true
        scroll.documentView=row; addSubview(scroll)
        rebuild()
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {
        HWTheme.paper.setFill(); bounds.fill()
        HWTheme.border.setFill(); NSRect(x:0,y:0,width:bounds.width,height:1).fill()
    }
    @objc private func tabChanged(_ sender:Any?) { rebuild() }
    func showTab(_ title:String) { if let i=tabs.firstIndex(where:{$0.title == title}) { selector.selectedSegment=i; rebuild() } }
    private func rebuild() {
        row.arrangedSubviews.forEach { row.removeArrangedSubview($0); $0.removeFromSuperview() }; controls=[:]
        row.orientation = .horizontal; row.alignment = .top; row.spacing=12
        row.edgeInsets=NSEdgeInsets(top:3,left:14,bottom:6,right:14)
        for group in tabs[selector.selectedSegment].groups {
            let items=NSStackView(); items.spacing=4; items.alignment = .centerY
            for spec in group.items {
                let control:NSControl
                if spec.editable {
                    let c=HWComboBox(); c.addItems(withObjectValues:spec.options); c.stringValue=spec.options.first ?? ""; c.delegate=self; c.font = .systemFont(ofSize:12)
                    c.widthAnchor.constraint(equalToConstant:spec.id == "font" ? 146 : 58).isActive=true
                    c.target=self; c.action=#selector(comboCommitted(_:)); control=c
                } else if !spec.options.isEmpty {
                    let c=HWPopupButton(); c.addItems(withTitles:spec.options); c.font = .systemFont(ofSize:12)
                    c.widthAnchor.constraint(lessThanOrEqualToConstant:175).isActive=true
                    c.target=self; c.action=#selector(menuChosen(_:)); control=c
                } else {
                    let c=HWActionButton(title:spec.title,target:self,action:#selector(buttonPressed(_:)))
                    c.bezelStyle = .regularSquare; c.isBordered=false; c.font = .systemFont(ofSize:12)
                    if let symbol=spec.symbol { c.image=NSImage(systemSymbolName:symbol,accessibilityDescription:spec.title); c.image?.size=NSSize(width:18,height:18); c.imageScaling = .scaleProportionallyDown; c.imagePosition = .imageAbove }
                    c.heightAnchor.constraint(equalToConstant:46).isActive=true
                    control=c
                }
                control.identifier=NSUserInterfaceItemIdentifier(spec.id); control.toolTip=spec.title
                control.setAccessibilityLabel(spec.title);
                if spec.options.isEmpty && !spec.editable { control.widthAnchor.constraint(equalToConstant:max(42,min(108,(spec.title as NSString).size(withAttributes:[.font:HWTheme.font(11.5)]).width+16))).isActive=true }
                items.addArrangedSubview(control); controls[spec.id]=control
            }
            let label=NSTextField(labelWithString:group.title); label.font = .systemFont(ofSize:10.5); label.textColor = HWTheme.secondary
            let stack=NSStackView(views:[items,label]); stack.orientation = .vertical; stack.spacing=3
            row.addArrangedSubview(stack)
            let divider=NSBox(); divider.boxType = .separator; divider.widthAnchor.constraint(equalToConstant:1).isActive=true; divider.heightAnchor.constraint(equalToConstant:65).isActive=true; row.addArrangedSubview(divider)
        }
        let size=row.fittingSize; row.frame=NSRect(x:0,y:0,width:max(bounds.width,size.width),height:74)
        onRefresh?()
    }
    @objc private func buttonPressed(_ sender:NSButton) { emit(sender,"") }
    @objc private func menuChosen(_ sender:NSPopUpButton) { emit(sender,String(sender.indexOfSelectedItem)) }
    @objc private func comboCommitted(_ sender:NSComboBox) { emit(sender,sender.stringValue) }
    private func emit(_ control:NSControl,_ value:String) { guard !reflecting,let id=control.identifier?.rawValue else { return }; onCommand?(id,value) }
    func comboBoxSelectionDidChange(_ notification:Notification) {
        guard let c=notification.object as? NSComboBox else { return }
        DispatchQueue.main.async { [weak self,weak c] in if let c { self?.comboCommitted(c) } }
    }
    func controlTextDidEndEditing(_ notification:Notification) { if let c=notification.object as? NSComboBox { comboCommitted(c) } }
    func reflectChoice(_ id:String,index:Int) {
        guard let menu=controls[id] as? NSPopUpButton else { return }
        if index>=0,index<menu.numberOfItems { menu.selectItem(at:index) }
        else {
            let label="사용자 지정"
            if menu.indexOfItem(withTitle:label)<0 { menu.addItem(withTitle:label); menu.lastItem?.isEnabled=false }
            menu.selectItem(withTitle:label)
        }
    }
    func selectedTitle(_ id:String)->String? { (controls[id] as? NSPopUpButton)?.titleOfSelectedItem }
    func isCommandEnabled(_ id:String,_ enabled:Bool) { controls[id]?.isEnabled=enabled }
    func reflectText(_ id:String,value:String) { if let c=controls[id] as? NSComboBox,c.currentEditor() == nil { c.stringValue=value } }
    func reflect(font:String?,size:Double?,bold:Bool,italic:Bool,underline:Bool) {
        reflecting=true; defer { reflecting=false }
        if let font, let c=controls["font"] as? NSComboBox, c.currentEditor() == nil { c.stringValue=font }
        if let size, let c=controls["size"] as? NSComboBox, c.currentEditor() == nil { c.stringValue=String(format:"%.1f",size).replacingOccurrences(of:".0",with:"") }
        for (id,on) in [("bold",bold),("italic",italic),("underline",underline)] { (controls[id] as? NSButton)?.state=on ? .on : .off }
    }
    static let clipboard=Group(title:"클립보드",items:[.button("cut","잘라내기","scissors"),.button("copy","복사","doc.on.doc"),.button("paste","붙여넣기","doc.on.clipboard")])
    static var text: Group { Group(title:"글꼴",items:[.field("font","글꼴",["Apple SD Gothic Neo","AppleMyungjo","Arial","Helvetica Neue","Times New Roman"]+NSFontManager.shared.availableFontFamilies),.field("size","글자 크기",["18","8","9","10","11","12","14","16","20","24","28","32","36","44","48","60","72"]),.button("bold","굵게","bold"),.button("italic","기울임","italic"),.button("underline","밑줄","underline")]) }
    static let colors=["검정","빨강","주황","노랑","초록","파랑","보라","흰색"]
    static let palette:[RGB]=[.black,RGB(r:220,g:40,b:40),RGB(r:235,g:130,b:30),RGB(r:255,g:225,b:70),RGB(r:35,g:150,b:90),RGB(r:40,g:100,b:210),RGB(r:140,g:65,b:185),RGB(r:255,g:255,b:255)]
    static func clipboardCommand(_ id:String) -> Bool {
        guard ["cut","copy","paste"].contains(id) else { return false }
        NSApp.sendAction(Selector(id+":"),to:nil,from:nil); return true
    }
}

/// Replaces attributed text through NSTextView change approval so edits share the
/// editor's real undo stack, preserving links, fields and table paragraph data.
enum RibbonText {
    static func attributes(_ old:[NSAttributedString.Key:Any],change:(inout CharProps)->Void) -> [NSAttributedString.Key:Any] {
        var c=AttributedBridge.charProps(old); change(&c)
        var result=old
        for key in [NSAttributedString.Key.font,.foregroundColor,.hwFont,.hwEastAsianFont,.hwFamily,.strokeWidth,.strokeColor,.obliqueness,.underlineStyle,.hwUnderline,.strikethroughStyle,.backgroundColor,.superscript,.kern,.expansion] { result[key]=nil }
        result.merge(AttributedBridge.charAttributes(c,eastAsian:true)) { _,new in new }; return result
    }
    static func character(_ tv:NSTextView,name:String,change:(inout CharProps)->Void) {
        let selection=tv.selectedRange()
        if selection.length == 0 { tv.typingAttributes=attributes(tv.typingAttributes,change:change); return }
        guard let storage=tv.textStorage else { return }
        let out=NSMutableAttributedString(attributedString:storage.attributedSubstring(from:selection))
        out.enumerateAttributes(in:NSRange(location:0,length:out.length)) { attrs,r,_ in out.setAttributes(attributes(attrs,change:change),range:r) }
        guard tv.shouldChangeText(in:selection,replacementString:out.string) else { return }
        storage.replaceCharacters(in:selection,with:out); tv.didChangeText()
        tv.setSelectedRange(selection); tv.undoManager?.setActionName(name)
    }
    static func paragraph(_ tv:NSTextView,name:String,change:(NSMutableParagraphStyle)->Void) {
        let selection=tv.selectedRange()
        guard let storage=tv.textStorage else { return }
        if storage.length == 0 {
            let ps=(tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle(); change(ps); tv.typingAttributes[.paragraphStyle]=ps; return
        }
        let range=(storage.string as NSString).paragraphRange(for:selection)
        let out=NSMutableAttributedString(attributedString:storage.attributedSubstring(from:range))
        out.enumerateAttribute(.paragraphStyle,in:NSRange(location:0,length:out.length)) { value,r,_ in
            let ps=(value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle(); change(ps)
            out.addAttribute(.paragraphStyle,value:ps,range:r); out.removeAttribute(.hwLineRule,range:r)
        }
        guard tv.shouldChangeText(in:range,replacementString:out.string) else { return }
        storage.replaceCharacters(in:range,with:out); tv.didChangeText()
        tv.setSelectedRange(selection); tv.undoManager?.setActionName(name)
    }
}
