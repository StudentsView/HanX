import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Decode Finder/Terminal drop text without ever evaluating shell code.
enum AgentPath {
    static func literalURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }
    static func inputURL(_ path: String) -> URL {
        let literal = literalURL(path)
        if FileManager.default.fileExists(atPath: literal.path) { return literal }
        if let decoded = try? dropped(path), FileManager.default.fileExists(atPath: decoded.path) { return decoded }
        return literal
    }
    static func dropped(_ text: String) throws -> URL {
        if !text.contains("\0"), FileManager.default.fileExists(atPath: literalURL(text).path) { return literalURL(text) }
        let value = text.trimmingCharacters(in: .newlines)
        guard !value.isEmpty, !value.contains("\0") else { throw AgentError("invalid_argument", "파일 경로를 입력해 주세요.") }
        if FileManager.default.fileExists(atPath: literalURL(value).path) { return literalURL(value) }
        if value.hasPrefix("file://"), let url = URL(string: value), url.isFileURL,
           url.host == nil || url.host == "" || url.host == "localhost" { return url.standardizedFileURL }
        var tokens: [String] = [], token = "", quote: Character?, escaped = false, started = false
        for c in value {
            if escaped { token.append(c); escaped = false; started = true; continue }
            if c == "\\", quote != "'" { escaped = true; started = true; continue }
            if let q = quote {
                if c == q { quote = nil } else { token.append(c) }
                started = true
            } else if c == "'" || c == "\"" { quote = c; started = true }
            else if c.isWhitespace {
                if started { tokens.append(token); token = ""; started = false }
            } else { token.append(c); started = true }
        }
        guard quote == nil, !escaped else { throw AgentError("invalid_argument", "파일 경로의 따옴표 또는 역슬래시를 확인해 주세요.") }
        if started { tokens.append(token) }
        guard tokens.count == 1, let path = tokens.first, !path.isEmpty else { throw AgentError("invalid_argument", "파일을 한 개만 드롭해 주세요.") }
        return literalURL(path)
    }
}
