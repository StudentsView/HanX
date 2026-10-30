import Foundation

// hanx-cli: headless harness for the import/export pipeline.
//   hanx-cli dump <file>          stats + text preview
//   hanx-cli convert <in> <out>   convert via the unified model (.docx/.hwpx/.hwp)
//   hanx-cli corpus <file...>     parse many files, report failures
let args = CommandLine.arguments
if args.count<2 || AgentCLI.commands.contains(args[1]) { exit(AgentCLI.run(Array(args.dropFirst()))) }
guard args.count >= 3 else {
    exit(AgentCLI.run(Array(args.dropFirst())))
}

func load(_ path: String) throws -> UDocument {
    try DocumentIO.load(url: URL(fileURLWithPath: path))
}

switch args[1] {
case "dump":
    let d = try load(args[2])
    let s = d.stats
    print("format=\(d.source.rawValue) sections=\(d.sections.count) paragraphs=\(s.paragraphs) tables=\(s.tables) images=\(s.images) imageData=\(d.images.count)")
    if let p = d.sections.first?.page { print("page \(p.width)x\(p.height) margins T\(p.marginTop) B\(p.marginBottom) L\(p.marginLeft) R\(p.marginRight)") }
    let limit = args.count > 3 ? Int(args[3]) ?? 1500 : 1500
    print(String(d.plainText.prefix(limit)))
    for (i, sec) in d.sections.enumerated() {
        if let h = sec.header { print("[section \(i + 1) header] " + h.map(UDocument.text(of:)).joined(separator: " / ")) }
        if let f = sec.footer { print("[section \(i + 1) footer] " + f.map(UDocument.text(of:)).joined(separator: " / ")) }
    }
case "styles":
    print(try HWP5Reader.inspectStyles(data: Data(contentsOf: URL(fileURLWithPath: args[2]))))
case "records":
    print(try HWP5Reader.dumpRecords(data: Data(contentsOf: URL(fileURLWithPath: args[2])), stream: args.count > 3 ? args[3] : "DocInfo"))
case "sheet":
    let book = try SheetIO.load(url: URL(fileURLWithPath: args[2]))
    let engine = FormulaEngine(book: book)
    for ws in book.sheets {
        print("[\(ws.name)] used=\(ws.usedRange?.a1 ?? "-") merges=\(ws.merges.count) formulas=\(ws.cells.values.filter(\.isFormula).count) charts=\(ws.charts.map { "\($0.kind.rawValue):\($0.data.a1)@\(Int($0.x)),\(Int($0.y)) \($0.title)" })")
        guard let u = ws.usedRange else { continue }
        for r in 0...min(u.end.row, 12) {
            print((0...min(u.end.col, 7)).map { engine.display(ws, CellRef(row: r, col: $0)) }.joined(separator: " | "))
        }
    }
    if args.count > 3 { try SheetIO.save(book, to: URL(fileURLWithPath: args[3])); print("wrote \(args[3])") }
case "formula-test":
    let book = Workbook(); let ws = book.sheets[0]; let e = FormulaEngine(book: book)
    let data: [(String, String)] = [("A1", "10"), ("A2", "20"), ("A3", "30"), ("B1", "사과"), ("B2", "배"), ("B3", "사과"),
        ("C1", "=SUM(A1:A3)"), ("C2", "=AVERAGE(A1:A3)*2"), ("C3", "=IF(C1>50,\"큼\",\"작음\")"), ("C4", "=SUMIF(B1:B3,\"사과\",A1:A3)"),
        ("C5", "=COUNTIF(A1:A3,\">15\")"), ("C6", "=VLOOKUP(\"배\",B1:C3,1,FALSE)"), ("C7", "=ROUND(10/3,2)&\"점\""), ("C8", "=C9+1"), ("C9", "=C8"),
        ("C10", "=MAX(A1:A3)-MIN(A1:A3)"), ("C11", "=1/0"), ("C12", "=INDEX(A1:A3,MATCH(20,A1:A3,0))"), ("C13", "=-2^2+50%")]
    for (a, v) in data { ws.set(CellRef(a1: a)!, input: v) }
    for r in 0..<13 { let ref = CellRef(row: r, col: 2); print(ref.a1, ws.cells[ref]?.input ?? "", "→", e.display(ws, ref)) }
    print("shift:", FormulaEngine.shift("=SUM(A1:A3)+$B$2", rowAt: 1, by: 2), XLSXReader.translate("A1+$B1*C$2", rows: 1, cols: 1))
case "slides":
    let pres = try SlidesIO.load(url: URL(fileURLWithPath: args[2]))
    print("size \(pres.width)x\(pres.height) slides=\(pres.slides.count) images=\(pres.images.count)")
    for (i, sl) in pres.slides.enumerated().prefix(6) {
        print("-- slide \(i + 1): \(sl.shapes.count) shapes, bg=\(sl.background?.hex ?? "-"), transition=\(sl.transition.kind.rawValue)")
        for a in sl.animations { print("   anim shape#\(a.shapeID) \(a.effect.rawValue) \(a.trigger.rawValue) \(a.duration)s +\(a.delay)s \(a.direction.rawValue)") }
        for sh in sl.shapes.prefix(8) {
            print("   \(sh.kind.rawValue)\(sh.locked ? "(layout)" : "") [\(Int(sh.frame.x)),\(Int(sh.frame.y)) \(Int(sh.frame.w))x\(Int(sh.frame.h))] \(sh.paragraphs.map(\.plainText).joined(separator: " / ").prefix(60))")
        }
    }
    if args.count > 3 { try PPTXWriter.write(pres).write(to: URL(fileURLWithPath: args[3])); print("wrote \(args[3])") }
case "make-slides":
    let pres = Presentation.blank()
    pres.slides[0].shapes[0].paragraphs = [Presentation.textParagraph("HanX 프레젠테이션", size: 44, bold: true, align: .center)]
    pres.slides[0].shapes[1].paragraphs = [Presentation.textParagraph("HWP · DOCX · XLSX · PPTX 통합 편집기", size: 24, align: .center)]
    var s2 = pres.contentSlide()
    s2.shapes[0].paragraphs = [Presentation.textParagraph("구성", size: 36, bold: true)]
    s2.shapes[1].paragraphs = ["문서: hwp, hwpx, docx", "도표: xlsx, csv", "프레젠테이션: pptx"].map { var p = Presentation.textParagraph($0, size: 24); p.props.listLabel = "•"; return p }
    var box = SlideShape(id: 4, name: "도형", kind: .roundRect, frame: Frame(x: 600, y: 300, w: 260, h: 120))
    box.fill = RGB(r: 68, g: 114, b: 196); box.anchor = .center
    box.paragraphs = [Presentation.textParagraph("강조 도형", size: 20, bold: true, align: .center, color: RGB(r: 255, g: 255, b: 255))]
    s2.shapes.append(box)
    var t = Table(); t.columnWidths = [120, 120]
    t.rows = [["항목", "값"], ["문서", "3"], ["도표", "2"]].map { $0.map { TableCell(blocks: [.paragraph(Presentation.textParagraph($0, size: 16))]) } }
    var ts = SlideShape(id: 5, name: "표", kind: .table, frame: Frame(x: 600, y: 140, w: 240, h: 120)); ts.table = t; ts.tableRowHeights = [40, 40, 40]
    s2.shapes.append(ts)
    s2.animations = [SlideAnimation(shapeID: 3, effect: .fade), SlideAnimation(shapeID: 4, effect: .flyIn, trigger: .afterPrevious, direction: .left),
                     SlideAnimation(shapeID: 4, effect: .spin, trigger: .onClick, duration: 2), SlideAnimation(shapeID: 5, effect: .zoomOut, trigger: .withPrevious)]
    s2.transition = SlideTransition(kind: .push, duration: 0.7, direction: .right)
    pres.slides.append(s2)
    try PPTXWriter.write(pres).write(to: URL(fileURLWithPath: args[2])); print("wrote \(args[2])")
case "numfmt":
    for (v, f) in [(60000.0, "_-* #,##0_-;-* #,##0_-;_-* \"-\"_-;_-@_-"), (0, "_-* #,##0_-;-* #,##0_-;_-* \"-\"_-;_-@_-"), (-1234.5, "#,##0.00;[Red]-#,##0.00"),
                   (0.256, "0.0%"), (731500, "[$₩-412]#,##0"), (46318, "yyyy\"년\" m\"월\" d\"일\""), (1234.5, "\"합계: \"#,##0\"원\""), (46318.5, "yyyy-mm-dd hh:mm")] {
        print(f, "→", NumberFormatter2.format(v, f))
    }
case "make-transition":
    let pres = Presentation.blank()
    // Distinct colours and titles so each effect is visible in test renders.
    pres.slides[0].background = RGB(r: 31, g: 78, b: 121)
    pres.slides[0].shapes[0].paragraphs = [Presentation.textParagraph("ONE", size: 96, bold: true, align: .center, color: .white)]
    var s2 = pres.contentSlide()
    s2.background = RGB(r: 237, g: 125, b: 49)
    s2.shapes[0].paragraphs = [Presentation.textParagraph("TWO", size: 96, bold: true, align: .center, color: .black)]
    s2.transition = SlideTransition(kind: TransitionKind(rawValue: args[2])!, duration: 0.8, direction: .right)
    pres.slides.append(s2)
    try PPTXWriter.write(pres).write(to: URL(fileURLWithPath: args[3]))
    let back = try SlidesIO.load(url: URL(fileURLWithPath: args[3]))
    print("written \(args[2]) → read back \(back.slides[1].transition.kind.rawValue)")
case "make-chart":
    let book = Workbook(); let ws = book.sheets[0]
    for (r, row) in [["월", "매출", "비용"], ["1월", "120", "80"], ["2월", "150", "95"], ["3월", "180", "100"], ["4월", "170", "120"]].enumerated() {
        for (c, v) in row.enumerated() { ws.set(CellRef(row: r, col: c), input: v) }
    }
    ws.set(CellRef(a1: "D1")!, input: "이익"); for r in 1...4 { ws.set(CellRef(row: r, col: 3), input: "=B\(r + 1)-C\(r + 1)") }
    ws.charts = [SheetChart(kind: .column, title: "월별 실적", data: CellRange(CellRef(a1: "A1")!, CellRef(a1: "D5")!), x: 280, y: 10),
                 SheetChart(kind: .pie, title: "매출 비중", data: CellRange(CellRef(a1: "A1")!, CellRef(a1: "B5")!), x: 280, y: 290, w: 300, h: 220)]
    try XLSXWriter.write(book).write(to: URL(fileURLWithPath: args[2])); print("wrote \(args[2])")
case "convert":
    let d = try load(args[2])
    try DocumentIO.save(d, to: URL(fileURLWithPath: args[3]))
    print("wrote \(args[3])")
case "corpus":
    var ok = 0, fail = 0, unsupported = 0
    for path in args.dropFirst(2) {
        do {
            let d = try load(path)
            _ = d.plainText
            ok += 1
        } catch let e as FormatError {
            if case .unsupported = e { unsupported += 1 } else { fail += 1; print("FAIL \(path): \(e)") }
        } catch {
            fail += 1; print("FAIL \(path): \(error)")
        }
    }
    print("ok=\(ok) fail=\(fail) unsupported=\(unsupported)")
case "formula-xlsx":
    // Writes dynamic-array / LAMBDA formulas to xlsx, reloads, and prints both evaluations.
    let book = Workbook(); let ws = book.sheets[0]
    book.definedNames["RATE"] = "0.1"
    let cells: [(String, String)] = [("A1", "3"), ("A2", "1"), ("A3", "2"), ("B1", "=SORT(A1:A3)"), ("C1", "=B1#*10"),
        ("D1", "=LET(x,A1,LAMBDA(y,x+y)(2))"), ("E1", "=FILTER(A1:A3,A1:A3>1)"), ("F1", "=SUM(A1:A3)*RATE"), ("G1", "=XLOOKUP(2,A1:A3,A1:A3)"),
        ("H1", "=TEXTJOIN(\",\",TRUE,A1:A3)"), ("I1", "=SEQUENCE(2,2)")]
    for (a, v) in cells { ws.set(CellRef(a1: a)!, input: v) }
    let url = URL(fileURLWithPath: args[2])
    try SheetIO.save(book, to: url)
    let back = try SheetIO.load(url: url)
    let e1 = FormulaEngine(book: book), e2 = FormulaEngine(book: back)
    for r in 0..<3 {
        print((0..<9).map { e1.display(ws, CellRef(row: r, col: $0)) }.joined(separator: " | "))
        print((0..<9).map { e2.display(back.sheets[0], CellRef(row: r, col: $0)) }.joined(separator: " | "))
    }
    print(back.sheets[0].cells.filter(\.value.isFormula).map { $0.key.a1 + " " + $0.value.input }.sorted().joined(separator: "\n"))
    print("names:", back.definedNames, "legacy:", back.sheets[0].legacyFormulas.count)
case "verify-cache":
    // Compares computed formula results with the values Excel cached in the file.
    var total = 0, same = 0
    for path in args.dropFirst(2) {
        guard let book = try? SheetIO.load(url: URL(fileURLWithPath: path)) else { print("skip", path); continue }
        let e = FormulaEngine(book: book)
        for ws in book.sheets {
            for (ref, cached) in ws.cachedValues.sorted(by: { $0.key < $1.key }) {
                guard ws.cells[ref]?.isFormula == true else { continue }
                total += 1
                let v = e.value(ws, ref)
                var ok: Bool
                switch (cached.0, v) {
                case ("n", .number(let d)): ok = Double(cached.1).map { abs($0 - d) <= 1e-9 * max(1, abs($0)) } ?? false
                case ("n", .empty): ok = cached.1.isEmpty || cached.1 == "0"
                case ("b", .bool(let b)): ok = (cached.1 == "1") == b
                case ("e", .error(let x)): ok = cached.1 == x
                case ("str", .string(let t)), ("s", .string(let t)): ok = cached.1 == t
                case ("str", .empty): ok = cached.1.isEmpty
                default: ok = false
                }
                if ok { same += 1 } else { print("DIFF", (path as NSString).lastPathComponent, ws.name, ref.a1, ws.cells[ref]!.input, "excel:", cached.1, "ours:", v.text) }
            }
        }
    }
    print("formulas \(total), matching \(same)")
case "fn-coverage":
    // Compares the registered functions with a name list (one per line).
    let names = try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let missing = names.filter { FunctionLibrary.table[$0] == nil }
    print("listed \(names.count), implemented \(names.count - missing.count), registered total \(FunctionLibrary.table.count)")
    if !missing.isEmpty { print("missing:", missing.joined(separator: " ")) }
case "eval":
    // eval [A1=value ...] =FORMULA ... — evaluates in a scratch workbook.
    let book = Workbook(); let ws = book.sheets[0]; let e = FormulaEngine(book: book)
    var row = 1000
    for arg in args.dropFirst(2) {
        if !arg.hasPrefix("="), let eq = arg.firstIndex(of: "="), let ref = CellRef(a1: String(arg[..<eq])) {
            ws.set(ref, input: String(arg[arg.index(after: eq)...])); continue
        }
        let ref = CellRef(row: row, col: 0); row += 1
        ws.set(ref, input: arg)
        e.invalidate()
        let v = e.value(ws, ref)
        if let m = e.spillArray(ws, ref) {
            print(arg, "→ {" + m.grid.map { $0.map { $0 == .empty ? "" : $0.text }.joined(separator: ", ") }.joined(separator: "; ") + "}")
        } else {
            print(arg, "→", v.isText ? "\"" + v.text + "\"" : v.text)
        }
        ws.set(ref, input: "")
    }
case "formula-suite":
    // Lines: FORMULA<TAB>EXPECTED. Data: A1:A5 = 1..5, B1:B5 = text, C1:C5 numbers.
    let book = Workbook(); let ws = book.sheets[0]; let e = FormulaEngine(book: book)
    let setup: [(String, String)] = [("A1", "1"), ("A2", "2"), ("A3", "3"), ("A4", "4"), ("A5", "5"),
        ("B1", "apple"), ("B2", "banana"), ("B3", "cherry"), ("B4", "apple"), ("B5", "date"),
        ("C1", "10"), ("C2", "20"), ("C3", "30"), ("C4", "40"), ("C5", "50"),
        ("D1", "Name"), ("D2", "Kim"), ("D3", "Lee"), ("D4", "Park"), ("E1", "Score"), ("E2", "90"), ("E3", "75"), ("E4", "82"),
        ("G1", "Score"), ("G2", ">80")]
    for (a, v) in setup { ws.set(CellRef(a1: a)!, input: v) }
    var pass = 0, fail = 0
    for line in try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let ref = CellRef(row: 999, col: 25)
        ws.set(ref, input: parts[0]); e.invalidate()
        var got: String
        if let m = e.spillArray(ws, ref) {
            got = "{" + m.grid.map { $0.map { $0.text }.joined(separator: ",") }.joined(separator: ";") + "}"
        } else {
            let v = e.value(ws, ref)
            if case .number(let d) = v { got = String(format: "%.10g", d) } else { got = v.text }
        }
        var ok = got == parts[1]
        if !ok, let x = Double(got), let y = Double(parts[1]) { ok = abs(x - y) <= 1e-6 * max(1, abs(y)) }
        if ok { pass += 1 } else { fail += 1; print("FAIL", parts[0], "expected", parts[1], "got", got) }
        ws.set(ref, input: "")
    }
    print("passed \(pass), failed \(fail)")
default:
    exit(AgentCLI.run(Array(args.dropFirst())))
}
