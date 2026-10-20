// Colour themes (lib/theme.ps1, plus Space, Launch and Hypercar - see Space.swift, Launch.swift, Hypercar.swift) and Clawd's skins (lib/skins.ps1).

import AppKit

struct Theme {
    var id: String, nameKo: String, nameEn: String
    var name: String { L(nameKo, nameEn) }
    var bg: NSColor, card: NSColor, text: NSColor, text2: NSColor, muted: NSColor, dim: NSColor, faint: NSColor, off: NSColor, accent: NSColor
    var pattern = false
    var space = false   // the animated starfield behind the whole widget
    var launch = false  // the launch site on the Moon behind the whole widget
    var hypercar = false    // the endurance prototype in a studio behind the whole widget
    var backdrop: Bool { space || launch || hypercar }
}

func makeTheme(_ id: String, _ nameKo: String, _ nameEn: String, _ c: [String: String], pattern: Bool = false, space: Bool = false, launch: Bool = false, hypercar: Bool = false) -> Theme {
    let base = ["bg": "#1A1A1E", "card": "#26262C", "text": "#E4E4E7", "text2": "#D4D4D8", "muted": "#8B8B94",
                "dim": "#6B7280", "faint": "#52525B", "off": "#3F3F46", "accent": "#60A5FA"]
    func k(_ key: String) -> NSColor { hexColor(c[key] ?? base[key]!) }
    return Theme(id: id, nameKo: nameKo, nameEn: nameEn, bg: k("bg"), card: k("card"), text: k("text"), text2: k("text2"), muted: k("muted"),
                 dim: k("dim"), faint: k("faint"), off: k("off"), accent: k("accent"), pattern: pattern, space: space, launch: launch, hypercar: hypercar)
}

let themes: [Theme] = [
    makeTheme("classic", "클래식", "Classic", [:]),
    makeTheme("oled", "OLED 블랙", "OLED black", ["bg": "#000000", "card": "#141414"]),
    makeTheme("midnight", "미드나이트", "Midnight", ["bg": "#0F172A", "card": "#1E293B", "text": "#E2E8F0", "text2": "#CBD5E1", "muted": "#8494AB",
                                       "dim": "#64748B", "faint": "#475569", "off": "#334155", "accent": "#38BDF8"]),
    makeTheme("mocha", "모카", "Mocha", ["bg": "#1E1E2E", "card": "#313244", "text": "#CDD6F4", "text2": "#BAC2DE", "muted": "#9399B2",
                               "dim": "#7F849C", "faint": "#585B70", "off": "#45475A", "accent": "#89B4FA"]),
    makeTheme("forest", "포레스트", "Forest", ["bg": "#111814", "card": "#1C2A21", "text": "#E1EAE3", "text2": "#CFDBD2", "muted": "#86998B",
                                    "dim": "#66786B", "faint": "#4B5B50", "off": "#35433A", "accent": "#5EEAD4"]),
    makeTheme("halloween", "할로윈", "Halloween", ["bg": "#1C1326", "card": "#2A1D38", "text": "#F5E6DA", "text2": "#E7D3C4", "muted": "#A08B9C",
                                     "dim": "#7E6A80", "faint": "#5B4A63", "off": "#3F3048", "accent": "#F97316"], pattern: true),
    makeTheme("space", "우주", "Space", ["bg": "#0B0618", "card": "#1E1535", "text": "#EDE9FE", "text2": "#DDD6FE", "muted": "#A89BCB",
                                      "dim": "#7C6F9E", "faint": "#5B4F80", "off": "#3B2F5C", "accent": "#C084FC"], space: true),
    makeTheme("launch", "발사", "Launch", ["bg": "#0C0C10", "card": "#1C1C22", "text": "#ECECF0", "text2": "#D6D6DC", "muted": "#9C9CA6",
                                       "dim": "#74747E", "faint": "#54545C", "off": "#33333A", "accent": "#FB923C"], launch: true),
    makeTheme("hypercar", "하이퍼카", "Hypercar", ["bg": "#100707", "card": "#22110E", "text": "#FFF1E6", "text2": "#F1DCCD", "muted": "#C09C90",
                                             "dim": "#8A6A60", "faint": "#5E4640", "off": "#3A2A26", "accent": "#FF7A1A"], hypercar: true),
]

// "auto" follows the season: Halloween in autumn, classic otherwise.
func currentTheme(_ id: String) -> Theme {
    var id = id
    if id == "auto" { id = (9 ... 11).contains(Calendar.current.component(.month, from: Date())) ? "halloween" : "classic" }
    return themes.first { $0.id == id } ?? themes[0]
}

// Halloween wallpaper: a tile of pixel sprites repeated faintly over the window.
let patternColors: [Character: NSColor] = ["o": hexColor("#F97316"), "g": hexColor("#65A30D"), "b": hexColor("#A78BFA"),
                                           "w": hexColor("#F5F5F4"), "y": hexColor("#FDE047")]
