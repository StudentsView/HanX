import AppKit

/// Slide text ↔ TextKit. Bullets use AppKit's own list convention
/// ("\t•\t" marker text plus NSTextList on the paragraph style) so pressing
/// Return in the editor continues the list exactly like TextEdit.
enum SlideText {
    static func attributed(_ paragraphs: [Paragraph], scale: Double = 1) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        var number = 0
        let ctx = AttributedBridge.Context(images: [:], source: .docx)
        for (i, var p) in paragraphs.enumerated() {
            if scale < 0.999 {
                p.markProps.size *= scale
                p.inlines = p.inlines.map {
                    switch $0 {
                    case .text(let t, var c): c.size *= scale; return .text(t, c)
                    case .tab(var c): c.size *= scale; return .tab(c)
                    case .lineBreak(var c): c.size *= scale; return .lineBreak(c)
                    default: return $0
                    }
                }
            }
            let s = NSMutableAttributedString(attributedString: AttributedBridge.paragraph(p, outer: [], width: 10_000, ctx: ctx))
            if i == paragraphs.count - 1, s.string.hasSuffix("\n") { s.deleteCharacters(in: NSRange(location: s.length - 1, length: 1)) }
            if let label = p.props.listLabel {
                number += 1
                let list = NSTextList(markerFormat: label == "#" ? .decimal : .disc, options: 0)
                let marker = label == "#" ? "\(number)." : label
                let first = p.inlines.lazy.compactMap { i -> CharProps? in if case .text(_, let c) = i { return c }; return nil }.first ?? p.markProps
                var attrs = AttributedBridge.charAttributes(first, eastAsian: false)
                let ps = (s.length > 0 ? s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                let indent = max(CGFloat(p.props.indentLeft), CGFloat(first.size) * 1.1)
                ps.headIndent = indent
                ps.firstLineHeadIndent = max(0, indent + CGFloat(min(0, p.props.firstLine == 0 ? -Double(indent) : p.props.firstLine)))
                ps.tabStops = [NSTextTab(textAlignment: .left, location: ps.firstLineHeadIndent + 0.01), NSTextTab(textAlignment: .left, location: indent)]
                ps.textLists = [list]
                attrs[.paragraphStyle] = ps
                s.insert(NSAttributedString(string: "\t\(marker)\t", attributes: attrs), at: 0)
                s.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: s.length))
            } else {
                number = 0
            }
            out.append(s)
        }
        return out
    }

    static func paragraphs(_ text: NSAttributedString) -> [Paragraph] {
        // Remove the "\t•\t" / "1.\t" marker text TextKit keeps in list
        // paragraphs, remembering which paragraphs were list items.
        let m = NSMutableAttributedString(attributedString: text)
        var lists: [(label: String, indent: Double, first: Double)?] = []
        var i = 0
        while i < m.length {
            let ns = m.string as NSString
            let r = ns.paragraphRange(for: NSRange(location: i, length: 0))
            var len = r.length
            if let ps = m.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle, let list = ps.textLists.first {
                let marker = (ns.substring(with: r) as NSString).range(of: "^\\t?[^\\t\\n]{1,6}\\t", options: .regularExpression)
                if marker.location != NSNotFound {
                    m.deleteCharacters(in: NSRange(location: r.location, length: marker.length))
                    len -= marker.length
                }
                lists.append((list.markerFormat == .decimal ? "#" : "•", Double(ps.headIndent), Double(ps.firstLineHeadIndent - ps.headIndent)))
            } else {
                lists.append(nil)
            }
            i = r.location + max(1, len)
        }
        let doc = AttributedBridge.document(from: m, base: UDocument(), page: PageSetup())
        var out: [Paragraph] = []
        for (n, b) in (doc.sections.first?.blocks ?? []).enumerated() {
            guard case .paragraph(var p) = b else { continue }
            if n < lists.count, let l = lists[n] {
                p.props.listLabel = l.label
                p.props.indentLeft = l.indent
                p.props.firstLine = l.first
            }
            out.append(p)
        }
        return out.isEmpty ? [Paragraph()] : out
    }
}

