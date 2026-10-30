import AppKit

// HanX: a folded document and two intersecting ribbons, drawn without font glyphs.
// Keep this geometry in sync with site/favicon.svg.
let out = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

for s in sizes {
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let k = r.width / 1024
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * k, y: y * k) }
        func polygon(_ points: [(CGFloat, CGFloat)], fill: NSColor) {
            let path = NSBezierPath()
            path.move(to: point(points[0].0, points[0].1))
            for p in points.dropFirst() { path.line(to: point(p.0, p.1)) }
            path.close()
            fill.setFill()
            path.fill()
        }

        let base = NSBezierPath(roundedRect: r.insetBy(dx: 96 * k, dy: 96 * k),
                                xRadius: 184 * k, yRadius: 184 * k)
        NSGradient(starting: color(0x2F6B9A), ending: color(0x234D76))!.draw(in: base, angle: -90)

        // A broad sheet keeps the mark legible in Finder's smallest list icons.
        let sheet = NSBezierPath()
        sheet.move(to: point(288, 192))
        sheet.curve(to: point(256, 224), controlPoint1: point(270, 192), controlPoint2: point(256, 206))
        sheet.line(to: point(256, 800))
        sheet.curve(to: point(288, 832), controlPoint1: point(256, 818), controlPoint2: point(270, 832))
        sheet.line(to: point(640, 832))
        sheet.line(to: point(768, 704))
        sheet.line(to: point(768, 224))
        sheet.curve(to: point(736, 192), controlPoint1: point(768, 206), controlPoint2: point(754, 192))
        sheet.close()
        color(0xFFFFFF).setFill()
        sheet.fill()
        if s >= 32 {
            polygon([(640, 832), (640, 736), (672, 704), (768, 704)], fill: color(0xDDEAF2))
        }

        // The first ribbon runs upper left to lower right; teal crosses it.
        polygon([(328, 672), (442, 672), (696, 320), (582, 320)], fill: color(0x234D76))
        polygon([(582, 672), (696, 672), (442, 320), (328, 320)], fill: color(0x168A98))
        return true
    }
    let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    // Each bitmap serves as the 1x of its own size and the 2x of half its size.
    var names: [String] = []
    if s <= 512 { names.append("icon_\(s)x\(s).png") }
    if s >= 32 { names.append("icon_\(s / 2)x\(s / 2)@2x.png") }
    for name in names { try png.write(to: URL(fileURLWithPath: out + "/" + name)) }
}
