// The Space theme's backdrop: a purple starfield behind the whole widget, with
// twinkling stars, drifting nebulae, two slowly turning pixel planets (one ringed),
// a shooting star now and then and a little ship crossing.

import AppKit

final class Space {
    struct Star { var x: Double, y: Double, size: Double, color: NSColor, phase: Double, speed: Double, bright: Bool }
    struct Planet {
        var x: Double, y: Double, amp: Double, r: Int, px: Double
        var palette: [RGBA], spin: Double, ring: Bool, seed: Double
    }
    let starColors = ["#FFFFFF", "#E9D5FF", "#C4B5FD", "#F9A8D4", "#A5B4FC", "#93C5FD"].map(hexColor)
    var stars: [Star] = []
    var planets: [Planet] = []
    var planetCache: [String: NSImage] = [:]
    var shoot: (x: Double, y: Double, t: Int)? = nil
    var shipX = 0.25
    var tick = 0

    init() {
        stars = (0 ..< 150).map { i in
            let bright = i < 9
            return Star(x: Double.random(in: 0 ... 1), y: Double.random(in: 0 ... 1),
                        size: bright ? 2 : [1, 1, 1, 1.5, 1.5, 2][rnd(6)],
                        color: starColors[rnd(starColors.count)],
                        phase: Double.random(in: 0 ... 6.28), speed: Double.random(in: 0.05 ... 0.22), bright: bright)
        }
        planets = [
            Planet(x: 0.50, y: 20, amp: 0.07, r: 8, px: 2,
                   palette: ["#2E1065", "#6D28D9", "#A855F7", "#F472B6", "#67E8F9", "#C084FC"].map(RGBA.init(opaque:)),
                   spin: 0.035, ring: false, seed: 1.3),
            Planet(x: 0.87, y: 15, amp: 0.04, r: 5, px: 2,
                   palette: ["#1E1B4B", "#3730A3", "#6366F1", "#A5B4FC", "#818CF8"].map(RGBA.init(opaque:)),
                   spin: 0.05, ring: true, seed: 4.1),
        ]
    }

    // Stars and nebulae fill r; the planets and the ship stay in the sky window
    // (`sky`), right of the big number, so they never cover the text.
    func draw(in r: CGRect, sky: CGRect) {
        tick += 1
        let w = r.width, h = r.height
        // Deep purple, with two soft nebulae drifting.
        NSGradient(starting: hexColor("#120A26"), ending: hexColor("#070311"))?
            .draw(from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY), options: [])
        for (i, (c, a)) in [("#7C3AED", 0.22), ("#DB2777", 0.13), ("#4F46E5", 0.15)].enumerated() {
            let t = Double(tick) / 600 + Double(i) * 2.1
            let cx = r.minX + w * (0.5 + 0.35 * sin(t + Double(i))), cy = r.minY + h * (0.3 + 0.25 * Double(i) + 0.05 * cos(t * 1.3))
            let rad = w * (0.45 + 0.1 * Double(i))
            NSGradient(starting: hexColor(c).withAlphaComponent(a), ending: hexColor(c).withAlphaComponent(0))?
                .draw(in: NSBezierPath(ovalIn: CGRect(x: cx - rad, y: cy - rad * 0.6, width: rad * 2, height: rad * 1.2)), relativeCenterPosition: .zero)
        }

        // Stars twinkle; the bright ones flare with a cross of light.
        for s in stars {
            let tw = 0.5 + 0.5 * sin(Double(tick) * s.speed + s.phase)
            let x = (r.minX + s.x * w).rounded(), y = (r.minY + s.y * h).rounded()
            if s.bright {
                let a = 0.55 + 0.45 * tw
                s.color.withAlphaComponent(a).setFill()
                NSBezierPath(rect: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
                let len = 2 + 4 * tw
                s.color.withAlphaComponent(a * 0.6).setFill()
                NSBezierPath(rect: CGRect(x: x - len, y: y - 0.5, width: len * 2, height: 1)).fill()
                NSBezierPath(rect: CGRect(x: x - 0.5, y: y - len, width: 1, height: len * 2)).fill()
                NSGradient(starting: s.color.withAlphaComponent(0.25 * a), ending: s.color.withAlphaComponent(0))?
                    .draw(in: NSBezierPath(ovalIn: CGRect(x: x - 7, y: y - 7, width: 14, height: 14)), relativeCenterPosition: .zero)
            } else {
                s.color.withAlphaComponent(0.25 + 0.6 * tw).setFill()
                NSBezierPath(rect: CGRect(x: x, y: y, width: s.size, height: s.size)).fill()
            }
        }

        // Planets sway slowly to and fro, turning, and bob a little.
        for p in planets {
            let d = Double(2 * p.r + 1) * p.px
            let cx = sky.minX + sky.width * (p.x + p.amp * sin(Double(tick) / 500 + p.seed))
            let cy = sky.minY + p.y + 2 * sin(Double(tick) / 90 + p.seed)
            let o = CGPoint(x: (cx - d / 2).rounded(), y: (cy - d / 2).rounded())
            // Atmosphere glow.
            let glow = p.palette[2].ns
            NSGradient(starting: glow.withAlphaComponent(0.28), ending: glow.withAlphaComponent(0))?
                .draw(in: NSBezierPath(ovalIn: CGRect(x: cx - d, y: cy - d, width: d * 2, height: d * 2)), relativeCenterPosition: .zero)
            if p.ring { drawRing(cx, cy, d, back: true, p.palette[3].ns) }
            planetImage(p).draw(in: CGRect(x: o.x, y: o.y, width: d, height: d))
            if p.ring { drawRing(cx, cy, d, back: false, p.palette[3].ns) }
        }

        // A little ship crosses every so often, its engine flickering.
        shipX += 0.0012
        if shipX > 1.4 { shipX = 0.25 }
        let sx = sky.minX + shipX * sky.width, sy = sky.minY + 4 + 2 * sin(Double(tick) / 25)
        drawShip(sx.rounded(), sy.rounded())

        // A shooting star now and then.
        if shoot == nil && rnd(160) == 0 { shoot = (Double.random(in: 0.3 ... 1), Double.random(in: 0 ... 0.35), 0) }
        if let s = shoot {
            let k = Double(s.t) / 14
            let hx = r.minX + s.x * w - k * 120, hy = r.minY + s.y * h + k * 45
            let tail = NSBezierPath()
            tail.move(to: CGPoint(x: hx, y: hy)); tail.line(to: CGPoint(x: hx + 26, y: hy - 10))
            tail.lineWidth = 1.2
            NSColor(white: 1, alpha: 0.8 * (1 - k)).setStroke(); tail.stroke()
            NSColor(white: 1, alpha: 1 - k).setFill()
            NSBezierPath(rect: CGRect(x: hx - 1, y: hy - 1, width: 2, height: 2)).fill()
            shoot = s.t >= 14 ? nil : (s.x, s.y, s.t + 1)
        }
    }

