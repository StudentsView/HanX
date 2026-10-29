import AppKit
import CoreText

/// Maps document font names to installed faces. HWP documents name Hancom
/// faces (함초롬바탕, 한컴돋움…) and Word documents name Office faces; when the
/// face is missing we fall back by design class (serif → 명조, sans → 고딕).
final class FontResolver {
    static let shared = FontResolver()

    struct Resolved { let font: NSFont; let syntheticBold: Bool; let syntheticItalic: Bool }

    private var cache: [String: Resolved] = [:]
    private var registered = false
    /// Every name a registered face answers to (all languages, from its
    /// 'name' table) → PostScript name. Korean names such as "HY헤드라인M"
    /// exist only there, not in AppKit's family list.
    private var nameIndex: [String: String] = [:]

    /// What Hancom Office substitutes when a face is missing, in order.
    static let substitutes: [String: [String]] = [
        "함초롬바탕": ["한컴바탕", "HY신명조", "바탕", "AppleMyungjo"],
        "함초롬돋움": ["한컴돋움", "돋움", "맑은 고딕", "Apple SD Gothic Neo"],
        "한컴바탕": ["HY신명조", "바탕", "AppleMyungjo"],
        "한컴돋움": ["돋움", "맑은 고딕", "Apple SD Gothic Neo"],
        "바탕": ["Batang", "한컴바탕", "AppleMyungjo"],
        "바탕체": ["BatangChe", "Batang", "AppleMyungjo"],
        "돋움": ["Dotum", "한컴돋움", "Apple SD Gothic Neo"],
        "돋움체": ["DotumChe", "Dotum", "Apple SD Gothic Neo"],
        "굴림": ["Gulim", "돋움", "Apple SD Gothic Neo"],
        "굴림체": ["GulimChe", "Gulim", "Apple SD Gothic Neo"],
        "궁서": ["Gungsuh", "HY궁서B", "AppleMyungjo"],
        "맑은 고딕": ["Malgun Gothic", "Apple SD Gothic Neo"],
        "나눔고딕": ["NanumGothic", "Apple SD Gothic Neo"],
        "나눔명조": ["NanumMyeongjo", "AppleMyungjo"],
        "새굴림": ["Gulim", "Apple SD Gothic Neo"],
        "휴먼명조": ["HY신명조", "한컴바탕", "AppleMyungjo"],
        "신명조": ["HY신명조", "한컴바탕", "AppleMyungjo"],
        "중고딕": ["HY중고딕", "한컴돋움", "Apple SD Gothic Neo"],
        "견고딕": ["HY견고딕", "Apple SD Gothic Neo"],
    ]

    private static func key(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }

    private func index(url: URL) {
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return }
        for d in descs {
            let font = CTFontCreateWithFontDescriptor(d, 12, nil)
            let ps = CTFontCopyPostScriptName(font) as String
            for n in FontResolver.names(font) {
                let k = FontResolver.key(n)
                // Prefer the regular face when several share a family name.
                if let existing = nameIndex[k], !ps.lowercased().contains("regular"), existing.count <= ps.count { continue }
                nameIndex[k] = ps
            }
        }
    }

    /// Family (1), full (4) and typographic family (16) names, every language.
    private static func names(_ font: CTFont) -> [String] {
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), []) as Data? else { return [] }
        let b = [UInt8](table)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
        let count = u16(2), strings = u16(4)
        var out: [String] = []
        for i in 0..<count {
            let r = 6 + i * 12
            let platform = u16(r), nameID = u16(r + 6), len = u16(r + 8), off = u16(r + 10)
            guard [1, 4, 16].contains(nameID), platform == 0 || platform == 3 else { continue }
            let start = strings + off
            guard start + len <= b.count else { continue }
            let raw = Array(b[start..<(start + len)])
            let units = stride(from: 0, to: raw.count - 1, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
            out.append(String(decoding: units, as: UTF16.self))
        }
        return out
    }

    /// The system font catalogue already includes fonts installed by the user.
    /// Do not register private fonts from another application's resource bundle.
    func registerBundledFonts() {
        guard !registered else { return }
        registered = true
    }

    func font(name: String, size: Double, bold: Bool, italic: Bool) -> Resolved {
        let key = "\(name)|\(size)|\(bold)|\(italic)"
        if let r = cache[key] { return r }
        let size = CGFloat(max(1, size))
        var base = lookup(name, size: size)
        if base == nil {
            for alt in FontResolver.substitutes[name] ?? [] { if let f = lookup(alt, size: size) { base = f; break } }
        }
        let resolvedBase = base ?? fallback(for: name, size: size)
        var font = resolvedBase
        let fm = NSFontManager.shared
        if bold { font = fm.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = fm.convert(font, toHaveTrait: .italicFontMask) }
        let traits = fm.traits(of: font)
        let r = Resolved(font: font,
                         syntheticBold: bold && !traits.contains(.boldFontMask),
                         syntheticItalic: italic && !traits.contains(.italicFontMask))
        cache[key] = r
        return r
    }

    private func lookup(_ name: String, size: CGFloat) -> NSFont? {
        if let ps = nameIndex[FontResolver.key(name)], let f = NSFont(name: ps, size: size) { return f }
        if let f = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size) { return f }
        if let f = NSFont(name: name, size: size) { return f }
        // Localised family names (e.g. "맑은 고딕" for Malgun Gothic).
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontDisplayNameAttribute: name] as CFDictionary)
        let matches = CTFontDescriptorCreateMatchingFontDescriptors(desc, nil) as? [CTFontDescriptor] ?? []
        if let m = matches.first { return CTFontCreateWithFontDescriptor(m, size, nil) as NSFont }
        let fdesc = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: name] as CFDictionary)
        if let m = (CTFontDescriptorCreateMatchingFontDescriptors(fdesc, nil) as? [CTFontDescriptor])?.first {
            return CTFontCreateWithFontDescriptor(m, size, nil) as NSFont
        }
        return nil
    }

    static func isSerif(_ name: String) -> Bool {
        let n = name.lowercased()
        let serif = ["바탕", "명조", "batang", "myungjo", "serif", "times", "궁서", "신명", "georgia", "cambria", "garamond", "book", "바른바탕"]
        let sans = ["돋움", "고딕", "굴림", "dotum", "gulim", "gothic", "sans", "맑은", "arial", "calibri", "helvetica", "segoe", "나눔고딕"]
        if sans.contains(where: n.contains) { return false }
        return serif.contains(where: n.contains)
    }

    private func fallback(for name: String, size: CGFloat) -> NSFont {
        let candidates = FontResolver.isSerif(name)
            ? ["AppleMyungjo", "Nanum Myeongjo", "Times New Roman"]
            : ["Apple SD Gothic Neo", "Nanum Gothic", "Helvetica Neue"]
        for c in candidates { if let f = NSFontManager.shared.font(withFamily: c, traits: [], weight: 5, size: size) { return f } }
        return NSFont.systemFont(ofSize: size)
    }
}

extension Character {
    /// Hangul, CJK ideographs, kana and CJK symbols — rendered with the
    /// East-Asian face, as both HWP and Word do.
    var isEastAsian: Bool {
        guard let v = unicodeScalars.first?.value else { return false }
        switch v {
        case 0x1100...0x11FF, 0x3000...0x303F, 0x3040...0x30FF, 0x3130...0x318F, 0x3200...0x32FF,
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA960...0xA97F, 0xAC00...0xD7AF, 0xD7B0...0xD7FF,
             0xF900...0xFAFF, 0xFF00...0xFFEF:
            return true
        default: return false
        }
    }
}
