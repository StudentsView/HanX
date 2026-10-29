import AppKit

enum HWTheme {
    static func color(_ light:UInt32,_ dark:UInt32)->NSColor {
        NSColor(name:nil) { appearance in
            let value=appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed:CGFloat((value>>16)&255)/255,green:CGFloat((value>>8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)
        }
    }
    static let paper=color(0xFFFFFF,0x232C38)
    static let toolbar=color(0xF6F8FB,0x202833)
    static let canvas=color(0xE7EBF1,0x151C25)
    static let ink=color(0x203247,0xE5ECF5)
    static let secondary=color(0x6C7D90,0xA4B1C2)
    static let border=color(0xDCE3EC,0x3A4657)
    static let accent=color(0x3266A8,0x8EB6EC)
    static let selection=color(0xE7EFFA,0x30445F)
    static func font(_ size:CGFloat,weight:NSFont.Weight = .regular)->NSFont {
        let face=weight == .semibold || weight == .bold ? "AppleSDGothicNeo-SemiBold" : "AppleSDGothicNeo-Regular"
        return NSFont(name:face,size:size) ?? NSFont.systemFont(ofSize:size,weight:weight)
    }
    static func surface(_ rect:NSRect,filled:NSColor=paper,bordered:Bool=true,radius:CGFloat=4) {
        let p=NSBezierPath(roundedRect:rect.insetBy(dx:0.5,dy:0.5),xRadius:radius,yRadius:radius)
        filled.setFill(); p.fill()
        if bordered { border.setStroke(); p.lineWidth=1; p.stroke() }
    }
    static func text(_ value:String,in rect:NSRect,size:CGFloat=12,color:NSColor=ink,alignment:NSTextAlignment = .left,weight:NSFont.Weight = .regular) {
        let p=NSMutableParagraphStyle(); p.alignment=alignment; p.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in:rect,withAttributes:[.font:font(size,weight:weight),.foregroundColor:color,.paragraphStyle:p])
    }
    static func symbol(_ image:NSImage,in rect:NSRect,color:NSColor) {
        let tinted=NSImage(size:rect.size,flipped:false) { bounds in
            image.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            color.setFill(); bounds.fill(using:.sourceAtop); return true
        }
        tinted.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    static func style(_ window:NSWindow) {
        if let content=window.contentView { let surface=HWSurfaceView(frame:content.frame); surface.fill=paper; window.contentView=surface }
        window.backgroundColor=toolbar
        window.titlebarAppearsTransparent=true
        window.toolbarStyle = .unifiedCompact
    }
}

final class HWSurfaceView:NSView {
    var fill:NSColor=HWTheme.paper
    override func draw(_ dirtyRect:NSRect) { fill.setFill(); bounds.fill() }
}

final class HWActionButton:NSButton {
    private var hovered=false
    private var tracking:NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        let area=NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseEnteredAndExited,.inVisibleRect],owner:self)
        addTrackingArea(area); tracking=area
    }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        let active=state == .on || isHighlighted
        if active || hovered { HWTheme.surface(bounds.insetBy(dx:1,dy:1),filled:active ? HWTheme.selection : HWTheme.toolbar,bordered:active,radius:4) }
        let tint = !isEnabled ? HWTheme.secondary.withAlphaComponent(0.5) : active ? HWTheme.accent : HWTheme.ink
        let big=imagePosition == .imageAbove && bounds.height>36
        if let image {
            let d:CGFloat=big ? 18 : 16
            let x=imagePosition == .imageOnly ? bounds.midX-d/2 : big ? bounds.midX-d/2 : 9
            let y=big ? (isFlipped ? 5 : bounds.maxY-24) : bounds.midY-d/2
            HWTheme.symbol(image,in:NSRect(x:x,y:y,width:d,height:d),color:tint)
        }
        if imagePosition != .imageOnly {
            let r=big ? NSRect(x:4,y:isFlipped ? bounds.height-20 : 4,width:bounds.width-8,height:16) : NSRect(x:image == nil ? 9 : 31,y:bounds.midY-8,width:bounds.width-(image == nil ? 18 : 38),height:17)
            HWTheme.text(title,in:r,size:11.5,color:tint,alignment:big ? .center : .left,weight:active ? .semibold : .regular)
        }
        if window?.firstResponder === self { HWTheme.accent.setStroke(); let p=NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:4,yRadius:4); p.lineWidth=2; p.stroke() }
    }
}

