import AppKit
import UniformTypeIdentifiers

enum DocType {
    static let hwp = "com.haansoft.HancomOfficeViewer.mac.hwp"
    static let hwt = "com.haansoft.HancomOfficeViewer.mac.hwt"
    static let hwpx = "com.haansoft.HancomOfficeViewer.mac.hwpx"
    static let docx = "org.openxmlformats.wordprocessingml.document"
    static let dotx = "org.openxmlformats.wordprocessingml.template"
    static let txt = "public.plain-text"
    static let rtf = "public.rtf"
    static let md = "net.daringfireball.markdown"

    static func format(forType type: String, url: URL? = nil) -> SourceFormat {
        // UTIs are case-insensitive; LaunchServices may report them lowercased.
        let t = [hwp, hwt, hwpx, docx, dotx].first { $0.caseInsensitiveCompare(type) == .orderedSame } ?? type
        switch t {
        case hwp, hwt: return .hwp
        case hwpx: return .hwpx
        case docx, dotx: return .docx
        default:
            switch url?.pathExtension.lowercased() {
            case "hwp", "hwt": return .hwp
            case "hwpx": return .hwpx
            case "docx", "dotx": return .docx
            default: return .unknown
            }
        }
    }
}

@objc(HWDocument)
final class HWDocument: NSDocument {
    let textStorage = NSTextStorage()
    private(set) var model = UDocument()
    var page = PageSetup.a4Hwp
    /// Documents opened from disk get "Save As" on their first save, so a
    /// lossy conversion never silently replaces the original file.
    private var inPlaceSaveConfirmed = false
    private var importWarningsPresented = false

    override init() {
        super.init()
        model.source = .hwp
    }

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { [DocType.hwp, DocType.hwpx, DocType.docx, DocType.hwt, DocType.dotx, DocType.txt, DocType.rtf, DocType.md, DocType.html, DocType.pdf] }
    override class var writableTypes: [String] { [DocType.hwp, DocType.hwpx, DocType.docx, DocType.pdf, DocType.html, DocType.txt, DocType.rtf, DocType.md] }
    override class func isNativeType(_ type: String) -> Bool { writableTypes.contains(type) }

