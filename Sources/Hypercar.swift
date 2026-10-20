// The Hypercar theme's backdrop: an orange-to-red endurance prototype on show in a dark
// studio, in 1-point pixels with ordered dithering. A red glow burns behind it, light strips
// pulse on the back wall, the glossy floor reflects the car, a highlight sweeps along the
// bodywork every few seconds and camera flashes go off now and then. The car is drawn once,
// in detail: Hangul-like graphics in the livery, panel lines, louvres, mirror, roof light,
// shark fin and swan-neck wing, two-line headlights, black multi-spoke wheels with orange
// calipers and yellow tyre lettering.

import AppKit

final class Hypercar {
    typealias C = Launch.C
    let hex = Launch.hex
    let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { (Float($0) + 0.5) / 16 }
    let t0 = Date.timeIntervalSinceReferenceDate
    var ctx: CGContext? = nil
    var base: [C] = []
    var bodyAt: [Int] = []          // screen index of every body pixel, with its local x + y for the sweep
    var bodyKey: [Float] = []
    var strips: [Int] = []
    var drl: [Int] = []
    var key = ""
    var bgColor = Launch.hex("#0C0606")
    var rng = SplitMix(seed: 23)
    var flash: (x: Int, y: Int, t: Double)? = nil
    var nextFlash = 2.0, lastNow: Double? = nil

    // The car: 168 long, 50 tall, rows counted up from the floor; nil is see-through.
    let L = 168, H = 50
    let wheelX = [32.0, 136.0], wheelR = 15.0
    var car: [[C?]] = []
    var body: [[Bool]] = []
    var drlLocal: [(Int, Int)] = []

    init() { buildCar() }

    // MARK: drawing

