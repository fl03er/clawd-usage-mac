// The Black hole theme's backdrop: a Schwarzschild black hole with a thin accretion disc,
// in 1-point pixels with ordered dithering. Light is ray traced round the hole once per
// widget width, so the far side of the disc shows over and under the shadow, a thin
// photon ring hugs its edge and the stars behind are lensed. Every frame the disc turns
// (faster inside than out), the side coming towards us is brighter and whiter (Doppler
// beaming, from the same rays), and a jet streams from the pole, its twin behind the
// disc fainter. The colours of the disc's rim and the dust lane nod to the SleighRide site.

import AppKit
import simd

final class BlackHole {
    // Geometry, in Schwarzschild radii (the horizon is r = 1).
    struct Params {
        var unit = 5.5                         // points per Schwarzschild radius
        var incl = 81.5 * Double.pi / 180      // line of sight against the disc's axis (90 = edge on)
        var roll = -12.0 * Double.pi / 180      // the picture's tilt
        var dist = 100.0                       // camera distance
        var rIn = 3.0, rOut = 30.0             // innermost stable orbit, outer edge
        var spin = 1.0                         // which way the disc turns
    }
    struct Lut {
        var w = 0, h = 0, cx = 0.0, cy = 0.0
        var hitStart: [Int32] = []            // hits of pixel i: hitStart[i] ..< hitStart[i + 1]
        var hitRow: [Int32] = [], hitPhi: [Float] = [], hitOmega: [Float] = [], hitAmp: [Float] = []
        var trans: [Float] = []               // what the disc and the shadow let through from behind
        var tint: [Float] = []                // 0 warm .. 1 blue-white, from the Doppler shift
        var star: [Float] = [], starPhase: [Float] = [], haze: [Float] = []
    }

    let p = Params()
    let maxH = 820
    static let nr = 128, nphi = 1024
    let tex: [Float]
    let jetNoise: [Float]
    var lut: Lut? = nil
    var building = false
    var ctx: CGContext? = nil
    var emit: [Float] = [], glow: [Float] = [], glowTmp: [Float] = []
    let t0 = Date.timeIntervalSinceReferenceDate

    // Hot inner disc to cool rim: white, gold, orange, a red that turns to the site's pink, then nothing.
    let warm: [RGBA] = ["#000000", "#1C0510", "#360A1C", "#561226", "#7A1D24", "#A12F1E", "#C44A1A", "#E06A1F",
                        "#F28A2E", "#FBAB47", "#FFCB78", "#FFE6B8", "#FFF6E6", "#FFFFFF", "#FFFFFF"].map(RGBA.init(opaque:))
    // The side coming towards us: the same, the hot end shifted blue-white.
    let cool: [RGBA] = ["#000000", "#1C0510", "#360A1C", "#561226", "#7A1D24", "#A12F1E", "#C44A1A", "#E36F25",
                        "#F49A42", "#FCC070", "#FFE0B0", "#FAF1E6", "#EEF2FF", "#F8FAFF", "#FFFFFF"].map(RGBA.init(opaque:))
    let jetRamp: [RGBA] = ["#000000", "#0A1430", "#14275E", "#22409A", "#3D63CF", "#6A8DEB", "#98B4F7", "#C4D6FF", "#E6EEFF", "#FFFFFF"].map(RGBA.init(opaque:))
    // The jet's strands: phase round the axis, how fast they wind with height, how fast they swirl.
    let strands: [(Float, Float, Float)] = (0 ..< 10).map { (k: Int) -> (Float, Float, Float) in
        let f = Float(k)
        let phase: Float = f * 0.628 + 0.5 * sin(f * 1.7)
        let wind: Float = 0.07 + 0.015 * Float(k % 3)
        let swirl: Float = 1.6 + 0.35 * Float(k % 4)
        return (phase, wind, swirl)
    }
    let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { (Float($0) + 0.5) / 16 }
    let bg = RGBA(opaque: "#06040A"), hazeColor = RGBA(opaque: "#C2479A"), hazeColor2 = RGBA(opaque: "#6D5FD8")

