// Clawd sprite: glyphs, poses and Claude Code animations (ported from lib/mascot.ps1).

import AppKit


let clawdColor = NSColor(srgbRed: 0xD7 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)
let gridW = 18, gridH = 12

// Glyph quadrants as bits: 1 top-left, 2 top-right, 4 bottom-left, 8 bottom-right.
let quad: [Character: Int] = [" ": 0, "█": 15, "▀": 3, "▄": 12, "▌": 5, "▐": 10, "▘": 1, "▝": 2,
                              "▖": 4, "▗": 8, "▛": 7, "▜": 11, "▙": 13, "▟": 14]
let armGlyphs: [String: (String, String, String, String)] = [
    "down":  (" ▐", "", "▝▜", "█▀"),
    "up":    ("▗▟", "▄", " ▜", "█▘"),
    "right": (" ▐", "▄", "▝▜", "█▘"),
    "left":  ("▗▟", "", " ▜", "█▀"),
]
let feetGlyphs = ["both": " ▝▝   ▝▝ ", "left": " ▝▝      ", "right": "      ▝▝ "]
let facingRows: [String: [(String, Int, Int)]] = [
    "right-12": [(" ▐█▜██▛█ ", 2, 8), ("▝▜██████▀", 2, 7), (" ▝▝   ▝▝ ", 0, 0)],
    "right-30": [("  █▛██▛▌ ", 2, 7), (" ▝█████▛ ", 2, 7), ("  ▘▘  ▘▘ ", 0, 0)],
    "right-55": [("  ▐█▛█▜  ", 3, 7), ("  ▐████  ", 3, 7), ("  ▝▝ ▝▝  ", 0, 0)],
    "right-75": [("   ██▛▌  ", 3, 6), ("   ███▌  ", 3, 6), ("   ▘  ▘  ", 0, 0)],
    "edge":     [("   ▐██   ", 4, 6), ("   ▐██   ", 4, 6), ("   ▝ ▝   ", 0, 0)],
    "back-105": [("   ███▌  ", 3, 6), ("   ███▌  ", 3, 6), ("   ▘  ▘  ", 0, 0)],
    "back-125": [("  ▐████  ", 3, 7), ("  ▐████  ", 3, 7), ("  ▝▝ ▝▝  ", 0, 0)],
    "back-150": [("  █████▌ ", 2, 7), (" ▝█████▛ ", 2, 7), ("  ▘▘  ▘▘ ", 0, 0)],
    "back":     [(" ▐██████ ", 2, 8), ("▝▜██████▀", 2, 7), (" ▝▝   ▝▝ ", 0, 0)],
    "left-75":  [("   ▛██▌  ", 3, 6), ("   ███▌  ", 3, 6), ("   ▘  ▘  ", 0, 0)],
    "left-55":  [("  ▐▜▛██  ", 3, 7), ("  ▐████  ", 3, 7), ("  ▝▝ ▝▝  ", 0, 0)],
    "left-30":  [("  ▛██▛█▌ ", 2, 7), (" ▝█████▛ ", 2, 7), ("  ▘▘  ▘▘ ", 0, 0)],
    "left-12":  [(" ▐▛███▜█ ", 2, 8), ("▝▜██████▀", 2, 7), (" ▝▝   ▝▝ ", 0, 0)],
]
// Black pixels "dx,dy" from the top-left of each eye cell; ";" separates left/right eye.
let eyeShapes: [String: String] = [
    "open": "1,2 1,3", "left": "0,0 0,1", "right": "2,0 2,1", "closed": "0,3 1,3",
    "blink": "0,3 1,3", "wink": "1,2 1,3;0,3 1,3", "happy": "0,3 1,2 2,3", "focus": "1,3",
    "wide": "0,1 1,1 0,2 1,2 0,3 1,3", "x": "0,1 2,1 1,2 0,3 2,3", "yawn": "0,3 1,3",
    "gasp": "0,1 2,1 1,2 0,3 2,3",   // crosses with an open mouth - the soul leaving
]