let patternSprites: [(Double, Double, [String])] = [
    (6, 6, ["....gg...", "...g.....", ".ooo.ooo.", "ooooooooo", "oo.ooo.oo", "ooooooooo", "oo.o.o.oo", ".ooooooo."]),
    (58, 20, ["b.........b", "bb..b.b..bb", "bbbbbbbbbbb", ".bbb.b.bbb.", "..b.....b.."]),
    (30, 56, ["..www..", ".wwwww.", "ww.w.ww", "wwwwwww", "wwwwwww", "wwwwwww", "w.w.w.w"]),
    (76, 70, [".y.", "yyy", ".y."]), (8, 84, ["y"]), (92, 4, ["y"]),
]
func drawPattern(in rect: CGRect) {
    let tile = 104.0, px = 2.0
    var ty = rect.minY
    while ty < rect.maxY {
        var tx = rect.minX
        while tx < rect.maxX {
            for (sx, sy, art) in patternSprites {
                for (y, row) in art.enumerated() {
                    for (x, ch) in row.enumerated() {
                        guard let c = patternColors[ch] else { continue }
                        c.withAlphaComponent(0.1).setFill()
                        NSBezierPath(rect: CGRect(x: tx + sx + Double(x) * px, y: ty + sy + Double(y) * px, width: px, height: px)).fill()
                    }
                }
            }
            tx += tile
        }
        ty += tile
    }
}

// MARK: - Skins

struct Skin {
    var id: String, fileName: String
    var name: String { (isKo ? skinNamesKo[id] : skinNamesEn[id]) ?? fileName }
    var body = clawdColor, eyes = hexColor("#141416")
    var layers: [(NSColor, [(Int, Int)])] = []
}

let skinNamesKo = ["classic": "기본", "bow": "리본", "crown": "왕관", "ears": "고양이 귀", "frost": "서리", "nerd": "안경",
                   "party": "파티", "santa": "산타 모자", "shades": "선글라스", "tired": "피곤", "tophat": "중절모", "witch": "마녀 모자"]
let skinNamesEn = ["classic": "Classic", "ears": "Cat ears"]

// A skin file: front matter (name, body, eyes, top, one colour per letter) and 18-pixel-wide art.
// Without "top" the art sits right on his head; rows above it are negative.
func readSkin(_ url: URL) -> Skin? {
    guard let raw = try? String(contentsOf: url, encoding: .utf8),
          let m = firstMatch(raw, "^\\s*---\\s*\\r?\\n([\\s\\S]*?)\\r?\\n---\\s*\\r?\\n?([\\s\\S]*)$") else { return nil }
    let id = url.deletingPathExtension().lastPathComponent.lowercased()
    var s = Skin(id: id, fileName: id.capitalized)
    var colors: [Character: NSColor] = [:]
    var top: Int? = nil
    for line in (m[1] ?? "").components(separatedBy: .newlines) {
        guard let kv = firstMatch(line, "^\\s*(\\w+)\\s*:\\s*(.*?)\\s*$"), let k = kv[1], let v = kv[2] else { continue }
        let isColor = v.range(of: "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$", options: .regularExpression) != nil
        switch k {
        case "name": s.fileName = v
        case "body": if isColor { s.body = hexColor(v) }
        case "eyes": if isColor { s.eyes = hexColor(v) }
        case "top": top = Int(v)
        default: if k.count == 1 && isColor { colors[k.first!] = hexColor(v) }
        }
    }
    var rows = (m[2] ?? "").components(separatedBy: .newlines).map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
    while let last = rows.last, last.isEmpty { rows.removeLast() }
    let t = top ?? -rows.count
    var byColor: [Character: [(Int, Int)]] = [:]
    for (y, row) in rows.enumerated() {
        for (x, ch) in row.prefix(gridW).enumerated() where colors[ch] != nil {
            byColor[ch, default: []].append((x, t + y))
        }
    }
    s.layers = byColor.map { (colors[$0.key]!, $0.value) }
    return s
}

func loadSkins() -> [Skin] {
    var all = [Skin(id: "classic", fileName: "Classic")]
    let dirs = [Bundle.main.resourceURL?.appendingPathComponent("skins"),
                appSupport.appendingPathComponent("skins")].compactMap { $0 }
    for dir in dirs {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "txt" }.sorted { $0.path < $1.path }
        for f in files {
            guard let s = readSkin(f) else { continue }
            if let i = all.firstIndex(where: { $0.id == s.id }) { all[i] = s } else { all.append(s) }
        }
    }
    return all
}

// Accessory pixels for a frame: above the head while the head is in the frame,
// on the body like the body; turning keeps only what is above the head, on his back none.
func accessoryRects(_ skin: Skin, _ f: Frame) -> [(NSColor, [CGRect])] {
    if f.flip { return [] }
    let oy = 4 * f.off + f.dig, ox = 2 * f.x
    let lim = f.dig > 0 ? gridH - 2 : gridH
    return skin.layers.map { (color, px) in
        var rects: [CGRect] = []
        for (x0, y) in px {
            let x = x0 + ox
            if y >= 0 && !f.facing.isEmpty { continue }
            let yy = y + oy
            if x < 0 || x >= gridW || yy >= lim { continue }
            if y < 0 ? oy < 0 : yy < 0 { continue }
            rects.append(CGRect(x: x, y: yy, width: 1, height: 1))
        }
        return (color, rects)
    }
}
