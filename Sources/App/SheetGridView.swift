import AppKit

protocol SheetGridDelegate: AnyObject {
    func gridSelectionChanged()
    func gridCommit(_ ref: CellRef, input: String)
    func gridClear(_ range: CellRange)
    func gridPaste(_ text: String, at: CellRef)
    func gridColumnResized(_ col: Int, width: Double)
    func gridChartsChanged(from old: [SheetChart], name: String)
    func gridEditChart(_ index: Int)
}

/// Spreadsheet grid: sticky row/column headers, selection, in-place editing.
final class SheetGridView: NSView, NSTextFieldDelegate {
    weak var delegate: SheetGridDelegate?
    var sheet: Worksheet { didSet { reloadSize(); needsDisplay = true } }
    let engine: FormulaEngine

    var anchor = CellRef(row: 0, col: 0)
    var cursor = CellRef(row: 0, col: 0)
    var selection: CellRange { CellRange(anchor, cursor) }

    private var headerW: CGFloat { printMode ? 0 : 46 }
    private var headerH: CGFloat { printMode ? 0 : 22 }
    private var editor: NSTextField?
    private var editingRef: CellRef?
    private var resizingCol: Int?
    private var resizeStartX: CGFloat = 0, resizeStartW: Double = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(sheet: Worksheet, engine: FormulaEngine) {
        self.sheet = sheet
        self.engine = engine
        super.init(frame: .zero)
        reloadSize()
    }

    required init?(coder: NSCoder) { fatalError() }

    var rowCount: Int { max(200, (sheet.usedRange?.end.row ?? 0) + 60, cursor.row + 30) }
    var colCount: Int { max(40, (sheet.usedRange?.end.col ?? 0) + 15, cursor.col + 10) }

    func reloadSize() {
        var w = headerW, h = headerH
        for c in 0..<colCount { w += CGFloat(sheet.width(c)) }
        for r in 0..<rowCount { h += CGFloat(sheet.height(r)) }
        setFrameSize(NSSize(width: w, height: h))
    }

    // MARK: Geometry

    func x(ofCol c: Int) -> CGFloat { headerW + (0..<c).reduce(0) { $0 + CGFloat(sheet.width($1)) } }
    func y(ofRow r: Int) -> CGFloat { headerH + (0..<r).reduce(0) { $0 + CGFloat(sheet.height($1)) } }

    func rect(_ ref: CellRef) -> NSRect {
        if let m = sheet.merge(containing: ref) { return rect(of: m) }
        return NSRect(x: x(ofCol: ref.col), y: y(ofRow: ref.row), width: CGFloat(sheet.width(ref.col)), height: CGFloat(sheet.height(ref.row)))
    }

    func rect(of range: CellRange) -> NSRect {
        let a = NSRect(x: x(ofCol: range.start.col), y: y(ofRow: range.start.row), width: 0, height: 0)
        let w = (range.start.col...range.end.col).reduce(0) { $0 + CGFloat(sheet.width($1)) }
        let h = (range.start.row...range.end.row).reduce(0) { $0 + CGFloat(sheet.height($1)) }
        return NSRect(x: a.minX, y: a.minY, width: w, height: h)
    }

    func cell(at p: NSPoint) -> CellRef {
        var c = 0, xx = headerW
        while c < colCount - 1 && xx + CGFloat(sheet.width(c)) < p.x { xx += CGFloat(sheet.width(c)); c += 1 }
        var r = 0, yy = headerH
        while r < rowCount - 1 && yy + CGFloat(sheet.height(r)) < p.y { yy += CGFloat(sheet.height(r)); r += 1 }
        return CellRef(row: r, col: c)
    }

    // MARK: Drawing

