#if canImport(AppKit) && !HANX_PORTABLE
import AppKit
import PDFKit

/// The command line uses the same native drawing code as the app. No print
/// dialog or external office application is needed.
enum AgentPDF {
    static func data(_ file: AgentFile) throws -> Data {
        guard Thread.isMainThread else { throw AgentError("invalid_argument", "PDF export must run on the main thread") }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let data: Data
        switch file {
        case .document(let doc): data = try document(doc)
        case .presentation(let pres):
            guard !pres.slides.isEmpty else { throw AgentError("invalid_argument", "A PDF presentation needs at least one slide") }
            data = SlideRenderer.pdf(pres)
        case .spreadsheet(let book):
            let engine = FormulaEngine(book: book, allowExternalIO: false)
            var pages: [Data] = []
            for sheet in book.sheets {
                let view = SheetGridView(sheet: sheet, engine: engine)
                view.printMode = true
                let sheetPages = try view.pdfPages(pageSize: NSSize(width: 770, height: 523))
                pages += sheetPages.isEmpty ? [view.dataWithPDF(inside: NSRect(x: 0, y: 0, width: 770, height: 523))] : sheetPages
            }
            data = PDFMerge.merge(pages)
        case .xml:
            throw AgentError("unsupported_format", "Generic XML cannot be exported as PDF. Convert an office document instead.")
        }
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw AgentError("invalid_input", "PDF rendering produced no pages")
        }
        return data
    }

    private static func document(_ doc: UDocument) throws -> Data {
        var views: [PageLayoutView] = []
        // Paginating each section separately preserves its paper size, margins
        // and decorations, including documents with mixed orientations.
        for section in doc.sections {
            let part = UDocument()
            part.source = doc.source
            part.images = doc.images
            part.sections = [section]
            let storage = NSTextStorage(attributedString: AttributedBridge.attributedString(from: part))
            let view = PageLayoutView(storage: storage, page: section.page)
            view.decorations = PageDecorations.make(header: section.header, footer: section.footer,
                                                   page: section.page, images: doc.images, source: doc.source)
            for _ in 0..<5000 {
                if let last = view.layoutManager.textContainers.last { view.layoutManager.ensureLayout(for: last) }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
                if !view.needsMorePages() { break }
            }
            guard !view.needsMorePages() else { throw AgentError("invalid_input", "Document exceeds the PDF pagination limit") }
            views.append(view)
        }
        let pageCount = views.reduce(0) { $0 + $1.pageCount }
        var number = 1
        var pages: [Data] = []
        for view in views {
            for sheet in view.subviews.compactMap({ $0 as? PageSheetView }) {
                sheet.pageNumber = number
                sheet.pageCount = pageCount
                number += 1
            }
            pages += view.sheetFrames.map { view.dataWithPDF(inside: $0) }
        }
        return PDFMerge.merge(pages)
    }
}

#endif
