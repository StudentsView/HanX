import Foundation
import PDFKit

enum PDFMerge {
    static func merge(_ pages: [Data]) -> Data {
        let out = PDFDocument()
        for d in pages {
            guard let doc = PDFDocument(data: d) else { continue }
            for i in 0..<doc.pageCount { if let p = doc.page(at: i) { out.insert(p, at: out.pageCount) } }
        }
        return out.dataRepresentation() ?? Data()
    }
}