    // A pixel sphere: bands of colour wrapped round it, lit from the upper left.
    func planetImage(_ p: Planet) -> NSImage {
        let rot = (Double(tick) * p.spin).truncatingRemainder(dividingBy: 2 * .pi)
        let step = Int(rot * 20)   // a new image every 1/20 radian
        let key = "\(p.seed)|\(step)"
        if let img = planetCache[key] { return img }
        if planetCache.count > 600 { planetCache.removeAll() }
        let n = 2 * p.r + 1
        let dark = RGBA(opaque: "#0B0518")
        let img = NSImage(size: NSSize(width: Double(n) * p.px, height: Double(n) * p.px), flipped: true) { _ in
            for j in 0 ..< n {
                for i in 0 ..< n {
                    let dx = (Double(i) + 0.5 - Double(n) / 2) / (Double(n) / 2)
                    let dy = (Double(j) + 0.5 - Double(n) / 2) / (Double(n) / 2)
                    let rr = dx * dx + dy * dy
                    if rr > 1 { continue }
                    let z = (1 - rr).squareRoot()
                    let u = atan2(dx, z) + Double(step) / 20, v = dy
                    let noise = sin(u * 3 + sin(v * 4 + p.seed) * 1.6) + 0.6 * sin(v * 6 + u * 2 + p.seed) + 0.3 * sin(u * 7 - v * 5)
                    let idx = min(p.palette.count - 1, max(0, Int((noise + 1.9) / 3.8 * Double(p.palette.count))))
                    let light = max(0.12, min(1, 0.3 + 0.9 * (-0.55 * dx - 0.45 * dy + 0.7 * z)))
                    dark.mix(p.palette[idx], light).ns.setFill()
                    NSBezierPath(rect: CGRect(x: Double(i) * p.px, y: Double(j) * p.px, width: p.px, height: p.px)).fill()
                }
            }
            return true
        }
        planetCache[key] = img
        return img
    }

    func drawRing(_ cx: Double, _ cy: Double, _ d: Double, back: Bool, _ c: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        // The far half of the ring goes behind the planet, the near half in front.
        NSBezierPath(rect: CGRect(x: cx - d * 1.2, y: back ? cy - d : cy, width: d * 2.4, height: d)).setClip()
        let ring = NSBezierPath(ovalIn: CGRect(x: cx - d * 0.95, y: cy - d * 0.22, width: d * 1.9, height: d * 0.44))
        ring.lineWidth = 2
        c.withAlphaComponent(back ? 0.45 : 0.85).setStroke()
        ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawShip(_ x: Double, _ y: Double) {
        let art = ["....##....", "..######..", ".##o##o##.", "##########", ".#..##..#."]
        let px = 1.6
        for (j, row) in art.enumerated() {
            for (i, ch) in row.enumerated() where ch != "." {
                (ch == "o" ? hexColor("#67E8F9") : hexColor("#94A3B8")).setFill()
                NSBezierPath(rect: CGRect(x: x + Double(i) * px, y: y + Double(j) * px, width: px, height: px)).fill()
            }
        }
        // Engine flame behind it.
        let f = 2 + Double(tick % 4)
        hexColor("#F472B6").withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: CGRect(x: x - f * px, y: y + 3 * px, width: f * px, height: px)).fill()
        hexColor("#FDE68A").setFill()
        NSBezierPath(rect: CGRect(x: x - px, y: y + 3 * px, width: px, height: px)).fill()
    }
}

extension RGBA {
    init(opaque hex: String) { self.init("#FF" + hex.dropFirst()) }
}
