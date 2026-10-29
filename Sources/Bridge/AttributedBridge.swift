import AppKit

/// Unified model ↔ TextKit. The editor works on an NSAttributedString (one
/// shared text storage across all page views, the way Word's PTLS layout
/// pulls runs from a single story); custom attributes carry what TextKit
/// cannot express so a load → edit → save round trip keeps the original
/// face names, HWP line-spacing rules and image payloads.
extension NSAttributedString.Key {
    static let hwFont = NSAttributedString.Key("HWFontName")
    static let hwEastAsianFont = NSAttributedString.Key("HWEastAsianFontName")
    static let hwFamily = NSAttributedString.Key("HWResolvedFamily")
    static let hwUnderline = NSAttributedString.Key("HWUnderline")
    static let hwLineRule = NSAttributedString.Key("HWLineRule")
    static let hwImage = NSAttributedString.Key("HWImageID")
    /// Page-number field ("page" / "pageCount"); its text is a placeholder.
    static let hwField = NSAttributedString.Key("HWField")
    /// Paragraph style name (바탕글, 제목 1, …).
    static let hwStyle = NSAttributedString.Key("HWStyle")
}

enum AttributedBridge {
    struct Context {
        var images: [String: ImageData]
        var source: SourceFormat
        var defaultTab: CGFloat { source == .docx ? 36 : 40 }
    }

    private static let metrics = NSLayoutManager()

    // MARK: Model → attributed string

    static func attributedString(from doc: UDocument) -> NSAttributedString {
        let ctx = Context(images: doc.images, source: doc.source)
        let out = NSMutableAttributedString()
        let width = doc.sections.first?.page.contentWidth ?? PageSetup().contentWidth
        for (si, section) in doc.sections.enumerated() {
            var blocks = section.blocks
            if si > 0, case .paragraph(var p)? = blocks.first {
                p.props.pageBreakBefore = true
                blocks[0] = .paragraph(p)
            }
            out.append(build(blocks, outer: [], width: width, ctx: ctx))
        }
        // NSTextView shows a trailing newline as an extra empty line.
        if out.length > 0, (out.string as NSString).character(at: out.length - 1) == 10 {
            let ps = out.attribute(.paragraphStyle, at: out.length - 1, effectiveRange: nil) as? NSParagraphStyle
            if ps?.textBlocks.isEmpty ?? true { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        }
        return out
    }

    static func build(_ blocks: [Block], outer: [NSTextBlock], width: Double, ctx: Context) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for b in blocks {
            switch b {
            case .paragraph(let p): out.append(paragraph(p, outer: outer, width: width, ctx: ctx))
            case .table(let t): out.append(table(t, outer: outer, width: width, ctx: ctx))
            }
        }
        return out
    }

    static func charAttributes(_ c: CharProps, eastAsian: Bool) -> [NSAttributedString.Key: Any] {
        let name = eastAsian ? (c.eastAsianFontName ?? c.fontName) : c.fontName
        let r = FontResolver.shared.font(name: name, size: c.size, bold: c.bold, italic: c.italic)
        let color = NSColor(srgbRed: CGFloat(c.color.r) / 255, green: CGFloat(c.color.g) / 255, blue: CGFloat(c.color.b) / 255, alpha: 1)
        var a: [NSAttributedString.Key: Any] = [
            .font: r.font, .foregroundColor: color,
            .hwFont: c.fontName, .hwEastAsianFont: c.eastAsianFontName ?? "", .hwFamily: r.font.familyName ?? "",
        ]
        if r.syntheticBold { a[.strokeWidth] = -3.0; a[.strokeColor] = color }
        if r.syntheticItalic { a[.obliqueness] = 0.2 }
        switch c.underline {
        case .none: break
        case .single: a[.underlineStyle] = NSUnderlineStyle.single.rawValue
        case .double: a[.underlineStyle] = NSUnderlineStyle.double.rawValue
        case .thick: a[.underlineStyle] = NSUnderlineStyle.thick.rawValue
        case .dotted: a[.underlineStyle] = NSUnderlineStyle.single.union(.patternDot).rawValue
        case .dashed: a[.underlineStyle] = NSUnderlineStyle.single.union(.patternDash).rawValue
        case .wave: a[.underlineStyle] = NSUnderlineStyle.single.rawValue; a[.hwUnderline] = "wave"
        }
        if c.strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let h = c.highlight {
            a[.backgroundColor] = NSColor(srgbRed: CGFloat(h.r) / 255, green: CGFloat(h.g) / 255, blue: CGFloat(h.b) / 255, alpha: 1)
        }
        switch c.verticalAlign {
        case .superscript: a[.superscript] = 1
        case .subscript: a[.superscript] = -1
        case .baseline: break
        }
        if c.spacing != 0 { a[.kern] = c.spacing }
        if c.widthRatio != 100 && c.widthRatio > 0 { a[.expansion] = log(c.widthRatio / 100) }
        return a
    }

