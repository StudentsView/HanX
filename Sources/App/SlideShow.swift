import AppKit
import QuartzCore

/// Full-screen slide show with PowerPoint-style animation playback.
/// Static content is flattened into one background layer per slide; every
/// animated shape gets its own layer so effects run on the GPU.
final class SlideShowController {
    private struct Step {
        var auto: Bool
        var items: [(anim: SlideAnimation, start: Double)]
    }

    private let pres: Presentation
    private let window: SlideShowWindow
    private let root = CALayer()
    private var stage = CALayer()
    private var layers: [Int: CALayer] = [:]
    private var steps: [Step] = []
    private var stepIndex = 0
    private var autoTimer: Timer?
    private var pendingNext:Timer?
    private var busyUntil:CFTimeInterval=0
    private(set) var index = 0
    var onEnd: ((Int) -> Void)?

    private var scale: CGFloat = 1
    private var backing: CGFloat = 2
    private var fitRect = CGRect.zero

    init(pres: Presentation, screen: NSScreen) {
        self.pres = pres
        window = SlideShowWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.level = .screenSaver
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = root
        root.backgroundColor = NSColor.black.cgColor
        window.contentView = view
        backing = screen.backingScaleFactor
        let size = screen.frame.size
        scale = min(size.width / CGFloat(pres.width), size.height / CGFloat(pres.height))
        fitRect = CGRect(x: (size.width - CGFloat(pres.width) * scale) / 2, y: (size.height - CGFloat(pres.height) * scale) / 2,
                         width: CGFloat(pres.width) * scale, height: CGFloat(pres.height) * scale)
        window.onKey = { [weak self] e in self?.handle(e) }
    }

    func start(at i: Int) {
        guard pres.slides.indices.contains(i) else { return }
        window.makeKeyAndOrderFront(nil)
        NSCursor.setHiddenUntilMouseMoves(true)
        show(i, transition: true)
    }

    // MARK: Building a slide

    private func render(size: CGSize, _ draw: () -> Void) -> CGImage? {
        let px = CGSize(width: max(1, size.width * scale * backing), height: max(1, size.height * scale * backing))
        guard let ctx = CGContext(data: nil, width: Int(px.width), height: Int(px.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: px.height)
        ctx.scaleBy(x: scale * backing, y: -scale * backing)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private func buildStage(_ slide: Slide) -> CALayer {
        let s = CALayer()
        s.frame = fitRect
        s.masksToBounds = true
        let animated = Set(slide.animations.map(\.shapeID))
        var still = slide
        still.shapes = []
        let bg = CALayer()
        bg.frame = s.bounds
        bg.contents = render(size: CGSize(width: pres.width, height: pres.height)) { SlideRenderer.draw(still, pres) }
        s.addSublayer(bg)

        layers = [:]
        let pad: CGFloat = 6
        for shape in slide.shapes {
            var r = SlideRenderer.cg(shape.frame).insetBy(dx: -pad, dy: -pad)
            if shape.rotation != 0 {
                let d = hypot(r.width, r.height)
                r = CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)
            }
            let l = CALayer()
            // Layers use bottom-left origin; slide coordinates are top-left.
            l.frame = CGRect(x: r.minX * scale, y: fitRect.height - r.maxY * scale, width: r.width * scale, height: r.height * scale)
            l.contents = render(size: r.size) {
                let t = NSAffineTransform(); t.translateX(by: -r.minX, yBy: -r.minY); t.concat()
                SlideRenderer.drawShape(shape, pres)
            }
            l.contentsGravity = .resize
            // Shapes whose first effect is an entrance start hidden.
            if slide.animations.first(where: { $0.shapeID == shape.id })?.effect.animClass == .entrance { l.opacity = 0 }
            s.addSublayer(l)
            if animated.contains(shape.id) { layers[shape.id] = l }
        }
        return s
    }

    private func buildSteps(_ anims: [SlideAnimation]) -> [Step] {
        var out: [Step] = []
        var groupStart = 0.0, groupEnd = 0.0
        for a in anims {
            if a.trigger == .onClick || out.isEmpty {
                out.append(Step(auto: out.isEmpty && a.trigger != .onClick, items: []))
                groupStart = 0; groupEnd = 0
            }
            if a.trigger == .afterPrevious { groupStart = groupEnd }
            let start = groupStart + a.delay
            out[out.count - 1].items.append((a, start))
            groupEnd = max(groupEnd, start + a.duration)
        }
        return out
    }

    private func show(_ i: Int, transition: Bool) {
        autoTimer?.invalidate()
        pendingNext?.invalidate(); pendingNext=nil
        index = i
        let slide = pres.slides[i]
        let newStage = buildStage(slide)
        let old = stage
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.addSublayer(newStage)
        stage = newStage
        CATransaction.commit()
        let hasTransition=transition && slide.transition.kind != .none && slide.transition.kind != .cut
        lastTransitionKeys=[]
        if hasTransition {
            lastTransitionKeys = TransitionAnimator.animate(slide.transition, from: old.superlayer == nil ? nil : old, to: newStage, in: root,
                                                            bounds: fitRect) { old.removeFromSuperlayer() }
        } else {
            old.removeFromSuperlayer()
        }
        steps = buildSteps(slide.animations)
        stepIndex = 0
        let lead = hasTransition ? max(0.05,slide.transition.duration) : 0
        busyUntil=CACurrentMediaTime()+lead
        if steps.first?.auto == true { play(steps[0], delay: lead); stepIndex = 1 }
        scheduleAutoAdvance()
    }

    /// Animation keys added by the last transition (test hook).
    private(set) var lastTransitionKeys: [String] = []

    private func scheduleAutoAdvance() {
        autoTimer?.invalidate(); autoTimer=nil
        guard let after = pres.slides[index].transition.advanceAfter, stepIndex >= steps.count else { return }
        let wait=max(0,busyUntil-CACurrentMediaTime())+max(0,after)
        let timer=Timer(timeInterval:max(0.001,wait),repeats:false) { [weak self] _ in self?.next() }
        autoTimer=timer; RunLoop.main.add(timer,forMode:.common)
    }

    // MARK: Effects

    private func play(_ step: Step, delay: Double = 0) {
        let now = CACurrentMediaTime()
        let end=step.items.map { $0.start+max(0.001,$0.anim.duration) }.max() ?? 0
        busyUntil=max(busyUntil,now+delay+end)
        for (a, start) in step.items {
            guard let l = layers[a.shapeID] else { continue }
            apply(a, to: l, at: now + delay + start)
        }
    }

    private func basic(_ key: String, _ from: Any?, _ to: Any?, _ dur: Double, _ begin: CFTimeInterval) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from; a.toValue = to
        a.duration = max(0.001, dur)
        a.beginTime = begin
        a.fillMode = .backwards
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return a
    }

