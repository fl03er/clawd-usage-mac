// The Launch theme's backdrop: a launch site on the Moon, under a black sky with Earth up in it,
// in 1-point pixels with ordered dithering, playing a 30-second loop. A three-core rocket rolls
// out of the base lying on its transporter, is raised on the pad, vents for a while, lights up
// and climbs out of the top of the widget on a wide vacuum plume. The blast throws regolith out
// on low arcs that fall back (no air to hold it up), lit orange by the engines and by the sun
// from the left, and it settles before the next rocket rolls out.

import AppKit

final class Launch {
    struct C { var r, g, b: Float }
    struct Puff { var x, y, vx, vy, r, grow, age, life, seed: Double; var trail: Bool }

    let cycle = 30.0
    let ignite = 15.0, liftoff = 16.2
    let t0 = Date.timeIntervalSinceReferenceDate - 4   // open the widget a few seconds into the rollout
    var lastNow: Double? = nil, lastCt = 0.0, spawnAcc = 0.0, ventAcc = 0.0
    var puffs: [Puff] = []
    var rng = SplitMix(seed: 11)
    var ctx: CGContext? = nil
    var base: [C] = [], over: [C?] = []
    var key = ""

    // Rocket: 23 x 71 colour indices (0 is see-through); columns 0 and 22 hold the grid fins.
    let sprite: [[UInt8]]
    let rocketColors: [C] = ["#000000", "#FFFFFF", "#EEF1F5", "#C8CED8", "#8F98A8", "#1E222A", "#3A404C"].map(Launch.hex)
    let smoke: [C] = ["#3E3B3A", "#55514E", "#6F6A66", "#8A857F", "#A6A09A", "#C2BCB5", "#DCD7D0"].map(Launch.hex)
    let flame: [C] = ["#000000", "#B8401A", "#F07A22", "#FFB547", "#FFE38A", "#FFFBEA", "#FFFFFF"].map(Launch.hex)
    let glowC = Launch.hex("#FF9440")
    let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { (Float($0) + 0.5) / 16 }
    var bgColor = Launch.hex("#0B1424")

    static func hex(_ s: String) -> C { let c = RGBA(opaque: s); return C(r: Float(c.r * 255), g: Float(c.g * 255), b: Float(c.b * 255)) }

    // Sprite size; the centre line is at sw / 2.
    let sw = 23, sh = 71
    var half: Double { Double(sw) / 2 }
    let nozzles = [-7.5, 0, 7.5]

    init() {
        var s = Array(repeating: Array(repeating: UInt8(0), count: 23), count: 71)
        // A cylinder lit from the left: highlight, white, light grey, shadow.
        func cyl(_ c0: Int, _ c1: Int, _ y0: Int, _ y1: Int) {
            for y in y0 ... y1 {
                for x in c0 ... c1 {
                    let f = (Double(x - c0) + 0.5) / Double(c1 - c0 + 1)
                    s[y][x] = f < 0.2 ? 1 : f < 0.5 ? 2 : f < 0.78 ? 3 : 4
                }
            }
        }
        func fill(_ c0: Int, _ c1: Int, _ y0: Int, _ y1: Int, _ c: UInt8) {
            for y in y0 ... y1 { for x in c0 ... c1 { s[y][x] = c } }
        }
        // Side boosters, 6 wide: engine bells, a black engine section, body, nose cone.
        for c0 in [1, 16] {
            cyl(c0, c0 + 5, 3, 42)
            cyl(c0, c0 + 5, 43, 44); cyl(c0 + 1, c0 + 4, 45, 46); cyl(c0 + 2, c0 + 3, 47, 48)
            fill(c0 + 1, c0 + 4, 0, 0, 6); fill(c0, c0 + 5, 1, 2, 5)
            for y in 3 ... 6 { s[y][c0 + 1] = 3; s[y][c0 + 4] = 4 }        // soot above the engines
            let outer = c0 == 1 ? c0 : c0 + 5, inner = c0 == 1 ? c0 + 2 : c0 + 3
            for y in 4 ... 16 { s[y][outer] = 6 }                            // folded landing legs
            for y in 6 ... 14 { s[y][inner] = 6 }
            let fin = c0 == 1 ? 0 : 22                                       // grid fins
            for y in 38 ... 40 { s[y][fin] = 5 }
        }
        // Core, 7 wide: same base, black interstage, second stage, wider fairing.
        cyl(8, 14, 3, 44)
        fill(9, 13, 0, 0, 6); fill(8, 14, 1, 2, 5)
        for y in 5 ... 15 { s[y][11] = 6 }
        fill(8, 14, 45, 48, 5)
        cyl(8, 14, 49, 55)
        cyl(7, 15, 56, 63)
        cyl(8, 14, 64, 65); cyl(9, 13, 66, 67); cyl(10, 12, 68, 69); s[70][11] = 2
        sprite = s
    }

