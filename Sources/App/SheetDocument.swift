import AppKit
import PDFKit

extension DocType {
    static let xlsx = "org.openxmlformats.spreadsheetml.sheet"
    static let csv = "public.comma-separated-values-text"
    static let tsv = "public.tab-separated-values-text"
    static let pdf = "com.adobe.pdf"
    static let html = "public.html"
}

@objc(SheetDocument)
final class SheetDocument: NSDocument {
    private(set) var book = Workbook()
    private(set) lazy var engine = FormulaEngine(book: book)
    private var inPlaceSaveConfirmed = false

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { [DocType.xlsx, DocType.csv, DocType.tsv] }
    override class var writableTypes: [String] { [DocType.xlsx, DocType.csv, DocType.tsv, DocType.html, DocType.pdf] }
    override class func isNativeType(_ type: String) -> Bool { type == DocType.xlsx }

    override func makeWindowControllers() { addWindowController(SheetWindowController(document: self)) }

    override func read(from url: URL, ofType typeName: String) throws {
        do { book = try SheetIO.load(url: url) } catch let e as FormatError {
            throw NSError(domain: "HanX", code: 1, userInfo: [NSLocalizedDescriptionKey: "문서를 열 수 없습니다", NSLocalizedFailureReasonErrorKey: e.description])
        }
        engine = FormulaEngine(book: book)
    }

    var currentSheetIndex = 0

    override func data(ofType typeName: String) throws -> Data {
        windowControllers.compactMap { $0 as? SheetWindowController }.forEach { $0.commitPendingEditing() }
        switch typeName {
        case DocType.csv: return DelimitedText.write(book.sheets[currentSheetIndex], engine: engine, separator: ",")
        case DocType.tsv: return DelimitedText.write(book.sheets[currentSheetIndex], engine: engine, separator: "\t")
        case DocType.html: return Data(SheetHTML.html(book, engine: engine).utf8)
        case DocType.pdf:
            var pages: [Data] = []
            for ws in book.sheets {
                let v = SheetGridView(sheet: ws, engine: engine)
                v.printMode = true
                pages += try v.pdfPages(pageSize: NSSize(width: 842 - 72, height: 595 - 72))
            }
            return PDFMerge.merge(pages)
        default: return XLSXWriter.write(book)
        }
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
        [DocType.xlsx: "xlsx", DocType.csv: "csv", DocType.tsv: "tsv", DocType.html: "html", DocType.pdf: "pdf"][typeName]
            ?? super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
    }

    // MARK: Edits (undoable)

    func setCells(_ changes: [(Worksheet, CellRef, SheetCell?)], actionName: String) {
        var undo: [(Worksheet, CellRef, SheetCell?)] = []
        for (ws, ref, cell) in changes {
            undo.append((ws, ref, ws.cells[ref]))
            ws.cells[ref] = (cell?.input.isEmpty ?? true) && (cell?.style ?? CellStyle()) == CellStyle() ? nil : cell
        }
        engine.invalidate()
        undoManager?.registerUndo(withTarget: self) { $0.setCells(undo, actionName: actionName) }
        undoManager?.setActionName(actionName)
        NotificationCenter.default.post(name: .sheetChanged, object: self)
    }
}

extension Notification.Name { static let sheetChanged = Notification.Name("HanXSheetChanged") }

