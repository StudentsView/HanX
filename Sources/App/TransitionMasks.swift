import AppKit
import QuartzCore

/// Deterministic masks: the same paths drive GPU playback and frame sampling.
enum TransitionMasks {
    static let kinds: Set<TransitionKind> = [.blinds,.checker,.comb,.randomBar,.strips,.circle,.diamond,.plus,.wedge,.wheel,.dissolve]
    static func path(_ t: SlideTransition, bounds b: CGRect, progress v: Double) -> CGPath {
        let p=CGMutablePath(), q=CGFloat(max(0,min(1,v))), w=b.width, h=b.height
        if q >= 1 { p.addRect(b); return p }
        if q <= 0 { return p }
        func rect(_ x:CGFloat,_ y:CGFloat,_ rw:CGFloat,_ rh:CGFloat) { p.addRect(CGRect(x:x,y:y,width:max(0,rw),height:max(0,rh))) }
        func polygon(_ pts:[CGPoint]) { p.addLines(between:pts); p.closeSubpath() }
        switch t.kind {
        case .circle: let d=hypot(w,h)*q; p.addEllipse(in:CGRect(x:w/2-d/2,y:h/2-d/2,width:d,height:d))
        case .diamond: let d=(w+h)*q/2; polygon([CGPoint(x:w/2,y:h/2+d),CGPoint(x:w/2+d,y:h/2),CGPoint(x:w/2,y:h/2-d),CGPoint(x:w/2-d,y:h/2)])
        case .plus: rect(0,h/2-h*q/2,w,h*q); rect(w/2-w*q/2,0,w*q,h)
        case .wedge, .wheel:
            let n=t.kind == .wheel ? 4 : 1, radius=hypot(w,h)
            for i in 0..<n {
                let a=CGFloat(i)*2 * .pi/CGFloat(n) + .pi/2
                p.move(to:CGPoint(x:w/2,y:h/2)); p.addArc(center:CGPoint(x:w/2,y:h/2),radius:radius,startAngle:a,endAngle:a-q*2 * .pi/CGFloat(n),clockwise:true); p.closeSubpath()
            }
        case .blinds:
            for i in 0..<12 { if t.vertical { rect(CGFloat(i)*w/12,0,w/12*q,h) } else { rect(0,CGFloat(i)*h/12,w,h/12*q) } }
        case .checker:
            for y in 0..<8 { for x in 0..<12 {
                let z=min(1,max(0,q*2-CGFloat((x+y)%2)))
                rect(CGFloat(x)*w/12,CGFloat(y)*h/8,t.vertical ? w/12 : w/12*z,t.vertical ? h/8*z : h/8)
            } }
        case .comb:
            for i in 0..<16 {
                if t.vertical { rect(CGFloat(i)*w/16,i%2 == 0 ? 0 : h*(1-q),w/16,h*q) }
                else { rect(i%2 == 0 ? 0 : w*(1-q),CGFloat(i)*h/16,w*q,h/16) }
            }
        case .randomBar:
            for i in 0..<36 {
                let start=CGFloat((i*17+5)%36)/72, z=min(1,max(0,(q-start)/(1-start)))
                if t.vertical { rect(CGFloat(i)*w/36,0,w/36,h*z) } else { rect(0,CGFloat(i)*h/36,w*z,h/36) }
            }
        case .strips:
            let z=(w+h)*q
            let pts=[CGPoint(x:0,y:0),CGPoint(x:z,y:0),CGPoint(x:0,y:z)]
            polygon(pts.map { pt in
                switch t.direction {
                case .left:return pt
                case .top:return CGPoint(x:w-pt.x,y:pt.y)
                case .right:return CGPoint(x:w-pt.x,y:h-pt.y)
                case .bottom:return CGPoint(x:pt.x,y:h-pt.y)
                }
            })
        case .dissolve:
            for y in 0..<15 { for x in 0..<24 where CGFloat((x*37+y*71)%360)/360 < q { rect(CGFloat(x)*w/24,CGFloat(y)*h/15,w/24+0.5,h/15+0.5) } }
        default: p.addRect(b)
        }
        return p
    }
    static func animate(_ t: SlideTransition, on layer: CALayer, duration: Double) {
        let mask=CAShapeLayer(); mask.frame=layer.bounds; mask.fillColor=NSColor.black.cgColor
        mask.path=path(t,bounds:layer.bounds,progress:1); layer.mask=mask
        let a=CAKeyframeAnimation(keyPath:"path")
        a.values=(0...40).map { path(t,bounds:layer.bounds,progress:Double($0)/40) }
        a.duration=duration; a.calculationMode = .discrete; a.fillMode = .both
        mask.add(a,forKey:"transition.mask")
    }
}