enum SlideRenderer {
    static func cg(_ f: Frame) -> NSRect { NSRect(x: f.x, y: f.y, width: f.w, height: f.h) }

    static func path(_ s: SlideShape, in r: NSRect) -> NSBezierPath {
        switch s.kind {
        case .ellipse: return NSBezierPath(ovalIn: r)
        case .roundRect: return NSBezierPath(roundedRect: r, xRadius: min(r.width, r.height) * 0.16, yRadius: min(r.width, r.height) * 0.16)
        case .triangle:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.midX, y: r.minY)); p.line(to: NSPoint(x: r.maxX, y: r.maxY)); p.line(to: NSPoint(x: r.minX, y: r.maxY)); p.close()
            return p
        case .rightArrow:
            let p = NSBezierPath(), head = min(r.width * 0.4, r.height)
            p.move(to: NSPoint(x: r.minX, y: r.minY + r.height * 0.25))
            p.line(to: NSPoint(x: r.maxX - head, y: r.minY + r.height * 0.25))
            p.line(to: NSPoint(x: r.maxX - head, y: r.minY))
            p.line(to: NSPoint(x: r.maxX, y: r.midY))
            p.line(to: NSPoint(x: r.maxX - head, y: r.maxY))
            p.line(to: NSPoint(x: r.maxX - head, y: r.minY + r.height * 0.75))
            p.line(to: NSPoint(x: r.minX, y: r.minY + r.height * 0.75))
            p.close()
            return p
        case .diamond, .pentagon, .hexagon, .octagon, .star5, .star6:
            let n = [ShapeKind.diamond:4, .pentagon:5, .hexagon:6, .octagon:8, .star5:10, .star6:12][s.kind]!
            let star = s.kind == .star5 || s.kind == .star6
            let pts = (0..<n).map { i -> NSPoint in
                let a = Double(i)*2*Double.pi/Double(n)-Double.pi/2
                let k: CGFloat = star && i%2 == 1 ? 0.43 : 1
                return NSPoint(x:r.midX+cos(a)*r.width/2*k,y:r.midY+sin(a)*r.height/2*k)
            }
            return polygon(pts)
        case .parallelogram: return polygon([point(r,0.2,0),point(r,1,0),point(r,0.8,1),point(r,0,1)])
        case .trapezoid: return polygon([point(r,0.2,0),point(r,0.8,0),point(r,1,1),point(r,0,1)])
        case .chevron: return polygon([point(r,0,0),point(r,0.65,0),point(r,1,0.5),point(r,0.65,1),point(r,0,1),point(r,0.35,0.5)])
        case .plus: return polygon([(0.35,0.0),(0.65,0),(0.65,0.35),(1,0.35),(1,0.65),(0.65,0.65),(0.65,1),(0.35,1),(0.35,0.65),(0,0.65),(0,0.35),(0.35,0.35)].map { point(r,$0.0,$0.1) })
        case .heart:
            let p=NSBezierPath(); p.move(to:point(r,0.5,1))
            p.curve(to:point(r,0.5,0.18), controlPoint1:point(r,-0.5,0.35),controlPoint2:point(r,0.05,-0.35))
            p.curve(to:point(r,0.5,1), controlPoint1:point(r,0.95,-0.35),controlPoint2:point(r,1.5,0.35)); p.close(); return p
        case .leftArrow, .upArrow, .downArrow:
            var right=s; right.kind = .rightArrow
            let vertical = s.kind == .upArrow || s.kind == .downArrow
            let box = NSRect(x:r.midX-(vertical ? r.height : r.width)/2,y:r.midY-(vertical ? r.width : r.height)/2,width:vertical ? r.height : r.width,height:vertical ? r.width : r.height)
            let p=path(right,in:box), t=AffineTransform(translationByX:r.midX,byY:r.midY)
            var rotation=AffineTransform(); rotation.rotate(byDegrees:s.kind == .leftArrow ? 180 : s.kind == .upArrow ? -90 : 90)
            var move=AffineTransform(translationByX:-r.midX,byY:-r.midY); move.append(rotation); move.append(t); p.transform(using:move); return p
        case .leftRightArrow:
            return polygon([(0.0,0.5),(0.25,0),(0.25,0.3),(0.75,0.3),(0.75,0),(1,0.5),(0.75,1),(0.75,0.7),(0.25,0.7),(0.25,1)].map { point(r,$0.0,$0.1) })
        case .line:
            let p = NSBezierPath()
            let a = NSPoint(x:r.minX,y:r.minY)
            let b = NSPoint(x:r.maxX,y:r.maxY)
            p.move(to: a); p.line(to: b)
            return p
        default: return NSBezierPath(rect: r)
        }
    }

    private static func point(_ r: NSRect, _ x: Double, _ y: Double) -> NSPoint { NSPoint(x:r.minX+r.width*x,y:r.minY+r.height*y) }
    private static func polygon(_ points: [NSPoint]) -> NSBezierPath {
        let p=NSBezierPath(); guard let first=points.first else { return p }; p.move(to:first)
        for pt in points.dropFirst() { p.line(to:pt) }; p.close(); return p
    }

    /// Draws a slide in slide coordinates into the current (flipped) context.
    static func draw(_ slide: Slide, _ pres: Presentation, hideTextOf hidden: Int? = nil) {
        let bounds = NSRect(x: 0, y: 0, width: pres.width, height: pres.height)
        (slide.background.map(AttributedBridge.nsColor) ?? .white).setFill()
        bounds.fill()
        if let id = slide.backgroundImage, let d = pres.images[id], let img = NSImage(data: d.data) {
            img.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        for s in slide.shapes { drawShape(s, pres, hideText: s.id == hidden && !s.locked) }
    }

    static func drawShape(_ s: SlideShape, _ pres: Presentation, hideText: Bool = false) {
        let r = cg(s.frame)
        NSGraphicsContext.saveGraphicsState()
        if s.rotation != 0 {
            let t = NSAffineTransform()
            t.translateX(by: r.midX, yBy: r.midY); t.rotate(byDegrees: CGFloat(s.rotation)); t.translateX(by: -r.midX, yBy: -r.midY)
            t.concat()
        }
        NSGraphicsContext.saveGraphicsState()
        if s.flipH || s.flipV {
            let t=NSAffineTransform(); t.translateX(by:r.midX,yBy:r.midY); t.scaleX(by:s.flipH ? -1 : 1,yBy:s.flipV ? -1 : 1); t.translateX(by:-r.midX,yBy:-r.midY); t.concat()
        }
        switch s.kind {
        case .image:
            if let id = s.imageID, let d = pres.images[id], let img = NSImage(data: d.data) {
                img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                NSColor(white: 0.9, alpha: 1).setFill(); r.fill()
            }
        case .table:
            if let t = s.table { drawTable(t, s, in: r) }
        default:
            let p = path(s, in: r)
            if let f = s.fill, s.kind != .line { AttributedBridge.nsColor(f).setFill(); p.fill() }
            if let l = s.line { AttributedBridge.nsColor(l).setStroke(); p.lineWidth = CGFloat(s.lineWidth); p.stroke() }
        }
        NSGraphicsContext.restoreGraphicsState()
        if !hideText && s.kind != .image && s.kind != .table && s.kind != .line && s.hasText {
            drawText(s.paragraphs, scale: s.autofitScale, in: textRect(s), anchor: s.anchor, wrap: s.wrap)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func textRect(_ s: SlideShape) -> NSRect {
        let r = cg(s.frame)
        return NSRect(x: r.minX + CGFloat(s.insets.left), y: r.minY + CGFloat(s.insets.top),
                      width: max(4, r.width - CGFloat(s.insets.left + s.insets.right)), height: max(4, r.height - CGFloat(s.insets.top + s.insets.bottom)))
    }

    static func drawText(_ paragraphs: [Paragraph], scale: Double, in r: NSRect, anchor: CellVAlign, wrap: Bool) {
        let text = SlideText.attributed(paragraphs, scale: scale)
        let width = wrap ? r.width : 100_000
        let h = text.boundingRect(with: NSSize(width: width, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        var y = r.minY
        switch anchor {
        case .center: y = r.midY - h / 2
        case .bottom: y = r.maxY - h
        case .top: break
        }
        text.draw(with: NSRect(x: r.minX, y: y, width: width, height: max(h, r.height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    static func drawTable(_ t: Table, _ s: SlideShape, in r: NSRect) {
        let rawCols = t.columnWidths.isEmpty ? Array(repeating: Double(r.width) / Double(max(1, t.columnCount)), count: t.columnCount) : t.columnWidths
        let rawHeights = t.rows.indices.map { $0 < s.tableRowHeights.count && s.tableRowHeights[$0] > 0 ? s.tableRowHeights[$0] : Double(r.height) / Double(max(1, t.rows.count)) }
        let cols = rawCols.map { $0 * Double(r.width)/max(1,rawCols.reduce(0,+)) }
        let heights = rawHeights.map { $0 * Double(r.height)/max(1,rawHeights.reduce(0,+)) }
        let grid = TableGrid(t)
        for (ri, row) in grid.slots.enumerated() {
            for (ci, slot) in row.enumerated() {
                guard case .origin(let cell) = slot else { continue }
                let x = r.minX + CGFloat(cols.prefix(ci).reduce(0, +))
                let y = r.minY + CGFloat(heights.prefix(ri).reduce(0, +))
                let w = CGFloat(cols[ci..<min(cols.count, ci + max(1, cell.colSpan))].reduce(0, +))
                let h = CGFloat(heights[ri..<min(heights.count, ri + max(1, cell.rowSpan))].reduce(0, +))
                let cr = NSRect(x: x, y: y, width: w, height: h)
                (cell.background.map(AttributedBridge.nsColor) ?? .clear).setFill(); cr.fill()
                NSColor.black.setStroke()
                let b = NSBezierPath(rect: cr); b.lineWidth = 0.75; b.stroke()
                let paras = cell.blocks.compactMap { if case .paragraph(let p) = $0 { return p } else { return nil } }
                drawText(paras, scale: 1, in: cr.insetBy(dx: 6, dy: 3), anchor: cell.verticalAlign, wrap: true)
            }
        }
    }

    static func image(_ slide: Slide, _ pres: Presentation, width: CGFloat) -> NSImage {
        let scale = width / CGFloat(pres.width)
        let size = NSSize(width: width, height: CGFloat(pres.height) * scale)
        return NSImage(size: size, flipped: true) { _ in
            let t = NSAffineTransform(); t.scale(by: scale); t.concat()
            draw(slide, pres)
            return true
        }
    }

    /// Rasterised slide (for layer contents).
    static func cgImage(_ slide: Slide, _ pres: Presentation, width: CGFloat) -> CGImage? {
        let scale = width / CGFloat(pres.width)
        let w = Int(width), h = Int(CGFloat(pres.height) * scale)
        guard let ctx = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw(slide, pres)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Vector PDF, one page per slide.
    static func pdf(_ pres: Presentation) -> Data {
        let pages = pres.slides.map { slide -> Data in
            let v = SlidePageView(frame: NSRect(x: 0, y: 0, width: pres.width, height: pres.height))
            v.slide = slide; v.pres = pres
            return v.dataWithPDF(inside: v.bounds)
        }
        return PDFMerge.merge(pages)
    }
}

/// Plain view that draws one slide at 1:1 (used for PDF and the slide show).
final class SlidePageView: NSView {
    var slide = Slide()
    var pres = Presentation()
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let sx = bounds.width / CGFloat(pres.width), sy = bounds.height / CGFloat(pres.height)
        let s = min(sx, sy)
        NSColor.black.setFill(); bounds.fill()
        let t = NSAffineTransform()
        t.translateX(by: (bounds.width - CGFloat(pres.width) * s) / 2, yBy: (bounds.height - CGFloat(pres.height) * s) / 2)
        t.scale(by: s)
        NSGraphicsContext.saveGraphicsState()
        t.concat()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pres.width, height: pres.height)).addClip()
        SlideRenderer.draw(slide, pres)
        NSGraphicsContext.restoreGraphicsState()
    }
}