    init() {
        tex = BlackHole.makeTexture(p)
        var g = SplitMix(seed: 77)
        let raw = (0 ..< 64).map { _ in g.next() }
        // Knots along the jet: smooth noise, periodic over 512 samples.
        jetNoise = (0 ..< 512).map { i in
            let x = Double(i) / 8, i0 = Int(x) % 64, f = x - Double(Int(x)), s = f * f * (3 - 2 * f)
            let v = raw[i0] * (1 - s) + raw[(i0 + 1) % 64] * s
            return Float(0.35 + 1.3 * v * v)
        }
    }

    // MARK: drawing

    func draw(in r: CGRect, hero: CGRect) {
        let w = Int(r.width.rounded()), h = min(maxH, Int(r.height.rounded()))
        bg.ns.setFill()
        NSBezierPath(rect: r).fill()
        guard w > 0, h > 0 else { return }
        guard let L = lut, L.w == w else {
            if !building {
                building = true
                let p = self.p, mh = maxH, cx = Double(w) * 0.63, cy = hero.minY + hero.height * 0.3 - r.minY
                DispatchQueue.global(qos: .userInitiated).async {
                    let l = BlackHole.build(p, w: w, h: mh, cx: cx, cy: cy)
                    DispatchQueue.main.async { self.lut = l; self.building = false }
                }
            }
            return
        }
        if ctx == nil || ctx!.width != w || ctx!.height != h {
            ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            emit = Array(repeating: 0, count: w * h)
        }
        guard let ctx, let data = ctx.data else { return }
        let t = Date.timeIntervalSinceReferenceDate - t0
        render(L, w: w, h: h, t: t, out: data.assumingMemoryBound(to: UInt8.self))
        guard let cg = ctx.makeImage() else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cg, size: NSSize(width: w, height: h))
            .draw(in: CGRect(x: r.minX, y: r.minY, width: Double(w), height: Double(h)), from: .zero,
                  operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    func render(_ L: Lut, w: Int, h: Int, t: Double, out: UnsafeMutablePointer<UInt8>) {
        let nphi = BlackHole.nphi
        // The disc turns each radius at its own speed; two copies of the texture, wound for
        // half a cycle apart, cross-fade so it never winds up too tight.
        let cycle = 7.0, speed = 7.5
        let c1 = t / cycle, c2 = t / cycle + 0.5
        let f1 = c1 - c1.rounded(.down), f2 = c2 - c2.rounded(.down)
        let tau1 = Float(f1 * cycle * speed), tau2 = Float(f2 * cycle * speed)
        let sh1 = Float(c1.rounded(.down) * 2.3), sh2 = Float(c2.rounded(.down) * 2.3 + 1.1)
        let w1 = Float(1 - abs(2 * f1 - 1)), w2 = 1 - w1
        let toIdx = Float(nphi) / (2 * .pi)

        // Disc light per pixel.
        tex.withUnsafeBufferPointer { tx in
        L.hitStart.withUnsafeBufferPointer { hs in
        L.hitRow.withUnsafeBufferPointer { hr in
        L.hitPhi.withUnsafeBufferPointer { hp in
        L.hitOmega.withUnsafeBufferPointer { ho in
        L.hitAmp.withUnsafeBufferPointer { ha in
        emit.withUnsafeMutableBufferPointer { e in
            for i in 0 ..< w * h {
                var s: Float = 0
                var k = Int(hs[i])
                let end = Int(hs[i + 1])
                while k < end {
                    let row = Int(hr[k]) * nphi, ph = hp[k], om = ho[k]
                    let a = Int((ph - om * tau1 + sh1) * toIdx + 1_000_000) & (nphi - 1)
                    let b = Int((ph - om * tau2 + sh2) * toIdx + 1_000_000) & (nphi - 1)
                    s += ha[k] * (w1 * tx[row + a] + w2 * tx[row + b])
                    k += 1
                }
                e[i] = s
            }
        }}}}}}}

        // A soft glow round the bright parts: blur a quarter-size copy.
        let gw = w / 4 + 2, gh = h / 4 + 2
        if glow.count != gw * gh { glow = Array(repeating: 0, count: gw * gh); glowTmp = glow }
        for i in 0 ..< glow.count { glow[i] = 0 }
        emit.withUnsafeBufferPointer { e in
            for y in 0 ..< h { for x in 0 ..< w { glow[(y >> 2) * gw + (x >> 2)] += e[y * w + x] / 16 } }
        }
        for _ in 0 ..< 2 { boxBlur(&glow, &glowTmp, gw, gh, 2) }

        // Compose: background, dithered disc, jet, lensed stars and dust.
        let ca = Float(cos(p.roll)), sa = Float(sin(p.roll))
        let cx = Float(L.cx), cy = Float(L.cy)
        let tf = Float(t)
        let exposure: Float = 2.0, glowK: Float = 0.9
        let nW = Float(warm.count - 1), nJ = Float(jetRamp.count - 1)
        let bgR = Float(bg.r * 255), bgG = Float(bg.g * 255), bgB = Float(bg.b * 255)
        let warmC = warm.map { (Float($0.r * 255), Float($0.g * 255), Float($0.b * 255)) }
        let coolC = cool.map { (Float($0.r * 255), Float($0.g * 255), Float($0.b * 255)) }
        let jetC = jetRamp.map { (Float($0.r * 255), Float($0.g * 255), Float($0.b * 255)) }
        let hz1 = (Float(hazeColor.r * 255), Float(hazeColor.g * 255), Float(hazeColor.b * 255))
        let hz2 = (Float(hazeColor2.r * 255), Float(hazeColor2.g * 255), Float(hazeColor2.b * 255))
        emit.withUnsafeBufferPointer { e in
        glow.withUnsafeBufferPointer { gl in
        jetNoise.withUnsafeBufferPointer { jn in
        L.trans.withUnsafeBufferPointer { tr in
        L.tint.withUnsafeBufferPointer { tn in
        L.star.withUnsafeBufferPointer { st in
        L.starPhase.withUnsafeBufferPointer { sp in
        L.haze.withUnsafeBufferPointer { hz in
            for y in 0 ..< h {
                let gy = (Float(y) + 0.5) / 4 - 0.5
                let gy0 = max(0, min(gh - 2, Int(gy))), fy = max(0, min(1, gy - Float(gy0)))
                for x in 0 ..< w {
                    let i = y * w + x
                    let d = bayer[(y & 3) * 4 + (x & 3)]
                    // Glow, bilinear from the quarter-size copy.
                    let gx = (Float(x) + 0.5) / 4 - 0.5
                    let gx0 = max(0, min(gw - 2, Int(gx))), fx = max(0, min(1, gx - Float(gx0)))
                    let g00 = gl[gy0 * gw + gx0], g10 = gl[gy0 * gw + gx0 + 1]
                    let g01 = gl[(gy0 + 1) * gw + gx0], g11 = gl[(gy0 + 1) * gw + gx0 + 1]
                    let gv = (g00 * (1 - fx) + g10 * fx) * (1 - fy) + (g01 * (1 - fx) + g11 * fx) * fy
                    // Inside the shadow the glow is faint: the hole stays black.
                    let v = 1 - exp(-exposure * (e[i] + glowK * gv * (tr[i] > 0 || e[i] > 0 ? 1 : 0.3)))
                    let di = min(Int(nW), Int(v * nW + d))
                    let tw = tn[i]
                    var r = bgR + warmC[di].0 + (coolC[di].0 - warmC[di].0) * tw
                    var g = bgG + warmC[di].1 + (coolC[di].1 - warmC[di].1) * tw
                    var b = bgB + warmC[di].2 + (coolC[di].2 - warmC[di].2) * tw

                    // The jet: thin strands wound round the picture's tilted vertical axis, swirling
                    // as they rise; the near side of each turn is brighter. White-hot at the base.
                    let dx = Float(x) + 0.5 - cx, dy = cy - (Float(y) + 0.5)
                    let along = dx * sa + dy * ca, across = dx * ca - dy * sa
                    let s = abs(along)
                    let cone = 2.0 + 0.2 * s
                    if s < 420 && abs(across) < cone + 6 {
                        let ac = along > 0 ? across : -across
                        var fil: Float = 0
                        for k in 0 ..< strands.count {
                            let (ph, wind, spin) = strands[k]
                            let a = ph + wind * s - spin * tf
                            let q = (ac - cone * sin(a)) / (0.45 + 0.012 * s)
                            if q * q < 9 {
                                fil += exp(-q * q) * (0.3 + 0.7 * max(0, cos(a))) * jn[(Int(s * 0.35 - tf * 16) + k * 67 + 100_000) & 511]
                            }
                        }
                        let sheath = 0.3 * exp(-(across * across) / (cone * cone))
                        let env = min(1, s / 10) * exp(-s / 110)
                        let base = 3.2 * exp(-s / 9) * exp(-(across * across) / (4 + 0.6 * s))
                        // The one going away is dimmer and hides behind the disc and the shadow.
                        let side: Float = along > 0 ? 1 : 0.16 * tr[i] * exp(-s / 40)
                        let jv = 1 - exp(-1.0 * ((fil + sheath) * env * 1.4 + base) * side)
                        if jv >= 0.04 {
                            let ji = min(Int(nJ), Int(jv * nJ + d))
                            r += jetC[ji].0; g += jetC[ji].1; b += jetC[ji].2
                        }
                    }
                    // Stars and the dust lane behind, bent round the hole.
                    let hv = hz[i]
                    if hv > 0 {
                        let m = max(0, min(1, hv * 3 - 0.2))
                        let a = hv * 255
                        r += a * (hz1.0 + (hz2.0 - hz1.0) * m) / 255
                        g += a * (hz1.1 + (hz2.1 - hz1.1) * m) / 255
                        b += a * (hz1.2 + (hz2.2 - hz1.2) * m) / 255
                    }
                    let sv = st[i]
                    if sv > 0 {
                        let a = sv * (0.55 + 0.45 * sin(tf * 2.1 + sp[i])) * 255
                        r += a; g += a * 0.95; b += a * (0.88 + 0.2 * sp[i] / 6.3)
                    }
                    let o = i * 4
                    out[o] = UInt8(min(255, r)); out[o + 1] = UInt8(min(255, g)); out[o + 2] = UInt8(min(255, b)); out[o + 3] = 255
                }
            }
        }}}}}}}}
    }

    func boxBlur(_ a: inout [Float], _ tmp: inout [Float], _ w: Int, _ h: Int, _ rad: Int) {
        let n = Float(2 * rad + 1)
        for y in 0 ..< h {
            for x in 0 ..< w {
                var s: Float = 0
                for k in -rad ... rad { s += a[y * w + max(0, min(w - 1, x + k))] }
                tmp[y * w + x] = s / n
            }
        }
        for y in 0 ..< h {
            for x in 0 ..< w {
                var s: Float = 0
                for k in -rad ... rad { s += tmp[max(0, min(h - 1, y + k)) * w + x] }
                a[y * w + x] = s / n
            }
        }
    }

    // MARK: ray tracing (once per width, off the main thread)

    static func build(_ p: Params, w: Int, h: Int, cx: Double, cy: Double) -> Lut {
        var L = Lut()
        L.w = w; L.h = h; L.cx = cx; L.cy = cy
        let n = w * h
        L.hitStart = [0]; L.hitStart.reserveCapacity(n + 1)
        L.trans = Array(repeating: 1, count: n); L.tint = Array(repeating: 0, count: n)
        L.star = Array(repeating: 0, count: n); L.starPhase = Array(repeating: 0, count: n); L.haze = Array(repeating: 0, count: n)

        // Camera: up is the disc's axis as seen from the side, right completes the frame.
        let fwd = SIMD3(0, cos(p.incl), sin(p.incl))          // from the hole to the camera
        let up = SIMD3(0, sin(p.incl), -cos(p.incl))
        let right = SIMD3(1.0, 0, 0)
        let cam = fwd * p.dist
        let perRad = p.unit * p.dist                          // points per radian
        let fMax = flux(49.0 / 36 * p.rIn, p.rIn)
        let band = simd_normalize(SIMD3(0.55, 0.35, -0.75))   // the dust lane's plane

        for y in 0 ..< h {
            for x in 0 ..< w {
                let i = y * w + x
                let dx = Double(x) + 0.5 - cx, dy = cy - (Double(y) + 0.5)
                let a = dx * cos(p.roll) - dy * sin(p.roll), b = dx * sin(p.roll) + dy * cos(p.roll)
                let dir = simd_normalize(-fwd + right * (a / perRad) + up * (b / perRad))
                let lEmit = -(cam.z * dir.x - cam.x * dir.z)  // the photon's angular momentum round the axis
                var hits: [(Double, Double)] = []
                let end = trace(cam, dir, rIn: p.rIn, rOut: p.rOut, escape: p.dist * 1.5) { r, phi in hits.append((r, phi)) }

                var T = 1.0, best = 0.0
                for (r, phi) in hits {
                    let om = (0.5 / (r * r * r)).squareRoot()
                    let g = (1 - 1.5 / r).squareRoot() / max(0.1, 1 - p.spin * om * lEmit)
                    let edge = 1 - smooth(p.rOut * 0.6, p.rOut, r)
                    let emitted = pow(flux(r, p.rIn) / fMax, 0.32) * g * g * g * edge
                    let alpha = 0.04 + 0.92 * (1 - smooth(p.rOut * 0.45, p.rOut, r))
                    let amp = T * alpha * emitted
                    if amp > best { best = amp; L.tint[i] = Float(max(0, min(1, (g - 1.02) / 0.3))) }
                    L.hitRow.append(Int32(max(0, min(nr - 1, Int((r - p.rIn) / (p.rOut - p.rIn) * Double(nr))))))
                    L.hitPhi.append(Float(phi))
                    L.hitOmega.append(Float(p.spin * om))
                    L.hitAmp.append(Float(amp))
                    T *= 1 - alpha
                }
                L.hitStart.append(Int32(L.hitRow.count))
                guard let out = end else { L.trans[i] = 0; continue }   // fell in
                L.trans[i] = Float(T)

                // Stars: one cell per point of sky as the camera sees it straight ahead.
                let th = acos(max(-1, min(1, out.y))), ps = atan2(out.z, out.x)
                let ci = Int((th * perRad).rounded(.down)), cj = Int((ps * perRad * sin(th)).rounded(.down))
                var rng = SplitMix(seed: UInt64(bitPattern: Int64(ci &* 73856093 ^ cj &* 19349663)))
                if rng.next() < 0.0065 {
                    let s = rng.next()
                    L.star[i] = Float(T * (0.3 + 0.7 * s * s * s))
                    L.starPhase[i] = Float(rng.next() * 6.28)
                }
                // A faint dust lane, clumpy.
                let off = simd_dot(out, band)
                let w1: Double = sin(out.x * 23 + 4 * sin(out.z * 17))
                let w2: Double = sin(out.y * 19 + out.z * 7)
                let clump = 0.55 + 0.45 * w1 * w2
                L.haze[i] = Float(T * 0.11 * exp(-off * off / 0.012) * clump)
            }
        }
        return L
    }

    // Light near a Schwarzschild hole (r_s = 1) bends like a particle pulled by 3/2 h² / r⁴,
    // h its angular momentum; RK4 with steps that shrink near the hole. Reports each time the
    // ray crosses the disc's plane within the disc, returns where it escapes to (nil: captured).
    static func trace(_ p0: SIMD3<Double>, _ d0: SIMD3<Double>, rIn: Double, rOut: Double, escape: Double,
                      hit: (Double, Double) -> Void) -> SIMD3<Double>? {
        var p = p0, v = d0
        let hv = simd_cross(p, v)
        let k = 1.5 * simd_dot(hv, hv)
        @inline(__always) func acc(_ q: SIMD3<Double>) -> SIMD3<Double> {
            let r2 = simd_dot(q, q)
            return q * (-k / (r2 * r2 * r2.squareRoot()))
        }
        var n = 0
        for _ in 0 ..< 6000 {
            let r = simd_length(p)
            if r < 1.0 { return nil }
            if r > escape && simd_dot(p, v) > 0 { return simd_normalize(v) }
            let dt = max(0.015, min(8, 0.05 * r * min(1, 2 * (r - 1))))
            let a1 = acc(p), p2 = p + v * (dt / 2), v2 = v + a1 * (dt / 2)
            let a2 = acc(p2), p3 = p + v2 * (dt / 2), v3 = v + a2 * (dt / 2)
            let a3 = acc(p3), p4 = p + v3 * dt, v4 = v + a3 * dt
            let a4 = acc(p4)
            let sv: SIMD3<Double> = v + v4 + (v2 + v3) * 2.0
            let sa: SIMD3<Double> = a1 + a4 + (a2 + a3) * 2.0
            let pn = p + sv * (dt / 6)
            let vn = v + sa * (dt / 6)
            if (p.y > 0) != (pn.y > 0) && n < 3 {
                let f = p.y / (p.y - pn.y)
                let c = p + (pn - p) * f
                let rc = (c.x * c.x + c.z * c.z).squareRoot()
                if rc >= rIn && rc <= rOut { hit(rc, atan2(-c.z, c.x)); n += 1 }
            }
            p = pn; v = vn
        }
        return nil
    }

    // A thin disc's brightness (Shakura-Sunyaev / Novikov-Thorne, Newtonian form).
    static func flux(_ r: Double, _ rIn: Double) -> Double { max(0, (1 - (rIn / r).squareRoot()) / (r * r * r)) }
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double { BlackHole.smooth(a, b, x) }

    // The disc's texture in (radius, angle): streaks drawn out along the orbit and wound into
    // a loose spiral, gaps and bright lanes between rings; periodic in angle.
    static func makeTexture(_ p: Params) -> [Float] {
        var t = [Float](repeating: 0, count: nr * nphi)
        var rng = SplitMix(seed: 2026)
        let lat = (0 ..< 64 * 256).map { _ in rng.next() }
        func vnoise(_ u: Double, _ v: Double, _ period: Int) -> Double {
            let x = u * Double(period), x0 = Int(x.rounded(.down)), fx = x - Double(x0)
            let y0 = Int(v.rounded(.down)), fy = v - Double(y0)
            func at(_ i: Int, _ j: Int) -> Double { lat[(((j % 256) + 256) % 256) * 64 + (((i % period) + period) % period) % 64] }
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            let a = at(x0, y0) * (1 - sx) + at(x0 + 1, y0) * sx
            let b = at(x0, y0 + 1) * (1 - sx) + at(x0 + 1, y0 + 1) * sx
            return a * (1 - sy) + b * sy
        }
        // Periodic 1-D noise over `arms` cells, so the spiral closes on itself round the disc.
        let arms = 23
        let sl = (0 ..< 64).map { _ in rng.next() }
        func streak(_ x: Double) -> Double {
            let x0 = Int(x.rounded(.down)), f = x - Double(x0), s = f * f * (3 - 2 * f)
            let m = arms
            let a = sl[((x0 % m) + m) % m], b = sl[(((x0 + 1) % m) + m) % m]
            let v = a * (1 - s) + b * s
            return v * v
        }
        for ir in 0 ..< nr {
            let r = p.rIn + (Double(ir) + 0.5) / Double(nr) * (p.rOut - p.rIn)
            // Rings: 1-D noise across the radius.
            let rings = 0.6 * vnoise(0, r * 3.2, 1) + 0.4 * vnoise(0, r * 8 + 40, 1)
            for j in 0 ..< nphi {
                let u = Double(j) / Double(nphi) + 0.32 * log(r)
                var f = 0.0, amp = 0.5, per = 6, rs = 1.9
                for o in 0 ..< 4 {
                    f += amp * vnoise(u, r * rs + Double(o) * 31, per)
                    amp *= 0.5; per *= 2; rs *= 2
                }
                // Fine streaks along a trailing spiral; as the disc turns they slide inwards.
                let sp = 40 * log(r) - Double(arms) * Double(j) / Double(nphi)
                let st = 0.6 * streak(sp) + 0.4 * streak(sp * 2 + 11)
                let v = 0.4 * f / 0.9375 + 0.2 * rings + 0.4 * st
                t[ir * nphi + j] = Float(0.15 + 2.0 * v * v * (0.55 + 0.9 * st))
            }
        }
        return t
    }
}
