#if HANX_PORTABLE || !canImport(AppKit)
import Foundation

/// Optional local PDF tools. Arguments are passed directly, never to a shell.
enum PortableTool {
    static func find(_ name: String) -> URL? {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        let separator: Character = ";"
        let suffix = ".exe"
        #else
        let separator: Character = ":"
        let suffix = ""
        #endif
        // Windows environment names are case-insensitive, but Swift dictionaries
        // are not. Runners and standard terminals commonly expose "Path".
        #if os(Windows)
        func value(_ name: String) -> String? { env.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }
        let searchPath = value("PATH") ?? ""
        #else
        let searchPath = env["PATH"] ?? ""
        #endif
        var dirs = searchPath.split(separator: separator).map(String.init)
        #if os(Windows)
        if let programFiles = value("ProgramFiles") { dirs += [programFiles + "/LibreOffice/program", programFiles + "/poppler/Library/bin"] }
        if let local = value("LOCALAPPDATA") { dirs.append(local + "/Microsoft/WinGet/Links") }
        if let choco = value("ChocolateyInstall") { dirs.append(choco + "/bin") }
        else if let data = value("ProgramData") { dirs.append(data + "/chocolatey/bin") }
        #elseif os(macOS)
        dirs += ["/Applications/LibreOffice.app/Contents/MacOS", "/opt/homebrew/bin", "/usr/local/bin"]
        #endif
        for dir in dirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name + suffix)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
    static func run(_ name: String, _ args: [String], in directory: URL) throws -> String {
        guard let executable = find(name) else {
            throw AgentError("missing_dependency", "PDF operation requires local \(name). Install \(name == "soffice" ? "LibreOffice" : "Poppler (pdfinfo and pdftotext)") and add its executable directory to PATH.")
        }
        let log = directory.appendingPathComponent(UUID().uuidString + ".log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.standardOutput = handle
        process.standardError = handle
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        try process.run()
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); throw AgentError("io_error", "\(name) exceeded the PDF operation time limit") }
        process.waitUntilExit()
        let message = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else { throw AgentError("invalid_input", "\(name) failed: \(message.prefix(2000))") }
        return message
    }
    static func temporary<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HanX-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }
}

enum AgentPDF {
    static func data(_ file: AgentFile) throws -> Data {
        try PortableTool.temporary { dir in
            let ext: String
            let source: Data
            switch file {
            case .document(let document): ext = "docx"; source = DOCXWriter(document).write()
            case .presentation(let presentation):
                guard !presentation.slides.isEmpty else { throw AgentError("invalid_argument", "A PDF presentation needs at least one slide") }
                ext = "pptx"; source = PPTXWriter.write(presentation)
            // Calculate in HanX's restricted engine and send values only. A
            // second spreadsheet engine must not execute untrusted formulas.
            case .spreadsheet(let book): ext = "xlsx"; source = XLSXWriter.write(book, allowExternalIO: false, includeFormulas: false)
            case .xml: throw AgentError("unsupported_format", "Generic XML cannot be exported as PDF")
            }
            let input = dir.appendingPathComponent("input." + ext)
            try source.write(to: input)
            // Isolate the profile, so an existing GUI process cannot consume this request.
            _ = try PortableTool.run("soffice", ["-env:UserInstallation=" + dir.appendingPathComponent("profile").absoluteString, "--headless", "--convert-to", "pdf", "--outdir", dir.path, input.path], in: dir)
            let output = dir.appendingPathComponent("input.pdf")
            guard let data = try? Data(contentsOf: output), PDFReader.isPDF(data) else { throw AgentError("invalid_input", "LibreOffice produced no PDF") }
            return data
        }
    }
}

enum PDFReader {
    static func isPDF(_ data: Data) -> Bool { data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil }
    static func read(_ data: Data) throws -> UDocument {
        guard isPDF(data) else { throw FormatError.invalid("Cannot read PDF document") }
        return try PortableTool.temporary { dir in
            let input = dir.appendingPathComponent("input.pdf"), output = dir.appendingPathComponent("text.txt")
            try data.write(to: input)
            let info = try PortableTool.run("pdfinfo", [input.path], in: dir)
            if info.contains("copy:no") || info.contains("copy: no") { throw FormatError.unsupported("PDF permissions do not allow text extraction") }
            _ = try PortableTool.run("pdftotext", ["-enc", "UTF-8", input.path, output.path], in: dir)
            let text = try String(contentsOf: output, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FormatError.unsupported("PDF contains no extractable text. Scanned PDFs require OCR, which HanX does not perform.") }
            let doc = UDocument()
            doc.warnings = ["PDF import extracts selectable text and page sizes using local Poppler. Layout, tables, images and annotations are not reconstructed; scanned pages require OCR."]
            var pages = text.components(separatedBy: "\u{0c}")
            if pages.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { pages.removeLast() }
            guard pages.count <= 5000 else { throw FormatError.unsupported("PDF exceeds 5000 pages") }
            for (index, page) in pages.enumerated() {
                var section = UDocument.plain(page, char: CharProps()).sections[0]
                let pageInfo = try PortableTool.run("pdfinfo", ["-f", String(index + 1), "-l", String(index + 1), input.path], in: dir)
                if let line = pageInfo.components(separatedBy: "\n").first(where: { $0.contains(" size:") || $0.hasPrefix("Page size:") }),
                   let colon = line.firstIndex(of: ":") {
                    let parts = line[line.index(after: colon)...].split(whereSeparator: { $0.isWhitespace })
                    if parts.count >= 3, let w = Double(parts[0]), let h = Double(parts[2]), w > 0, h > 0, w <= 100000, h <= 100000 {
                        section.page = PageSetup(width: w, height: h, marginTop: min(36,h/8), marginBottom: min(36,h/8), marginLeft: min(36,w/8), marginRight: min(36,w/8), header: 18, footer: 18)
                    }
                }
                if page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    doc.warnings.append("PDF page \(index + 1) contains no extractable text; OCR may be required.")
                }
                doc.sections.append(section)
            }
            return doc
        }
    }
}
#endif
