// Backdrop behind Clawd (lib/sky.ps1): colour follows the real sunrise and sunset,
// the sun and the moon (in its real phase) travel an arc, stars twinkle at night,
// clouds, rain, snow, fog and lightning follow the weather from Open-Meteo.

import AppKit

struct RGBA {
    var r, g, b, a: Double
    init(_ hex: String) {
        var v: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
        a = Double(v >> 24 & 0xFF) / 255; r = Double(v >> 16 & 0xFF) / 255; g = Double(v >> 8 & 0xFF) / 255; b = Double(v & 0xFF) / 255
    }
    init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
    func mix(_ o: RGBA, _ k: Double) -> RGBA {
        let k = max(0, min(1, k))
        return RGBA(r: r + (o.r - r) * k, g: g + (o.g - g) * k, b: b + (o.b - b) * k, a: a + (o.a - a) * k)
    }
    // Cloudiness: the colour fades toward gray and darkens.
    func dim(_ g0: Double) -> RGBA {
        let l = 0.3 * r + 0.59 * g + 0.11 * b, f = 1 - 0.3 * g0
        return RGBA(r: (r + (l - r) * g0) * f, g: (g + (l - g) * g0) * f, b: (b + (l - b) * g0) * f, a: a)
    }
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

let skyPal: [String: (RGBA, RGBA, Double)] = [
    "night": (RGBA("#00304A8C"), RGBA("#1A304A8C"), 0),
    "dawn": (RGBA("#00404E8A"), RGBA("#33E08A66"), 0.5),
    "day": (RGBA("#004A8CCB"), RGBA("#2E6FA8D8"), 1),
    "dusk": (RGBA("#00383070"), RGBA("#33D86A50"), 0.5),
]
let cloudShapes = [["....###.....", "..#######...", ".##########.", "############"],
                   ["..###...", ".######.", "########"],
                   ["...##.##..", ".########.", "##########"]]
let sunArt = ["..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###.."]

final class Sky {
    struct Cloud { var shape: Int; var x = -1.0; var fy: Double; var v: Double; var fade = 0.0 }
    struct Drop { var x = 0.0, y = -99.0, v = 0.0, ph = 0.0 }
    var tick = 0
    var stars: [(Double, Double)] = (0 ..< 20).map { _ in (Double.random(in: 0 ... 1), Double.random(in: 0 ... 0.6)) }
    var clouds: [Cloud] = (0 ..< 9).map { Cloud(shape: $0 % 3, fy: 0.05 + 0.3 * Double.random(in: 0 ... 1), v: 0.7 + 0.6 * Double.random(in: 0 ... 1)) }
    var drops = [Drop](repeating: Drop(), count: 40)
    var flakes = [Drop](repeating: Drop(), count: 34)
    var fog: [(Double, Double)] = (0 ..< 3).map { (Double.random(in: 0 ... 1), 0.42 + 0.2 * Double($0)) }
    var flash = 0
    var moonKey = "", moonLit: [CGRect] = [], moonDark: [CGRect] = []

