import Foundation
import Darwin

/// Interactive prompts stay outside the JSON/stdio agent protocol.
enum AgentInteractive {
    static let welcome = """
    ┌──────────────────────────────────────────────┐
    │  HanX                                        │
    │  문서 / 엑셀 / 슬라이드                      │
    ├──────────────────────────────────────────────┤
    │  파일 변환     hanx --convert                │
    │  명령어 표     hanx --help                   │
    │  지원 기능     hanx capabilities --pretty    │
    │  에이전트 연결 hanx mcp                      │
    └──────────────────────────────────────────────┘
    """
    private enum Key { case byte(UInt8), up, down, escape, pasteStart, pasteEnd, end }
    private final class Terminal {
        var saved = termios()
        init() throws {
            guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
                throw AgentError("terminal_required", "터미널에서 hanx --convert를 실행하세요. 자동화: hanx convert 원본.hwp --output 결과.docx")
            }
            guard tcgetattr(STDIN_FILENO, &saved) == 0 else { throw AgentError("io_error", "터미널 설정을 읽을 수 없습니다.") }
            try activate()
        }
        func activate() throws {
            var raw = saved
            raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
            // Keep UTF-8 input intact; process Ctrl-C ourselves so settings can be restored.
            raw.c_iflag &= ~tcflag_t(ISTRIP | IXON)
            raw.c_cc.16 = 1 // Darwin VMIN
            raw.c_cc.17 = 0 // Darwin VTIME
            guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { throw AgentError("io_error", "터미널 입력을 설정할 수 없습니다.") }
        }
        func restore() { tcsetattr(STDIN_FILENO, TCSANOW, &saved) }
        deinit { restore() }
        func output(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
        func byte(timeout: Int32? = nil) -> UInt8? {
            if let timeout {
                var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                if poll(&descriptor, 1, timeout) <= 0 { return nil }
            }
            var value: UInt8 = 0
            return Darwin.read(STDIN_FILENO, &value, 1) == 1 ? value : nil
        }
        func key() -> Key {
            guard let first = byte() else { return .end }
            guard first == 27 else { return .byte(first) }
            guard let next = byte(timeout: 100), next == 91 || next == 79 else { return .escape }
            var sequence: [UInt8] = []
            for _ in 0..<8 {
                guard let c = byte(timeout: 100) else { return .escape }
                sequence.append(c)
                if (64...126).contains(c) { break }
            }
            switch String(bytes: sequence, encoding: .ascii) {
            case "A": return .up
            case "B": return .down
            case "200~": return .pasteStart
            case "201~": return .pasteEnd
            default: return .escape
            }
        }
        func path() throws -> String {
            output("여기에 파일을 드래그 드롭한 후 Enter 키를 눌러주세요.\n› ")
            var buffer: [UInt8] = []
            while true {
                switch key() {
                case .byte(10), .byte(13):
                    output("\n")
                    guard let text = String(bytes: buffer, encoding: .utf8) else { throw AgentError("invalid_argument", "파일 경로의 문자 인코딩을 확인해 주세요.") }
                    return text
                case .byte(3), .byte(4), .escape, .end: throw AgentError("cancelled", "변환을 취소했습니다.")
                case .byte(127), .byte(8):
                    if var text = String(bytes: buffer, encoding: .utf8), !text.isEmpty { text.removeLast(); buffer = Array(text.utf8); output("\r\u{1b}[2K› " + text) }
                case .byte(let b):
                    guard b >= 32, buffer.count < 32768 else { continue }
                    buffer.append(b); FileHandle.standardOutput.write(Data([b]))
                default: continue
                }
            }
        }
        func choose(_ choices: [String]) throws -> String {
            var selected = 0, drawn = false
            while true {
                if drawn { output("\u{1b}[\(choices.count + 1)A") }
                for (index, ext) in choices.enumerated() { output("\r\u{1b}[2K  \(index == selected ? "❯" : " ") \(ext.uppercased())\n") }
                output("\r\u{1b}[2K  ↑ ↓ 선택   Enter 변환   Esc / Ctrl-C 취소\n")
                drawn = true
                switch key() {
                case .up: selected = (selected + choices.count - 1) % choices.count
                case .down: selected = (selected + 1) % choices.count
                case .byte(10), .byte(13): return choices[selected]
                case .byte(3), .byte(4), .byte(113), .escape, .end: throw AgentError("cancelled", "변환을 취소했습니다.")
                default: continue
                }
            }
        }
    }
    static func formats(_ file: AgentFile, input: URL) -> [String] {
        let values: [String]
        switch file {
        case .document: values = ["docx", "hwpx", "hwp", "pdf", "txt", "md", "html", "hml", "json", "xml"]
        case .presentation: values = ["pptx", "pdf", "txt", "json", "xml"]
        case .spreadsheet: values = ["xlsx", "csv", "tsv", "pdf", "html", "json", "xml"]
        case .xml(let xml):
            if xml.rootElement()?.local.uppercased() == "HWPML" { values = ["docx", "hwpx", "hwp", "pdf", "txt", "md", "html", "json"] }
            else if xml.rootElement()?.local == "package", let parts = xml.rootElement()?.children {
                let names = parts.compactMap { ($0 as? XMLElement)?.attributes?.first { $0.local == "name" }?.stringValue }
                if names.contains("/word/document.xml") { values = ["docx"] }
                else if names.contains("/ppt/presentation.xml") { values = ["pptx"] }
                else if names.contains("/xl/workbook.xml") { values = ["xlsx"] }
                else if names.contains("/Contents/header.xml") { values = ["hwpx"] }
                else { values = [] }
            } else { values = [] }
        }
        // Flat OPC needs an actual ZIP input, not an arbitrary JSON model or CSV.
        return values.filter { ext in
            ext != input.pathExtension.lowercased() && (ext != "xml" || file.kind == "document" || ["pptx", "xlsx"].contains(input.pathExtension.lowercased()))
        }
    }
    static func run(_ arguments: [String]) -> Int32 {
        do {
            guard arguments.count <= 1 else { throw AgentError("invalid_argument", "사용법: hanx --convert [파일 경로]") }
            let terminal = try Terminal()
            let path = try arguments.first ?? terminal.path()
            let input = try AgentPath.dropped(path)
            terminal.restore()
            terminal.output("파일 확인 중…\n")
            let file = try AgentFile.load(input.path)
            let choices = formats(file, input: input)
            guard !choices.isEmpty else { throw AgentError("unsupported_format", "이 파일의 변환 가능한 형식이 없습니다. 일반 XML은 xml read / xml edit를 사용하세요.") }
            terminal.output("\n파일  │ \(input.lastPathComponent)\n형식  │ \(input.pathExtension.uppercased()) →\n")
            if input.pathExtension.lowercased() == "pdf" { terminal.output("PDF → 문서: 텍스트 추출, 원본 배치와 스캔 OCR 미지원\n") }
            try terminal.activate()
            let ext = try terminal.choose(choices)
            let output = input.deletingPathExtension().appendingPathExtension(ext)
            guard output.standardizedFileURL != input.standardizedFileURL else { throw AgentError("invalid_argument", "원본과 다른 출력 형식을 선택해 주세요.") }
            terminal.restore()
            terminal.output("\n변환 중…\n")
            let result = try AgentCLI.execute("convert", ["input": input.path, "output": output.path])
            terminal.output("저장  │ \(output.path)\n")
            for warning in result["warnings"] as? [String] ?? [] { terminal.output("안내  │ \(warning)\n") }
            return 0
        } catch {
            let error = AgentIO.error(error)
            let message = error.code == "output_exists" ? "같은 이름의 파일이 이미 있습니다. 기존 파일을 보존했습니다. 직접 변환할 때 다른 --output 경로를 지정하세요." : error.message
            print("\n\(message)")
            return error.code == "cancelled" ? 130 : error.status
        }
    }
}
