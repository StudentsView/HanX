import AppKit

/// Draws a SheetChart (column, bar, line, area, pie) into a rect using the
/// Office default palette.
enum ChartRenderer {
    static let palette: [NSColor] = [
        (68, 114, 196), (237, 125, 49), (165, 165, 165), (255, 192, 0), (91, 155, 213), (112, 173, 71),
        (38, 68, 120), (158, 72, 14), (99, 99, 99), (153, 115, 0),
    ].map { NSColor(srgbRed: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255, blue: CGFloat($0.2) / 255, alpha: 1) }

    private static func label(_ s: String, size: CGFloat = 10, color: NSColor = NSColor(white: 0.35, alpha: 1), bold: Bool = false) -> NSAttributedString {
        let font = FontResolver.shared.font(name: "맑은 고딕", size: Double(size), bold: bold, italic: false).font
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    }

    static func niceStep(_ range: Double) -> Double {
        guard range > 0 else { return 1 }
        let raw = range / 5
        let mag = pow(10, floor(log10(raw)))
        let f = raw / mag
        return (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * mag
    }

    static func draw(_ chart: SheetChart, ws: Worksheet, engine: FormulaEngine, in rect: NSRect, selected: Bool) {
        let (cats, series) = chart.resolve(ws, engine)
        NSColor.white.setFill()
        let frame = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        frame.fill()
        (selected ? NSColor.controlAccentColor : NSColor(white: 0.8, alpha: 1)).setStroke()
        frame.lineWidth = selected ? 2 : 0.75
        frame.stroke()

        var area = rect.insetBy(dx: 12, dy: 10)
        if !chart.title.isEmpty {
            let t = label(chart.title, size: 14, color: NSColor(white: 0.2, alpha: 1), bold: true)
            let sz = t.size()
            t.draw(at: NSPoint(x: area.midX - sz.width / 2, y: area.minY))
            area.origin.y += sz.height + 6; area.size.height -= sz.height + 6
        }
        guard !series.isEmpty, !cats.isEmpty else {
            label("데이터 없음").draw(at: NSPoint(x: area.midX - 24, y: area.midY))
            return
        }

        // Legend
        let legendItems: [(String, NSColor)] = chart.kind == .pie
            ? cats.enumerated().map { ($0.element, palette[$0.offset % palette.count]) }
            : series.enumerated().map { ($0.element.name, palette[$0.offset % palette.count]) }
        if chart.kind == .pie {
            let w: CGFloat = min(120, area.width * 0.32)
            var y = area.minY + 4
            for (name, color) in legendItems.prefix(12) {
                color.setFill(); NSRect(x: area.maxX - w, y: y + 3, width: 9, height: 9).fill()
                label(name).draw(at: NSPoint(x: area.maxX - w + 14, y: y))
                y += 16
            }
            area.size.width -= w + 8
        } else {
            var x = area.minX
            let y = area.maxY - 14
            var widths: CGFloat = 0
            for (name, _) in legendItems { widths += label(name).size().width + 26 }
            x = area.midX - widths / 2
            for (name, color) in legendItems {
                color.setFill(); NSRect(x: x, y: y + 3, width: 9, height: 9).fill()
                let l = label(name); l.draw(at: NSPoint(x: x + 13, y: y)); x += l.size().width + 26
            }
            area.size.height -= 20
        }

        if chart.kind == .pie { drawPie(series[0].values, in: area); return }

        let all = series.flatMap(\.values)
        var lo = min(0, all.min() ?? 0), hi = max(0, all.max() ?? 1)
        if lo == hi { hi = lo + 1 }
        let step = niceStep(hi - lo)
        lo = floor(lo / step) * step; hi = ceil(hi / step) * step
        let horizontal = chart.kind == .bar
        let valueLabels = stride(from: lo, through: hi + step / 2, by: step).map { SheetValue.general($0) }
        let labelW = (valueLabels.map { label($0).size().width }.max() ?? 20) + 6
        let catLabelH: CGFloat = 16
        let plot: NSRect = horizontal
            ? NSRect(x: area.minX + min(90, (cats.map { label($0).size().width }.max() ?? 30) + 6), y: area.minY, width: 0, height: area.height - catLabelH)
            : NSRect(x: area.minX + labelW, y: area.minY + 4, width: area.width - labelW, height: area.height - catLabelH - 4)
        var p = plot
        if horizontal { p.size.width = area.maxX - p.minX }

        func pos(_ v: Double) -> CGFloat {
            let t = CGFloat((v - lo) / (hi - lo))
            return horizontal ? p.minX + t * p.width : p.maxY - t * p.height
        }
        // Gridlines and value axis labels
        NSColor(white: 0.9, alpha: 1).setStroke()
        for v in stride(from: lo, through: hi + step / 2, by: step) {
            let l = label(SheetValue.general(v))
            if horizontal {
                NSBezierPath.strokeLine(from: NSPoint(x: pos(v), y: p.minY), to: NSPoint(x: pos(v), y: p.maxY))
                l.draw(at: NSPoint(x: pos(v) - l.size().width / 2, y: p.maxY + 2))
            } else {
                NSBezierPath.strokeLine(from: NSPoint(x: p.minX, y: pos(v)), to: NSPoint(x: p.maxX, y: pos(v)))
                l.draw(at: NSPoint(x: p.minX - l.size().width - 4, y: pos(v) - 7))
            }
        }
        NSColor(white: 0.55, alpha: 1).setStroke()
        if horizontal { NSBezierPath.strokeLine(from: NSPoint(x: pos(0), y: p.minY), to: NSPoint(x: pos(0), y: p.maxY)) }
        else { NSBezierPath.strokeLine(from: NSPoint(x: p.minX, y: pos(0)), to: NSPoint(x: p.maxX, y: pos(0))) }

        let n = cats.count
        let slot = (horizontal ? p.height : p.width) / CGFloat(n)
        for (i, c) in cats.enumerated() {
            let l = label(c)
            if horizontal { l.draw(at: NSPoint(x: p.minX - l.size().width - 4, y: p.minY + slot * (CGFloat(i) + 0.5) - 7)) }
            else if l.size().width < slot + 10 || i % max(1, Int(ceil(l.size().width / slot))) == 0 {
                l.draw(at: NSPoint(x: p.minX + slot * (CGFloat(i) + 0.5) - l.size().width / 2, y: p.maxY + 2))
            }
        }

        switch chart.kind {
        case .column, .bar:
            let group = slot * 0.7, bw = group / CGFloat(series.count)
            for (si, s) in series.enumerated() {
                palette[si % palette.count].setFill()
                for (i, v) in s.values.enumerated() {
                    let start = slot * CGFloat(i) + (slot - group) / 2 + bw * CGFloat(si)
                    let a = pos(0), b = pos(v)
                    let r = horizontal
                        ? NSRect(x: min(a, b), y: p.minY + start, width: abs(b - a), height: bw * 0.92)
                        : NSRect(x: p.minX + start, y: min(a, b), width: bw * 0.92, height: abs(b - a))
                    r.fill()
                }
            }
        case .line, .area:
            for (si, s) in series.enumerated() {
                let color = palette[si % palette.count]
                let pts = s.values.enumerated().map { NSPoint(x: p.minX + slot * (CGFloat($0.offset) + 0.5), y: pos($0.element)) }
                guard let first = pts.first else { continue }
                let path = NSBezierPath()
                path.move(to: first)
                pts.dropFirst().forEach { path.line(to: $0) }
                if chart.kind == .area {
                    let fill = path.copy() as! NSBezierPath
                    fill.line(to: NSPoint(x: pts.last!.x, y: pos(0)))
                    fill.line(to: NSPoint(x: first.x, y: pos(0)))
                    fill.close()
                    color.withAlphaComponent(0.55).setFill()
                    fill.fill()
                }
                color.setStroke()
                path.lineWidth = 2.25
                path.lineJoinStyle = .round
                path.stroke()
                if chart.kind == .line {
                    color.setFill()
                    for pt in pts { NSBezierPath(ovalIn: NSRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)).fill() }
                }
            }
        case .pie: break
        }
    }

    private static func drawPie(_ values: [Double], in area: NSRect) {
        let total = values.map { max(0, $0) }.reduce(0, +)
        guard total > 0 else { return }
        let d = min(area.width, area.height) * 0.9
        let center = NSPoint(x: area.midX, y: area.midY)
        var angle: CGFloat = -90
        for (i, v) in values.enumerated() where v > 0 {
            let sweep = CGFloat(v / total) * 360
            let path = NSBezierPath()
            path.move(to: center)
            // Flipped context: clockwise on screen.
            path.appendArc(withCenter: center, radius: d / 2, startAngle: angle, endAngle: angle + sweep, clockwise: false)
            path.close()
            palette[i % palette.count].setFill()
            path.fill()
            NSColor.white.setStroke(); path.lineWidth = 1.5; path.stroke()
            let mid = (angle + sweep / 2) * .pi / 180
            let pct = label("\(Int((v / total * 100).rounded()))%", size: 10, color: .white, bold: true)
            if sweep > 14 {
                pct.draw(at: NSPoint(x: center.x + cos(mid) * d * 0.32 - pct.size().width / 2, y: center.y + sin(mid) * d * 0.32 - 7))
            }
            angle += sweep
        }
    }
}