struct Frame {
    var eyes = "open", arms = "down", feet = "both"
    var look = 0, flip = false, lift = 0.0, off = 0, x = 0
    var facing = "", poof = "", shadow = ""
    var dig = 0, spray = 0
    var soul = 0.0, soulT = 0   // soul height above the mouth (not part of the geometry key)
    var key: String { "\(eyes)|\(arms)|\(feet)|\(look)|\(flip)|\(off)|\(x)|\(facing)|\(poof)|\(shadow)|\(dig)|\(spray)" }
}

let poses = ["default": "open/down/both", "arms-up": "open/up/both",
             "look-left": "left/down/both", "look-right": "right/down/both"]

func F(_ pose: String, _ n: Int = 1, off: Int = 0, x: Int = 0, poof: String = "", shadow: String = "") -> [Frame] {
    var f = Frame()
    f.off = off; f.x = x; f.poof = poof; f.shadow = shadow
    if pose.hasPrefix("face:") {
        f.facing = String(pose.dropFirst(5))
    } else {
        let p = (poses[pose] ?? pose).split(separator: "/").map(String.init)
        f.eyes = p[0]; f.arms = p[1]; f.feet = p[2]
    }
    return Array(repeating: f, count: n)
}
func turnSeq(_ list: [String], shadow: String = "") -> [Frame] { list.flatMap { F("face:" + $0, shadow: shadow) } }

// Animations from Claude Code, 60 ms per frame.
let clawdSeqs: [String: [Frame]] = {
    let cr = F("default", off: 1, poof: "dot") + F("default", off: 1, poof: "wave")
    let bo = F("default")
    let ts = F("closed/down/both") + bo
    let jump = cr + F("arms-up", 3) + bo + cr + F("arms-up", 3) + bo
    var waddle = F("look-right", x: -9)
    for u in -6 ... -1 { waddle += F("right/down/\(u % 2 == 0 ? "left" : "right")", 2, x: u) }
    return [
        "jump": jump,
        "look": F("look-right", 5) + F("look-left", 5) + bo,
        "celebrate": jump + F("default", 3, off: 1),
        "skip": F("default", off: 1, x: -9) + F("arms-up", 2, x: -6) + F("default", x: -6) +
            F("default", off: 1, x: -6) + F("arms-up", 2, x: -3) + F("default", x: -3) +
            F("default", off: 1, x: -3) + F("arms-up", 2) + cr + bo,
        "spin": F("look-left", 2) + F("look-right", 2) + F("look-left", 2) + F("arms-up", 3) + bo,
        "peekaboo": F("default", off: 3) + F("default", 3, off: 2) + F("look-right", 3, off: 2) +
            F("look-left", 3, off: 2) + F("default", 2, off: 2) + F("default", off: 1) +
            F("arms-up", 4) + F("default", 2) + ts,
        "drop": F("arms-up", off: -3) + F("arms-up", 2, off: -2) + F("arms-up", 2, off: -1) +
            F("arms-up") + cr + F("default", 3) + ts,
        "waddle": waddle + F("look-right", 2) + F("default", 2) + ts,
        "peek": F("look-right", x: -9) + F("look-right", 5, x: -6) + F("look-right", 3, x: -9) +
            F("look-right", 4, x: -5) + F("arms-up", 2, x: -3) + F("arms-up", 2) + cr + bo,
        "wink": F("wink/down/both", 5) + bo,
        "boop": F("closed/down/both", off: 1, poof: "dot") + F("closed/down/both", 2, off: 1, poof: "wave") +
            F("look-left", 4) + F("default", 2) + ts,
        "tap": F("open/down/left", 2) + F("open/down/right", 2) + F("open/down/left", 2) +
            F("open/down/right", 2) + F("open/down/left") + F("open/down/right") + F("arms-up", 3) + bo,
        "sneeze": F("closed/up/both", 4) + F("closed/down/both", 2, off: 1, poof: "wave") +
            F("closed/down/both", 2) + F("default", 2) + ts,
        "turn": turnSeq(["right-12", "right-30", "right-55", "right-75", "edge"]) +
            turnSeq(["back-105", "back-125", "back-150", "back", "back"]) +
            turnSeq(["back-150", "back-125", "back-105", "edge"]) +
            turnSeq(["left-75", "left-55", "left-30", "left-12"]) + bo,
        "coin-hop": F("default", 2, off: 1) + F("arms-up", shadow: "wide") +
            turnSeq(["right-55", "edge", "back-125", "back"], shadow: "narrow") +
            turnSeq(["back-125", "edge", "left-55"], shadow: "narrow") +
            F("arms-up", shadow: "wide") + cr + bo,
    ]
}()
let customActLen = ["wave": 24, "stretch": 22, "yawn": 22, "stumble": 20, "burrow": 30, "unburrow": 28, "stir": 22, "soul": 66]
// On click: everything that starts in place (no slide-in), as in Claude Code.
let clickActs = clawdSeqs.keys.filter { clawdSeqs[$0]![0].x == 0 && $0 != "celebrate" }.sorted()
let burrowDig = 4