    func draw(in rect: CGRect, ground: Double, bg: NSColor) {
        let w = Int(rect.width.rounded()), g = Int((ground - rect.minY).rounded())
        let h = min(Int(rect.height.rounded()), g + 30)
        guard w > L, h > g else { return }
        let b = bg.usingColorSpace(.sRGB) ?? bg
        bgColor = C(r: Float(b.redComponent * 255), g: Float(b.greenComponent * 255), b: Float(b.blueComponent * 255))
        let k = "\(w)x\(h)x\(g)"
        if k != key { key = k; buildScene(w: w, h: h, g: g) }
        if ctx == nil || ctx!.width != w || ctx!.height != h {
            ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx, let data = ctx.data else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let dt = min(0.2, max(0, now - (lastNow ?? now)))
        lastNow = now
        var px = base
        animate(&px, t: now - t0, dt: dt, w: w, h: h, g: g)
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
            .draw(in: CGRect(x: rect.minX, y: rect.minY, width: Double(w), height: Double(h)), from: .zero,
                  operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    func animate(_ px: inout [C], t: Double, dt: Double, w: Int, h: Int, g: Int) {
        func d(_ i: Int) -> Float { let x = i % w, y = i / w; return bayer[(y & 3) * 4 + (x & 3)] }
        func add(_ i: Int, _ c: C, _ k: Float) { px[i].r += c.r * k; px[i].g += c.g * k; px[i].b += c.b * k }
        // Light strips on the back wall: a bright pulse runs down each one in turn.
        let warm = hex("#FF8A4A")
        for (n, x) in strips.enumerated() {
            let head = ((t * 38 + Double(n) * 23).truncatingRemainder(dividingBy: Double(g) + 60)) - 30
            let lo = max(0, Int(head) - 14), hi = min(g - 12, Int(head))
            if lo > hi { continue }
            for y in lo ... hi {
                let i = y * w + x
                let k = Float(1 - (head - Double(y)) / 14) * 0.55
                if k > 0 && px[i].r < 120 { add(i, warm, k) }
            }
        }
        // A highlight sweeps along the bodywork every six seconds.
        let ph = t.truncatingRemainder(dividingBy: 6)
        if ph < 1.7 {
            let band = Float(-30 + ph / 1.7 * Double(L + 60))
            for (j, i) in bodyAt.enumerated() {
                let u = bodyKey[j] - band
                if u > 0 && u < 9 {
                    let k = (u < 2 || u > 7 ? 0.18 : 0.38) as Float
                    px[i].r += (255 - px[i].r) * k; px[i].g += (255 - px[i].g) * k; px[i].b += (255 - px[i].b) * k
                }
            }
        }
        // The two-line headlights breathe.
        let lv = Float(0.85 + 0.15 * sin(t * 1.7))
        for i in drl { px[i] = C(r: 235 * lv + 20, g: 242 * lv + 13, b: 255) }
        // Camera flashes from the crowd.
        nextFlash -= dt
        if nextFlash <= 0 {
            nextFlash = 1.5 + rng.next() * 3.5
            flash = (Int(rng.next() * Double(w - L - 20)) + 6, Int(Double(g) * (0.25 + 0.5 * rng.next())), t)
        }
        if let f = flash {
            let age = t - f.t
            if age > 0.18 { flash = nil } else {
                let r = age < 0.06 ? 4 : 2
                for k in -r ... r {
                    for (x, y) in [(f.x + k, f.y), (f.x, f.y + k)] where x >= 0 && x < w && y >= 0 && y < h {
                        px[y * w + x] = C(r: 255, g: 255, b: 250)
                    }
                }
                if age < 0.06 { for i in bodyAt where d(i) < 0.12 { px[i].r += (255 - px[i].r) * 0.3; px[i].g += (255 - px[i].g) * 0.3; px[i].b += (255 - px[i].b) * 0.3 } }
            }
        }
    }

    // MARK: the studio (static)

    func buildScene(w: Int, h: Int, g: Int) {
        base = Array(repeating: bgColor, count: w * h)
        func d(_ x: Int, _ y: Int) -> Float { bayer[(y & 3) * 4 + (x & 3)] }
        func mix(_ a: C, _ b: C, _ k: Float) -> C { C(r: a.r + (b.r - a.r) * k, g: a.g + (b.g - a.g) * k, b: a.b + (b.b - a.b) * k) }
        let x0 = w - L - 6
        let cx = Double(x0) + Double(L) * 0.5, cy = Double(g) - 24

        // Back wall: near black, with a red glow behind the car and faint Hangul-like graphics in it.
        let glow = ["#120509", "#2A070B", "#4A0B0C", "#7A160F", "#B02C10", "#DE4E16"].map(hex)
        for y in 0 ..< g {
            for x in 0 ..< w {
                let dx = (Double(x) - cx) / 190, dy = (Double(y) - cy) / 62
                let k = Float(exp(-(dx * dx + dy * dy) * 2.1))
                base[y * w + x] = glow[min(5, Int(k * 5.4 + d(x, y)))]
            }
        }
        var gr = SplitMix(seed: 41)
        for _ in 0 ..< 26 {
            let gx = Int(gr.next() * Double(w)), gy = Int(gr.next() * Double(g - 16))
            let shape = glyphs[Int(gr.next() * Double(glyphs.count))]
            for (j, row) in shape.enumerated() {
                for (i, v) in row.enumerated() where v == "#" {
                    for a in 0 ..< 3 { for b in 0 ..< 3 {
                        let x = gx + i * 3 + a, y = gy + j * 3 + b
                        let dx = (Double(x) - cx) / 190, dy = (Double(y) - cy) / 62
                        if x >= 0 && x < w && y >= 0 && y < g && dx * dx + dy * dy < 0.5 { base[y * w + x] = mix(base[y * w + x], hex("#FF6A2A"), 0.06) }
                    } }
                }
            }
        }
        // Vertical light strips.
        strips = stride(from: 9, to: w, by: 27).map { $0 }
        for x in strips { for y in 0 ..< g - 12 { base[y * w + x] = mix(base[y * w + x], hex("#5A3A3A"), 0.5) } }
        // A white line where the wall meets the floor.
        for x in 0 ..< w { base[(g - 12) * w + x] = mix(base[(g - 12) * w + x], hex("#E8D8CC"), 0.35) }

        // Glossy floor: dark, the glow reflected, light lines running to a vanishing point.
        for y in g - 11 ..< h {
            for x in 0 ..< w {
                let dx = (Double(x) - cx) / 200, dy = (Double(y) - Double(g) - 4) / 26
                let k = Float(exp(-(dx * dx + dy * dy) * 2.4)) * 0.5
                var c = mix(hex("#070405"), hex("#5A120C"), Float(Int(k * 4 + d(x, y))) / 4)
                let vx = Double(w) * 0.42, vy = Double(g) - 40
                let ang = atan2(Double(x) - vx, Double(y) - vy)
                if abs(sin(ang * 14)) < 0.05 + 0.002 * Double(y - g + 11) { c = mix(c, hex("#E89A6A"), 0.18) }
                base[y * w + x] = c
            }
        }
        // Contact shadow, the car, and its reflection fading into the floor.
        for y in g - 2 ... g + 1 {
            for x in x0 + 6 ..< x0 + L - 6 where d(x, y) < 0.85 { base[y * w + x] = hex("#040203") }
        }
        bodyAt = []; bodyKey = []; drl = []
        for ly in 0 ..< H {
            for lx in 0 ..< L {
                guard let c = car[ly][lx] else { continue }
                let x = x0 + lx, y = g - 1 - ly
                guard x >= 0 && x < w && y >= 0 && y < h else { continue }
                base[y * w + x] = c
                if body[ly][lx] { bodyAt.append(y * w + x); bodyKey.append(Float(lx) + Float(ly) * 0.7) }
                let ry = g + ly
                if ry < h && ly < 24 {
                    let k = 0.34 * (1 - Float(ly) / 24)
                    if k > d(x, ry) * 0.5 { base[ry * w + x] = mix(base[ry * w + x], c, k) }
                }
            }
        }
        for (lx, ly) in drlLocal { drl.append((g - 1 - ly) * w + x0 + lx) }
        // Into the widget's background.
        for y in g + 8 ..< h {
            let fade = Float(max(0, min(1, Double(y - g - 8) / 20)))
            for x in 0 ..< w where fade > d(x, y) { base[y * w + x] = bgColor }
        }
    }

    // MARK: the car (built once)

    let glyphs: [[String]] = [
        ["######", ".....#", ".....#", ".....#", ".....#", ".....#"],   // ㄱ
        ["#.....", "#.....", "#.....", "#.....", "#.....", "######"],   // ㄴ
        ["######", "#....#", "#....#", "#....#", "#....#", "######"],   // ㅁ
        ["..##..", "######", "......", ".####.", "#....#", ".####."],   // ㅎ
        [".####.", "#....#", "#....#", "#....#", "#....#", ".####."],   // ㅇ
        ["######", ".....#", "######", "#.....", "#.....", "######"],   // ㄹ
        ["#....#", "#....#", "######", "#....#", "#....#", "######"],   // ㅂ
    ]

    func buildCar() {
        car = Array(repeating: Array(repeating: nil, count: L), count: H)
        body = Array(repeating: Array(repeating: false, count: L), count: H)
        func set(_ x: Int, _ y: Int, _ c: C, body b: Bool = false) {
            if x >= 0 && x < L && y >= 0 && y < H { car[y][x] = c; body[y][x] = b }
        }
        func mix(_ a: C, _ b: C, _ k: Float) -> C { C(r: a.r + (b.r - a.r) * k, g: a.g + (b.g - a.g) * k, b: a.b + (b.b - a.b) * k) }
        func scale(_ c: C, _ k: Float) -> C { C(r: min(255, c.r * k), g: min(255, c.g * k), b: min(255, c.b * k)) }
        func dth(_ x: Int, _ y: Int) -> Float { bayer[(y & 3) * 4 + (x & 3)] }

        // Profile: tail to nose. Rear deck, rear arch, engine cover, canopy, windscreen, front arch, nose.
        let prof: [(Double, Double)] = [(0, 26), (6, 30), (18, 32), (32, 35), (44, 33), (58, 33), (70, 37), (80, 42), (88, 45),
                                        (98, 45), (106, 41), (112, 33), (118, 29), (126, 32), (136, 36), (146, 33), (154, 25),
                                        (162, 17), (166, 12), (168, 10)]
        func top(_ x: Double) -> Double {
            for k in 1 ..< prof.count where x <= prof[k].0 {
                let (a, ya) = prof[k - 1], (b, yb) = prof[k]
                return ya + (yb - ya) * (x - a) / (b - a)
            }
            return prof.last!.1
        }
        // Livery: red at the tail through orange to yellow at the nose.
        let livery = ["#C8161D", "#E43A1A", "#FF6A13", "#FF9415", "#FFB21E", "#FFC83A"].map(hex)
        func paint(_ x: Int) -> C {
            let t = Float(x) / Float(L - 1) * Float(livery.count - 1)
            let i = min(livery.count - 2, Int(t))
            return mix(livery[i], livery[i + 1], t - Float(i))
        }
        func shade(_ x: Int, _ y: Int) -> C {
            let tp = top(Double(x) + 0.5)
            let f = Float(Double(y - 4) / max(1, tp - 4))
            let q = Float(Int((0.66 + 0.46 * f) * 10 + dth(x, y) * 0.9)) / 10
            var c = scale(paint(x), q)
            if tp - Double(y) < 1.5 { c = mix(c, hex("#FFF1D8"), 0.45) }        // the light catching the top
            else if tp - Double(y) < 3 { c = scale(c, 1.12) }
            return c
        }
        for x in 0 ..< L {
            let tp = top(Double(x) + 0.5)
            for y in 4 ..< H where Double(y) < tp { set(x, y, shade(x, y), body: true) }
        }
        let carbon = hex("#1A191E"), carbonLit = hex("#34333B"), line = hex("#3A0C08"), well = hex("#0A0708")
        // Floor, splitter, diffuser, and the black lower sidepod between the wheels.
        for x in 3 ..< L - 1 { set(x, 3, carbon); set(x, 4, carbon) }
        for x in 148 ..< L { set(x, 3, carbonLit); set(x, 2, carbon) }
        for x in 0 ..< 13 { for y in 4 ... 9 { set(x, y, (x % 3 == 0) ? carbonLit : carbon) } }
        for x in 50 ..< 120 {
            let hgt = 8 + Int(2 * sin(Double(x - 50) / 70 * .pi))
            for y in 5 ... hgt { set(x, y, y == hgt ? scale(paint(x), 0.75) : carbon) }
        }
        // Panel lines: engine cover seam, door cut, front fender line.
        for x in 40 ... 78 { set(x, 29, scale(shade(x, 29), 0.62)) }
        for y in 10 ... Int(top(108)) - 1 { set(108, y, line) }
        for x in 112 ... 152 { let y = Int(top(Double(x)) - 5); if y > 12 { set(x, y, scale(shade(x, y), 0.7)) } }
        // Louvres on top of the front fender.
        for k in 0 ..< 6 {
            let x = 126 + k * 3
            let y = Int(top(Double(x))) - 1
            set(x, y, carbon); set(x + 1, y - 1, carbon)
        }
        // Cockpit: windscreen and side window with a frame, a glint, the roof light and antenna.
        let glass = hex("#101018"), glassLit = hex("#3E4458"), frame = hex("#1C1214")
        for x in 84 ... 113 {
            let tp = Int(top(Double(x) + 0.5))
            let bottom = x < 90 ? 36 + (90 - x) / 2 : (x > 104 ? 33 + (x - 104) / 3 : 33)
            if bottom >= tp - 1 { continue }
            for y in bottom ..< tp - 1 {
                let edge = y == tp - 2 || y == bottom || x == 84
                let lit = (x - y) % 11 == 0 && y > bottom + 1
                set(x, y, edge ? frame : (lit ? glassLit : glass))
            }
        }
        for y in 34 ... 42 { set(96, y, frame) }                                    // window frame
        for x in 92 ... 97 { set(x, 46, carbon) }
        set(94, 47, hex("#4ADE80")); set(95, 47, hex("#4ADE80"))                    // position light
        for y in 46 ... 50 where y < H { set(90, y, carbon) }                     // antenna
        // Wing mirror on the front fender.
        for x in 115 ... 121 { for y in 35 ... 38 { set(x, y, y == 38 ? hex("#FFE7A8") : (x < 117 ? glass : paint(x)), body: y != 38 && x >= 117) } }
        for y in 31 ... 34 { set(118, y, carbon) }
        // Shark fin from the canopy back to the wing.
        for x in 22 ... 80 {
            let fy = 44 - Int(Double(x - 22) * 0.03)
            for y in Int(top(Double(x))) ... fy where y < H { set(x, y, scale(paint(x), y == fy ? 1.18 : 0.94), body: true) }
        }
        // Rear wing: main plane, a slim flap, a swan-neck pylon, endplate with a stripe.
        for x in 0 ... 28 { set(x, 47, hex("#55545E")); set(x, 46, carbon) }
        for x in 3 ... 22 { set(x, 44, carbonLit) }
        for y in 35 ... 48 { set(17, y, carbon) }
        set(16, 48, carbon); set(18, 48, carbon)
        for y in 24 ... 49 { set(0, y, scale(paint(0), 0.8), body: true); set(1, y, paint(1), body: true); set(2, y, scale(paint(2), 1.1), body: true) }
        for y in 30 ... 46 where y % 4 != 0 { set(1, y, hex("#FFD34D")) }
        // Tail light bar and the light along the rear.
        for y in 20 ... 30 { set(3, y, hex("#FF2A2A")) }
        for x in 3 ... 12 { set(x, 25, hex("#E01818")) }
        // Headlights: two thin lines, the marque's signature, set in a dark housing; a winged badge.
        for x in 152 ... 165 { for y in 16 ... 22 where Double(y) < top(Double(x)) - 1 { set(x, y, hex("#24151A")) } }
        drlLocal = []
        for x in 154 ... 164 { drlLocal.append((x, 21)); drlLocal.append((x - 1, 18)) }
        for (x, y) in drlLocal { set(x, y, hex("#EEF3FF")) }
        let wings = ["##.#.##", ".##.##.", "..###.."]
        for (j, row) in wings.enumerated() { for (i, v) in row.enumerated() where v == "#" { set(143 + i, 26 - j, hex("#ECECF0")) } }
        // Hangul-like graphics laid over the livery, a shade darker.
        var r = SplitMix(seed: 7)
        for _ in 0 ..< 22 {
            let gx = 8 + Int(r.next() * Double(L - 24)), gy = 10 + Int(r.next() * 22)
            let shape = glyphs[Int(r.next() * Double(glyphs.count))]
            for (j, row) in shape.enumerated() {
                for (i, v) in row.enumerated() where v == "#" {
                    let x = gx + i, y = gy + 5 - j
                    if x < L && y < H && body[y][x] { car[y][x] = scale(car[y][x]!, 0.9) }
                }
            }
        }
        // Sponsor stickers: a white tag with a red mark, a shell-yellow dot, a blue and yellow strip.
        for x in 72 ... 78 { for y in 30 ... 33 { set(x, y, hex("#F4F4F6")) } }
        for x in 74 ... 76 { set(x, 31, hex("#D81E2A")); set(x, 32, hex("#D81E2A")) }
        for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1)] { set(84 + dx, 27 + dy, hex("#FFD320")) }
        set(84, 27, hex("#E2231A"))
        for x in 122 ... 130 { set(x, 11, hex("#27509B")); set(x, 12, hex("#FCE300")) }
        // Name along the side, number on the engine cover, both with a dark drop shadow.
        let font: [Character: [String]] = [
            "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
            "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
            "N": ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
            "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
            "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
            "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
            "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        ]
        func write(_ s: String, _ x0: Int, _ yTop: Int, _ c: C, _ shadow: C) {
            for pass in 0 ..< 2 {
                var x = x0
                for ch in s {
                    guard let gl = font[ch] else { continue }
                    for (j, row) in gl.enumerated() {
                        for (i, v) in row.enumerated() where v == "#" {
                            if pass == 0 { set(x + i + 1, yTop - j - 1, shadow) } else { set(x + i, yTop - j, c) }
                        }
                    }
                    x += gl[0].count + 1
                }
            }
        }
        write("GENESIS", 60, 21, hex("#FFD34D"), hex("#5A1308"))
        write("19", 46, 32, hex("#FFFFFF"), hex("#2A0A06"))

        // Wheels: arches cut round them, then tyre, lettering, black spokes, disc and orange caliper.
        for wx in wheelX {
            for y in 0 ..< H {
                for x in 0 ..< L {
                    let dx = Double(x) + 0.5 - wx, dy = Double(y) + 0.5 - wheelR
                    let rr = (dx * dx + dy * dy).squareRoot()
                    if rr < wheelR + 2.2 && car[y][x] != nil { car[y][x] = rr < wheelR + 0.6 ? nil : well; body[y][x] = false }
                }
            }
            for y in 0 ..< Int(wheelR * 2) + 1 {
                for x in Int(wx - wheelR) - 1 ... Int(wx + wheelR) + 1 {
                    let dx = Double(x) + 0.5 - wx, dy = Double(y) + 0.5 - wheelR
                    let rr = (dx * dx + dy * dy).squareRoot()
                    if rr > wheelR + 0.4 { continue }
                    let a = atan2(dy, dx)            // y is up: a = pi/2 at the top
                    var c: C
                    if rr > wheelR - 1.6 { c = hex("#121114") }
                    else if rr > 11 {
                        c = hex("#1E1D22")
                        let mark = (a > 1.9 && a < 2.7) || (a < -0.5 && a > -1.3)
                        if mark && rr > 12 && rr < 13.6 && sin(a * 38) > -0.2 { c = hex("#E8C440") }
                    } else if rr > 2.6 {
                        let m = (a / (2 * .pi / 10)).truncatingRemainder(dividingBy: 1)
                        let spoke = abs(m) < 0.16 || abs(m) > 0.84
                        if spoke { c = rr > 9.8 ? hex("#2A2A30") : (a > 1 && a < 2.8 ? hex("#55545D") : hex("#2E2D34")) }
                        else if rr > 5.2 && rr < 9.8 && a > 1.7 && a < 2.9 { c = hex("#FF7A1A") }                   // caliper
                        else { c = rr > 4 && rr < 9.6 ? hex("#3A3A41") : hex("#18171B") }                              // disc
                    } else { c = rr < 1.4 ? hex("#FFD34D") : hex("#E06A12") }                                       // centre lock
                    set(x, y, c)
                }
            }
        }
        // A dark outline round the whole shape.
        let solid = car.map { $0.map { $0 != nil } }
        let edge = hex("#060304")
        for y in 1 ..< H {
            for x in 0 ..< L where !solid[y][x] {
                func s(_ a: Int, _ b: Int) -> Bool { a >= 0 && a < L && b >= 0 && b < H && solid[b][a] }
                if s(x - 1, y) || s(x + 1, y) || s(x, y - 1) || s(x, y + 1) { car[y][x] = edge }
            }
        }
    }
}