final class HWPopupCell:NSPopUpButtonCell {
    override func draw(withFrame frame:NSRect,in controlView:NSView) {
        HWTheme.surface(frame,filled:isEnabled ? HWTheme.paper : HWTheme.toolbar)
        HWTheme.text(title,in:NSRect(x:frame.minX+9,y:frame.midY-8,width:max(1,frame.width-29),height:17),size:12,color:isEnabled ? HWTheme.ink : HWTheme.secondary)
        HWTheme.secondary.setStroke(); let p=NSBezierPath(); p.lineWidth=1.2
        let sign:CGFloat=controlView.isFlipped ? -1 : 1
        p.move(to:NSPoint(x:frame.maxX-17,y:frame.midY+2*sign)); p.line(to:NSPoint(x:frame.maxX-13,y:frame.midY-2*sign)); p.line(to:NSPoint(x:frame.maxX-9,y:frame.midY+2*sign)); p.stroke()
    }
}
final class HWPopupButton:NSPopUpButton {
    override init(frame:NSRect,pullsDown:Bool) {
        super.init(frame:frame,pullsDown:pullsDown)
        cell=HWPopupCell(textCell:"",pullsDown:pullsDown); font=HWTheme.font(12); focusRingType = .none
    }
    convenience init() { self.init(frame:.zero,pullsDown:false) }
    required init?(coder:NSCoder) { super.init(coder:coder) }
    override var intrinsicContentSize:NSSize { let size=super.intrinsicContentSize; return NSSize(width:max(64,size.width+6),height:28) }
}

final class HWComboBox:NSComboBox {
    override init(frame:NSRect) {
        super.init(frame:frame); isBordered=false; isBezeled=false; drawsBackground=false; font=HWTheme.font(12); focusRingType = .none
    }
    convenience init() { self.init(frame:.zero) }
    required init?(coder:NSCoder) { super.init(coder:coder) }
    override func draw(_ dirtyRect:NSRect) { HWTheme.surface(bounds); super.draw(dirtyRect) }
    override var intrinsicContentSize:NSSize { NSSize(width:super.intrinsicContentSize.width,height:28) }
}
final class HWTextField:NSTextField {
    override init(frame:NSRect) {
        super.init(frame:frame); isBordered=false; isBezeled=false; drawsBackground=false; font=HWTheme.font(12); textColor=HWTheme.ink; focusRingType = .none
    }
    convenience init() { self.init(frame:.zero) }
    required init?(coder:NSCoder) { super.init(coder:coder) }
    override func draw(_ dirtyRect:NSRect) { HWTheme.surface(bounds); super.draw(dirtyRect) }
    override var intrinsicContentSize:NSSize { NSSize(width:super.intrinsicContentSize.width,height:28) }
}

final class HWSegmentCell:NSSegmentedCell {
    override func draw(withFrame frame:NSRect,in controlView:NSView) {
        var x=frame.minX
        for i in 0..<segmentCount {
            let w=width(forSegment:i)>0 ? width(forSegment:i) : frame.width/CGFloat(max(1,segmentCount))
            let r=NSRect(x:x,y:frame.minY,width:w,height:frame.height)
            if isSelected(forSegment:i) { HWTheme.selection.setFill(); r.fill() }
            if let image=image(forSegment:i) { HWTheme.symbol(image,in:NSRect(x:r.midX-8,y:r.midY-8,width:16,height:16),color:isSelected(forSegment:i) ? HWTheme.accent : HWTheme.secondary) }
            else { HWTheme.text(label(forSegment:i) ?? "",in:NSRect(x:r.minX+4,y:r.midY-8,width:r.width-8,height:17),size:12,color:isSelected(forSegment:i) ? HWTheme.accent : HWTheme.secondary,alignment:.center,weight:isSelected(forSegment:i) ? .semibold : .regular) }
            if isSelected(forSegment:i) { HWTheme.accent.setFill(); NSRect(x:r.minX+8,y:controlView.isFlipped ? frame.maxY-2 : frame.minY,width:max(0,r.width-16),height:2).fill() }
            x += w
        }
    }
}
final class HWTabControl:NSSegmentedControl {
    override init(frame:NSRect) { super.init(frame:frame); cell=HWSegmentCell(); focusRingType = .none }
    convenience init() { self.init(frame:.zero) }
    required init?(coder:NSCoder) { super.init(coder:coder) }
    convenience init(labels:[String],trackingMode:NSSegmentedControl.SwitchTracking,target:AnyObject?,action:Selector?) {
        self.init(); segmentCount=labels.count; self.trackingMode=trackingMode; self.target=target; self.action=action
        for (i,label) in labels.enumerated() { setLabel(label,forSegment:i); setWidth(labels == ["서식","애니메이션","전환"] ? 76 : max(28,(label as NSString).size(withAttributes:[.font:HWTheme.font(12)]).width+18),forSegment:i) }
    }
}