    func draw(in r: CGRect, weather: Weather?, place: Place?) {
        tick += 1
        let w = r.width, h = r.height
        let (sr, ss): (Double, Double) = {
            if let wx = weather, let a = wx.sunrise, let b = wx.sunset { return (a, b) }
            if let p = place { return sunCalc(p.lat, p.lon) }
            return (420, 1140)
        }()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let t = skyClockOverride ?? Double(comps.hour! * 60 + comps.minute!)
        let fresh = weather.map { Date().timeIntervalSince($0.at) < 3 * 3600 } ?? false
        let kind = weatherKind(fresh ? weather!.code : 0)
        let wind = fresh ? weather!.wind : 8

        // Sky colour between the phases around sunrise and sunset.
        let stops: [(Double, String)] = [(sr - 80, "night"), (sr - 10, "dawn"), (sr + 70, "day"), (ss - 70, "day"), (ss + 10, "dusk"), (ss + 80, "night")]
        var a = skyPal["night"]!, b = skyPal["night"]!, k = 0.0
        for i in 0 ..< stops.count - 1 where t >= stops[i].0 && t < stops[i + 1].0 {
            a = skyPal[stops[i].1]!; b = skyPal[stops[i + 1].1]!
            k = (t - stops[i].0) / (stops[i + 1].0 - stops[i].0)
        }
        let light = a.2 + (b.2 - a.2) * k
        let g = kind.cover * 0.9
        let top = a.0.mix(b.0, k).dim(g), bottom = a.1.mix(b.1, k).dim(g)
        NSGradient(starting: top.ns, ending: bottom.ns)?.draw(from: CGPoint(x: r.midX, y: r.minY), to: CGPoint(x: r.midX, y: r.maxY), options: [])

        // Stars twinkle.
        let starOp = (1 - light * 2) * max(0, 1 - kind.cover * 1.4)
        if starOp > 0 {
            for (i, s) in stars.enumerated() {
                NSColor(white: 0.98, alpha: starOp * (0.55 + 0.45 * sin(Double(tick) / 7 + Double(i) * 1.7))).setFill()
                NSBezierPath(rect: CGRect(x: r.minX + (s.0 * (w - 2)).rounded(), y: r.minY + (2 + s.1 * h).rounded(), width: 1.2, height: 1.2)).fill()
            }
        }

        // Position on the arc: p 0..1 from horizon to horizon.
        func arc(_ p: Double) -> CGPoint? {
            if p < -0.06 || p > 1.06 { return nil }
            return CGPoint(x: r.minX + 7 + p * (w - 14), y: r.minY + h + 3 - sin(.pi * p) * (h - 12))
        }
        let vis = max(0, 1 - kind.cover * 1.15)
        if vis > 0, let c = arc((t - sr) / (ss - sr)) {
            let p = (t - sr) / (ss - sr)
            NSGradient(starting: hexColor("#40FDE68A"), ending: hexColor("#00FDE68A"))?
                .draw(in: NSBezierPath(ovalIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)), relativeCenterPosition: .zero)
            RGBA("#FFFB923C").mix(RGBA("#FFFDE68A"), sin(.pi * p) * 1.6).ns.withAlphaComponent(vis).setFill()
            pixels(sunArt, CGPoint(x: c.x - 4.9, y: c.y - 4.9), 1.4)
        }
        let q = ((t - ss + 1440).truncatingRemainder(dividingBy: 1440)) / (sr + 1440 - ss)
        if vis > 0, let c = arc(q) {
            updateMoon(lat: place?.lat ?? 37)
            hexColor("#2EE5E7EB").withAlphaComponent(0.18 * vis).setFill()
            for m in moonDark { NSBezierPath(rect: m.offsetBy(dx: c.x - 4.55, dy: c.y - 4.55)).fill() }
            hexColor("#F1F5F9").withAlphaComponent(vis).setFill()
            for m in moonLit { NSBezierPath(rect: m.offsetBy(dx: c.x - 4.55, dy: c.y - 4.55)).fill() }
        }

        // Clouds drift with the wind; extra ones fade out, needed ones fade in.
        let dens = max(1, w / 140)
        let nClouds = min(clouds.count, Int((kind.cover * 5 * dens).rounded()))
        var cc = RGBA("#FF5E5E68").mix(RGBA("#FFB4B4BC"), light)
        if kind.rain > 0 || kind.storm { cc = cc.mix(RGBA("#FF52525B"), 0.55) }
        let drift = 0.04 + wind / 350
        for i in clouds.indices {
            let want = i < nClouds ? 1.0 : 0.0
            clouds[i].fade += max(-0.03, min(0.03, want - clouds[i].fade))
            if clouds[i].fade <= 0 { continue }
            let cw = Double(cloudShapes[clouds[i].shape][0].count) * 2
            if clouds[i].x == -1 { clouds[i].x = Double.random(in: 0 ... 1) * w }   // first appearance
            clouds[i].x += drift * clouds[i].v
            if clouds[i].x > w { clouds[i].x = -cw + 0.01; clouds[i].fy = 0.05 + 0.3 * Double.random(in: 0 ... 1) }
            cc.ns.withAlphaComponent(0.65 * clouds[i].fade).setFill()
            pixels(cloudShapes[clouds[i].shape], CGPoint(x: r.minX + clouds[i].x.rounded(), y: r.minY + (clouds[i].fy * h).rounded()), 2)
        }

        // Fog - translucent bands crawling slowly.
        if kind.fog {
            for i in fog.indices {
                fog[i].0 = (fog[i].0 + 0.0015).truncatingRemainder(dividingBy: 1.6)
                let op = 0.14 + 0.05 * sin(Double(tick) / 20 + fog[i].1 * 10)
                let band = CGRect(x: r.minX + (fog[i].0 - 0.6) * w, y: r.minY + fog[i].1 * h, width: w * 0.6, height: 3)
                NSGradient(colors: [hexColor("#00E5E7EB"), hexColor("#E5E7EB").withAlphaComponent(op), hexColor("#00E5E7EB")])?.draw(in: band, angle: 0)
            }
        }

