import AppKit
// Renders the HanWord icon: a document sheet carrying 한 (HWP) and W (Word).
let out = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for s in sizes {
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let k = r.width / 1024
        let bg = NSBezierPath(roundedRect: r.insetBy(dx: 100 * k, dy: 100 * k), xRadius: 185 * k, yRadius: 185 * k)
        NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.36, blue: 0.85, alpha: 1), ending: NSColor(srgbRed: 0.05, green: 0.62, blue: 0.75, alpha: 1))!.draw(in: bg, angle: -60)
        let sheet = NSBezierPath(roundedRect: NSRect(x: 250 * k, y: 200 * k, width: 524 * k, height: 640 * k), xRadius: 36 * k, yRadius: 36 * k)
        NSColor.white.setFill(); sheet.fill()
        let han = NSAttributedString(string: "한", attributes: [.font: NSFont.boldSystemFont(ofSize: 300 * k), .foregroundColor: NSColor(srgbRed: 0.10, green: 0.36, blue: 0.85, alpha: 1)])
        han.draw(at: NSPoint(x: 290 * k, y: 420 * k))
        let w = NSAttributedString(string: "W", attributes: [.font: NSFont.systemFont(ofSize: 230 * k, weight: .heavy), .foregroundColor: NSColor(srgbRed: 0.05, green: 0.55, blue: 0.70, alpha: 1)])
        w.draw(at: NSPoint(x: 470 * k, y: 215 * k))
        return true
    }
    let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    // Each bitmap serves as the 1x of its own size and the 2x of half its size.
    var names: [String] = []
    if s <= 512 { names.append("icon_\(s)x\(s).png") }
    if s >= 32 { names.append("icon_\(s / 2)x\(s / 2)@2x.png") }
    for n in names { try! png.write(to: URL(fileURLWithPath: out + "/" + n)) }
}
