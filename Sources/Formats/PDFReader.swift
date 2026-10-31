import Foundation
import PDFKit

/// PDF is a page description, not an editable office document. Import its
/// selectable text into one section per page and make the loss explicit.
enum PDFReader {
    static func isPDF(_ data: Data) -> Bool {
        data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil
    }

    static func read(_ data: Data) throws -> UDocument {
        guard isPDF(data), let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw FormatError.invalid("Cannot read PDF document")
        }
        guard !pdf.isLocked else {
            throw FormatError.unsupported("Password-protected PDF. Unlock the PDF before importing it.")
        }
        guard pdf.allowsCopying else {
            throw FormatError.unsupported("PDF permissions do not allow text extraction.")
        }
        let doc = UDocument()
        doc.warnings = ["PDF import extracts selectable text and page sizes. Layout, tables, images and annotations are not reconstructed; scanned pages require OCR, which HanX does not perform."]
        var emptyPages: [Int] = []
        var hasText = false
        var char = CharProps()
        char.fontName = "Arial"
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { throw FormatError.invalid("Cannot read PDF page \(index + 1)") }
            let box = page.bounds(for: .mediaBox)
            let rotated = abs(page.rotation % 180) == 90
            let width = rotated ? box.height : box.width
            let height = rotated ? box.width : box.height
            guard width.isFinite, height.isFinite, width > 0, height > 0,
                  width <= 100_000, height <= 100_000 else {
                throw FormatError.unsupported("PDF page \(index + 1) has unsupported dimensions")
            }
            let text = (page.string ?? "").replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyPages.append(index + 1)
            } else {
                hasText = true
            }
            var section = UDocument.plain(text, char: char).sections[0]
            let horizontal = min(36, width / 8), vertical = min(36, height / 8)
            section.page = PageSetup(width: width, height: height, marginTop: vertical,
                                     marginBottom: vertical, marginLeft: horizontal, marginRight: horizontal,
                                     header: vertical / 2, footer: vertical / 2)
            doc.sections.append(section)
        }
        guard hasText else {
            throw FormatError.unsupported("PDF contains no extractable text. Scanned or image-only PDFs require OCR, which HanX does not perform.")
        }
        if !emptyPages.isEmpty {
            let listed = emptyPages.prefix(50).map(String.init).joined(separator: ", ")
            let more = emptyPages.count > 50 ? " (and \(emptyPages.count - 50) more)" : ""
            doc.warnings.append("PDF pages \(listed)\(more) have no extractable text and remain empty. Scanned pages require OCR; HanX does not perform OCR.")
        }
        return doc
    }
}