    override func draw(_ dirty: NSRect) {
        NSColor.white.setFill(); dirty.fill()
        let vis = visibleRect
        let first = cell(at: NSPoint(x: max(dirty.minX, headerW), y: max(dirty.minY, headerH)))
        let last = cell(at: NSPoint(x: dirty.maxX, y: dirty.maxY))
        let grid = printMode ? NSColor.clear : NSColor(white: 0.86, alpha: 1)

        drawCells(rows: first.row...last.row, cols: first.col...last.col, grid: grid)

        drawCharts()
        if printMode { return }

        // Selection
        let sel = rect(of: expandedSelection())
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        sel.fill()
        NSColor.controlAccentColor.setStroke()
        let sp = NSBezierPath(rect: sel.insetBy(dx: 0.5, dy: 0.5)); sp.lineWidth = 2; sp.stroke()
        // Spill range outline (Excel's thin blue border around a dynamic array).
        if let spill = engine.spillRange(sheet, cursor), spill.start != spill.end {
            NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
            let b = NSBezierPath(rect: rect(of: spill).insetBy(dx: 1, dy: 1))
            b.lineWidth = 1
            b.setLineDash([4, 2], count: 2, phase: 0)
            b.stroke()
        }

        drawFrozen(grid: grid, first: first, last: last)

        // Sticky headers
        let hdrBg = NSColor(white: 0.95, alpha: 1)
        let hdrAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray]
        let topBar = NSRect(x: vis.minX, y: vis.minY, width: vis.width, height: headerH)
        hdrBg.setFill(); topBar.fill()
        for c in first.col...last.col {
            let r = NSRect(x: x(ofCol: c), y: vis.minY, width: CGFloat(sheet.width(c)), height: headerH)
            if c >= selection.start.col && c <= selection.end.col { NSColor.controlAccentColor.withAlphaComponent(0.2).setFill(); r.fill() }
            grid.setStroke(); NSBezierPath.stroke(NSRect(x: r.maxX, y: r.minY, width: 0, height: r.height))
            let s = NSAttributedString(string: CellRef.columnName(c), attributes: hdrAttrs)
            s.draw(at: NSPoint(x: r.midX - s.size().width / 2, y: r.minY + 4))
        }
        let leftBar = NSRect(x: vis.minX, y: vis.minY, width: headerW, height: vis.height)
        hdrBg.setFill(); leftBar.fill()
        for r in first.row...last.row {
            let rr = NSRect(x: vis.minX, y: y(ofRow: r), width: headerW, height: CGFloat(sheet.height(r)))
            if rr.maxY < vis.minY + headerH { continue }
            if r >= selection.start.row && r <= selection.end.row { NSColor.controlAccentColor.withAlphaComponent(0.2).setFill(); rr.fill() }
            grid.setStroke(); NSBezierPath.stroke(NSRect(x: rr.minX, y: rr.maxY, width: rr.width, height: 0))
            let s = NSAttributedString(string: String(r + 1), attributes: hdrAttrs)
            s.draw(at: NSPoint(x: rr.midX - s.size().width / 2, y: rr.midY - 7))
        }
        hdrBg.setFill(); NSRect(x: vis.minX, y: vis.minY, width: headerW, height: headerH).fill()
        grid.setStroke()
        NSBezierPath.stroke(NSRect(x: vis.minX, y: vis.minY + headerH, width: vis.width, height: 0))
        NSBezierPath.stroke(NSRect(x: vis.minX + headerW, y: vis.minY, width: 0, height: vis.height))
    }

    private func drawCells(rows: ClosedRange<Int>, cols: ClosedRange<Int>, grid: NSColor) {
        var drawnMerges = Set<CellRange>()
        for r in rows {
            for c in cols {
                let ref = CellRef(row: r, col: c)
                var area = rect(ref)
                if let m = sheet.merge(containing: ref) {
                    if drawnMerges.contains(m) { continue }
                    drawnMerges.insert(m)
                    area = rect(of: m)
                }
                let cell = sheet.cells[sheet.merge(containing: ref)?.start ?? ref]
                if let fill = cell?.style.fill { AttributedBridge.nsColor(fill).setFill(); area.fill() }
                grid.setStroke()
                let path = NSBezierPath(rect: area.insetBy(dx: -0.25, dy: -0.25))
                path.lineWidth = 0.5
                path.stroke()
                if cell?.style.border == true {
                    NSColor.black.setStroke()
                    let b = NSBezierPath(rect: area); b.lineWidth = 0.8; b.stroke()
                }
                guard editingRef != ref else { continue }
                if let cell, !cell.input.isEmpty {
                    drawText(cell, ref: sheet.merge(containing: ref)?.start ?? ref, in: area)
                } else if engine.value(sheet, ref) != .empty {
                    // Part of a dynamic-array spill from another cell.
                    drawText(cell ?? SheetCell(), ref: ref, in: area)
                }
            }
        }
    }

    // MARK: Charts

    var selectedChart: Int? { didSet { needsDisplay = true } }
    private var chartDrag: (index: Int, start: NSPoint, original: SheetChart, resize: Bool)?

    func chartRect(_ c: SheetChart) -> NSRect {
        NSRect(x: headerW + CGFloat(c.x), y: headerH + CGFloat(c.y), width: CGFloat(c.w), height: CGFloat(c.h))
    }

    private func drawCharts() {
        for (i, c) in sheet.charts.enumerated() {
            let r = chartRect(c)
            guard r.intersects(visibleRect) || printMode else { continue }
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 4; shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowColor = NSColor.black.withAlphaComponent(printMode ? 0 : 0.2)
            shadow.set()
            NSColor.white.setFill(); r.fill()
            NSGraphicsContext.restoreGraphicsState()
            ChartRenderer.draw(c, ws: sheet, engine: engine, in: r, selected: !printMode && selectedChart == i)
            if !printMode && selectedChart == i {
                NSColor.controlAccentColor.setFill()
                NSRect(x: r.maxX - 5, y: r.maxY - 5, width: 10, height: 10).fill()
            }
        }
    }

    // MARK: Freeze panes

    private var frozenHeight: CGFloat { (0..<sheet.frozenRows).reduce(0) { $0 + CGFloat(sheet.height($1)) } }
    private var frozenWidth: CGFloat { (0..<sheet.frozenCols).reduce(0) { $0 + CGFloat(sheet.width($1)) } }

    /// Frozen rows/columns are redrawn pinned below/right of the headers.
    private func drawFrozen(grid: NSColor, first: CellRef, last: CellRef) {
        let vis = visibleRect
        func pinned(_ clip: NSRect, dx: CGFloat, dy: CGFloat, rows: ClosedRange<Int>, cols: ClosedRange<Int>) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: clip).addClip()
            NSColor.white.setFill(); clip.fill()
            let t = NSAffineTransform(); t.translateX(by: dx, yBy: dy); t.concat()
            drawCells(rows: rows, cols: cols, grid: grid)
            NSGraphicsContext.restoreGraphicsState()
        }
        let fh = frozenHeight, fw = frozenWidth
        let dy = vis.minY, dx = vis.minX
        if sheet.frozenRows > 0 && dy > 0 {
            pinned(NSRect(x: vis.minX, y: vis.minY + headerH, width: vis.width, height: fh), dx: 0, dy: dy,
                   rows: 0...(sheet.frozenRows - 1), cols: first.col...last.col)
        }
        if sheet.frozenCols > 0 && dx > 0 {
            pinned(NSRect(x: vis.minX + headerW, y: vis.minY, width: fw, height: vis.height), dx: dx, dy: 0,
                   rows: first.row...last.row, cols: 0...(sheet.frozenCols - 1))
        }
        if sheet.frozenRows > 0 && sheet.frozenCols > 0 && (dx > 0 || dy > 0) {
            pinned(NSRect(x: vis.minX + headerW, y: vis.minY + headerH, width: fw, height: fh), dx: dx, dy: dy,
                   rows: 0...(sheet.frozenRows - 1), cols: 0...(sheet.frozenCols - 1))
        }
        NSColor.systemGray.setStroke()
        // The freeze line sits at the pane edge, pinned while scrolled.
        if sheet.frozenRows > 0 {
            let line = max(0, dy) + headerH + fh
            NSBezierPath.strokeLine(from: NSPoint(x: vis.minX, y: line), to: NSPoint(x: vis.maxX, y: line))
        }
        if sheet.frozenCols > 0 {
            let line = max(0, dx) + headerW + fw
            NSBezierPath.strokeLine(from: NSPoint(x: line, y: vis.minY), to: NSPoint(x: line, y: vis.maxY))
        }
    }

    /// Cell under a mouse point, honouring pinned frozen panes.
    func hitCell(at p: NSPoint) -> CellRef {
        let vis = visibleRect
        var q = p
        if sheet.frozenRows > 0, vis.minY > 0, p.y - vis.minY - headerH < frozenHeight { q.y = p.y - vis.minY }
        if sheet.frozenCols > 0, vis.minX > 0, p.x - vis.minX - headerW < frozenWidth { q.x = p.x - vis.minX }
        return cell(at: q)
    }

    private func expandedSelection() -> CellRange {
        var r = selection
        for m in sheet.merges where m.start.row <= r.end.row && m.end.row >= r.start.row && m.start.col <= r.end.col && m.end.col >= r.start.col {
            r = CellRange(CellRef(row: min(r.start.row, m.start.row), col: min(r.start.col, m.start.col)),
                          CellRef(row: max(r.end.row, m.end.row), col: max(r.end.col, m.end.col)))
        }
        return r
    }

    private func drawText(_ cell: SheetCell, ref: CellRef, in area: NSRect) {
        let value = engine.value(sheet, ref)
        let text = engine.display(sheet, ref)
        let st = cell.style
        var font = FontResolver.shared.font(name: st.fontName ?? "맑은 고딕", size: st.fontSize ?? 11, bold: st.bold, italic: st.italic).font
        if font.pointSize > 30 { font = NSFontManager.shared.convert(font, toSize: 30) }
        var color = st.color.map(AttributedBridge.nsColor) ?? .black
        if value.isError { color = .systemRed }
        let para = NSMutableParagraphStyle()
        let isNumber: Bool = { if case .number = value { return true }; return false }()
        switch st.align {
        case .left: para.alignment = .left
        case .center: para.alignment = .center
        case .right: para.alignment = .right
        case .general: para.alignment = isNumber || value.isError ? .right : (value.truthy != nil && { if case .bool = value { return true }; return false }() ? .center : .left)
        }
        para.lineBreakMode = st.wrap ? .byWordWrapping : .byClipping
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        if st.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let s = NSAttributedString(string: text, attributes: attrs)
        let inner = area.insetBy(dx: 3, dy: 1)
        let h = st.wrap ? s.boundingRect(with: NSSize(width: inner.width, height: 1e6), options: [.usesLineFragmentOrigin]).height : font.ascender - font.descender + font.leading
        let y = inner.minY + max(0, (inner.height - h) / 2)
        NSGraphicsContext.saveGraphicsState()
        // Text may overflow into empty neighbours on the right, like Excel.
        var clip = inner
        if !st.wrap && !isNumber && para.alignment == .left {
            var c = ref.col + 1
            while c < colCount, sheet.cells[CellRef(row: ref.row, col: c)]?.input.isEmpty ?? true,
                  engine.value(sheet, CellRef(row: ref.row, col: c)) == .empty, clip.width < s.size().width + 6, c < ref.col + 20 {
                clip.size.width += CGFloat(sheet.width(c)); c += 1
            }
        }
        NSBezierPath(rect: clip).addClip()
        s.draw(with: NSRect(x: inner.minX, y: y, width: st.wrap ? inner.width : max(inner.width, clip.width), height: inner.maxY - y), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        commitEdit()
        if p.y - visibleRect.minY < headerH {
            // Column header: resize when near an edge, else select the column.
            for c in 0..<colCount {
                let edge = x(ofCol: c + 1)
                if abs(p.x - edge) < 4 { resizingCol = c; resizeStartX = p.x; resizeStartW = sheet.width(c); return }
                if edge > p.x { break }
            }
            let c = cell(at: NSPoint(x: p.x, y: headerH + 1)).col
            anchor = CellRef(row: 0, col: c); cursor = CellRef(row: rowCount - 1, col: c)
            changed(); return
        }
        if p.x - visibleRect.minX < headerW {
            let r = cell(at: NSPoint(x: headerW + 1, y: p.y)).row
            anchor = CellRef(row: r, col: 0); cursor = CellRef(row: r, col: colCount - 1)
            changed(); return
        }
        for (i, c) in sheet.charts.enumerated().reversed() {
            let r = chartRect(c)
            guard r.insetBy(dx: -6, dy: -6).contains(p) else { continue }
            selectedChart = i
            let corner = NSRect(x: r.maxX - 10, y: r.maxY - 10, width: 16, height: 16).contains(p)
            chartDrag = (i, p, c, corner)
            if event.clickCount == 2 { chartDrag = nil; delegate?.gridEditChart(i) }
            return
        }
        selectedChart = nil
        let ref = hitCell(at: p)
        if event.modifierFlags.contains(.shift) { cursor = ref } else { anchor = ref; cursor = ref }
        if event.clickCount == 2 { beginEdit(nil) }
        changed()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let d = chartDrag, d.index < sheet.charts.count {
            let dx = Double(p.x - d.start.x), dy = Double(p.y - d.start.y)
            var c = d.original
            if d.resize { c.w = max(120, c.w + dx); c.h = max(90, c.h + dy) }
            else { c.x = max(0, c.x + dx); c.y = max(0, c.y + dy) }
            sheet.charts[d.index] = c
            needsDisplay = true
            return
        }
        if let c = resizingCol {
            sheet.columnWidths[c] = max(12, resizeStartW + Double(p.x - resizeStartX))
            reloadSize(); needsDisplay = true
            return
        }
        cursor = hitCell(at: p)
        autoscroll(with: event)
        changed()
    }

    override func mouseUp(with event: NSEvent) {
        if let d = chartDrag {
            chartDrag = nil
            if d.index < sheet.charts.count, sheet.charts[d.index] != d.original {
                var old = sheet.charts
                old[d.index] = d.original
                delegate?.gridChartsChanged(from: old, name: d.resize ? "차트 크기" : "차트 이동")
            }
            return
        }
        if let c = resizingCol { delegate?.gridColumnResized(c, width: sheet.width(c)); resizingCol = nil }
    }

    override func resetCursorRects() {
        let vis = visibleRect
        for c in 0..<colCount {
            let e = x(ofCol: c + 1)
            if e < vis.minX { continue }
            if e > vis.maxX { break }
            addCursorRect(NSRect(x: e - 3, y: vis.minY, width: 6, height: headerH), cursor: .resizeLeftRight)
        }
    }

    private func changed() {
        needsDisplay = true
        scrollToVisible(rect(cursor).insetBy(dx: -headerW, dy: -headerH))
        delegate?.gridSelectionChanged()
    }

    func select(_ ref: CellRef) { anchor = ref; cursor = ref; changed() }

    // MARK: Keyboard

    override func menu(for event:NSEvent)->NSMenu? {
        commitEdit(); window?.makeFirstResponder(self)
        let point=convert(event.locationInWindow,from:nil)
        let menu=NSMenu(title:"셀")
        if let index=sheet.charts.indices.reversed().first(where:{chartRect(sheet.charts[$0]).contains(point)}) {
            selectedChart=index; needsDisplay=true
            let edit=NSMenuItem(title:"차트 편집",action:#selector(editSelectedChart(_:)),keyEquivalent:""); edit.target=self; menu.addItem(edit)
            let remove=NSMenuItem(title:"차트 삭제",action:#selector(delete(_:)),keyEquivalent:""); remove.target=self; menu.addItem(remove)
            return menu
        }
        selectedChart=nil
        let ref=hitCell(at:point)
        if point.x-visibleRect.minX<headerW { anchor=CellRef(row:ref.row,col:0); cursor=CellRef(row:ref.row,col:colCount-1); changed() }
        else if point.y-visibleRect.minY<headerH { anchor=CellRef(row:0,col:ref.col); cursor=CellRef(row:rowCount-1,col:ref.col); changed() }
        else if !selection.contains(ref) { select(ref) }
        for (title,action,key) in [("잘라내기",#selector(cut(_:)),"x"),("복사",#selector(copy(_:)),"c"),("붙여넣기",#selector(paste(_:)),"v"),("내용 지우기",#selector(delete(_:)),"")] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:key); item.target=self; menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title,action) in [("행 삽입",#selector(SheetWindowController.insertRow(_:))),("행 삭제",#selector(SheetWindowController.deleteRow(_:))),("열 삽입",#selector(SheetWindowController.insertColumn(_:))),("열 삭제",#selector(SheetWindowController.deleteColumn(_:))),("셀 병합 / 해제",#selector(SheetWindowController.mergeCells(_:))),("열 너비 자동 맞춤",#selector(autoFitFromMenu(_:)))] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:""); if action == #selector(autoFitFromMenu(_:)) { item.target=self }; menu.addItem(item)
        }
        return menu
    }
    @objc private func editSelectedChart(_ sender:Any?) { if let selectedChart { delegate?.gridEditChart(selectedChart) } }
    @objc private func autoFitFromMenu(_ sender:Any?) { (window?.windowController as? SheetWindowController)?.ribbonCommand("autofit","") }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        func move(_ dr: Int, _ dc: Int) {
            let n = CellRef(row: max(0, cursor.row + dr), col: max(0, cursor.col + dc))
            if shift { cursor = n } else { anchor = n; cursor = n }
            changed()
        }
        switch event.keyCode {
        case 123: move(0, -1)
        case 124: move(0, 1)
        case 125: move(1, 0)
        case 126: move(-1, 0)
        case 48: move(0, shift ? -1 : 1)                        // tab
        case 36, 76: if shift { move(-1, 0) } else { beginEdit(nil) }   // return
        case 51, 117:
            if let i = selectedChart, i < sheet.charts.count {
                let old = sheet.charts
                sheet.charts.remove(at: i)
                selectedChart = nil
                delegate?.gridChartsChanged(from: old, name: "차트 삭제")
            } else {
                delegate?.gridClear(selection); needsDisplay = true
            }
        case 116: move(-20, 0)
        case 121: move(20, 0)
        case 120: beginEdit(nil)                                // F2
        default:
            if let chars = event.characters, !chars.isEmpty, !event.modifierFlags.contains(.command),
               let scalar = chars.unicodeScalars.first, scalar.value >= 32 {
                beginEdit(chars)
            } else if !event.modifierFlags.contains(.command) {
                // Hangul and other IMEs send composing input through interpretKeyEvents.
                beginEdit("")
                editor?.currentEditor()?.keyDown(with: event)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @objc func copy(_ sender: Any?) {
        let r = selection
        var lines: [String] = []
        for row in r.start.row...min(r.end.row, (sheet.usedRange?.end.row ?? r.start.row)) {
            lines.append((r.start.col...min(r.end.col, (sheet.usedRange?.end.col ?? r.start.col))).map {
                engine.display(sheet, CellRef(row: row, col: $0))
            }.joined(separator: "\t"))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc func cut(_ sender: Any?) { copy(sender); delegate?.gridClear(selection); needsDisplay = true }
    @objc func paste(_ sender: Any?) {
        if let s = NSPasteboard.general.string(forType: .string) { delegate?.gridPaste(s, at: selection.start); needsDisplay = true }
    }
    @objc override func selectAll(_ sender: Any?) {
        anchor = CellRef(row: 0, col: 0); cursor = CellRef(row: rowCount - 1, col: colCount - 1); changed()
    }
    @objc func delete(_ sender: Any?) {
        if let i=selectedChart,sheet.charts.indices.contains(i) { let old=sheet.charts; sheet.charts.remove(at:i); selectedChart=nil; delegate?.gridChartsChanged(from:old,name:"차트 삭제") }
        else { delegate?.gridClear(selection) }
        needsDisplay=true
    }

    // MARK: Editing

    func beginEdit(_ initial: String?) {
        commitEdit()
        let ref = sheet.merge(containing: cursor)?.start ?? cursor
        let f = NSTextField(frame: rect(ref).insetBy(dx: -1, dy: -1))
        f.stringValue = initial ?? (sheet.cells[ref]?.input ?? "")
        f.font = .systemFont(ofSize: 12)
        f.isBordered = true
        f.focusRingType = .none
        f.delegate = self
        f.cell?.isScrollable = true
        addSubview(f)
        editor = f
        editingRef = ref
        window?.makeFirstResponder(f)
        if let ed = f.currentEditor() { ed.selectedRange = NSRange(location: f.stringValue.utf16.count, length: 0) }
        needsDisplay = true
    }

    var isEditing: Bool { editor != nil }
    var editingText: String? { editor?.stringValue }

    func commitEdit() {
        guard let f = editor, let ref = editingRef else { return }
        editor = nil; editingRef = nil
        let value = f.stringValue
        f.removeFromSuperview()
        delegate?.gridCommit(ref, input: value)
        needsDisplay = true
    }

    func cancelEdit() {
        editor?.removeFromSuperview(); editor = nil; editingRef = nil
        window?.makeFirstResponder(self); needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            commitEdit(); window?.makeFirstResponder(self)
            anchor = CellRef(row: cursor.row + 1, col: cursor.col); cursor = anchor; changed(); return true
        case #selector(NSResponder.insertTab(_:)):
            commitEdit(); window?.makeFirstResponder(self)
            anchor = CellRef(row: cursor.row, col: cursor.col + 1); cursor = anchor; changed(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelEdit(); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if editor != nil { commitEdit() }
    }

    // MARK: Printing / PDF

    /// Hides headers and selection so the view can be rendered to PDF.
    var printMode = false { didSet { reloadSize(); needsDisplay = true } }

    /// One PDF page per slice of the used range, each at most `pageSize`.
    func pdfPages(pageSize: NSSize) -> [Data] {
        guard let used = sheet.usedRange else { return [] }
        let full = rect(of: CellRange(CellRef(row: 0, col: 0), used.end))
        var pages: [Data] = []
        var top = full.minY
        while top < full.maxY - 0.5 {
            var bottom = top
            var r = cell(at: NSPoint(x: headerW + 1, y: top + 0.5)).row
            while r <= used.end.row && y(ofRow: r) + CGFloat(sheet.height(r)) - top <= pageSize.height { bottom = y(ofRow: r) + CGFloat(sheet.height(r)); r += 1 }
            if bottom <= top { bottom = min(full.maxY, top + pageSize.height) }
            var left = full.minX
            while left < full.maxX - 0.5 {
                var right = left
                var c = cell(at: NSPoint(x: left + 0.5, y: headerH + 1)).col
                while c <= used.end.col && x(ofCol: c) + CGFloat(sheet.width(c)) - left <= pageSize.width { right = x(ofCol: c) + CGFloat(sheet.width(c)); c += 1 }
                if right <= left { right = min(full.maxX, left + pageSize.width) }
                pages.append(dataWithPDF(inside: NSRect(x: left, y: top, width: right - left, height: bottom - top)))
                left = right
            }
            top = bottom
        }
        return pages
    }
}