        // Rain slants with the wind; snow falls slowly and sways.
        let slant = min(1.2, wind / 25)
        let nRain = min(drops.count, Int((Double(kind.rain) * dens).rounded()))
        hexColor("#8093C5FD").setFill()
        for i in drops.indices {
            if i >= nRain { drops[i].y = -99; continue }
            if drops[i].y < -50 || drops[i].y > h {
                drops[i].x = Double.random(in: 0 ... 1) * (w + 10) - 10
                drops[i].y = drops[i].y < -50 ? Double.random(in: 0 ... 1) * h : -4
                drops[i].v = 3.5 + 1.5 * Double.random(in: 0 ... 1)
            }
            drops[i].y += drops[i].v; drops[i].x += slant
            NSBezierPath(rect: CGRect(x: r.minX + drops[i].x, y: r.minY + drops[i].y, width: 1, height: 3.5)).fill()
        }
        let nSnow = min(flakes.count, Int((Double(kind.snow) * dens).rounded()))
        hexColor("#C0E4E4E7").setFill()
        for i in flakes.indices {
            if i >= nSnow { flakes[i].y = -99; continue }
            if flakes[i].y < -50 || flakes[i].y > h {
                flakes[i].x = Double.random(in: 0 ... 1) * w
                flakes[i].y = flakes[i].y < -50 ? Double.random(in: 0 ... 1) * h : -2
                flakes[i].v = 0.3 + 0.35 * Double.random(in: 0 ... 1)
                flakes[i].ph = Double.random(in: 0 ... 6.28)
            }
            flakes[i].y += flakes[i].v
            let fx = flakes[i].x + 1.5 * sin(Double(tick) / 9 + flakes[i].ph) + slant * flakes[i].y / 4
            NSBezierPath(rect: CGRect(x: r.minX + fx, y: r.minY + flakes[i].y, width: 1.6, height: 1.6)).fill()
        }
        // Snow has settled - a thin white strip underfoot.
        if kind.snow > 0 {
            RGBA("#50A1A8B5").mix(RGBA("#80DDE4EC"), light).ns.setFill()
            NSBezierPath(rect: CGRect(x: r.minX, y: r.maxY - 1.5, width: w, height: 1.5)).fill()
        }
        // Thunderstorm: now and then the sky flashes.
        if kind.storm && flash <= 0 && rnd(140) == 0 { flash = 7 }
        if flash > 0 {
            NSColor(white: 0.98, alpha: [0, 0.18, 0.05, 0, 0.25, 0.1, 0.04][flash - 1]).setFill()
            NSBezierPath(rect: r).fill()
            flash -= 1
        }
    }

    func pixels(_ rows: [String], _ o: CGPoint, _ px: Double) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" {
                NSBezierPath(rect: CGRect(x: o.x + Double(x) * px, y: o.y + Double(y) * px, width: px, height: px)).fill()
            }
        }
    }

    // A pixel is lit if it is on the bright side of the terminator u = cos(θ)·√(1-v²).
    func updateMoon(lat: Double) {
        let age = moonAge()
        let key = "\(Int((age * 2).rounded()))|\(lat < 0)"
        if key == moonKey { return }
        moonKey = key
        let th = 2 * Double.pi * age / moonMonth, k = cos(th)
        let n = 7, rr = 3.5, px = 1.3
        moonLit = []; moonDark = []
        for y in 0 ..< n {
            for x in 0 ..< n {
                var u = (Double(x) + 0.5 - rr) / rr
                let v = (Double(y) + 0.5 - rr) / rr
                if lat < 0 { u = -u }   // in the southern hemisphere the waxing moon is on the left
                let inside = u * u + v * v <= 1.05
                let tt = k * (max(0, 1 - v * v)).squareRoot()
                let on = inside && (th < .pi ? u > tt : u < -tt)
                let rect = CGRect(x: Double(x) * px, y: Double(y) * px, width: px, height: px)
                if on { moonLit.append(rect) } else if inside { moonDark.append(rect) }
            }
        }
    }
}

func moonDescription() -> String {
    let f = moonAge() / moonMonth
    let names = ["삭", "초승달", "상현달", "차오르는 달", "보름달", "기우는 달", "하현달", "그믐달"]
    let lit = Int(((1 - cos(2 * .pi * f)) / 2 * 100).rounded())
    return "\(names[Int((f * 8 + 0.5).rounded(.down)) % 8]) \(lit)%"
}