    private func apply(_ a: SlideAnimation, to l: CALayer, at begin: CFTimeInterval) {
        let d = a.duration
        let id = UUID().uuidString
        let final = l.position
        let offscreen: CGPoint = {
            switch a.direction {
            case .bottom: return CGPoint(x: final.x, y: -l.bounds.height / 2)
            case .top: return CGPoint(x: final.x, y: fitRect.height + l.bounds.height / 2)
            case .left: return CGPoint(x: -l.bounds.width / 2, y: final.y)
            case .right: return CGPoint(x: fitRect.width + l.bounds.width / 2, y: final.y)
            }
        }()
        func show() { l.opacity = 1; l.add(basic("opacity", 0, 1, 0.001, begin), forKey: id + "v") }
        func wipe(inward: Bool, center: Bool) {
            let m = CALayer()
            m.backgroundColor = NSColor.black.cgColor
            let full = l.bounds
            let horizontal = center || a.direction == .left || a.direction == .right
            m.anchorPoint = center ? CGPoint(x: 0.5, y: 0.5) : [.left: CGPoint(x: 0, y: 0.5), .right: CGPoint(x: 1, y: 0.5),
                                                                 .top: CGPoint(x: 0.5, y: 1), .bottom: CGPoint(x: 0.5, y: 0)][a.direction]!
            m.bounds = full
            m.position = CGPoint(x: full.width * m.anchorPoint.x, y: full.height * m.anchorPoint.y)
            l.mask = m
            let key = horizontal ? "bounds.size.width" : "bounds.size.height"
            let size = horizontal ? full.width : full.height
            if !inward { m.setValue(0, forKeyPath: key) }
            m.add(basic(key, inward ? 0 : size, inward ? size : 0, d, begin), forKey: id)
        }
        switch a.effect {
        case .appear: show()
        case .fade: l.opacity = 1; l.add(basic("opacity", 0, 1, d, begin), forKey: id)
        case .flyIn: show(); l.add(basic("position", NSValue(point: offscreen), NSValue(point: final), d, begin), forKey: id)
        case .floatIn:
            l.opacity = 1
            l.add(basic("opacity", 0, 1, d, begin), forKey: id + "o")
            l.add(basic("position", NSValue(point: CGPoint(x: final.x, y: final.y - fitRect.height * 0.1)), NSValue(point: final), d, begin), forKey: id)
        case .wipe: show(); wipe(inward: true, center: false)
        case .split: show(); wipe(inward: true, center: true)
        case .zoom:
            l.opacity = 1
            l.add(basic("opacity", 0, 1, d, begin), forKey: id + "o")
            l.add(basic("transform.scale", 0.05, 1, d, begin), forKey: id)
        case .wheel:
            l.opacity = 1
            l.add(basic("opacity", 0, 1, d, begin), forKey: id + "o")
            l.add(basic("transform.rotation.z", Double.pi * 2, 0, d, begin), forKey: id)
        case .spin:
            let r = basic("transform.rotation.z", 0, -Double.pi * 2, d, begin)   // clockwise
            r.isAdditive = true
            l.add(r, forKey: id)
        case .growShrink:
            l.transform = CATransform3DMakeScale(1.5, 1.5, 1)
            l.add(basic("transform.scale", 1, 1.5, d, begin), forKey: id)
        case .pulse:
            let p = basic("transform.scale", 1, 1.08, d / 2, begin)
            p.autoreverses = true
            l.add(p, forKey: id)
        case .transparency: l.opacity = 0.5; l.add(basic("opacity", 1, 0.5, d, begin), forKey: id)
        case .disappear: l.opacity = 0; l.add(basic("opacity", 1, 0, 0.001, begin), forKey: id)
        case .fadeOut: l.opacity = 0; l.add(basic("opacity", 1, 0, d, begin), forKey: id)
        case .flyOut:
            l.position = offscreen
            l.add(basic("position", NSValue(point: final), NSValue(point: offscreen), d, begin), forKey: id)
        case .floatOut:
            l.opacity = 0
            l.add(basic("opacity", 1, 0, d, begin), forKey: id + "o")
            let to = CGPoint(x: final.x, y: final.y - fitRect.height * 0.1)
            l.position = to
            l.add(basic("position", NSValue(point: final), NSValue(point: to), d, begin), forKey: id)
        case .wipeOut: wipe(inward: false, center: false)
        case .splitOut: wipe(inward: false, center: true)
        case .zoomOut:
            l.opacity = 0
            l.add(basic("opacity", 1, 0, d, begin), forKey: id + "o")
            l.add(basic("transform.scale", 1, 0.05, d, begin), forKey: id)
        }
    }