// Pixel rectangles in grid units (x in pixel columns, y in pixel rows).
struct Geo { var body: [CGRect] = [], eyes: [CGRect] = [], fx: [CGRect] = [], sand: [CGRect] = [] }

func buildGeo(_ f: Frame) -> Geo {
    let W = gridW, H = gridH
    var g = Array(repeating: Array(repeating: 0, count: H), count: W)   // 0 empty, 1 body, 2 black
    func paint(_ glyphs: String, _ col: Int, _ row: Int, _ mode: String) {
        for (i, c) in glyphs.enumerated() {
            let fg = mode == "lid" ? 2 : 1
            let bg = mode == "eyes" ? 2 : (mode == "lid" ? 1 : 0)
            for sy in 0 ..< 4 {
                for sx in 0 ..< 2 {
                    let bit = (sy < 2 ? 1 : 4) * (sx == 1 ? 2 : 1)
                    let on = c == "▂" ? sy == 3 : ((quad[c] ?? 0) & bit) != 0
                    let v = on ? fg : bg
                    let gx = 2 * (col + i) + sx, gy = 4 * row + sy
                    if v != 0 && gx < W && gy < H { g[gx][gy] = v }
                }
            }
        }
    }
    if !f.facing.isEmpty, let rows = facingRows[f.facing] {
        for (r, (s, from, to)) in rows.enumerated() {
            let a = Array(s)
            paint(String(a[0 ..< from]), 0, r, "")
            paint(String(a[from ..< to]), from, r, "eyes")
            paint(String(a[to...]), to, r, "")
        }
    } else {
        let a = armGlyphs[f.arms]!
        paint(a.0, 0, 0, ""); paint("██████", 2, 0, "eyes"); paint(a.1, 8, 0, "")
        paint(a.2, 0, 1, ""); paint("█████", 2, 1, "eyes"); paint(a.3, 7, 1, "")
        paint(feetGlyphs[f.feet]!, 0, 2, "")
        // Looking sideways with normal eyes uses Claude Code's poses; other expressions shift the pupils.
        var eyes = f.eyes, shift = 0
        if eyes == "open" && f.look < 0 { eyes = "left" }
        else if eyes == "open" && f.look > 0 { eyes = "right" }
        else if !["open", "left", "right", "wink"].contains(eyes) { shift = f.look }
        let sh = (eyeShapes[eyes] ?? eyeShapes["open"]!).split(separator: ";").map(String.init)
        let ex = [4, 12]
        for k in 0 ..< 2 {
            for pt in sh[min(k, sh.count - 1)].split(separator: " ") {
                let d = pt.split(separator: ",").compactMap { Int($0) }
                let gx = ex[k] + d[0] + shift
                if gx >= 0 && gx < W { g[gx][d[1]] = 2 }
            }
        }
        if eyes == "yawn" || eyes == "gasp" { for x in 8 ... 10 { g[x][4] = 2; g[x][5] = 2 } }
    }

    var geo = Geo()
    let oy = 4 * f.off + f.dig, ox = 2 * f.x
    let lim = f.dig > 0 ? H - 2 : H
    for y in 0 ..< H {
        var sy = y
        if f.flip { if y >= H - 2 { continue } else { sy = H - 3 - y } }
        let yy = sy + oy
        if yy < 0 || yy >= lim { continue }
        var x = 0
        while x < W {
            let c = g[x][y]
            if c == 0 { x += 1; continue }
            let x0 = x
            while x < W && g[x][y] == c { x += 1 }
            let l = max(0, x0 + ox), r = min(W, x + ox)
            if r <= l { continue }
            let rect = CGRect(x: l, y: yy, width: r - l, height: 1)
            if c == 2 { geo.eyes.append(rect) } else { geo.body.append(rect) }
        }
    }
    // Dust at the edges of the bottom row while crouched.
    if !f.poof.isEmpty && f.off > 0 {
        for cx in [0.0, Double(W - 2)] {
            let pts: [[Double]] = f.poof == "dot" ? [[0.6, 9.4, 0.8, 0.9]]
                : [[0.0, 9.6, 0.7, 0.6], [0.7, 9.1, 0.6, 0.6], [1.3, 9.6, 0.7, 0.6]]
            for p in pts { geo.fx.append(CGRect(x: cx + p[0], y: p[1], width: p[2], height: p[3])) }
        }
    }
    if !f.shadow.isEmpty {
        let (sc, sw) = f.shadow == "wide" ? (6.0, 6.0) : (8.0, 2.0)
        geo.fx.append(CGRect(x: sc, y: Double(H) - 0.5, width: sw, height: 0.5))
    }
    // Sand mound over the burrow, and grains flying from the legs.
    let Wd = Double(W), Hd = Double(H)
    if f.dig >= 1 { geo.sand.append(CGRect(x: -2, y: Hd - 3, width: Wd + 4, height: 1)) }
    if f.dig >= 2 { geo.sand.append(CGRect(x: -1, y: Hd - 4, width: Wd + 2, height: 1)) }
    if f.dig >= 3 {
        geo.sand.append(CGRect(x: -1, y: Hd - 5, width: 2, height: 1))
        geo.sand.append(CGRect(x: Wd - 1, y: Hd - 5, width: 2, height: 1))
    }
    if f.spray > 0 {
        for k in 0 ..< 2 {
            let d = Double(f.spray + 2 * k)
            let sx = 1.5 + 0.9 * d, sy = (Hd - 4) - 0.9 * d * (5 - d) / 2
            geo.sand.append(CGRect(x: -sx, y: sy, width: 0.8, height: 0.8))
            geo.sand.append(CGRect(x: Wd - 0.8 + sx, y: sy, width: 0.8, height: 0.8))
        }
    }
    return geo
}


// Health by heart halves (lib/hearts.ps1).
struct Tier { var speed: Double; var hop = 0; var yawn = 0; var eyes = ""; var sweat = false; var stagger = false; var stumble = 0 }
let tiers: [Int: Tier] = [
    6: Tier(speed: 1.25, hop: 300), 5: Tier(speed: 1.0), 4: Tier(speed: 0.9, yawn: 350),
    3: Tier(speed: 0.75, yawn: 200, eyes: "focus"), 2: Tier(speed: 0.55, yawn: 160, eyes: "focus", sweat: true),
    1: Tier(speed: 0.35, eyes: "blink", sweat: true, stagger: true, stumble: 220), 0: Tier(speed: 0),
]

func rnd(_ n: Int) -> Int { Int.random(in: 0 ..< max(1, n)) }