    /// Split text into East-Asian / other script segments, each with its face.
    static func text(_ s: String, _ c: CharProps) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var buf = ""
        var bufEA: Bool?
        func flush() {
            if let ea = bufEA, !buf.isEmpty { out.append(NSAttributedString(string: buf, attributes: charAttributes(c, eastAsian: ea))) }
            buf = ""
        }
        for ch in s {
            let ch: Character = ch == "\n" || ch == "\r" ? "\u{2028}" : ch
            // Spaces and punctuation stay with the surrounding run.
            let ea = ch.isWhitespace || ch.isPunctuation ? (bufEA ?? ch.isEastAsian) : ch.isEastAsian
            if ea != bufEA { flush(); bufEA = ea }
            buf.append(ch)
        }
        flush()
        return out
    }

    static func paragraphStyle(_ p: ParaProps, mark: CharProps, outer: [NSTextBlock], ctx: Context) -> (NSParagraphStyle, String?) {
        let ps = NSMutableParagraphStyle()
        switch p.alignment {
        case .left: ps.alignment = .left
        case .right: ps.alignment = .right
        case .center: ps.alignment = .center
        case .justify, .distribute: ps.alignment = .justified
        }
        ps.headIndent = CGFloat(max(0, p.indentLeft))
        ps.firstLineHeadIndent = CGFloat(max(0, p.indentLeft + p.firstLine))
        ps.tailIndent = p.indentRight > 0 ? -CGFloat(p.indentRight) : 0
        ps.paragraphSpacingBefore = CGFloat(max(0, p.spaceBefore))
        ps.paragraphSpacing = CGFloat(max(0, p.spaceAfter))
        ps.tabStops = []
        ps.defaultTabInterval = ctx.defaultTab
        ps.textBlocks = outer
        var rule: String?
        switch p.lineSpacing {
        case .multiple(let m): ps.lineHeightMultiple = CGFloat(max(0.5, m))
        case .percentOfSize(let pct):
            let font = FontResolver.shared.font(name: mark.eastAsianFontName ?? mark.fontName, size: mark.size, bold: false, italic: false).font
            let natural = metrics.defaultLineHeight(for: font)
            let mult = natural > 0 ? CGFloat(mark.size * pct / 100) / natural : 1
            ps.lineHeightMultiple = max(0.5, mult)
            rule = String(format: "pct:%g:%.4f", pct, Double(ps.lineHeightMultiple))
        case .exact(let v): ps.minimumLineHeight = CGFloat(v); ps.maximumLineHeight = CGFloat(v)
        case .atLeast(let v): ps.minimumLineHeight = CGFloat(v)
        }
        return (ps, rule)
    }

    static func paragraph(_ p: Paragraph, outer: [NSTextBlock], width: Double, ctx: Context) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let firstText = p.inlines.lazy.compactMap { i -> CharProps? in if case .text(_, let c) = i { return c }; return nil }.first
        let mark = firstText ?? p.markProps
        if p.props.pageBreakBefore && outer.isEmpty {
            s.append(NSAttributedString(string: "\u{0C}", attributes: charAttributes(mark, eastAsian: false)))
        }
        for i in p.inlines {
            switch i {
            case .text(let t, let c): s.append(text(t, c))
            case .tab(let c): s.append(NSAttributedString(string: "\t", attributes: charAttributes(c, eastAsian: false)))
            case .lineBreak(let c): s.append(NSAttributedString(string: "\u{2028}", attributes: charAttributes(c, eastAsian: false)))
            case .pageBreak: s.append(NSAttributedString(string: "\u{0C}", attributes: charAttributes(mark, eastAsian: false)))
            case .field(let k, let c): s.append(field(k, c))
            case .image(let id, let w, let h): s.append(image(id: id, width: w, height: h, maxWidth: width, mark: mark, ctx: ctx))
            }
        }
        s.append(NSAttributedString(string: "\n", attributes: charAttributes(p.markProps, eastAsian: false)))
        let (ps, rule) = paragraphStyle(p.props, mark: mark, outer: outer, ctx: ctx)
        let all = NSRange(location: 0, length: s.length)
        s.addAttribute(.paragraphStyle, value: ps, range: all)
        if let rule { s.addAttribute(.hwLineRule, value: rule, range: all) }
        if let st = p.props.styleName, EditorStyleNames.known.contains(st) { s.addAttribute(.hwStyle, value: st, range: all) }
        return s
    }

    static func field(_ k: FieldKind, _ c: CharProps) -> NSAttributedString {
        var a = charAttributes(c, eastAsian: false)
        a[.hwField] = k.rawValue
        a[.backgroundColor] = NSColor.systemBlue.withAlphaComponent(0.15)
        return NSAttributedString(string: k == .page ? "쪽" : "전체 쪽", attributes: a)
    }

    /// Replaces field placeholders with actual numbers (header/footer drawing).
    static func resolveFields(_ s: NSAttributedString, page: Int, pages: Int) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: s)
        var ranges: [(NSRange, String)] = []
        m.enumerateAttribute(.hwField, in: NSRange(location: 0, length: m.length)) { v, r, _ in
            if let k = v as? String { ranges.append((r, k == FieldKind.page.rawValue ? "\(page)" : "\(pages)")) }
        }
        for (r, text) in ranges.reversed() {
            var attrs = m.attributes(at: r.location, effectiveRange: nil)
            attrs[.backgroundColor] = nil
            m.replaceCharacters(in: r, with: NSAttributedString(string: text, attributes: attrs))
        }
        return m
    }

    static func image(id: String, width: Double, height: Double, maxWidth: Double, mark: CharProps, ctx: Context) -> NSAttributedString {
        let data = ctx.images[id]
        let att = NSTextAttachment()
        var img = data.flatMap { NSImage(data: $0.data) }
        if img == nil { img = placeholder(data?.ext.uppercased() ?? "?", size: NSSize(width: max(40, width), height: max(30, height))) }
        if let d = data {
            let fw = FileWrapper(regularFileWithContents: d.data)
            fw.preferredFilename = d.name
            att.fileWrapper = fw
        }
        att.image = img
        var w = width, h = height
        if (w <= 0 || h <= 0), let size = img?.size { w = size.width; h = size.height }
        if w > maxWidth && maxWidth > 0 { h *= maxWidth / w; w = maxWidth }
        att.bounds = CGRect(x: 0, y: 0, width: max(1, w), height: max(1, h))
        var a = charAttributes(mark, eastAsian: false)
        a[.attachment] = att
        a[.hwImage] = id
        return NSAttributedString(string: "\u{FFFC}", attributes: a)
    }

    private static func placeholder(_ label: String, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            NSColor(white: 0.92, alpha: 1).setFill(); r.fill()
            NSColor.gray.setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            let s = NSAttributedString(string: "그림 (\(label))", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.darkGray])
            s.draw(at: NSPoint(x: 4, y: r.midY - 6))
            return true
        }
    }

    static func nsColor(_ c: RGB) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    static func table(_ t: Table, outer: [NSTextBlock], width: Double, ctx: Context) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let grid = TableGrid(t)
        guard grid.cols > 0, !grid.slots.isEmpty else { return out }
        var widths = (0..<grid.cols).map { $0 < t.columnWidths.count ? max(4, t.columnWidths[$0]) : 60 }
        let total = widths.reduce(0, +)
        if total > width && width > 0 { widths = widths.map { $0 * width / total } }
        let table = GridTextTable(columnWidths: widths.map { CGFloat($0) })
        let rows = grid.slots.count

        // Resolve shared edges once, the way HWP and Word collapse borders:
        // each cell paints its top/left edge (the heavier of the two
        // neighbours' lines) and only boundary cells paint right/bottom.
        var owner = [[TableCell?]](repeating: [TableCell?](repeating: nil, count: grid.cols), count: rows)
        for (r, row) in grid.slots.enumerated() {
            for (c, slot) in row.enumerated() {
                guard case .origin(let cell) = slot else { continue }
                for rr in r..<min(rows, r + max(1, cell.rowSpan)) {
                    for cc in c..<min(grid.cols, c + max(1, cell.colSpan)) { owner[rr][cc] = cell }
                }
            }
        }
        func heavier(_ a: BorderLine, _ b: BorderLine?) -> BorderLine {
            guard let b, b.visible else { return a }
            return !a.visible || b.width > a.width ? b : a
        }

        for (r, row) in grid.slots.enumerated() {
            for (c, slot) in row.enumerated() {
                guard case .origin(let cell) = slot else { continue }
                let rs = max(1, min(cell.rowSpan, rows - r)), cs = max(1, min(cell.colSpan, grid.cols - c))
                let block = GridCellBlock(table: table, startingRow: r, rowSpan: rs, startingColumn: c, columnSpan: cs)
                block.source = cell
                let w = widths[c..<(c + cs)].reduce(0, +)
                block.setValue(CGFloat(w), type: .absoluteValueType, for: .width)

                var b = cell.borders
                if r > 0 { b.top = heavier(b.top, owner[r - 1][c]?.borders.bottom) }
                if c > 0 { b.left = heavier(b.left, owner[r][c - 1]?.borders.right) }
                if r + rs < rows { b.bottom = .none }
                if c + cs < grid.cols { b.right = .none }
                for (edge, line) in [(NSRectEdge.minX, b.left), (.maxX, b.right), (.minY, b.top), (.maxY, b.bottom)] {
                    block.setWidth(line.visible ? CGFloat(line.width) : 0, type: .absoluteValueType, for: .border, edge: edge)
                    block.setBorderColor(nsColor(line.color), for: edge)
                }
                let pad = cell.padding ?? (ctx.source == .docx ? .wordDefault : .hwpDefault)
                block.setWidth(CGFloat(pad.left), type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(CGFloat(pad.right), type: .absoluteValueType, for: .padding, edge: .maxX)
                block.setWidth(CGFloat(pad.top), type: .absoluteValueType, for: .padding, edge: .minY)
                block.setWidth(CGFloat(pad.bottom), type: .absoluteValueType, for: .padding, edge: .maxY)
                if let h = cell.height, rs == 1 {
                    let content = h - pad.top - pad.bottom - (b.top.visible ? b.top.width : 0) - (b.bottom.visible ? b.bottom.width : 0)
                    if content > 1 { block.setValue(CGFloat(content), type: .absoluteValueType, for: .minimumHeight) }
                    block.minimumBoxHeight = CGFloat(h)
                }
                switch cell.verticalAlign {
                case .top: block.verticalAlignment = .topAlignment
                case .center: block.verticalAlignment = .middleAlignment
                case .bottom: block.verticalAlignment = .bottomAlignment
                }
                if let bg = cell.background { block.backgroundColor = nsColor(bg) }
                var blocks = cell.blocks
                if blocks.isEmpty { blocks = [.paragraph(Paragraph())] }
                let inner = w - pad.left - pad.right
                let content = build(blocks, outer: outer + [block], width: inner, ctx: ctx)
                if content.length == 0 || !content.string.hasSuffix("\n") {
                    content.append(paragraph(Paragraph(), outer: outer + [block], width: inner, ctx: ctx))
                }
                out.append(content)
            }
        }
        return out
    }

    static func emptyTable(rows: Int, cols: Int, width: Double, source: SourceFormat) -> NSAttributedString {
        var t = Table()
        t.columnWidths = Array(repeating: width / Double(max(1, cols)), count: cols)
        var mark = CharProps()
        if source == .docx { mark.fontName = "Calibri"; mark.eastAsianFontName = "맑은 고딕"; mark.size = 11 }
        var p = Paragraph(); p.markProps = mark
        p.props.lineSpacing = source == .docx ? .multiple(1) : .percentOfSize(160)
        t.rows = (0..<rows).map { _ in (0..<cols).map { _ in TableCell(blocks: [.paragraph(p)]) } }
        return table(t, outer: [], width: width, ctx: Context(images: [:], source: source))
    }

    // MARK: Attributed string → model

    private struct Para { let range: NSRange; let blocks: [NSTextBlock] }

    static func document(from text: NSAttributedString, base: UDocument, page: PageSetup) -> UDocument {
        let doc = UDocument()
        doc.source = base.source
        doc.title = base.title
        doc.images = base.images
        let ns = text.string as NSString
        var paras: [Para] = []
        var loc = 0
        while loc < ns.length {
            let r = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let ps = text.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle
            paras.append(Para(range: r, blocks: ps?.textBlocks ?? []))
            loc = NSMaxRange(r)
        }
        var userImages = 0
        var blocks = build(paras[...], depth: 0, text: text, doc: doc, userImages: &userImages)
        if blocks.isEmpty { blocks = [.paragraph(Paragraph())] }
        doc.sections = [Section(page: page, blocks: blocks)]
        return doc
    }

    private static func build(_ paras: ArraySlice<Para>, depth: Int, text: NSAttributedString, doc: UDocument, userImages: inout Int) -> [Block] {
        var out: [Block] = []
        var i = paras.startIndex
        while i < paras.endIndex {
            let p = paras[i]
            if p.blocks.count > depth, let tb = p.blocks[depth] as? NSTextTableBlock {
                let table = tb.table
                var j = i
                while j < paras.endIndex, paras[j].blocks.count > depth,
                      let b = paras[j].blocks[depth] as? NSTextTableBlock, b.table === table { j += 1 }
                out.append(.table(makeTable(table, paras[i..<j], depth: depth, text: text, doc: doc, userImages: &userImages)))
                i = j
            } else {
                out.append(.paragraph(paragraph(p.range, text: text, doc: doc, userImages: &userImages)))
                i += 1
            }
        }
        return out
    }

    private static func makeTable(_ table: NSTextTable, _ paras: ArraySlice<Para>, depth: Int, text: NSAttributedString, doc: UDocument, userImages: inout Int) -> Table {
        var groups: [(block: NSTextTableBlock, paras: ArraySlice<Para>)] = []
        var k = paras.startIndex
        while k < paras.endIndex {
            let b = paras[k].blocks[depth] as! NSTextTableBlock
            var e = k
            while e < paras.endIndex, paras[e].blocks[depth] === b { e += 1 }
            groups.append((b, paras[k..<e]))
            k = e
        }
        let cols = max(1, table.numberOfColumns)
        let rows = groups.map { $0.block.startingRow + $0.block.rowSpan }.max() ?? 0
        var grid = [[TableCell?]](repeating: [TableCell?](repeating: nil, count: cols), count: rows)
        var widths = [Double](repeating: 0, count: cols)
        for g in groups {
            let b = g.block
            guard b.startingRow < rows, b.startingColumn < cols else { continue }
            var cell = (b as? GridCellBlock)?.source ?? TableCell()
            cell.blocks = build(g.paras, depth: depth + 1, text: text, doc: doc, userImages: &userImages)
            cell.colSpan = b.columnSpan
            cell.rowSpan = b.rowSpan
            cell.isMergedAway = false
            if b.valueType(for: .width) == .absoluteValueType { cell.width = Double(b.value(for: .width)) }
            cell.background = b.backgroundColor.map(rgb)
            switch b.verticalAlignment {
            case .middleAlignment: cell.verticalAlign = .center
            case .bottomAlignment: cell.verticalAlign = .bottom
            default: cell.verticalAlign = .top
            }
            grid[b.startingRow][b.startingColumn] = cell
            for rr in b.startingRow..<min(rows, b.startingRow + b.rowSpan) {
                for cc in b.startingColumn..<min(cols, b.startingColumn + b.columnSpan) where !(rr == b.startingRow && cc == b.startingColumn) {
                    var m = TableCell(); m.isMergedAway = true; grid[rr][cc] = m
                }
            }
            if b.columnSpan == 1, let w = cell.width, widths[b.startingColumn] == 0 { widths[b.startingColumn] = w }
        }
        var t = Table()
        let known = widths.filter { $0 > 0 }
        let avg = known.isEmpty ? 72 : known.reduce(0, +) / Double(known.count)
        t.columnWidths = (table as? GridTextTable)?.columnWidths.map(Double.init) ?? widths.map { $0 > 0 ? $0 : avg }
        if let bw = groups.first?.block.width(for: .border, edge: .minX), bw > 0 { t.borderWidth = Double(bw) }
        t.rows = grid.map { $0.map { $0 ?? TableCell(blocks: [.paragraph(Paragraph())]) } }
        return t
    }

    private static func rgb(_ c: NSColor) -> RGB {
        let s = c.usingColorSpace(.sRGB) ?? c
        func b(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return RGB(r: b(s.redComponent), g: b(s.greenComponent), b: b(s.blueComponent))
    }

    static func charProps(_ a: [NSAttributedString.Key: Any]) -> CharProps {
        var c = CharProps()
        let font = a[.font] as? NSFont ?? NSFont.systemFont(ofSize: 10)
        let family = font.familyName ?? font.fontName
        if let fam = a[.hwFamily] as? String, fam == family, let orig = a[.hwFont] as? String {
            c.fontName = orig
            let ea = a[.hwEastAsianFont] as? String ?? ""
            c.eastAsianFontName = ea.isEmpty ? nil : ea
        } else {
            c.fontName = family
            c.eastAsianFontName = family
        }
        c.size = Double(font.pointSize)
        let traits = NSFontManager.shared.traits(of: font)
        c.bold = traits.contains(.boldFontMask) || ((a[.strokeWidth] as? NSNumber)?.doubleValue ?? 0) < 0
        c.italic = traits.contains(.italicFontMask) || ((a[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0
        if let u = (a[.underlineStyle] as? NSNumber)?.intValue, u != 0 {
            let style = NSUnderlineStyle(rawValue: u)
            if a[.hwUnderline] as? String == "wave" { c.underline = .wave }
            else if style.contains(.double) { c.underline = .double }
            else if style.contains(.thick) { c.underline = .thick }
            else if style.contains(.patternDot) { c.underline = .dotted }
            else if style.contains(.patternDash) || style.contains(.patternDashDot) { c.underline = .dashed }
            else { c.underline = .single }
        }
        c.strike = ((a[.strikethroughStyle] as? NSNumber)?.intValue ?? 0) != 0
        if let fg = a[.foregroundColor] as? NSColor { c.color = rgb(fg) }
        if let bg = a[.backgroundColor] as? NSColor { c.highlight = rgb(bg) }
        let sup = (a[.superscript] as? NSNumber)?.intValue ?? 0
        c.verticalAlign = sup > 0 ? .superscript : sup < 0 ? .subscript : .baseline
        c.spacing = (a[.kern] as? NSNumber)?.doubleValue ?? 0
        if let e = (a[.expansion] as? NSNumber)?.doubleValue, e != 0 { c.widthRatio = (exp(e) * 100).rounded() }
        return c
    }

    static func paraProps(_ ps: NSParagraphStyle?, rule: String?) -> ParaProps {
        var p = ParaProps()
        guard let ps else { return p }
        switch ps.alignment {
        case .right: p.alignment = .right
        case .center: p.alignment = .center
        case .justified: p.alignment = .justify
        default: p.alignment = .left
        }
        p.indentLeft = Double(ps.headIndent)
        p.firstLine = Double(ps.firstLineHeadIndent - ps.headIndent)
        p.indentRight = ps.tailIndent < 0 ? Double(-ps.tailIndent) : 0
        p.spaceBefore = Double(ps.paragraphSpacingBefore)
        p.spaceAfter = Double(ps.paragraphSpacing)
        if let rule, rule.hasPrefix("pct:") {
            let parts = rule.split(separator: ":")
            if parts.count == 3, let pct = Double(parts[1]), let m = Double(parts[2]), abs(m - Double(ps.lineHeightMultiple)) < 0.001 {
                p.lineSpacing = .percentOfSize(pct)
                return p
            }
        }
        if ps.maximumLineHeight > 0 && ps.maximumLineHeight == ps.minimumLineHeight { p.lineSpacing = .exact(Double(ps.maximumLineHeight)) }
        else if ps.minimumLineHeight > 0 { p.lineSpacing = .atLeast(Double(ps.minimumLineHeight)) }
        else if ps.lineHeightMultiple > 0 { p.lineSpacing = .multiple(Double(ps.lineHeightMultiple)) }
        else { p.lineSpacing = .multiple(1) }
        return p
    }

    private static func paragraph(_ range: NSRange, text: NSAttributedString, doc: UDocument, userImages: inout Int) -> Paragraph {
        let ns = text.string as NSString
        var content = range
        while content.length > 0 {
            let ch = ns.character(at: NSMaxRange(content) - 1)
            if ch == 10 || ch == 13 || ch == 0x2029 { content.length -= 1 } else { break }
        }
        let markAt = min(max(0, NSMaxRange(range) - 1), max(0, text.length - 1))
        var para = Paragraph()
        if text.length > 0 {
            let attrs = text.attributes(at: markAt, effectiveRange: nil)
            para.markProps = charProps(attrs)
            let lineRule = text.attribute(.hwLineRule, at: range.location < text.length ? range.location : markAt, effectiveRange: nil) as? String
            para.props = paraProps(attrs[.paragraphStyle] as? NSParagraphStyle, rule: lineRule)
            para.props.styleName = attrs[.hwStyle] as? String
        }
        var pending = ""
        var pendingProps: CharProps?
        func flush() {
            if let pp = pendingProps, !pending.isEmpty { para.inlines.append(.text(pending, pp)) }
            pending = ""
        }
        text.enumerateAttributes(in: content, options: []) { attrs, r, _ in
            if let k = (attrs[.hwField] as? String).flatMap(FieldKind.init(rawValue:)) {
                flush()
                var c = charProps(attrs)
                c.highlight = nil
                para.inlines.append(.field(k, c))
                return
            }
            let cp = charProps(attrs)
            if pendingProps != cp { flush(); pendingProps = cp }
            let sub = ns.substring(with: r)
            for ch in sub {
                switch ch {
                case "\t": flush(); para.inlines.append(.tab(cp))
                case "\u{2028}": flush(); para.inlines.append(.lineBreak(cp))
                case "\u{0C}":
                    flush()
                    if para.inlines.isEmpty { para.props.pageBreakBefore = true } else { para.inlines.append(.pageBreak) }
                case "\u{FFFC}":
                    flush()
                    if let att = attrs[.attachment] as? NSTextAttachment, let img = imageInline(att, id: attrs[.hwImage] as? String, doc: doc, userImages: &userImages) {
                        para.inlines.append(img)
                    }
                default: pending.append(ch)
                }
            }
        }
        flush()
        return para
    }

    private static func imageInline(_ att: NSTextAttachment, id: String?, doc: UDocument, userImages: inout Int) -> Inline? {
        let size = att.bounds.size
        if let id, doc.images[id] != nil {
            return .image(id: id, width: Double(size.width), height: Double(size.height))
        }
        var data = att.fileWrapper?.regularFileContents
        var name = att.fileWrapper?.preferredFilename ?? ""
        let image = att.image ?? data.flatMap { NSImage(data: $0) }
        if data == nil || NSImage(data: data!) == nil, let img = image, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            data = png; name = ""
        }
        guard let bytes = data else { return nil }
        userImages += 1
        var ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty { ext = "png" }
        let key = "user/image\(userImages).\(ext)"
        doc.images[key] = ImageData(name: "image\(userImages).\(ext)", data: bytes)
        var w = Double(size.width), h = Double(size.height)
        if (w <= 1 || h <= 1), let s = image?.size { w = s.width; h = s.height }
        return .image(id: key, width: w, height: h)
    }
}

/// Table that places cells on explicit column boundaries. AppKit's own
/// algorithms derive column widths from the first row and mis-handle cells
/// that span columns; HWP and Word both lay tables out on a fixed grid.
final class GridTextTable: NSTextTable {
    var columnWidths: [CGFloat] = []

    convenience init(columnWidths: [CGFloat]) {
        self.init()
        self.columnWidths = columnWidths
        numberOfColumns = columnWidths.count
        collapsesBorders = false
        hidesEmptyCells = false
        layoutAlgorithm = .fixedLayoutAlgorithm
        setValue(columnWidths.reduce(0, +), type: .absoluteValueType, for: .width)
    }

    private func span(_ b: NSTextTableBlock) -> (x: CGFloat, width: CGFloat) {
        guard !columnWidths.isEmpty else { return (0, 0) }
        let c = max(0, min(b.startingColumn, columnWidths.count - 1))
        let e = max(c + 1, min(columnWidths.count, b.startingColumn + b.columnSpan))
        return (columnWidths[..<c].reduce(0, +), columnWidths[c..<e].reduce(0, +))
    }

    func contentWidth(_ b: NSTextTableBlock) -> CGFloat {
        max(1, span(b).width - inset(b, .minX) - inset(b, .maxX))
    }

    func inset(_ b: NSTextBlock, _ edge: NSRectEdge) -> CGFloat {
        b.width(for: .padding, edge: edge) + b.width(for: .border, edge: edge) + b.width(for: .margin, edge: edge)
    }

    override func rect(for block: NSTextTableBlock, layoutAt startingPoint: NSPoint, in rect: NSRect,
                       textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        var r = super.rect(for: block, layoutAt: startingPoint, in: rect, textContainer: textContainer, characterRange: charRange)
        guard !columnWidths.isEmpty else { return r }
        let s = span(block)
        r.origin.x = rect.minX + s.x + inset(block, .minX)
        r.size.width = max(1, s.width - inset(block, .minX) - inset(block, .maxX))
        return r
    }

    override func boundsRect(for block: NSTextTableBlock, contentRect: NSRect, in rect: NSRect,
                             textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        var r = super.boundsRect(for: block, contentRect: contentRect, in: rect, textContainer: textContainer, characterRange: charRange)
        guard !columnWidths.isEmpty else { return r }
        let s = span(block)
        r.origin.x = rect.minX + s.x
        r.size.width = s.width
        return r
    }
}

/// Cell block that remembers the model cell it came from, so properties
/// TextKit cannot show (border styles, fixed heights) survive a save.
final class GridCellBlock: NSTextTableBlock {
    var source: TableCell?
    /// Fixed row height from the source file (border box), if any.
    var minimumBoxHeight: CGFloat?
}

/// Applies fixed row heights from HWP/DOCX files. TextKit sizes table rows
/// from the lines inside the cells, so the missing height is added to a
/// cell's first and/or last line fragment according to its vertical
/// alignment (called from the layout manager delegate).
enum TableRowSizer {
    private static var cache: [ObjectIdentifier: (length: Int, hash: Int, height: CGFloat)] = [:]

    static func adjust(_ lm: NSLayoutManager, lineRect: UnsafeMutablePointer<NSRect>, usedRect: UnsafeMutablePointer<NSRect>,
                       baseline: UnsafeMutablePointer<CGFloat>, glyphRange: NSRange) {
        guard let storage = lm.textStorage, glyphRange.length > 0 else { return }
        let chars = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard chars.location < storage.length,
              let ps = storage.attribute(.paragraphStyle, at: chars.location, effectiveRange: nil) as? NSParagraphStyle,
              let block = ps.textBlocks.last as? GridCellBlock, let minBox = block.minimumBoxHeight,
              let table = block.table as? GridTextTable else { return }
        let cell = storage.range(of: block, at: chars.location)
        let first = chars.location == cell.location
        let last = NSMaxRange(chars) >= NSMaxRange(cell)
        guard first || last else { return }
        let target = minBox - table.inset(block, .minY) - table.inset(block, .maxY)
        let natural = naturalHeight(storage, cell, block: block, width: table.contentWidth(block), depth: ps.textBlocks.count)
        let extra = max(0, target - natural)
        guard extra > 0.5 else { return }
        let above: CGFloat
        switch block.verticalAlignment {
        case .middleAlignment: above = (extra / 2).rounded(.down)
        case .bottomAlignment: above = extra
        default: above = 0
        }
        if first && above > 0 {
            lineRect.pointee.size.height += above
            usedRect.pointee.origin.y += above
            baseline.pointee += above
        }
        if last {
            lineRect.pointee.size.height += extra - above
            usedRect.pointee.size.height += extra - above
        }
    }

    private static func naturalHeight(_ storage: NSTextStorage, _ range: NSRange, block: NSTextBlock, width: CGFloat, depth: Int) -> CGFloat {
        let sub = storage.attributedSubstring(from: range)
        let key = ObjectIdentifier(block)
        let hash = sub.string.hashValue
        if let c = cache[key], c.length == range.length, c.hash == hash { return c.height }
        // Measure the cell's text on its own: strip the table blocks so the
        // typesetter lays it out as plain paragraphs at the cell width.
        let plain = NSMutableAttributedString(attributedString: sub)
        var nested = false
        plain.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: plain.length)) { v, r, _ in
            guard let ps = v as? NSParagraphStyle, let m = ps.mutableCopy() as? NSMutableParagraphStyle else { return }
            if ps.textBlocks.count > depth { nested = true }
            m.textBlocks = []
            plain.addAttribute(.paragraphStyle, value: m, range: r)
        }
        var h: CGFloat = .greatestFiniteMagnitude
        if !nested {
            let s = plain.string.hasSuffix("\n") ? plain.attributedSubstring(from: NSRange(location: 0, length: plain.length - 1)) : plain
            let measured = s.length == 0
                ? (plain.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map { NSLayoutManager().defaultLineHeight(for: $0) } ?? 14
                : s.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            h = ceil(measured)
        }
        cache[key] = (range.length, hash, h)
        return h
    }
}

/// Style names HanWord applies; carried as an attribute so they survive editing.
enum EditorStyleNames {
    static let known: Set<String> = ["바탕글", "제목", "부제목", "제목 1", "제목 2", "제목 3", "본문", "인용", "강조"]
    /// WordprocessingML built-in style ids for the names above.
    static let wordIDs: [String: String] = ["제목": "Title", "부제목": "Subtitle", "제목 1": "Heading1", "제목 2": "Heading2",
                                            "제목 3": "Heading3", "인용": "Quote", "강조": "IntenseQuote"]
}