final class SheetWindowController: NSWindowController, SheetGridDelegate, NSToolbarDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    private unowned let doc: SheetDocument
    private var grid: SheetGridView!
    private var scroll: NSScrollView!
    private var ribbon:OfficeRibbon!
    private let nameBox = HWTextField()
    private let formula = HWTextField()
    private let tabs = NSSegmentedControl()
    private var sheetIndex = 0 { didSet { doc.currentSheetIndex = sheetIndex } }

    private var sheet: Worksheet { doc.book.sheets[sheetIndex] }

    init(document: SheetDocument) {
        doc = document
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 600, height: 400)
        w.tabbingMode = .preferred
        HWTheme.style(w)
        super.init(window: w)
        build()
        w.center()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .sheetChanged, object: document)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String { "\(displayName)  도표" }

    private func build() {
        guard let content = window?.contentView else { return }
        let W = content.bounds.width, H = content.bounds.height - OfficeRibbon.height
        let barH: CGFloat = 30, tabH: CGFloat = 28

        nameBox.frame = NSRect(x: 8, y: H - barH + 4, width: 70, height: 22)
        nameBox.autoresizingMask = [.minYMargin]
        nameBox.alignment = .center
        nameBox.delegate = self
        nameBox.placeholderString = "A1"
        let fx = NSTextField(labelWithString: "fx")
        fx.frame = NSRect(x: 84, y: H - barH + 6, width: 20, height: 18)
        fx.autoresizingMask = [.minYMargin]
        fx.font = .systemFont(ofSize: 12, weight: .semibold)
        fx.textColor = .secondaryLabelColor
        formula.frame = NSRect(x: 106, y: H - barH + 4, width: W - 114, height: 22)
        formula.autoresizingMask = [.width, .minYMargin]
        formula.delegate = self
        formula.placeholderString = "값 또는 =수식"
        [nameBox, fx, formula].forEach(content.addSubview)

        grid = SheetGridView(sheet: sheet, engine: doc.engine)
        grid.delegate = self
        scroll = NSScrollView(frame: NSRect(x: 0, y: tabH, width: W, height: H - barH - tabH))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = grid
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            self?.grid.needsDisplay = true
            self?.window?.invalidateCursorRects(for: self!.grid)
        }
        content.addSubview(scroll)

        tabs.frame = NSRect(x: 8, y: 3, width: W - 60, height: 22)
        tabs.autoresizingMask = [.width]
        tabs.segmentStyle = .rounded
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        let add = NSButton(title: "+", target: self, action: #selector(addSheet(_:)))
        add.frame = NSRect(x: W - 46, y: 2, width: 38, height: 24)
        add.autoresizingMask = [.minXMargin]
        add.bezelStyle = .rounded
        add.toolTip = "시트 추가"
        content.addSubview(tabs)
        content.addSubview(add)
        reloadTabs()
        buildRibbon(in:content)

        let tb = NSToolbar(identifier: "SheetToolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        window?.toolbar = tb
        window?.toolbarStyle = .unifiedCompact
        window?.makeFirstResponder(grid)
        gridSelectionChanged()
    }

    private func reloadTabs() {
        tabs.segmentCount = doc.book.sheets.count
        for (i, ws) in doc.book.sheets.enumerated() {
            tabs.setLabel(ws.name, forSegment: i)
            tabs.setWidth(0, forSegment: i)
        }
        tabs.selectedSegment = sheetIndex
        tabs.sizeToFit()
    }

    @objc private func tabChanged(_ s: NSSegmentedControl) {
        grid.commitEdit()
        sheetIndex = max(0, s.selectedSegment)
        grid.sheet = sheet
        grid.select(CellRef(row: 0, col: 0))
    }

    @objc func addSheet(_ sender: Any?) {
        var n = doc.book.sheets.count + 1
        while doc.book.sheet(named: "Sheet\(n)") != nil { n += 1 }
        doc.book.sheets.append(Worksheet(name: "Sheet\(n)"))
        sheetIndex = doc.book.sheets.count - 1
        reloadTabs()
        grid.sheet = sheet
        doc.updateChangeCount(.changeDone)
    }

    @objc func renameSheet(_ sender: Any?) {
        let a = NSAlert()
        a.messageText = "시트 이름 바꾸기"
        let f = NSTextField(string: sheet.name)
        f.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        a.accessoryView = f
        a.addButton(withTitle: "확인"); a.addButton(withTitle: "취소")
        a.beginSheetModal(for: window!) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self, !f.stringValue.isEmpty else { return }
            self.sheet.name = f.stringValue
            self.reloadTabs()
            self.doc.updateChangeCount(.changeDone)
        }
    }

    @objc func refresh() { grid.reloadSize(); grid.needsDisplay = true; gridSelectionChanged() }

    // MARK: Grid delegate

    func gridSelectionChanged() {
        reflectRibbon()
        let ref = sheet.merge(containing: grid.cursor)?.start ?? grid.cursor
        nameBox.stringValue = grid.selection.start == grid.selection.end ? ref.a1 : grid.selection.a1
        formula.stringValue = sheet.cells[ref]?.input ?? ""
        formula.textColor = .labelColor
        if formula.stringValue.isEmpty, let spill = doc.engine.spillRange(sheet, ref), spill.start != ref {
            // Spilled cells show the anchor's formula greyed out, like Excel.
            formula.stringValue = sheet.cells[spill.start]?.input ?? ""
            formula.textColor = .secondaryLabelColor
        }
        if !grid.isEditing, let ed = formula.currentEditor() { ed.string = formula.stringValue }
    }

    func gridCommit(_ ref: CellRef, input: String) {
        var c = sheet.cells[ref] ?? SheetCell()
        guard c.input != input else { return }
        c.input = input
        doc.setCells([(sheet, ref, c)], actionName: "입력")
    }

    func gridClear(_ range: CellRange) {
        let changes: [(Worksheet, CellRef, SheetCell?)] = sheet.cells.keys.filter { range.contains($0) }.map {
            var c = sheet.cells[$0]!; c.input = ""; return (sheet, $0, c)
        }
        if !changes.isEmpty { doc.setCells(changes, actionName: "지우기") }
    }

    func gridPaste(_ text: String, at: CellRef) {
        let ws = DelimitedText.parse(text, separator: text.contains("\t") ? "\t" : ",")
        var changes: [(Worksheet, CellRef, SheetCell?)] = []
        for (ref, cell) in ws.cells {
            let target = CellRef(row: at.row + ref.row, col: at.col + ref.col)
            var c = sheet.cells[target] ?? SheetCell()
            c.input = cell.input
            changes.append((sheet, target, c))
        }
        doc.setCells(changes, actionName: "붙이기")
    }

    func gridColumnResized(_ col: Int, width: Double) { doc.updateChangeCount(.changeDone) }

    // MARK: Charts

    /// Charts were already changed on the sheet; record how to go back.
    func gridChartsChanged(from old: [SheetChart], name: String) {
        let ws = sheet
        doc.undoManager?.registerUndo(withTarget: self) { $0.setCharts(old, on: ws, name: name) }
        doc.undoManager?.setActionName(name)
        refresh()
    }

    private func setCharts(_ charts: [SheetChart], on ws: Worksheet, name: String) {
        let current = ws.charts
        ws.charts = charts
        grid.selectedChart = nil
        doc.undoManager?.registerUndo(withTarget: self) { $0.setCharts(current, on: ws, name: name) }
        doc.undoManager?.setActionName(name)
        refresh()
    }

    @objc func insertChart(_ sender: Any?) {
        let kind = ChartKind.allCases[max(0, (sender as? NSMenuItem)?.tag ?? 0)]
        guard let range = workRange else { NSSound.beep(); return }
        let old = sheet.charts
        let x = Double(grid.x(ofCol: range.end.col + 1) - grid.x(ofCol: 0)) + 16
        let y = Double(grid.y(ofRow: range.start.row) - grid.y(ofRow: 0))
        sheet.charts.append(SheetChart(kind: kind, title: "", data: range, x: x, y: y))
        grid.selectedChart = sheet.charts.count - 1
        gridChartsChanged(from: old, name: "차트 삽입")
        grid.scrollToVisible(grid.chartRect(sheet.charts[sheet.charts.count - 1]))
    }

    func gridEditChart(_ index: Int) {
        guard index < sheet.charts.count else { return }
        let chart = sheet.charts[index]
        let a = NSAlert()
        a.messageText = "차트 설정"
        let kind = NSPopUpButton()
        kind.addItems(withTitles: ChartKind.allCases.map(\.title))
        kind.selectItem(at: ChartKind.allCases.firstIndex(of: chart.kind) ?? 0)
        let title = NSTextField(string: chart.title)
        title.placeholderString = "차트 제목"
        let range = NSTextField(string: chart.data.a1)
        let grid = NSGridView(views: [[NSTextField(labelWithString: "종류"), kind], [NSTextField(labelWithString: "제목"), title],
                                      [NSTextField(labelWithString: "데이터 범위"), range]])
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: 90)
        title.widthAnchor.constraint(equalToConstant: 200).isActive = true
        a.accessoryView = grid
        a.addButton(withTitle: "확인"); a.addButton(withTitle: "취소"); a.addButton(withTitle: "차트 삭제")
        a.beginSheetModal(for: window!) { [weak self] r in
            guard let self, r != .alertSecondButtonReturn, index < self.sheet.charts.count else { return }
            let old = self.sheet.charts
            if r == .alertThirdButtonReturn {
                self.sheet.charts.remove(at: index)
                self.grid.selectedChart = nil
                self.gridChartsChanged(from: old, name: "차트 삭제")
                return
            }
            var c = self.sheet.charts[index]
            c.kind = ChartKind.allCases[max(0, kind.indexOfSelectedItem)]
            c.title = title.stringValue
            let parts = range.stringValue.uppercased().split(separator: ":").compactMap { CellRef(a1: String($0)) }
            if parts.count == 2 { c.data = CellRange(parts[0], parts[1]) }
            self.sheet.charts[index] = c
            self.gridChartsChanged(from: old, name: "차트 설정")
        }
    }

    // MARK: Formula bar

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f === formula {
            let ref = sheet.merge(containing: grid.cursor)?.start ?? grid.cursor
            let showingSpill = formula.textColor == .secondaryLabelColor
                && formula.stringValue == doc.engine.spillRange(sheet, ref).flatMap { sheet.cells[$0.start]?.input }
            if !showingSpill { gridCommit(ref, input: formula.stringValue) }
            window?.makeFirstResponder(grid)
        } else if f === nameBox {
            let parts = f.stringValue.split(separator: ":").map(String.init)
            if let a = parts.first.flatMap(CellRef.init(a1:)) {
                grid.anchor = a
                grid.cursor = parts.count > 1 ? CellRef(a1: parts[1]) ?? a : a
                grid.select(grid.cursor)
                grid.anchor = a
            }
            window?.makeFirstResponder(grid)
        }
    }

    // MARK: Formatting commands

    private func restyle(_ name: String, _ change: (inout CellStyle) -> Void) {
        let r = grid.selection
        let used = sheet.usedRange
        let count=(r.end.row-r.start.row+1)*(r.end.col-r.start.col+1)
        let end = count <= 100_000 ? r.end : CellRef(row: min(r.end.row, max(r.start.row, used?.end.row ?? r.start.row)), col: min(r.end.col, max(r.start.col, used?.end.col ?? r.start.col)))
        var changes: [(Worksheet, CellRef, SheetCell?)] = []
        for ref in CellRange(r.start, end).cells {
            var c = sheet.cells[ref] ?? SheetCell()
            change(&c.style)
            changes.append((sheet, ref, c))
        }
        doc.setCells(changes, actionName: name)
    }

    private var currentStyle: CellStyle { sheet.cells[grid.cursor]?.style ?? CellStyle() }

    @objc func toggleBold(_ s: Any?) { let v = !currentStyle.bold; restyle("굵게") { $0.bold = v } }
    @objc func toggleBoldface(_ s:Any?) { toggleBold(s) }
    @objc func toggleItalics(_ s:Any?) { toggleItalic(s) }
    @objc func underline(_ s:Any?) { toggleUnderline(s) }
    @objc func toggleItalic(_ s: Any?) { let v = !currentStyle.italic; restyle("기울임") { $0.italic = v } }
    @objc func toggleUnderline(_ s: Any?) { let v = !currentStyle.underline; restyle("밑줄") { $0.underline = v } }
    @objc func alignLeft(_ s: Any?) { restyle("정렬") { $0.align = .left } }
    @objc func alignCenter(_ s: Any?) { restyle("정렬") { $0.align = .center } }
    @objc func alignRight(_ s: Any?) { restyle("정렬") { $0.align = .right } }
    @objc func toggleBorder(_ s: Any?) { let v = !currentStyle.border; restyle("테두리") { $0.border = v } }
    @objc func toggleWrap(_ s: Any?) { let v = !currentStyle.wrap; restyle("줄 바꿈") { $0.wrap = v } }

    @objc func numberFormat(_ s: NSMenuItem) {
        let codes = ["General", "#,##0", "#,##0.00", "\"₩\"#,##0", "0%", "0.00%", "yyyy-mm-dd", "yyyy\"년\" m\"월\" d\"일\""]
        let code = codes[max(0, min(codes.count - 1, s.tag))]
        restyle("표시 형식") { $0.numberFormat = code == "General" ? nil : code }
    }

    @objc func fillColor(_ s: Any?) {
        let panel = NSColorPanel.shared
        panel.setTarget(self); panel.setAction(#selector(applyFill(_:)))
        panel.orderFront(nil)
    }

    @objc private func applyFill(_ p: NSColorPanel) {
        let c = p.color.usingColorSpace(.sRGB) ?? p.color
        let rgb = RGB(r: UInt8(c.redComponent * 255), g: UInt8(c.greenComponent * 255), b: UInt8(c.blueComponent * 255))
        restyle("채우기") { $0.fill = rgb == RGB(r: 255, g: 255, b: 255) ? nil : rgb }
    }

    @objc func mergeCells(_ s: Any?) {
        grid.commitEdit()
        var range=grid.selection
        var merges=sheet.merges
        if let old=sheet.merge(containing:range.start),old == range || range.start == range.end {
            merges.removeAll { $0 == old }
        } else {
            guard range.start != range.end else { return }
            var expanding=true
            while expanding {
                expanding=false
                for m in merges where m.start.row<=range.end.row && m.end.row>=range.start.row && m.start.col<=range.end.col && m.end.col>=range.start.col {
                    let bigger=CellRange(CellRef(row:min(range.start.row,m.start.row),col:min(range.start.col,m.start.col)),CellRef(row:max(range.end.row,m.end.row),col:max(range.end.col,m.end.col)))
                    if bigger != range { range=bigger; expanding=true }
                }
            }
            merges.removeAll { $0.start.row<=range.end.row && $0.end.row>=range.start.row && $0.start.col<=range.end.col && $0.end.col>=range.start.col }
            merges.append(range)
        }
        setMerges(merges,on:sheet)
    }
    private func setMerges(_ merges:[CellRange],on ws:Worksheet) {
        let old=ws.merges
        doc.undoManager?.registerUndo(withTarget:self) { $0.setMerges(old,on:ws) }
        ws.merges=merges; doc.engine.invalidate(); doc.undoManager?.setActionName("셀 병합"); refresh()
    }

    @objc func autoSum(_ s: Any?) {
        let ref = grid.cursor
        var top = ref.row - 1
        while top >= 0, case .number = doc.engine.value(sheet, CellRef(row: top, col: ref.col)) { top -= 1 }
        guard top + 1 < ref.row else { grid.beginEdit("=SUM()"); return }
        gridCommit(ref, input: "=SUM(\(CellRef(row: top + 1, col: ref.col).a1):\(CellRef(row: ref.row - 1, col: ref.col).a1))")
    }

    private func shiftFormulas(rowAt: Int? = nil, colAt: Int? = nil, by n: Int) {
        for ws in doc.book.sheets {
            for (k, v) in ws.cells where v.isFormula {
                ws.cells[k]?.input = FormulaEngine.shift(v.input, rowAt: rowAt, colAt: colAt, by: n)
            }
        }
    }

    @objc func insertRow(_ s: Any?) { structural("행 삽입") { $0.shift(rows: self.grid.cursor.row, by: 1); self.shiftFormulas(rowAt: self.grid.cursor.row, by: 1) } }
    @objc func deleteRow(_ s: Any?) { structural("행 삭제") { $0.shift(rows: self.grid.cursor.row + 1, by: -1); self.shiftFormulas(rowAt: self.grid.cursor.row + 1, by: -1) } }
    @objc func insertColumn(_ s: Any?) { structural("열 삽입") { $0.shift(cols: self.grid.cursor.col, by: 1); self.shiftFormulas(colAt: self.grid.cursor.col, by: 1) } }
    @objc func deleteColumn(_ s: Any?) { structural("열 삭제") { $0.shift(cols: self.grid.cursor.col + 1, by: -1); self.shiftFormulas(colAt: self.grid.cursor.col + 1, by: -1) } }

    /// Structural edits snapshot the whole workbook for undo.
    private func structural(_ name: String, _ op: (Worksheet) -> Void) {
        let snapshot = doc.book.sheets.map { ($0, $0.cells) }
        op(sheet)
        doc.engine.invalidate()
        doc.undoManager?.registerUndo(withTarget: self) { wc in
            for (ws, cells) in snapshot { ws.cells = cells }
            wc.doc.engine.invalidate(); wc.refresh()
        }
        doc.undoManager?.setActionName(name)
        refresh()
    }

    // MARK: Data commands

    /// Range a data command works on: the selection, or the used range when
    /// a single cell is selected.
    private var workRange: CellRange? {
        let sel = grid.selection
        guard let used = sheet.usedRange else { return nil }
        if sel.start == sel.end { return used }
        let end = CellRef(row: min(sel.end.row, used.end.row), col: min(sel.end.col, used.end.col))
        return end.row >= sel.start.row && end.col >= sel.start.col ? CellRange(sel.start, end) : nil
    }

    private func sort(ascending: Bool) {
        guard var range = workRange else { return }
        // A text-only first row above other data is treated as a header.
        if grid.selection.start == grid.selection.end, range.end.row > range.start.row {
            let firstRow = (range.start.col...range.end.col).map { doc.engine.value(sheet, CellRef(row: range.start.row, col: $0)) }
            let isHeader = firstRow.allSatisfy { if case .string = $0 { return true }; return $0 == .empty } && firstRow.contains { $0 != .empty }
            if isHeader { range = CellRange(CellRef(row: range.start.row + 1, col: range.start.col), range.end) }
        }
        let key = min(max(grid.cursor.col, range.start.col), range.end.col)
        let rows = Array(range.start.row...range.end.row)
        func rank(_ v: SheetValue) -> (Int, Double, String) {
            switch v {
            case .number(let d): return (0, d, "")
            case .bool(let b): return (2, b ? 1 : 0, "")
            case .string(let t): return (1, 0, t)
            case .error, .array, .lambda: return (3, 0, "")
            case .empty: return (4, 0, "")
            }
        }
        let sorted = rows.sorted { a, b in
            let x = rank(doc.engine.value(sheet, CellRef(row: a, col: key))), y = rank(doc.engine.value(sheet, CellRef(row: b, col: key)))
            if x.0 != y.0 { return x.0 < y.0 }              // blanks always last
            let less = x.0 == 1 ? x.2.localizedStandardCompare(y.2) == .orderedAscending : x.1 < y.1
            let greater = x.0 == 1 ? x.2.localizedStandardCompare(y.2) == .orderedDescending : x.1 > y.1
            return ascending ? less : greater
        }
        structural(ascending ? "오름차순 정렬" : "내림차순 정렬") { ws in
            var moved: [CellRef: SheetCell] = [:]
            for (newIndex, oldRow) in sorted.enumerated() {
                for c in range.start.col...range.end.col {
                    if let cell = ws.cells[CellRef(row: oldRow, col: c)] { moved[CellRef(row: range.start.row + newIndex, col: c)] = cell }
                }
            }
            for r in range.start.row...range.end.row { for c in range.start.col...range.end.col { ws.cells[CellRef(row: r, col: c)] = nil } }
            for (k, v) in moved { ws.cells[k] = v }
        }
    }

    @objc func sortAscending(_ s: Any?) { sort(ascending: true) }
    @objc func sortDescending(_ s: Any?) { sort(ascending: false) }

    /// Copies the first row/column of the selection across it, shifting
    /// relative references the way Excel's 아래로/오른쪽으로 채우기 does.
    private func fill(down: Bool) {
        let r = grid.selection
        guard down ? r.end.row > r.start.row : r.end.col > r.start.col else { return }
        var changes: [(Worksheet, CellRef, SheetCell?)] = []
        for target in r.cells where down ? target.row > r.start.row : target.col > r.start.col {
            let source = down ? CellRef(row: r.start.row, col: target.col) : CellRef(row: target.row, col: r.start.col)
            var cell = sheet.cells[source] ?? SheetCell()
            if cell.isFormula {
                cell.input = "=" + XLSXReader.translate(String(cell.input.dropFirst()), rows: target.row - source.row, cols: target.col - source.col)
            }
            changes.append((sheet, target, cell))
        }
        doc.setCells(changes, actionName: down ? "아래로 채우기" : "오른쪽으로 채우기")
    }

    @objc func fillDown(_ s: Any?) { fill(down: true) }
    @objc func duplicate(_ s:Any?) { fillDown(s) }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if item.action == #selector(duplicate(_:)) { item.title="아래로 채우기" }
        return true
    }
    @objc func fillRight(_ s: Any?) { fill(down: false) }

    /// 연속 데이터: continues numeric steps (1,2 → 3,4…) or "항목1" style
    /// trailing numbers down each column of the selection.
    @objc func fillSeries(_ s: Any?) {
        let r = grid.selection
        guard r.end.row > r.start.row else { fill(down: false); return }
        var changes: [(Worksheet, CellRef, SheetCell?)] = []
        for c in r.start.col...r.end.col {
            let a = sheet.cells[CellRef(row: r.start.row, col: c)]?.input ?? ""
            let b = sheet.cells[CellRef(row: r.start.row + 1, col: c)]?.input ?? ""
            if let x = Double(a) {
                let step = Double(b).map { $0 - x } ?? 1
                let start = Double(b) != nil ? 2 : 1
                for (k, row) in ((r.start.row + start)...r.end.row).enumerated() {
                    var cell = sheet.cells[CellRef(row: r.start.row, col: c)] ?? SheetCell()
                    cell.input = SheetValue.general(x + step * Double(k + start))
                    changes.append((sheet, CellRef(row: row, col: c), cell))
                }
            } else if let m = a.range(of: "[0-9]+$", options: .regularExpression), let n = Int(a[m]) {
                let prefix = a[..<m.lowerBound]
                for (k, row) in ((r.start.row + 1)...r.end.row).enumerated() {
                    var cell = sheet.cells[CellRef(row: r.start.row, col: c)] ?? SheetCell()
                    cell.input = prefix + String(n + k + 1)
                    changes.append((sheet, CellRef(row: row, col: c), cell))
                }
            } else {
                for row in (r.start.row + 1)...r.end.row {
                    changes.append((sheet, CellRef(row: row, col: c), sheet.cells[CellRef(row: r.start.row, col: c)]))
                }
            }
        }
        doc.setCells(changes, actionName: "연속 데이터 채우기")
    }

    @objc func toggleFreezePanes(_ s: Any?) {
        if sheet.frozenRows > 0 || sheet.frozenCols > 0 { sheet.frozenRows = 0; sheet.frozenCols = 0 }
        else {
            let c = grid.cursor
            sheet.frozenRows = c.row == 0 && c.col == 0 ? 1 : c.row
            sheet.frozenCols = c.col
        }
        doc.updateChangeCount(.changeDone)
        refresh()
    }

    // MARK: Find

    private var lastSearch = ""

    @objc func performFindPanelAction(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 1
        if tag == Int(NSFindPanelAction.next.rawValue) || tag == Int(NSFindPanelAction.previous.rawValue), !lastSearch.isEmpty {
            findNext(lastSearch, backwards: tag == Int(NSFindPanelAction.previous.rawValue)); return
        }
        let a = NSAlert()
        a.messageText = "찾기"
        let f = NSTextField(string: lastSearch)
        f.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        f.placeholderString = "찾을 내용 (값 또는 수식)"
        a.accessoryView = f
        a.addButton(withTitle: "다음 찾기"); a.addButton(withTitle: "취소")
        a.window.initialFirstResponder = f
        a.beginSheetModal(for: window!) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self, !f.stringValue.isEmpty else { return }
            self.lastSearch = f.stringValue
            self.findNext(f.stringValue, backwards: false)
        }
    }

    private func findNext(_ text: String, backwards: Bool) {
        let keys = sheet.cells.keys.sorted()
        let matches = keys.filter { k in
            let c = sheet.cells[k]!
            return c.input.localizedCaseInsensitiveContains(text) || doc.engine.display(sheet, k).localizedCaseInsensitiveContains(text)
        }
        guard !matches.isEmpty else { NSSound.beep(); return }
        let cur = grid.cursor
        let next = backwards ? (matches.last { $0 < cur } ?? matches.last!) : (matches.first { $0 > cur } ?? matches.first!)
        grid.select(next)
    }

    @objc func zoomIn(_ s: Any?) { scroll.allowsMagnification = true; scroll.magnification *= 1.2 }
    @objc func zoomOut(_ s: Any?) { scroll.allowsMagnification = true; scroll.magnification /= 1.2 }
    @objc func zoomActual(_ s: Any?) { scroll.magnification = 1 }

    // MARK: Toolbar

    private let items: [(String, String, String, Selector)] = [
        ("bold", "굵게", "bold", #selector(toggleBold(_:))),
        ("italic", "기울임", "italic", #selector(toggleItalic(_:))),
        ("underline", "밑줄", "underline", #selector(toggleUnderline(_:))),
        ("left", "왼쪽", "text.alignleft", #selector(alignLeft(_:))),
        ("center", "가운데", "text.aligncenter", #selector(alignCenter(_:))),
        ("right", "오른쪽", "text.alignright", #selector(alignRight(_:))),
        ("fill", "채우기", "paintbrush.fill", #selector(fillColor(_:))),
        ("border", "테두리", "square.dashed", #selector(toggleBorder(_:))),
        ("merge", "병합", "rectangle.split.2x1", #selector(mergeCells(_:))),
        ("sum", "합계", "sum", #selector(autoSum(_:))),
        ("sortup", "오름차순", "arrow.up.square", #selector(sortAscending(_:))),
        ("sortdown", "내림차순", "arrow.down.square", #selector(sortDescending(_:))),
        ("freeze", "틀 고정", "pin", #selector(toggleFreezePanes(_:))),
        ("insrow", "행 삽입", "plus.rectangle", #selector(insertRow(_:))),
        ("inscol", "열 삽입", "plus.rectangle.portrait", #selector(insertColumn(_:))),
    ]

    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        let ids = items.map { NSToolbarItem.Identifier($0.0) }
        var items = Array(ids[0..<3])
        items.append(.space)
        items.append(contentsOf: ids[3..<6])
        items.append(.space)
        items.append(contentsOf: ids[6..<9])
        items.append(NSToolbarItem.Identifier("format"))
        items.append(.flexibleSpace)
        return items
            + Array(ids[9...12]) + [NSToolbarItem.Identifier("chart")]
    }

    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        items.map { NSToolbarItem.Identifier($0.0) } + [NSToolbarItem.Identifier("format"), NSToolbarItem.Identifier("chart"), .space, .flexibleSpace]
    }

    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id.rawValue == "chart" {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "차트"
            item.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: nil)
            let m = NSMenu()
            for (i, k) in ChartKind.allCases.enumerated() {
                let mi = NSMenuItem(title: k.title, action: #selector(insertChart(_:)), keyEquivalent: "")
                mi.tag = i; mi.target = self
                mi.image = NSImage(systemSymbolName: ["chart.bar.fill", "chart.bar.doc.horizontal", "chart.xyaxis.line", "chart.line.uptrend.xyaxis", "chart.pie.fill"][i], accessibilityDescription: nil)
                m.addItem(mi)
            }
            item.menu = m
            item.showsIndicator = true
            return item
        }
        if id.rawValue == "format" {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "표시 형식"
            item.image = NSImage(systemSymbolName: "number", accessibilityDescription: nil)
            let m = NSMenu()
            for (i, t) in ["일반", "숫자 (1,234)", "숫자 (1,234.00)", "통화 (₩)", "백분율 (0%)", "백분율 (0.00%)", "날짜 (2026-01-31)", "날짜 (2026년 1월 31일)"].enumerated() {
                let mi = NSMenuItem(title: t, action: #selector(numberFormat(_:)), keyEquivalent: "")
                mi.tag = i; mi.target = self
                m.addItem(mi)
            }
            item.menu = m
            item.showsIndicator = true
            return item
        }
        guard let spec = items.first(where: { $0.0 == id.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = spec.1
        item.image = NSImage(systemSymbolName: spec.2, accessibilityDescription: spec.1)
        item.target = self
        item.action = spec.3
        return item
    }
}

extension SheetWindowController {
    private func buildRibbon(in content:NSView) {
        typealias R=OfficeRibbon
        ribbon=R(tabs:[
            .init(title:"홈",groups:[R.clipboard,R.text,.init(title:"셀 정렬",items:[.button("left","왼쪽","text.alignleft"),.button("center","가운데","text.aligncenter"),.button("right","오른쪽","text.alignright"),.button("wrap","줄 바꿈","text.word.spacing"),.button("merge","병합 해제","rectangle.split.2x1")])]),
            .init(title:"셀 서식",groups:[.init(title:"색과 테두리",items:[.menu("textColor","글자 색",R.colors),.menu("fill","채우기",["채우기 없음"]+R.colors),.button("border","모든 테두리","square.dashed"),.button("clearFormat","서식 지우기","eraser")]),.init(title:"표시 형식",items:[.menu("numberFormat","표시 형식",["일반","숫자 (1,234)","숫자 (1,234.00)","통화 (₩)","백분율 (0%)","백분율 (0.00%)","날짜 (2026-01-31)","날짜 (2026년 1월 31일)"]),.menu("decimal","소수 자릿수",["소수 자릿수…","정수","1자리","2자리","3자리","4자리"])])]),
            .init(title:"삽입 크기",groups:[.init(title:"행과 열",items:[.button("insertRow","행 삽입","plus.rectangle"),.button("deleteRow","행 삭제","minus.rectangle"),.button("insertColumn","열 삽입","plus.rectangle.portrait"),.button("deleteColumn","열 삭제","minus.rectangle.portrait"),.button("autofit","열 너비 자동","arrow.left.and.right"),.field("rowHeight","행 높이 (pt)",["20","24","30","40","60"])]),.init(title:"시트 차트",items:[.button("newSheet","시트 추가","plus.square"),.button("renameSheet","시트 이름","pencil"),.menu("chart","차트",ChartKind.allCases.map(\.title))])]),
            .init(title:"데이터",groups:[.init(title:"계산과 정렬",items:[.button("sum","자동 합계","sum"),.button("sortUp","오름차순","arrow.up.square"),.button("sortDown","내림차순","arrow.down.square"),.button("fillDown","아래로 채우기","arrow.down.to.line"),.button("fillRight","오른쪽 채우기","arrow.right.to.line"),.button("series","연속 데이터","number")])]),
            .init(title:"보기",groups:[.init(title:"화면",items:[.button("freeze","틀 고정 해제","pin"),.button("zoomOut","축소","minus.magnifyingglass"),.button("actual","100%","1.magnifyingglass"),.button("zoomIn","확대","plus.magnifyingglass"),.button("find","찾기","magnifyingglass")])])
        ],width:content.bounds.width)
        ribbon.frame.origin.y=content.bounds.height-R.height; ribbon.onCommand={ [weak self] id,value in self?.ribbonCommand(id,value) }; ribbon.onRefresh={ [weak self] in self?.reflectRibbon() }; content.addSubview(ribbon); reflectRibbon()
    }
    func commitPendingEditing() { window?.makeFirstResponder(grid); grid.commitEdit() }
    var debugGrid: SheetGridView { grid }
    var debugRibbon:OfficeRibbon { ribbon }
    private func reflectRibbon() {
        guard ribbon != nil,grid != nil else { return }
        let c=currentStyle
        ribbon.reflect(font:c.fontName ?? "Apple SD Gothic Neo",size:c.fontSize ?? 11,bold:c.bold,italic:c.italic,underline:c.underline)
        ribbon.reflectChoice("textColor",index:OfficeRibbon.palette.firstIndex(of:c.color ?? .black) ?? -1)
        ribbon.reflectChoice("fill",index:c.fill.flatMap { OfficeRibbon.palette.firstIndex(of:$0).map { $0+1 } } ?? (c.fill == nil ? 0 : -1))
        let formats=["General","#,##0","#,##0.00","\"₩\"#,##0","0%","0.00%","yyyy-mm-dd","yyyy\"년\" m\"월\" d\"일\""]
        ribbon.reflectChoice("numberFormat",index:formats.firstIndex(of:c.numberFormat ?? "General") ?? -1)
        ribbon.reflectText("rowHeight",value:String(format:"%g",sheet.height(grid.cursor.row)))
    }

    func ribbonCommand(_ id:String,_ value:String) {
        if OfficeRibbon.clipboardCommand(id) { return }
        grid.commitEdit(); let n=Int(value) ?? 0
        switch id {
        case "font": restyle("글꼴") { $0.fontName=value }
        case "size": if let v=Double(value),v.isFinite,v>0 { restyle("글자 크기") { $0.fontSize=min(400,v) } }
        case "bold": toggleBold(nil)
        case "italic": toggleItalic(nil)
        case "underline": toggleUnderline(nil)
        case "left": alignLeft(nil)
        case "center": alignCenter(nil)
        case "right": alignRight(nil)
        case "wrap": toggleWrap(nil)
        case "merge": mergeCells(nil)
        case "textColor": restyle("글자 색") { $0.color=OfficeRibbon.palette[n] }
        case "fill": restyle("채우기") { $0.fill=n == 0 ? nil : OfficeRibbon.palette[n-1] }
        case "border": toggleBorder(nil)
        case "clearFormat": restyle("서식 지우기") { $0=CellStyle() }
        case "numberFormat": let item=NSMenuItem(); item.tag=n; numberFormat(item)
        case "decimal": if n>0 { restyle("소수 자릿수") { $0.numberFormat=n == 1 ? "#,##0" : "#,##0."+String(repeating:"0",count:n-1) } }
        case "insertRow": insertRow(nil)
        case "deleteRow": deleteRow(nil)
        case "insertColumn": insertColumn(nil)
        case "deleteColumn": deleteColumn(nil)
        case "autofit": autoFitColumns()
        case "rowHeight": if let h=Double(value),h.isFinite,h>0 { let rows=grid.selection; var sizes=sheet.rowHeights; for i in rows.start.row...min(rows.end.row,rows.start.row+10000) { sizes[i]=max(8,min(1000,h)) }; setDimensions(columns:sheet.columnWidths,rows:sizes) }
        case "newSheet": addSheet(nil)
        case "renameSheet": renameSheet(nil)
        case "chart": let item=NSMenuItem(); item.tag=n; insertChart(item)
        case "sum": autoSum(nil)
        case "sortUp": sortAscending(nil)
        case "sortDown": sortDescending(nil)
        case "fillDown": fillDown(nil)
        case "fillRight": fillRight(nil)
        case "series": fillSeries(nil)
        case "freeze": toggleFreezePanes(nil)
        case "zoomOut": zoomOut(nil)
        case "zoomIn": zoomIn(nil)
        case "actual": zoomActual(nil)
        case "find": performFindPanelAction(nil)
        default:break
        }
        reflectRibbon()
    }
    private func setDimensions(columns:[Int:Double],rows:[Int:Double]) {
        let ws=sheet,oldC=ws.columnWidths,oldR=ws.rowHeights
        doc.undoManager?.registerUndo(withTarget:self) { $0.restoreDimensions(on:ws,columns:oldC,rows:oldR) }
        ws.columnWidths=columns; ws.rowHeights=rows; doc.undoManager?.setActionName("행 열 크기"); refresh()
    }
    private func restoreDimensions(on ws:Worksheet,columns:[Int:Double],rows:[Int:Double]) {
        let oldC=ws.columnWidths,oldR=ws.rowHeights
        doc.undoManager?.registerUndo(withTarget:self) { $0.restoreDimensions(on:ws,columns:oldC,rows:oldR) }
        ws.columnWidths=columns; ws.rowHeights=rows; refresh()
    }
    private func autoFitColumns() {
        let range=grid.selection; var sizes=sheet.columnWidths
        for col in range.start.col...min(range.end.col,range.start.col+1024) {
            var width:CGFloat=24
            for (ref,cell) in sheet.cells where ref.col == col {
                let f=FontResolver.shared.font(name:cell.style.fontName ?? "Arial",size:cell.style.fontSize ?? 11,bold:cell.style.bold,italic:cell.style.italic).font
                let text=cell.isFormula ? doc.engine.display(sheet,ref) : cell.input
                width=max(width,(text as NSString).size(withAttributes:[.font:f]).width+16)
            }
            sizes[col]=Double(min(1000,width))
        }
        setDimensions(columns:sizes,rows:sheet.rowHeights)
    }
}
