import AppKit
import UniformTypeIdentifiers

let app = NSApplication.shared
let args = CommandLine.arguments
if args.contains("--dark") { app.appearance=NSAppearance(named:.darkAqua) }

if let i=args.firstIndex(of:"--editingchecks"), args.count>i+1 {
    app.setActivationPolicy(.prohibited)
    FontResolver.shared.registerBundledFonts()
    do { try EditingChecks.run(to:URL(fileURLWithPath:args[i+1])); exit(0) }
    catch { print("FAIL \(error)"); exit(1) }
}

// Headless verification: HanWord --render <file> <outdir> [pages]
// Lays the document out exactly as the editor does and writes page PNGs.
if let i = args.firstIndex(of: "--render"), args.count > i + 2 {
    app.setActivationPolicy(.prohibited)
    FontResolver.shared.registerBundledFonts()
    do {
        let doc = try DocumentIO.load(url: URL(fileURLWithPath: args[i + 1]))
        let storage = NSTextStorage(attributedString: AttributedBridge.attributedString(from: doc))
        let view = PageLayoutView(storage: storage, page: doc.sections.first?.page ?? .a4Hwp)
        view.decorations = PageDecorations.make(header: doc.sections.first?.header, footer: doc.sections.first?.footer,
                                                page: view.page, images: doc.images, source: doc.source)
        for _ in 0..<2000 {
            if let last = view.layoutManager.textContainers.last { view.layoutManager.ensureLayout(for: last) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            if !view.needsMorePages() { break }
        }
        let outDir = URL(fileURLWithPath: args[i + 2])
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let limit = args.count > i + 3 ? Int(args[i + 3]) ?? 2 : 2
        for (n, rect) in view.sheetFrames.prefix(limit).enumerated() {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { continue }
            view.cacheDisplay(in: rect, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("page-\(n + 1).png"))
        }
        print("pages=\(view.pageCount)")
        exit(0)
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

// Font diagnostics: HanWord --fonts <name>...
if let i = args.firstIndex(of: "--fonts") {
    FontResolver.shared.registerBundledFonts()
    for n in args[(i + 1)...] {
        let f = FontResolver.shared.font(name: n, size: 10, bold: false, italic: false).font
        print("\(n) → \(f.fontName) [\(f.familyName ?? "")]")
    }
    exit(0)
}

// Headless verification of the editor save path: file → TextKit → file.
if let i = args.firstIndex(of: "--bridge-convert"), args.count > i + 2 {
    app.setActivationPolicy(.prohibited)
    do {
        let doc = try DocumentIO.load(url: URL(fileURLWithPath: args[i + 1]))
        let storage = NSTextStorage(attributedString: AttributedBridge.attributedString(from: doc))
        let back = AttributedBridge.document(from: storage, base: doc, page: doc.sections.first?.page ?? .a4Hwp)
        try DocumentIO.save(back, to: URL(fileURLWithPath: args[i + 2]))
        print("ok")
        exit(0)
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

// Headless save-as through the real document classes:
//   HanWord --export <in> <out>   (format chosen by the output extension)
if let i = args.firstIndex(of: "--export"), args.count > i + 2 {
    app.setActivationPolicy(.prohibited)
    FontResolver.shared.registerBundledFonts()
    do {
        let input = URL(fileURLWithPath: args[i + 1]), output = URL(fileURLWithPath: args[i + 2])
        let dc = HWDocumentController()
        let inType = try dc.typeForContents(of: input)
        guard let cls = dc.documentClass(forType: inType) as? NSDocument.Type else { throw FormatError.unsupported(inType) }
        let doc = cls.init()
        try doc.read(from: input, ofType: inType)
        guard let outType = UTType(filenameExtension: output.pathExtension)?.identifier else { throw FormatError.unsupported(output.pathExtension) }
        try doc.data(ofType: outType).write(to: output)
        print("\(String(describing: cls)) \(inType) → \(outType)")
        exit(0)
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

// UI verification without screen capture: builds the real window offscreen
// and renders its content view.  HanWord --snapshot <file|start|new-sheet|new-slides> <out.png>
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 {
    app.setActivationPolicy(.prohibited)
    FontResolver.shared.registerBundledFonts()
    NSApp.mainMenu = MainMenu.build()
    let dc = HWDocumentController()
    var window: NSWindow?
    do {
        switch args[i + 1] {
        case "start": window = StartWindowController.shared.window
        case "new-sheet", "new-slides", "new-doc":
            let type = args[i + 1] == "new-sheet" ? DocType.xlsx : args[i + 1] == "new-slides" ? DocType.pptx : DocType.hwp
            let doc = try dc.makeUntitledDocument(ofType: type)
            dc.addDocument(doc)
            doc.makeWindowControllers()
            window = doc.windowControllers.first?.window
        default:
            let url = URL(fileURLWithPath: args[i + 1])
            let doc = try dc.makeDocument(withContentsOf: url, ofType: dc.typeForContents(of: url))
            dc.addDocument(doc)
            doc.makeWindowControllers()
            window = doc.windowControllers.first?.window
        }
        if args.count > i + 3, let wc = window?.windowController as? SlideWindowController {
            let parts = args[i + 3].split(separator: ",").compactMap { Int($0) }   // slide,shape,tab
            wc.debugSelect(slide: parts[safe: 0] ?? 0, shape: parts[safe: 1] ?? 0, animationTab: (parts[safe: 2] ?? 0) == 1)
        }
        if args.contains("--table-editor"),let wc=window?.windowController as? SlideWindowController {
            wc.insertTable(nil)
            if let id=wc.debugCanvas.selectedID { wc.canvasEditTable(id) }
            window=wc.debugTableWindow
        }
        if let i=args.firstIndex(of:"--ribbon-tab"),args.count>i+1 {
            let title=args[i+1]
            if let wc=window?.windowController as? SlideWindowController { wc.debugRibbon.showTab(title) }
            if let wc=window?.windowController as? SheetWindowController { wc.debugRibbon.showTab(title) }
            if let wc=window?.windowController as? EditorWindowController { wc.debugRibbon.showTab(title) }
        }
        if let i=args.firstIndex(of:"--window-width"),args.count>i+1,let width=Double(args[i+1]),let w=window { var f=w.frame; f.size.width=max(w.minSize.width,width); w.setFrame(f,display:false) }
        guard let w = window, let v = w.contentView else { throw FormatError.invalid("no window") }
        w.setFrame(NSRect(x: 0, y: 0, width: w.frame.width, height: w.frame.height), display: false)
        for _ in 0..<40 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { throw FormatError.invalid("no bitmap") }
        v.cacheDisplay(in: v.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 2]))
        print("ok \(Int(v.bounds.width))x\(Int(v.bounds.height))")
        exit(0)
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

// Slide show test: HanWord --showtest <pptx> <slide> <clicks> <out.png>
if let i = args.firstIndex(of: "--showtest"), args.count > i + 4 {
    app.setActivationPolicy(.prohibited)
    FontResolver.shared.registerBundledFonts()
    do {
        let pres = try SlidesIO.load(url: URL(fileURLWithPath: args[i + 1]))
        let c = SlideShowController(pres: pres, screen: NSScreen.main!)
        guard let img = c.snapshot(slide: Int(args[i + 2])! - 1, clicks: Int(args[i + 3])!) else { throw FormatError.invalid("render") }
        let rep = NSBitmapImageRep(cgImage: img)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 4]))
        print("ok")
        exit(0)
    } catch { print("error: \(error)"); exit(1) }
}

// Transition filmstrip: HanWord --transitionframes <pptx> <toSlide> <out.png>
// Renders the real transition animation at 0, 20, 40, 60, 80, 100 % with CARenderer.
if let i = args.firstIndex(of: "--transitionframes"), args.count > i + 3 {
    app.setActivationPolicy(.prohibited)
    do {
        let pres = try SlidesIO.load(url: URL(fileURLWithPath: args[i + 1]))
        let to = Int(args[i + 2])! - 1
        guard let img = TransitionFilmstrip.render(pres, to: to) else { print("render failed"); exit(1) }
        let rep = NSBitmapImageRep(cgImage: img)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 3]))
        print("ok \(pres.slides[to].transition.kind.rawValue)")
        exit(0)
    } catch { print("error: \(error)"); exit(1) }
}

// Transition test: HanWord --transitiontest <pptx> <fromSlide>
if let i = args.firstIndex(of: "--transitiontest"), args.count > i + 2 {
    app.setActivationPolicy(.prohibited)
    do {
        let pres = try SlidesIO.load(url: URL(fileURLWithPath: args[i + 1]))
        let c = SlideShowController(pres: pres, screen: NSScreen.main!)
        print(c.transitionProbe(from: Int(args[i + 2])! - 1))
        exit(0)
    } catch { print("error: \(error)"); exit(1) }
}

// Finder association: HanWord --set-default-handlers
if args.contains("--set-default-handlers") {
    HWDocumentController.makeDefaultHandler { failed in
        print(failed.isEmpty ? "ok" : "failed: \(failed)")
        exit(failed.isEmpty ? 0 : 1)
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 10))
    exit(2)
}

let delegate = AppDelegate()
app.delegate = delegate
_ = HWDocumentController()      // first instance becomes NSDocumentController.shared
app.run()