    // MARK: drawing

    // Fills r: the scene from the top down to a little under `ground` (where Clawd stands), then bg.
    func draw(in r: CGRect, ground: Double, bg: NSColor) {
        let w = Int(r.width.rounded()), g = Int((ground - r.minY).rounded())
        let h = min(Int(r.height.rounded()), g + 28)
        guard w > 0, h > 0 else { return }
        let b = bg.usingColorSpace(.sRGB) ?? bg
        bgColor = C(r: Float(b.redComponent * 255), g: Float(b.greenComponent * 255), b: Float(b.blueComponent * 255))
        let k = "\(w)x\(h)x\(g)"
        if k != key { key = k; buildStatic(w: w, h: h, g: g) }
        if ctx == nil || ctx!.width != w || ctx!.height != h {
            ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx, let data = ctx.data else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let dt = min(0.2, max(0, now - (lastNow ?? now)))
        lastNow = now
        let ct = (now - t0).truncatingRemainder(dividingBy: cycle)
        if ct < lastCt { puffs.removeAll() }   // a new rocket: the sky has cleared
        lastCt = ct
        var px = base
        step(ct, dt, w: w, g: g)
        compose(&px, ct, w: w, h: h, g: g, t: now - t0)
        let out = data.assumingMemoryBound(to: UInt8.self)
        for i in 0 ..< w * h {
            out[i * 4] = UInt8(max(0, min(255, px[i].r)))
            out[i * 4 + 1] = UInt8(max(0, min(255, px[i].g)))
            out[i * 4 + 2] = UInt8(max(0, min(255, px[i].b)))
            out[i * 4 + 3] = 255
        }
        guard let cg = ctx.makeImage() else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cg, size: NSSize(width: w, height: h))
            .draw(in: CGRect(x: r.minX, y: r.minY, width: Double(w), height: Double(h)), from: .zero,
                  operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    // Where things stand on a w-wide scene.
    func padX(_ w: Int) -> Double { Double(w) * 0.55 }
    func hangarX(_ w: Int) -> Int { w - 64 }

    // The rocket at time ct: base centre, angle from vertical (pi/2: lying, nose to the right), visible.
    func rocket(_ ct: Double, w: Int, g: Int) -> (x: Double, y: Double, a: Double, on: Bool) {
        let pad = Double(g) - 5, px = padX(w)
        func ease(_ x: Double) -> Double { let t = max(0, min(1, x)); return t * t * (3 - 2 * t) }
        if ct < 7 {
            return (Double(hangarX(w)) + 4 + (px - Double(hangarX(w)) - 4) * ease(ct / 7), pad - 13, .pi / 2, true)
        }
        if ct < 10 {
            let a = .pi / 2 * (1 - ease((ct - 7) / 3))
            return (px, pad - 13 * sin(a), a, true)
        }
        if ct < liftoff { return (px, pad, 0, true) }
        let tau = ct - liftoff
        let s = 9 * tau * tau
        let a = 0.13 * ease((tau - 1.5) / 3)
        return (px + s * sin(a) * 0.6, pad - s, a, pad - s > -90)
    }

    func flameLevel(_ ct: Double) -> Double {
        if ct < ignite || ct > liftoff + 9 { return 0 }
        return min(1, (ct - ignite) / 0.4)
    }

    func step(_ ct: Double, _ dt: Double, w: Int, g: Int) {
        let rk = rocket(ct, w: w, g: g)
        let gy = Double(g)
        // Exhaust: a burst of regolith along the ground through the flame trench.
        if ct >= ignite && ct < liftoff + 4.5 {
            let groundRate = ct < liftoff + 2.5 ? 55.0 : 12.0
            spawnAcc += groundRate * dt
            while spawnAcc >= 1 {
                spawnAcc -= 1
                let side = rng.next() < 0.62 ? -1.0 : 1.0
                puffs.append(Puff(x: padX(w) + side * Double.random(in: 5 ... 15), y: gy - Double.random(in: 2 ... 9),
                                  vx: side * Double.random(in: 18 ... (side < 0 ? 42 : 70)), vy: -Double.random(in: 4 ... 18),
                                  r: Double.random(in: 3.5 ... 7), grow: Double.random(in: 7 ... 12), age: 0,
                                  life: Double.random(in: 2.8 ... 4.2), seed: rng.next() * 6.28, trail: false))
            }
        }
        // Venting while it waits on the pad: small wisps of cold vapour off the side.
        if ct > 10.5 && ct < ignite {
            if rng.next() < 6 * dt {
                let side = rng.next() < 0.5 ? -1.0 : 1.0
                puffs.append(Puff(x: rk.x + side * 10, y: rk.y - Double.random(in: 26 ... 44), vx: side * Double.random(in: 4 ... 9),
                                  vy: Double.random(in: -1 ... 2), r: 1.2, grow: 2.2, age: 0, life: 1.8, seed: rng.next() * 6.28, trail: true))
            }
        }
        for i in puffs.indices {
            var p = puffs[i]
            p.age += dt
            p.vx *= exp(-(p.trail ? 0.6 : 0.9) * dt)
            // No air on the Moon: dust flies out on arcs and falls back under a sixth of Earth's pull.
            p.vy = p.trail ? p.vy * exp(-0.9 * dt) - 0.6 * dt : p.vy + 9 * dt
            p.x += p.vx * dt; p.y += p.vy * dt
            p.r = min(p.trail ? 8 : 10, p.r + p.grow * dt / (1 + 0.9 * p.age))
            if p.y > gy - p.r * 0.45 { p.y = gy - p.r * 0.45 }
            puffs[i] = p
        }
        puffs.removeAll { $0.age > $0.life }
        if puffs.count > 320 { puffs.removeFirst(puffs.count - 320) }
    }

    func compose(_ px: inout [C], _ ct: Double, w: Int, h: Int, g: Int, t: Double) {
        let rk = rocket(ct, w: w, g: g)
        let fl = flameLevel(ct)
        func put(_ x: Int, _ y: Int, _ c: C) { if x >= 0 && x < w && y >= 0 && y < h { px[y * w + x] = c } }
        let dark = Launch.hex("#3D4350"), wheel = Launch.hex("#15181E")
        let towerX = Int(padX(w)) - 23

        // Swing arm to the core while it waits; it pulls back just before ignition.
        if ct > 10.2 && ct < ignite {
            let reach = 9.0 * min(1, (ct - 10.2) / 0.8) * (ct > ignite - 1.2 ? max(0, (ignite - 0.4 - ct) / 0.8) : 1)
            for i in 0 ..< Int(reach) { put(towerX + 7 + i, g - 60, dark); put(towerX + 7 + i, g - 59, dark) }
        }
        // Transporter: under the rocket for the ride, then back into the hangar.
        let tx: Double? = ct < 10 ? (ct < 7 ? rk.x : padX(w)) : ct < 15 ? padX(w) + (Double(w) - padX(w)) * (ct - 10) / 5 : nil
        if let tx {
            for x in Int(tx) - 2 ..< Int(tx) + 72 {
                for y in g - 5 ..< g - 2 { put(x, y, dark) }
                if (x - Int(tx)) % 6 == 1 { put(x, g - 2, wheel); put(x, g - 1, wheel); put(x + 1, g - 2, wheel); put(x + 1, g - 1, wheel) }
            }
        }
        if rk.on { drawRocket(&px, rk, w: w, h: h) }
        // The hangar goes over the rocket, so it rolls out of the door.
        for i in 0 ..< w * h { if let c = over[i] { px[i] = c } }

        // Glow from the engines on everything near them.
        let fx = rk.x, fy = rk.y + 3
        if fl > 0 {
            let rad = 60
            let y0 = max(0, Int(fy) - rad), y1 = min(h, Int(fy) + rad), x0 = max(0, Int(fx) - rad), x1 = min(w, Int(fx) + rad)
            for y in y0 ..< max(y0, y1) {
                for x in x0 ..< max(x0, x1) {
                    let d = ((Double(x) - fx) * (Double(x) - fx) + (Double(y) - fy) * (Double(y) - fy)).squareRoot()
                    let gl = Float(fl * 0.75 * exp(-d / 15))
                    let q = (Float(Int(gl * 5 + bayer[(y & 3) * 4 + (x & 3)]))) / 5
                    if q > 0 { let i = y * w + x; px[i].r += glowC.r * q; px[i].g += glowC.g * q * 0.9; px[i].b += glowC.b * q * 0.6 }
                }
            }
        }
        // Exhaust clouds, oldest first.
        let lx = -0.45, ly = -0.6, lz = 0.66
        for p in puffs {
            let alpha = min(1, p.age / 0.3) * (1 - smooth(p.life * 0.55, p.life, p.age)) * (p.trail ? 0.85 : 1)
            let r = p.r
            let ri = Int(r * 1.25) + 1
            if alpha <= 0 || Int(p.x) + ri < 0 || Int(p.x) - ri >= w || Int(p.y) + ri < 0 || Int(p.y) - ri >= h { continue }
            // A lumpy outline: its radius round the puff, in 32 steps.
            let edges = (0 ..< 32).map { k -> Double in
                let ang = Double(k) / 32 * 2 * .pi
                return 1 + 0.13 * sin(5 * ang + p.seed) + 0.08 * sin(9 * ang + 2 * p.seed)
            }
            for y in max(0, Int(p.y) - ri) ... max(0, min(h - 1, Int(p.y) + ri)) {
                for x in max(0, Int(p.x) - ri) ... max(0, min(w - 1, Int(p.x) + ri)) {
                    let dx = (Double(x) + 0.5 - p.x) / r, dy = (Double(y) + 0.5 - p.y) / r
                    let d2 = dx * dx + dy * dy
                    if d2 > 1.6 { continue }
                    // Angle without atan2: position round a diamond, 0 ..< 4.
                    let s = abs(dx) + abs(dy) + 1e-9
                    let dia = dy >= 0 ? (dx >= 0 ? dy / s : 1 - dx / s) : (dx < 0 ? 2 - dy / s : 3 + dx / s)
                    let edge = edges[Int(dia * 8) & 31]
                    if d2 > edge * edge { continue }
                    let dth = bayer[(y & 3) * 4 + (x & 3)]
                    if Float(alpha) < dth { continue }
                    let nz = max(0, 1 - d2 / (edge * edge)).squareRoot()
                    let lit = max(0, dx * lx + dy * ly + nz * lz)
                    let tone = 0.22 + 0.62 * lit + 0.16 * nz
                    let c = smoke[min(6, Int(Float(tone) * 6 + dth))]
                    var o = c
                    if fl > 0 {
                        let dd = ((Double(x) - fx) * (Double(x) - fx) + (Double(y) - fy) * (Double(y) - fy)).squareRoot()
                        let gl = Float(fl * exp(-dd / 26) * (0.55 + 0.45 * dy))
                        let q = Float(Int(gl * 4 + dth)) / 4
                        o.r = c.r + (glowC.r - c.r) * q * 0.8; o.g = c.g + (glowC.g - c.g) * q * 0.8; o.b = c.b + (glowC.b - c.b) * q * 0.8
                    }
                    px[y * w + x] = o
                }
            }
        }
        // The flame: three plumes that merge, white at the nozzles, flickering; longer as it climbs.
        if fl > 0 && rk.on {
            let tau = max(0, ct - liftoff)
            let len = (ct < liftoff ? 12 : min(62, 16 + 16 * tau)) * fl
            let ca = cos(rk.a), sa = sin(rk.a)
            let ext = Int(len) + 16
            for y in max(0, min(h - 1, Int(rk.y) - 16)) ... max(0, min(h - 1, Int(rk.y) + ext)) {
                for x in max(0, Int(rk.x) - ext) ... min(w - 1, Int(rk.x) + ext) {
                    let dx = Double(x) + 0.5 - rk.x, dy = Double(y) + 0.5 - rk.y
                    let lxv = dx * ca + dy * sa, a = -(dx * sa - dy * ca)   // across, and distance below the base
                    if a < 0 || a > len { continue }
                    let wd = 2.0 + a * 0.3   // a vacuum plume spreads wide
                    let q = min(abs(lxv + 7.5), abs(lxv), abs(lxv - 7.5)) / wd
                    let best = exp(-q * q)
                    let flick = 0.82 + 0.18 * sin(a * 0.9 - t * 37 + lxv)
                    let v = best * pow(1 - a / len, 0.6) * flick
                    let i = Int(Float(v) * 6.4 + bayer[(y & 3) * 4 + (x & 3)] - 0.25)
                    if i > 0 { px[y * w + x] = flame[min(6, i)] }
                }
            }
        }
        // The red light on the tower blinks.
        if sin(t * 3.2) > 0.2 { put(towerX + 3, g - 88, Launch.hex("#FF4D4D")) }
    }

    func drawRocket(_ px: inout [C], _ rk: (x: Double, y: Double, a: Double, on: Bool), w: Int, h: Int) {
        let ca = cos(rk.a), sa = sin(rk.a)
        let ext = 75
        for y in max(0, Int(rk.y) - ext) ... max(0, min(h - 1, Int(rk.y) + 14)) {
            for x in max(0, Int(rk.x) - ext) ... max(0, min(w - 1, Int(rk.x) + ext)) {
                let dx = Double(x) + 0.5 - rk.x, dy = Double(y) + 0.5 - rk.y
                // Right is (cos a, sin a), up is (sin a, -cos a), in a y-down picture.
                let lx = dx * ca + dy * sa, ly = dx * sa - dy * ca
                let ix = Int((lx + half).rounded(.down)), iy = Int(ly.rounded(.down))
                if ix < 0 || ix >= sw || iy < 0 || iy >= sh { continue }
                let c = sprite[iy][ix]
                if c > 0 && y >= 0 && y < h && x >= 0 && x < w { px[y * w + x] = rocketColors[Int(c)] }
            }
        }
    }

    // MARK: the still parts

    func buildStatic(w: Int, h: Int, g: Int) {
        base = Array(repeating: bgColor, count: w * h)
        over = Array(repeating: nil, count: w * h)
        func d(_ x: Int, _ y: Int) -> Float { bayer[(y & 3) * 4 + (x & 3)] }
        func lerp(_ a: C, _ b: C, _ t: Float) -> C { C(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t) }
        func put(_ x: Int, _ y: Int, _ c: C) { if x >= 0 && x < w && y >= 0 && y < h { base[y * w + x] = c } }
        func putO(_ x: Int, _ y: Int, _ c: C) { if x >= 0 && x < w && y >= 0 && y < h { over[y * w + x] = c } }

        // Sky: black, a little lighter at the horizon, full of stars that never twinkle (no air).
        let sky = ["#020206", "#05050B", "#090911"].map(Launch.hex)
        var rs = SplitMix(seed: 9)
        for y in 0 ..< g {
            let t = pow(Float(y) / Float(g), 2)
            for x in 0 ..< w {
                var c = sky[min(2, Int(t * 2 + d(x, y)))]
                let v = rs.next()
                if v < 0.009 {
                    let b = Float(70 + 185 * pow(rs.next(), 3))
                    c = C(r: b, g: b, b: b * (0.9 + 0.2 * Float(rs.next())))
                }
                base[y * w + x] = c
            }
        }
        // Earth, half lit from the left: oceans, land, clouds, a thin blue rim.
        let ex = Int(Double(w) * 0.42), ey = 32, er = 11.5
        let ocean = ["#0B1E45", "#123A7A", "#1E5BB8", "#3C82D8"].map(Launch.hex)
        let land = ["#1C2E1A", "#2F5A2C", "#4E7D3A", "#7FA25A"].map(Launch.hex)
        let cloud = ["#3A4458", "#8D98AC", "#D9DFEA", "#FFFFFF"].map(Launch.hex)
        for y in ey - 13 ... ey + 13 {
            for x in ex - 13 ... ex + 13 {
                let dx = (Double(x) + 0.5 - Double(ex)) / er, dy = (Double(y) + 0.5 - Double(ey)) / er
                let d2 = dx * dx + dy * dy
                if d2 > 1.12 { continue }
                if d2 > 1 { if dx < 0.2 { put(x, y, lerp(base[y * w + x], Launch.hex("#3C7BE0"), 0.45)) }; continue }
                let z = (1 - d2).squareRoot()
                let u = atan2(dx, z) * 2.2, v = dy * 3
                let landV = sin(u * 1.7 + 0.8) * sin(v * 1.3 + 0.5) + 0.45 * sin(u * 3.1 - v * 2.2)
                let cloudV = sin(u * 4.2 + v * 1.1) * sin(v * 5.5 - u) + 0.3 * sin(u * 9 + v * 3)
                let lit = max(0, min(1, -0.85 * dx - 0.25 * dy + 0.45 * z + 0.15))
                let k = min(3, Int(Float(lit) * 3.2 + d(x, y) * 0.9))
                let pal = cloudV > 0.55 ? cloud : landV > 0.35 ? land : ocean
                put(x, y, lit < 0.06 ? Launch.hex("#050812") : pal[k])
            }
        }
        // Far ridges on the horizon, sunlit along their crests.
        let ridgeFar = Launch.hex("#2A2A30"), ridgeNear = Launch.hex("#45454C"), crest = Launch.hex("#8C8C93")
        for x in 0 ..< w {
            let fx = Double(x)
            let hf = Int(8 + 4 * sin(fx * 0.027 + 0.6) + 2.5 * sin(fx * 0.091 + 2))
            let hn = Int(4 + 3 * sin(fx * 0.045 + 3.1) + 1.5 * sin(fx * 0.17))
            for y in g - hf ..< g { put(x, y, ridgeFar) }
            for y in g - hn ..< g { put(x, y, y == g - hn ? crest : ridgeNear) }
        }
        // Regolith, pocked with shallow craters, then fade into the widget's background.
        let dust = ["#4E4E53", "#626267", "#77777C", "#8E8E93", "#A8A8AC"].map(Launch.hex)
        for y in g ..< h {
            for x in 0 ..< w {
                let n = Float(sin(Double(x) * 0.53 + Double(y) * 1.7) * sin(Double(x) * 0.13 - Double(y) * 0.6) * 0.5 + 0.5)
                put(x, y, dust[min(4, 1 + Int(n * 2.2 + d(x, y)))])
            }
        }
        var rc = SplitMix(seed: 21)
        for _ in 0 ..< 14 {
            let cx = rc.next() * Double(w), cy = Double(g) + 1.5 + rc.next() * 9
            let rx = 4 + rc.next() * 9, ry = rx * (0.24 + 0.08 * rc.next())
            for y in Int(cy - ry - 2) ... Int(cy + ry + 2) {
                for x in Int(cx - rx - 2) ... Int(cx + rx + 2) {
                    guard y >= g else { continue }
                    let u = (Double(x) + 0.5 - cx) / rx, v = (Double(y) + 0.5 - cy) / ry
                    let q = u * u + v * v
                    if q < 0.8 { put(x, y, dust[u < 0.1 ? 0 : (u > 0.55 ? 3 : 1)]) }       // sun from the left: the left wall is in shadow
                    else if q < 1.25 { put(x, y, dust[u < 0 ? 4 : 2]) }                 // the rim, lit on its left
                }
            }
        }
        for y in g ..< h {
            let fade = Float(max(0, min(1, Double(y - g - 8) / 18)))
            for x in 0 ..< w where fade > d(x, y) { put(x, y, bgColor) }
        }
        // Concrete pad and the flame trench beside it.
        let concrete = ["#7D8189", "#9A9EA6", "#B7BAC0"].map(Launch.hex)
        let px0 = Int(padX(w))
        for y in g - 5 ..< g + 2 {
            let half = 22 + (y - (g - 5))
            for x in px0 - half ... px0 + half { put(x, y, concrete[y == g - 5 ? 2 : (x + y) % 5 == 0 ? 0 : 1]) }
        }
        for x in px0 - 38 ..< px0 - 10 { put(x, g + 1, Launch.hex("#2A2D33")); put(x, g + 2, Launch.hex("#2A2D33")) }

        // Launch tower: a lattice with a mast on top.
        let steel = Launch.hex("#4A505C"), steelLit = Launch.hex("#6E7684")
        let tx = px0 - 23, top = g - 78
        for y in top ..< g - 5 {
            put(tx, y, steelLit); put(tx + 6, y, steel)
            let k = (y - top) % 8
            if k == 0 { for x in tx ... tx + 6 { put(x, y, steel) } }
            put(tx + min(6, k * 6 / 7), y, steel)   // diagonal
        }
        for y in g - 88 ..< top { put(tx + 3, y, steel) }

        // A dish antenna on a mast between the pad and the base, looking up at Earth.
        let wx = w - 86, wy = g - 26
        for y in wy ..< g { put(wx, y, steel); if y > g - 6 { put(wx - 1, y, steel); put(wx + 1, y, steel) } }
        let th = -0.55
        for y in wy - 10 ... wy + 6 {
            for x in wx - 10 ... wx + 10 {
                let dx = Double(x) + 0.5 - Double(wx), dy = Double(y) + 0.5 - Double(wy)
                let u = dx * cos(th) + dy * sin(th), v = -dx * sin(th) + dy * cos(th)
                if (u / 8.5) * (u / 8.5) + (v / 3.2) * (v / 3.2) < 1 && v > -0.6 - 0.04 * u * u {
                    put(x, y, concrete[min(2, max(0, Int(1.4 - u / 5 + Double(d(x, y)) * 0.7)))])
                }
            }
        }
        for k in 0 ..< 7 { put(wx + Int(Double(k) * -sin(th) * 0.9), wy - 1 - Int(Double(k) * cos(th) * 0.9), steelLit) }
        put(wx + Int(7 * -sin(th) * 0.9), wy - 2 - Int(7 * cos(th) * 0.9), Launch.hex("#FF4D4D"))

        // The hangar: corrugated white walls, a darker lower band with doors, and a sign.
        let hx = hangarX(w), hTop = g - 42
        let wall = ["#D9DEE6", "#C3CAD5"].map(Launch.hex), side = Launch.hex("#9BA5B5")
        let band = Launch.hex("#56637A"), door = Launch.hex("#3B465A"), roof = Launch.hex("#8A93A3")
        for y in hTop ..< g {
            for x in hx - 6 ..< hx { if y > hTop + (hx - x) / 2 { putO(x, y, side) } }   // the side in shadow
            for x in hx ..< w {
                var c = wall[(x - hx) % 3 == 2 ? 1 : 0]
                if y < hTop + 3 { c = roof }
                if y >= g - 13 { c = (x - hx) % 14 < 11 && y > g - 12 ? door : band }
                putO(x, y, c)
            }
        }
        // A small flag, then the wordmark with its swoosh rising through the X.
        let red = Launch.hex("#C8323C"), white = Launch.hex("#F4F5F7"), canton = Launch.hex("#2B3E73")
        for j in 0 ..< 7 {
            for i in 0 ..< 10 {
                let c = i < 4 && j < 4 ? ((i + j) % 2 == 1 && j % 2 == 1 ? white : canton) : (j % 2 == 0 ? red : white)
                putO(hx + 3 + i, hTop + 13 + j, c)
            }
        }
        let glyphs: [Character: [String]] = [
            "S": ["###", "#..", "###", "..#", "###"], "P": ["###", "#.#", "###", "#..", "#.."],
            "A": [".#.", "#.#", "###", "#.#", "#.#"], "C": ["###", "#..", "#..", "#..", "###"],
            "E": ["###", "#..", "##.", "#..", "###"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        ]
        let ink = Launch.hex("#1E2F55")
        let ty = hTop + 12
        var cx = hx + 16, xAt = 0
        for ch in "SPACEX" {
            if ch == "X" { xAt = cx }
            for (j, row) in glyphs[ch]!.enumerated() {
                for (i, v) in row.enumerated() where v == "#" {
                    for a in 0 ..< 2 { for b in 0 ..< 2 { putO(cx + i * 2 + a, ty + j * 2 + b, ink) } }
                }
            }
            cx += 7
        }
        // The swoosh: a thin curve from under the E, through the X, up past its top; thicker in the middle.
        let p0 = (Double(xAt - 13), Double(ty + 12)), p1 = (Double(xAt + 2), Double(ty + 12)), p2 = (Double(xAt + 11), Double(ty - 4))
        for k in 0 ... 240 {
            let t = Double(k) / 240, u = 1 - t
            let x = u * u * p0.0 + 2 * u * t * p1.0 + t * t * p2.0
            let y = u * u * p0.1 + 2 * u * t * p1.1 + t * t * p2.1
            putO(Int(x), Int(y), ink)
            if t > 0.25 && t < 0.8 { putO(Int(x), Int(y) + 1, ink) }
        }
    }

    func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
}

// A small, seedable random source: same stars and texture every launch.
struct SplitMix {
    var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> Double {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