    var sourceFormat: SourceFormat { model.source }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController(document: self))
    }

    override func read(from url: URL, ofType typeName: String) throws {
        let ext = url.pathExtension.lowercased()
        if ["txt", "text", "md", "markdown", "rtf", "html", "htm"].contains(ext) {
            try readText(url: url, ext: ext)
            return
        }
        let d: UDocument
        do { d = try DocumentIO.load(url: url) } catch let e as FormatError {
            throw NSError(domain: "HanX", code: 1, userInfo: [NSLocalizedDescriptionKey: "문서를 열 수 없습니다", NSLocalizedFailureReasonErrorKey: e.description])
        }
        model = d
        importWarningsPresented = false
        page = d.sections.first?.page ?? .a4Hwp
        header = d.sections.first?.header
        footer = d.sections.first?.footer
        let attr = AttributedBridge.attributedString(from: d)
        textStorage.beginEditing()
        textStorage.setAttributedString(attr)
        textStorage.endEditing()
        // Templates open as new untitled documents.
        if ["hwt", "dotx"].contains(url.pathExtension.lowercased()) {
            DispatchQueue.main.async { [weak self] in
                self?.fileURL = nil
                self?.fileType = d.source == .docx ? DocType.docx : DocType.hwp
            }
        }
    }

    /// Plain text, Markdown, RTF and HTML open as editable documents.
    private func readText(url: URL, ext: String) throws {
        let data = try Data(contentsOf: url)
        var attr: NSAttributedString
        model = UDocument()
        importWarningsPresented = false
        model.source = .docx
        page = .a4Hwp
        if ext == "rtf" || ext == "html" || ext == "htm" {
            let type: NSAttributedString.DocumentType = ext == "rtf" ? .rtf : .html
            attr = try NSAttributedString(data: data, options: [.documentType: type, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
            let d = AttributedBridge.document(from: attr, base: model, page: page)
            attr = AttributedBridge.attributedString(from: d)
        } else {
            let text = DelimitedText.decode(data).replacingOccurrences(of: "\r\n", with: "\n")
            let d = UDocument.plain(text, char: HWDocument.defaultCharProps(for: .docx))
            attr = AttributedBridge.attributedString(from: d)
        }
        textStorage.setAttributedString(attr)
        DispatchQueue.main.async { [weak self] in self?.fileType = DocType.docx; self?.fileURL = nil; self?.displayNameOverride = url.deletingPathExtension().lastPathComponent }
    }

    private var displayNameOverride: String?

    /// The notice belongs to the opened document, not its selection, edits or windows.
    func presentImportWarnings(in window: NSWindow) {
        guard !importWarningsPresented, !model.warnings.isEmpty else { return }
        let notices = model.warnings.map { warning in
            warning == "PDF import extracts selectable text and page sizes. Layout, tables, images and annotations are not reconstructed; scanned pages require OCR, which HanX does not perform."
                ? "PDF에서 선택 가능한 텍스트와 페이지 크기를 가져왔습니다. 원본 배치, 표, 이미지, 주석은 재구성하지 않습니다. 스캔한 페이지에는 OCR이 필요하며 HanX는 OCR을 지원하지 않습니다."
                : warning
        }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !notices.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "문서 가져오기 안내"
        let fullText = notices.joined(separator: "\n\n")
        if fullText.count <= 1200 {
            alert.informativeText = fullText
        } else {
            alert.informativeText = "가져오기 안내 \(notices.count)개가 있습니다. 아래 목록에서 전체 내용을 확인하세요."
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 240))
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.borderType = .bezelBorder
            let details = NSTextView(frame: scroll.contentView.bounds)
            details.isEditable = false
            details.isSelectable = true
            details.isRichText = false
            details.isVerticallyResizable = true
            details.isHorizontallyResizable = false
            details.minSize = NSSize(width: 0, height: scroll.contentSize.height)
            details.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            details.autoresizingMask = [.width]
            details.textContainer?.widthTracksTextView = true
            details.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            details.textContainerInset = NSSize(width: 8, height: 8)
            details.font = .systemFont(ofSize: 12)
            details.textColor = .labelColor
            details.setAccessibilityLabel("가져오기 안내 전체 내용")
            scroll.documentView = details
            details.string = fullText
            alert.accessoryView = scroll
        }
        alert.addButton(withTitle: "확인")
        importWarningsPresented = true
        // AppKit queues this sheet if another operation already has one open.
        alert.beginSheetModal(for: window)
    }

    override var displayName: String! {
        get { displayNameOverride.map { fileURL == nil ? $0 : super.displayName } ?? super.displayName }
        set { super.displayName = newValue }
    }

    /// 머리말 / 꼬리말 of the document (first section's, applied to all pages).
    var header: [Block]?
    var footer: [Block]?

    func currentModel() -> UDocument {
        let d = AttributedBridge.document(from: textStorage, base: model, page: page)
        if !d.sections.isEmpty { d.sections[0].header = header; d.sections[0].footer = footer }
        return d
    }

    func decorations() -> PageDecorations {
        PageDecorations.make(header: header, footer: footer, page: page, images: model.images, source: model.source)
    }

    override func data(ofType typeName: String) throws -> Data {
        let doc = currentModel()
        let typeName = HWDocument.writableTypes.first { $0.caseInsensitiveCompare(typeName) == .orderedSame } ?? typeName
        switch typeName {
        case DocType.txt: return Data(doc.plainText.utf8)
        case DocType.md: return Data(MarkdownWriter.write(doc).utf8)
        case DocType.html: return Data(HTMLWriter.write(doc).utf8)
        case DocType.rtf:
            return textStorage.rtf(from: NSRange(location: 0, length: textStorage.length),
                                   documentAttributes: [.paperSize: NSSize(width: page.width, height: page.height),
                                                        .leftMargin: page.marginLeft, .rightMargin: page.marginRight,
                                                        .topMargin: page.marginTop, .bottomMargin: page.marginBottom]) ?? Data()
        case DocType.pdf: return pdfData()
        default: break
        }
        switch DocType.format(forType: typeName, url: fileURL) {
        case .docx: return DOCXWriter(doc).write()
        case .hwpx: return HWPXWriter(doc).write()
        case .hwp: return HWP5Writer(doc).write()
        case .unknown: throw NSError(domain: "HanX", code: 2, userInfo: [NSLocalizedDescriptionKey: "이 형식으로는 저장할 수 없습니다"])
        }
    }

    /// Vector PDF of the paginated layout, one PDF page per sheet.
    func pdfData() -> Data {
        let copy = NSTextStorage(attributedString: textStorage)
        let view = PageLayoutView(storage: copy, page: page)
        view.decorations = decorations()
        for _ in 0..<5000 {
            if let last = view.layoutManager.textContainers.last { view.layoutManager.ensureLayout(for: last) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
            if !view.needsMorePages() { break }
        }
        let pages = view.sheetFrames.map { view.dataWithPDF(inside: $0) }
        return PDFMerge.merge(pages)
    }

    override func save(_ sender: Any?) {
        if fileURL != nil && !inPlaceSaveConfirmed {
            saveAs(sender)
        } else {
            super.save(sender)
        }
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil && saveOperation != .saveToOperation { self?.inPlaceSaveConfirmed = true }
            completionHandler(error)
        }
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let view = (windowControllers.first as? EditorWindowController)?.pages else {
            throw NSError(domain: "HanX", code: 3, userInfo: [NSLocalizedDescriptionKey: "인쇄할 창이 없습니다"])
        }
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        info.paperSize = NSSize(width: page.width, height: page.height)
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        view.textViews.forEach { $0.setSelectedRange(NSRange(location: $0.selectedRange().location, length: 0)) }
        return NSPrintOperation(view: view, printInfo: info)
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.isExtensionHidden = false
        return true
    }

    override var shouldRunSavePanelWithAccessoryView: Bool { true }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        switch typeName {
        case DocType.docx: return "docx"
        case DocType.hwpx: return "hwpx"
        case DocType.hwp: return "hwp"
        case DocType.pdf: return "pdf"
        case DocType.html: return "html"
        case DocType.txt: return "txt"
        case DocType.rtf: return "rtf"
        case DocType.md: return "md"
        default: return super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
        }
    }

    // MARK: Defaults for new documents

    static func defaultCharProps(for f: SourceFormat) -> CharProps {
        var c = CharProps()
        if f == .docx { c.fontName = "Calibri"; c.eastAsianFontName = "맑은 고딕"; c.size = 11 }
        else { c.fontName = "함초롬바탕"; c.eastAsianFontName = "함초롬바탕"; c.size = 10 }
        return c
    }

    func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
        var a = AttributedBridge.charAttributes(HWDocument.defaultCharProps(for: sourceFormat), eastAsian: true)
        var p = ParaProps()
        if sourceFormat == .docx { p.alignment = .left; p.lineSpacing = .multiple(1.08); p.spaceAfter = 8 }
        let (ps, rule) = AttributedBridge.paragraphStyle(p, mark: HWDocument.defaultCharProps(for: sourceFormat), outer: [],
                                                         ctx: .init(images: [:], source: sourceFormat))
        a[.paragraphStyle] = ps
        if let rule { a[.hwLineRule] = rule }
        return a
    }
}