    /// Test hook: goes from slide `i` to `i + 1` with its transition and
    /// reports the animation keys plus the presentation-layer state mid-way.
    func transitionProbe(from i: Int) -> String {
        root.frame = CGRect(origin: .zero, size: window.frame.size)
        show(i, transition: false)
        show(i + 1, transition: true)
        let keys = lastTransitionKeys
        let anims = stage.animationKeys() ?? []
        let mask = stage.mask?.animationKeys() ?? []
        return "transition=\(pres.slides[i + 1].transition.kind.rawValue) keys=\(keys) stageAnims=\(anims) maskAnims=\(mask) layers=\(root.sublayers?.count ?? 0)"
    }

    /// Test hook: builds slide `i`, runs `clicks` steps, and renders the
    /// resulting layer tree (final animation state) without showing a window.
    func snapshot(slide i: Int, clicks: Int) -> CGImage? {
        show(i, transition: false)
        for _ in 0..<clicks where stepIndex < steps.count { play(steps[stepIndex]); stepIndex += 1 }
        root.frame = CGRect(origin: .zero, size: window.frame.size)
        let w = Int(root.bounds.width), h = Int(root.bounds.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        root.render(in: ctx)
        return ctx.makeImage()
    }

    // MARK: Navigation

    func next() {
        autoTimer?.invalidate()
        let remaining=busyUntil-CACurrentMediaTime()
        if remaining>0.01 {
            pendingNext?.invalidate()
            let timer=Timer(timeInterval:remaining,repeats:false) { [weak self] _ in self?.pendingNext=nil; self?.next() }
            pendingNext=timer; RunLoop.main.add(timer,forMode:.common)
            return
        }
        if stepIndex < steps.count {
            play(steps[stepIndex])
            stepIndex += 1
            scheduleAutoAdvance()
        } else if index + 1 < pres.slides.count {
            show(index + 1, transition: true)
        } else {
            end()
        }
    }

    func previous() {
        autoTimer?.invalidate()
        guard index > 0 else { show(0, transition: false); return }
        // Previous slide in its fully built state, as PowerPoint does.
        show(index - 1, transition: false)
        while stepIndex < steps.count { play(steps[stepIndex]); stepIndex += 1 }
        for l in layers.values { l.removeAllAnimations() }
        busyUntil=CACurrentMediaTime(); scheduleAutoAdvance()
    }

    private func handle(_ e: NSEvent) {
        if e.type == .leftMouseDown { if stepIndex < steps.count || pres.slides[index].transition.advanceOnClick { next() }; return }
        if e.type == .rightMouseDown { previous(); return }
        switch e.keyCode {
        case 53: end()                                   // esc
        case 123, 126, 116, 51: previous()               // ← ↑ pageup delete
        case 124, 125, 121, 49, 36, 76: next()           // → ↓ pagedown space return
        case 115: show(0, transition: false)             // home
        case 119: show(pres.slides.count - 1, transition: false)
        default: break
        }
    }

    func end() {
        autoTimer?.invalidate()
        pendingNext?.invalidate(); pendingNext=nil; busyUntil=0
        window.orderOut(nil)
        onEnd?(index)
    }
}

/// Slide transitions as explicit Core Animation animations, shared by the
/// slide show and the editor's instant preview.
enum TransitionAnimator {
    /// Animates `new` (already in `container`) replacing `old`; calls `done`
    /// when finished. Returns the animation keys used.
    @discardableResult
    static func animate(_ t: SlideTransition, from old: CALayer?, to new: CALayer, in container: CALayer,
                        bounds: CGRect, done: @escaping () -> Void) -> [String] {
        let d = max(0.05, t.duration)
        var keys: [String] = []
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        func add(_ layer: CALayer, _ key: String, _ from: Any?, _ to: Any?, timing: CAMediaTimingFunctionName = .easeInEaseOut) {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from; a.toValue = to; a.duration = d
            a.timingFunction = CAMediaTimingFunction(name: timing)
            a.fillMode = .both
            a.isRemovedOnCompletion = true
            layer.add(a, forKey: "transition." + key)
            keys.append("transition." + key)
        }
        // Offset of the incoming slide's start position (layers: y grows upward).
        let w = bounds.width, h = bounds.height
        let offset: CGPoint = [.right: CGPoint(x: w, y: 0), .left: CGPoint(x: -w, y: 0), .top: CGPoint(x: 0, y: h), .bottom: CGPoint(x: 0, y: -h)][t.direction]!
        let home = new.position
        func moved(_ p: CGPoint, _ k: CGFloat) -> NSValue { NSValue(point: CGPoint(x: p.x + offset.x * k, y: p.y + offset.y * k)) }
        func mask(center: Bool) {
            let m = CALayer()
            m.backgroundColor = NSColor.black.cgColor
            let horizontal = center || t.direction == .left || t.direction == .right
            m.anchorPoint = center ? CGPoint(x: 0.5, y: 0.5)
                : [.right: CGPoint(x: 1, y: 0.5), .left: CGPoint(x: 0, y: 0.5), .top: CGPoint(x: 0.5, y: 1), .bottom: CGPoint(x: 0.5, y: 0)][t.direction]!
            m.bounds = new.bounds
            m.position = CGPoint(x: new.bounds.width * m.anchorPoint.x, y: new.bounds.height * m.anchorPoint.y)
            new.mask = m
            let key = horizontal ? "bounds.size.width" : "bounds.size.height"
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = 0; a.toValue = horizontal ? new.bounds.width : new.bounds.height; a.duration = d
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            m.add(a, forKey: "reveal")
            keys.append("mask." + key)
        }
        switch t.kind {
        case .none, .cut: break
        case .fade: add(new, "opacity", 0, 1)
        case .dissolve, .blinds, .checker, .comb, .randomBar, .strips, .circle, .diamond, .plus, .wedge, .wheel:
            TransitionMasks.animate(t,on:new,duration:d); keys.append("transition.mask")
        case .push:
            add(new, "position", moved(home, 1), NSValue(point: home))
            if let old { add(old, "position", NSValue(point: old.position), moved(old.position, -1)) }
        case .cover: add(new, "position", moved(home, 1), NSValue(point: home))
        case .pull:
            // Uncover: the outgoing slide slides away on top of the new one.
            if let old {
                container.insertSublayer(new, below: old)
                add(old, "position", NSValue(point: old.position), moved(old.position, -1))
            } else {
                add(new, "opacity", 0, 1)
            }
        case .wipe: mask(center: false)
        case .split:
            if t.inward, let old {
                container.insertSublayer(new,below:old)
                let m=CALayer(); m.backgroundColor=NSColor.black.cgColor; m.frame=old.bounds; old.mask=m
                add(m,t.vertical ? "bounds.size.height" : "bounds.size.width",t.vertical ? old.bounds.height : old.bounds.width,0)
            } else {
                let m=CALayer(); m.backgroundColor=NSColor.black.cgColor; m.frame=new.bounds; new.mask=m
                add(m,t.vertical ? "bounds.size.height" : "bounds.size.width",0,t.vertical ? new.bounds.height : new.bounds.width)
            }
        case .zoom:
            add(new, "transform.scale", t.inward ? 2.5 : 0.05, 1)
            add(new, "opacity", 0, 1)
        case .newsflash:
            add(new,"transform.rotation.z",Double.pi*2,0); add(new,"transform.scale",0.02,1); add(new,"opacity",0,1)
        }
        CATransaction.commit()
        return keys
    }
}

/// Test hook: renders a transition's frames offscreen by evaluating the
/// attached Core Animation animations at fixed times (same timing curves),
/// so the motion can be inspected without a screen.
enum TransitionFilmstrip {
    static func render(_ pres: Presentation, to index: Int, frames: Int = 6) -> CGImage? {
        let w = 320, h = 180
        let strip = CGContext(data: nil, width: w * frames + 4 * (frames - 1), height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        strip.setFillColor(NSColor.systemRed.cgColor)
        strip.fill(CGRect(x: 0, y: 0, width: strip.width, height: h))
        let t = pres.slides[index].transition
        for f in 0..<frames {
            let progress = Double(f) / Double(frames - 1)
            let container = CALayer()
            container.frame = CGRect(x: 0, y: 0, width: w, height: h)
            container.backgroundColor = NSColor.black.cgColor
            container.masksToBounds = true
            func stage(_ s: Slide?) -> CALayer {
                let l = CALayer()
                l.frame = container.bounds
                if let s { l.contents = SlideRenderer.cgImage(s, pres, width: CGFloat(w) * 2) } else { l.backgroundColor = NSColor.black.cgColor }
                l.contentsGravity = .resize
                return l
            }
            let old = stage(index > 0 ? pres.slides[index - 1] : nil), new = stage(pres.slides[index])
            CATransaction.begin(); CATransaction.setDisableActions(true)
            container.addSublayer(old); container.addSublayer(new)
            TransitionAnimator.animate(t, from: old, to: new, in: container, bounds: container.bounds) {}
            for layer in [old, new].compactMap({ $0 }) { apply(layer, progress) }
            if TransitionMasks.kinds.contains(t.kind), let m=new.mask as? CAShapeLayer { m.removeAllAnimations(); m.path=TransitionMasks.path(t,bounds:new.bounds,progress:progress) }
            CATransaction.commit()
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            container.render(in: ctx)
            if let img = ctx.makeImage() { strip.draw(img, in: CGRect(x: f * (w + 4), y: 0, width: w, height: h)) }
        }
        return strip.makeImage()
    }

    /// Sets each animated key path to its value at `progress` (0…1 of the duration).
    private static func apply(_ layer: CALayer, _ progress: Double) {
        for key in layer.animationKeys() ?? [] {
            guard let a = layer.animation(forKey: key) as? CABasicAnimation, let path = a.keyPath else { continue }
            let p = Double(a.timingFunction.map { ease($0, Float(progress)) } ?? Float(progress))
            func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * p }
            if let from = a.fromValue as? NSNumber, let to = a.toValue as? NSNumber {
                layer.setValue(lerp(from.doubleValue, to.doubleValue), forKeyPath: path)
            } else if let from = (a.fromValue as? NSValue)?.pointValue, let to = (a.toValue as? NSValue)?.pointValue {
                layer.setValue(NSValue(point: NSPoint(x: lerp(from.x, to.x), y: lerp(from.y, to.y))), forKeyPath: path)
            }
            layer.removeAnimation(forKey: key)
        }
        // A width/height mask animation hides everything outside the revealed part.
        if let m = layer.mask { apply(m, progress) }
    }

    /// Solves the cubic-bezier timing curve y(x).
    private static func ease(_ f: CAMediaTimingFunction, _ x: Float) -> Float {
        var c1: [Float] = [0, 0], c2: [Float] = [0, 0]
        f.getControlPoint(at: 1, values: &c1); f.getControlPoint(at: 2, values: &c2)
        func bez(_ t: Float, _ a: Float, _ b: Float) -> Float { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
        var lo: Float = 0, hi: Float = 1
        for _ in 0..<40 { let m = (lo + hi) / 2; if bez(m, c1[0], c2[0]) < x { lo = m } else { hi = m } }
        return bez((lo + hi) / 2, c1[1], c2[1])
    }
}
