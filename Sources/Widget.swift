// The widget: header with hearts, the session percent over the sky with Clawd,
// limit bars, sessions, Anthropic status, and the details (last 24 h / 7 days,
// the 7-day limits chart, projects, versions).

import AppKit

let heartRows = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
let fableColor = hexColor("#A78BFA")
let soulUp = 26, soulBack = 48     // frames: the soul reaches the top / starts being sucked back
let soulTop = 20.0                 // height above the mouth
let soulArt = ["..########..", "..#.####.#..", "############", "..########..", "...######...", "....####....", ".....##....."]

final class ClawdView: NSView {
    weak var app: AppDelegate?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var theme = themes[0]
    var skin = Skin(id: "classic", fileName: "Classic")
    let sky = Sky()
    let space = Space()

    // Layout.
    let pad = 16.0, heroTop = 36.0, heroH = 72.0
    var hero: CGRect { CGRect(x: pad, y: heroTop, width: bounds.width - 2 * pad, height: heroH) }
    // Clawd walks over the sky to the right of the big number.
    var areaRect: CGRect { CGRect(x: pad + 92, y: heroTop, width: bounds.width - 2 * pad - 96, height: heroH) }
    var ground: Double { hero.maxY - 2 }
    var contentHeight = 300.0
    var toggleRect = CGRect.zero, gearRect = CGRect.zero, chartRect = CGRect.zero
    var hoverX: Double? = nil

    // Clawd's scale.
    let S = 1.5
    var px: Double { 2.0 * S }
    var py: Double { 2.2 * S }
    var mascotW: Double { Double(gridW) * px }

    // Mascot state (lib/mascot.ps1 $script:Mz).
    var mx = -1.0, dir = 1, target: Double? = nil, look = 0
    var tick = 0, blinkAt = 30
    var mood = "sleep", cur = "sleep", crit = false, idleSince = Date()
    var act: String? = nil, actT = 0
    var pct: Int? = nil, shownHalves: Int? = nil, lostT = -1, lostFrom = 0
    var loveT = -1, noteT = -1, confT = -1
    var busyN = -1, waitingN = 0, lastReset: Date? = nil, lastPct: Int? = nil
    var buried = false
    var cf = Frame(), bubble = "", zzz = false, dust = false, sweat = false, stagger = false
    var confetti: [(x: Double, y: Double, v: Double, d: Double, c: NSColor)] = []
    var geoCache: [String: Geo] = [:]
    var timer: Timer?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let h: Double? = chartRect.insetBy(dx: 0, dy: -4).contains(p) ? Double(p.x - chartRect.minX) : nil
        if h != hoverX { hoverX = h; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hoverX = nil }

    func geo(_ f: Frame) -> Geo {
        if let g = geoCache[f.key] { return g }
        let g = buildGeo(f); geoCache[f.key] = g; return g
    }

    func start() {
        startAct(clawdSeqs.keys.filter { $0 != "celebrate" }.randomElement()!)
        scheduleStep()
    }

    func scheduleStep() {
        // Claude Code animations run at its pace - 60 ms per frame, everything else 90 ms.
        let ms = (act.map { clawdSeqs[$0] != nil } ?? false) ? 0.06 : 0.09
        timer = Timer.scheduledTimer(withTimeInterval: ms, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.step()
            self.scheduleStep()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func startAct(_ name: String) {
        act = name; actT = 0
        if name == "celebrate" { startConfetti() }
    }

    func actLen(_ name: String) -> Int { clawdSeqs[name]?.count ?? customActLen[name] ?? 20 }

    // Three hearts with halves: every ~16.7% of what is left is one half.
    func halves() -> Int? {
        guard let p = pct else { return nil }
        return min(6, max(0, Int((Double(max(0, 100 - p)) * 6 / 100).rounded(.up))))
    }

    func setMood(sessions ss: [Sess], usage: Usage?) {
        let busy = ss.filter(\.busy).count, waiting = ss.filter(\.waiting).count
        let p = usage?.session?.pct
        let m: String
        if let p, p >= 100 { m = "dead" }
        else if waiting > 0 { m = "wait" }
        else if busy > 0 { m = "work" }
        else if !ss.isEmpty { m = "idle" }
        else { m = "sleep" }
        if m != mood { idleSince = Date() }
        mood = m
        // A session finished its reply (rather than stopping to wait for us): jump.
        if busyN > 0 && busy < busyN && waiting <= waitingN && act == nil { startAct("jump") }
        busyN = busy; waitingN = waiting
        crit = (p ?? 0) >= 85
        pct = p
        // The 5-hour window reset: reset time moved forward and the percent dropped.
        if let r = usage?.session?.reset {
            if let lr = lastReset, r > lr.addingTimeInterval(60), let lp = lastPct, let p, p < lp { startAct("celebrate") }
            lastReset = r; lastPct = p
        }
    }

    func startConfetti() {
        let colors = ["#F87171", "#FBBF24", "#4ADE80", "#60A5FA", "#A78BFA", "#D77757"].map(hexColor)
        confetti = (0 ..< 12).map { i in
            (x: mx - 12 * S + Double.random(in: 0 ... 1) * (mascotW + 24 * S),
             y: (34 + Double.random(in: 0 ... 12)) * S * 0.8,
             v: (0.9 + Double.random(in: 0 ... 1.2)) * S,
             d: (Double.random(in: 0 ... 1) - 0.5) * 0.8 * S,
             c: colors[i % colors.count])
        }
        confT = 0
    }

    func mouseLook() -> Int? {
        guard let w = window, w.isVisible, w.frame.contains(NSEvent.mouseLocation) else { return nil }
        let p = convert(w.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let cx = areaRect.minX + mx + mascotW / 2
        if p.x > cx + 10 * S { return 1 }
        if p.x < cx - 10 * S { return -1 }
        return 0
    }

    // One-shot animation frame; returns the bubble text above the head.
    func stepAct(_ f: inout Frame) -> String {
        guard let a = act else { return "" }
        let t = actT
        var b = ""
        if let seq = clawdSeqs[a] {
            let fr = seq[min(t, seq.count - 1)]
            f.eyes = fr.eyes; f.arms = fr.arms; f.feet = fr.feet; f.off = fr.off; f.x = fr.x
            f.facing = fr.facing; f.poof = fr.poof; f.shadow = fr.shadow; f.look = 0
            if a == "celebrate" { b = "!" }
        } else {
            switch a {
            case "wave":
                f.look = 0; f.eyes = "happy"; f.arms = (t / 4) % 2 == 1 ? "down" : "right"
            case "stretch":
                if t >= 4 && t < 18 { f.arms = "up"; f.eyes = "closed"; f.lift = 1.5 }
            case "yawn":
                f.look = 0; f.eyes = (t >= 3 && t < 17) ? "yawn" : "closed"
            case "stumble":
                if t < 12 { f.off = 1; f.eyes = "closed" } else { f.eyes = "wide" }
                f.look = 0
            case "burrow":
                if t < 4 { f.look = t < 2 ? -1 : 1 }
                else if t < 24 {
                    f.look = 0; f.eyes = "focus"
                    f.dig = min(burrowDig, Int(Double(t - 4) / 3.5))
                    f.feet = (t / 2) % 2 == 1 ? "left" : "right"
                    f.arms = (t / 2) % 2 == 1 ? "up" : "down"
                    f.spray = t % 3 + 1
                } else { f.look = 0; f.dig = burrowDig; f.eyes = t < 27 ? "blink" : "closed" }
            case "unburrow":
                f.look = 0
                if t < 3 { f.dig = burrowDig; f.eyes = "wide" }
                else if t < 9 {
                    f.dig = max(0, burrowDig - (t - 3)); f.eyes = "wide"; f.arms = "up"; f.spray = t % 3 + 1
                    if t == 8 { f.lift = 2 }
                } else if t < 21 {
                    f.eyes = "closed"
                    f.look = (t / 2) % 2 == 1 ? -1 : 1
                    f.feet = (t / 2) % 2 == 1 ? "left" : "right"
                    if t < 15 { f.spray = t % 3 + 1 }
                } else if t < 23 { f.eyes = "blink" }
            case "soul":
                // Like in anime: the soul flies out of the open mouth on a thread, hangs over
                // the body, then gets sucked back in - and the body twitches.
                f.flip = true; f.look = 0
                if t < 6 {
                    f.eyes = "x"; f.feet = t % 2 == 1 ? "left" : "right"
                } else if t < soulBack + 6 {
                    f.eyes = "gasp"; f.soulT = t
                    if t < soulUp {
                        let k = Double(t - 6) / Double(soulUp - 6)
                        f.soul = soulTop * (1 - (1 - k) * (1 - k))           // floats out, slowing down
                    } else if t < soulBack {
                        f.soul = soulTop + 1.5 * sin(Double(t - soulUp) / 2.5)
                    } else {
                        let k = Double(t - soulBack) / 6
                        f.soul = soulTop * (1 - k * k)                       // snaps back in
                    }
                } else if t < soulBack + 9 {
                    f.eyes = "wide"; f.lift = 2.5                            // wakes for a moment
                } else {
                    f.eyes = "x"
                }
            case "stir":
                f.dig = t < 15 ? burrowDig - 1 : burrowDig
                if t < 3 { f.eyes = "wide"; f.look = 0 }
                else if t < 13 { f.look = t < 8 ? -1 : 1 }
                else if t < 17 { f.eyes = "blink"; f.look = 0 }
                else { f.eyes = "closed"; f.look = 0 }
            default: break
            }
        }
        actT += 1
        if actT >= actLen(a) { act = nil }
        return b
    }

    func step() {
        tick += 1
        let span = max(0, areaRect.width - mascotW)
        if mx < 0 { mx = span / 2 }
        if mx > span { mx = span }
        if let t = target, t > span { target = span }

        var md = mood
        let tierN = halves() ?? 5
        let tier = tiers[tierN]!
        let perky = tier.speed >= 0.9
        let ml = mouseLook()
        if ml != nil { idleSince = Date() }
        if md == "idle" && Date().timeIntervalSince(idleSince) >= 600 { md = "doze" }

        // Falling asleep: burrows into the sand; waking up: climbs out at once.
        if md == "sleep" {
            if !buried && act == nil { buried = true; startAct("burrow") }
        } else if buried {
            buried = false; startAct("unburrow")
        }

        var f = Frame()
        f.look = look
        if cur == "work" && md != "work" { target = nil }
        cur = md
        bubble = ""; zzz = false; dust = false
        var canBlink = true

        if act != nil {
            bubble = stepAct(&f); canBlink = false
        } else {
            switch md {
            case "sleep":
                f.dig = burrowDig; f.eyes = "closed"; f.look = 0; zzz = true
            case "doze":
                f.look = 0
                let p = tick % 70
                if p < 6 { f.eyes = "wide"; if p < 2 { f.lift = 1.5 } } else { f.eyes = "blink"; zzz = true }
            case "dead":
                f.flip = true; f.eyes = "x"; f.look = 0
                let p = tick % 50
                if p < 6 { f.feet = p % 2 == 1 ? "left" : "right" }
            case "wait":
                bubble = "?"; f.eyes = "wide"; f.look = ml ?? 0
                let p = tick % 40
                if p < 8 { let k = Double(p) / 7; f.lift = 12 * k * (1 - k); f.arms = "right" }
            default:
                var speed: Double
                if md == "work" {
                    speed = 1.6 * tier.speed * S
                    if target == nil { target = dir > 0 ? span : 0 }
                } else {
                    speed = 0.6 * tier.speed * S
                    if target == nil {
                        if rnd(70) == 0 { target = Double.random(in: 0 ... 1) * span }
                        else if rnd(45) == 0 { look = Int.random(in: -1 ... 1) }
                        else if rnd(400) == 0 { startAct(["wave", "stretch", "look"].randomElement()!) }
                    }
                }
                var walking = false
                if let t = target {
                    let d = t - mx
                    if abs(d) <= speed {
                        mx = t; target = nil
                        if md == "work" { dir = -dir }
                    } else {
                        dir = d > 0 ? 1 : -1
                        mx += speed * Double(dir)
                        look = dir
                        walking = true
                    }
                }
                if walking {
                    var st = md == "work" ? 2 : 3
                    if tier.speed < 0.8 { st += 1 }
                    if tier.speed < 0.5 { st += 1 }
                    f.feet = (tick / st) % 2 == 1 ? "left" : "right"
                    if md == "work" {
                        if f.feet == "left" && perky { f.lift = 1 }
                        dust = true
                        if perky && rnd(150) == 0 { startAct("jump") }
                    } else if perky && noteT < 0 && rnd(80) == 0 {
                        noteT = 0   // whistles while walking
                    }
                    if tier.stumble > 0 && rnd(tier.stumble) == 0 { startAct("stumble") }
                } else if crit {
                    look = (tick / 5) % 2 == 1 ? -1 : 1   // limit running out: eyes dart nervously
                } else if let ml {
                    look = ml   // standing: follows the cursor
                }
                f.look = look
                if md == "work" { f.eyes = "focus" }
                if act == nil {
                    if tier.hop > 0 && rnd(tier.hop) == 0 { startAct("jump") }
                    if tier.yawn > 0 && rnd(tier.yawn) == 0 { startAct("yawn") }
                }
            }
        }

        if !tier.eyes.isEmpty && act == nil && ["open", "focus"].contains(f.eyes) { f.eyes = tier.eyes }
        if loveT >= 0 && act == nil && f.eyes == "open" { f.eyes = "happy" }
        if noteT >= 0 {
            if bubble.isEmpty && md == "idle" { bubble = "♪" }
            noteT += 1
            if noteT >= 30 { noteT = -1 }
        }
        if canBlink && f.eyes == "open" && tick >= blinkAt {
            f.eyes = "blink"
            if tick >= blinkAt + 1 { blinkAt = tick + Int.random(in: 25 ..< 70) }
        }
        sweat = (crit || tier.sweat) && !["sleep", "dead"].contains(md)
        stagger = tier.stagger && !["sleep", "dead"].contains(md)

        // Lost a heart: the lost part blinks for a couple of seconds.
        let h = halves()
        if let sh = shownHalves, let h, h < sh { lostT = 0; lostFrom = sh }
        shownHalves = h
        if lostT >= 0 { lostT += 1; if lostT >= 16 { lostT = -1 } }

        if confT >= 0 {
            for i in confetti.indices { confetti[i].y -= confetti[i].v; confetti[i].x += confetti[i].d }
            confT += 1
            if confT >= 45 { confT = -1 }
        }
        if loveT >= 0 { loveT += 1; if loveT >= 20 { loveT = -1 } }

        if cf.key != f.key { app?.updateStatusIcon(f) }
        cf = f
        if let r = app?.recorder { display(); r.capture(self) }
        // Only the animated part when the details are steady.
        // The Space theme animates the whole widget; otherwise only the top part moves.
        if window?.isVisible == true { theme.space ? (needsDisplay = true) : setNeedsDisplay(CGRect(x: 0, y: 0, width: bounds.width, height: heroTop + heroH + 4)) }
    }

    // MARK: input

    var mascotRect: CGRect {
        let top = ground - (cf.lift * S - 2 * py) - Double(gridH) * py
        return CGRect(x: areaRect.minX + mx, y: top, width: mascotW, height: Double(gridH) * py).insetBy(dx: -6, dy: -6)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if toggleRect.contains(p) {
            app?.toggleDetails()
        } else if gearRect.contains(p) {
            if let menu = app?.buildMenu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        } else if mascotRect.contains(p) {
            // Lying with the limit used up: its soul leaves the body instead.
            if mood == "dead" || cur == "dead" { if act == nil { startAct("soul") }; return }
            loveT = 0
            if buried && cur == "sleep" { if act == nil { startAct("stir") }; return }
            if act == nil { startAct(clickActs.randomElement()!) }
        } else if app?.pinned == true {
            window?.performDrag(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = app?.buildMenu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }

    // MARK: drawing helpers

    func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, mono: Bool = false) -> NSFont {
        mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    }

    @discardableResult
    func text(_ s: String, _ x: Double, _ y: Double, _ f: NSFont, _ c: NSColor, right: Bool = false) -> CGSize {
        let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c])
        let sz = str.size()
        str.draw(at: CGPoint(x: right ? x - sz.width : x, y: y))
        return sz
    }

    // Wrapped paragraph; returns its height.
    func para(_ s: String, _ x: Double, _ y: Double, _ w: Double, _ f: NSFont, _ c: NSColor) -> Double {
        let ps = NSMutableParagraphStyle(); ps.lineSpacing = 1.5
        ps.lineBreakStrategy = [.hangulWordPriority, .pushOut]   // break Korean between words
        let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c, .paragraphStyle: ps])
        let h = ceil(str.boundingRect(with: CGSize(width: w, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        str.draw(with: CGRect(x: x, y: y, width: w, height: h + 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return h
    }

    func bar(_ y: Double, _ pct: Int, _ color: NSColor, h: Double = 5) {
        let r = CGRect(x: pad, y: y, width: bounds.width - 2 * pad, height: h)
        theme.off.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2).fill()
        var fill = r; fill.size.width = max(h, r.width * Double(min(100, pct)) / 100)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: h / 2, yRadius: h / 2).fill()
    }

    func caps(_ s: String, _ y: Double) {
        text(s, pad, y, font(10.5, .semibold), theme.muted)
    }

    func separator(_ y: Double) {
        theme.off.withAlphaComponent(0.6).setFill()
        NSBezierPath(rect: CGRect(x: pad, y: y, width: bounds.width - 2 * pad, height: 1)).fill()
    }

    func heart(_ x: Double, _ y: Double, _ hp: Double, fullCols: Int, on: NSColor, off: NSColor) {
        for (yy, row) in heartRows.enumerated() {
            for (xx, c) in row.enumerated() where c == "#" {
                (xx <= fullCols ? on : off).setFill()
                NSBezierPath(rect: CGRect(x: x + Double(xx) * hp, y: y + Double(yy) * hp, width: hp, height: hp)).fill()
            }
        }
    }

    // MARK: draw

    override func draw(_ dirtyRect: NSRect) {
        guard let app else { return }
        let w = bounds.width
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        theme.bg.withAlphaComponent(0.97).setFill()
        bg.fill()
        if theme.pattern {
            NSGraphicsContext.saveGraphicsState(); bg.setClip(); drawPattern(in: bounds); NSGraphicsContext.restoreGraphicsState()
        }
        if theme.space {
            NSGraphicsContext.saveGraphicsState(); bg.setClip(); space.draw(in: bounds, sky: hero); NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(white: 1, alpha: 0.08).setStroke()
        bg.stroke()

        // Header: title, hearts, settings, details toggle.
        text("CLAUDE USAGE", pad, 12, font(11, .semibold), theme.muted)
        toggleRect = CGRect(x: w - pad - 14, y: 8, width: 18, height: 20)
        text(app.detailsOn ? "▴" : "▾", w - pad, 10, font(12), theme.muted, right: true)
        gearRect = CGRect(x: w - pad - 38, y: 8, width: 20, height: 20)
        text("⚙︎", w - pad - 20, 9, font(13), theme.muted, right: true)
        if let h = halves() {
            var show = h
            if lostT >= 0 && lostT % 4 < 2 { show = lostFrom }
            let hp = 1.6
            var beat = 1.0
            if h > 0 && h <= 2 { let p = tick % 12; beat = p == 0 ? 1.3 : (p == 1 ? 1.15 : 1) }
            for i in 0 ..< 3 {
                let hx = w - pad - 48 - Double(3 - i) * (7 * hp + 3)
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform()
                t.translateX(by: hx + 3.5 * hp, yBy: 13 + 3 * hp); t.scale(by: beat); t.translateX(by: -3.5 * hp, yBy: -3 * hp)
                t.concat()
                let cols = show - 2 * i >= 2 ? 6 : (show - 2 * i == 1 ? 3 : -1)
                heart(0, 0, hp, fullCols: cols, on: hexColor("#F87171"), off: theme.off)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        // Hero: sky, big session percent, Clawd.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: hero, xRadius: 8, yRadius: 8).setClip()
        if app.showSky && !theme.space { sky.draw(in: hero, weather: app.weather, place: app.place) }
        NSGraphicsContext.restoreGraphicsState()

        let u = app.usage
        if let s = u?.session {
            let sz = text("\(s.pct)", pad + 2, heroTop + 8, font(44, .light, mono: true), levelColor(s.pct))
            text("%", pad + 4 + sz.width, heroTop + 12, font(15, .regular), levelColor(s.pct).withAlphaComponent(0.85))
        } else {
            text("–", pad + 2, heroTop + 8, font(44, .light), theme.dim)
        }
        drawMascot()

        var y = hero.maxY + 6
        if let s = u?.session {
            bar(y, s.pct, levelColor(s.pct), h: 6); y += 12
            let r = s.reset.map { L("\(leftText($0)) 후 리셋 · \(clock($0))", "resets in \(leftText($0)) · \(clock($0))") } ?? L("아직 시작 안 됨", "not started yet")
            text(r, pad, y, font(13), theme.text); y += 26
        } else {
            let msg = app.errorText ?? L("사용량 불러오는 중…", "Loading usage…")
            y += para(msg, pad, y + 4, w - 2 * pad, font(11), theme.muted) + 14
        }

        func limitRow(_ label: String, _ l: Limit, _ color: NSColor) {
            caps(label, y)
            let right = l.reset.map { "\(l.pct)%  ·  \(leftText($0))" } ?? "\(l.pct)%"
            text(right, w - pad, y - 1, font(11.5, mono: true), theme.text2, right: true)
            y += 18
            bar(y, l.pct, color, h: 4)
            y += 16
        }
        if let wk = u?.week { limitRow(L("주간", "WEEK"), wk, theme.accent) }
        if let fb = u?.fable { limitRow(L("FABLE · 주간", "FABLE · WEEK"), fb, fableColor) }

        // Sessions.
        let ss = app.sessions
        caps(L("세션", "SESSIONS"), y)
        text(L("\(ss.count)개 실행  ·  \(ss.filter(\.busy).count) 작업", "\(ss.count) sessions  ·  \(ss.filter(\.busy).count) working")
             + (ss.contains(where: \.waiting) ? L("  ·  \(ss.filter(\.waiting).count) 대기", "  ·  \(ss.filter(\.waiting).count) waiting") : ""),
             w - pad, y - 1, font(11.5), theme.text2, right: true)
        y += 24

        // Anthropic status.
        if let st = app.status {
            let (dot, msg): (NSColor, String) = {
                switch st.indicator {
                case "none": return (hexColor("#4ADE80"), L("모든 Claude 시스템 정상", "All Claude systems operational"))
                case "minor": return (hexColor("#FBBF24"), st.incidents.first ?? L("일부 장애: ", "Degraded: ") + st.broken.joined(separator: ", "))
                default: return (hexColor("#F87171"), st.incidents.first ?? L("장애: ", "Outage: ") + st.broken.joined(separator: ", "))
                }
            }()
            dot.setFill()
            NSBezierPath(ovalIn: CGRect(x: pad + 1, y: y + 4.5, width: 7, height: 7)).fill()
            y += para(msg, pad + 15, y, w - 2 * pad - 15, font(12), theme.text2) + 8
        }

        if app.detailsOn { y = drawDetails(y + 2) }
        y += 10

        if abs(y - contentHeight) > 0.5 {
            contentHeight = y
            DispatchQueue.main.async { app.resizePanel() }
        }
    }

    func drawDetails(_ y0: Double) -> Double {
        guard let app else { return y0 }
        let w = bounds.width
        var y = y0
        separator(y); y += 12

        func period(_ title: String, _ p: Period?) {
            guard let p else { return }
            caps(title, y); y += 17
            text(L("\(p.requests) 요청  ·  \(p.sessions) 세션", "\(p.requests) requests  ·  \(p.sessions) sessions"), pad, y, font(13), theme.text); y += 19
            if !p.lines.isEmpty {
                y += para(p.lines.map(formatStat).joined(separator: "  ·  "), pad, y, w - 2 * pad, font(11), theme.muted)
            }
            y += 12
        }
        period(L("최근 24시간 · 이 컴퓨터", "LAST 24 HOURS · THIS COMPUTER"), app.usage?.day)
        period(L("최근 7일", "LAST 7 DAYS"), app.usage?.week7)

        // Limits over 7 days: the session line with an area, the week line on top.
        caps(L("한도 · 7일", "LIMITS · 7 DAYS"), y); y += 18
        let cw = w - 2 * pad, ch = 48.0
        chartRect = CGRect(x: pad, y: y, width: cw, height: ch)
        drawChart(chartRect)
        y += ch + 3
        // Weekday names under each day.
        let now = Date()
        let t1 = now.timeIntervalSince1970 / 60, t0 = t1 - 7 * 1440
        var day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: t0 * 60)).addingTimeInterval(86400)
        var prevX = 0.0
        while true {
            let x = day < now ? cw * (day.timeIntervalSince1970 / 60 - t0) / (t1 - t0) : cw
            if x - prevX >= 14 {
                let name = clock(day.addingTimeInterval(-86400), "E")
                let sz = NSAttributedString(string: name, attributes: [.font: font(9)]).size()
                text(name, pad + (prevX + x) / 2 - sz.width / 2, y, font(9), theme.faint)
            }
            if day >= now { break }
            prevX = x
            day = day.addingTimeInterval(86400)
        }
        y += 15
        if hoverX == nil && !app.history.samples.isEmpty {
            // Legend in the colours of the two lines.
            var x = pad
            for (label, c) in [(L("세션 (5시간)", "session (5h)"), hexColor("#4ADE80")), (L("주간", "week"), theme.accent)] {
                x += text("━ ", x, y, font(11, .bold), c).width
                x += text(label, x, y, font(11), theme.muted).width + 14
            }
            y += 30
        } else {
            y += para(chartCaption(), pad, y, cw, font(11), theme.muted) + 14
        }

        // Projects over 7 days, by tokens weighted with model prices.
        caps(L("프로젝트 · 7일", "PROJECTS · 7 DAYS"), y); y += 18
        if let p = app.projects, p.total.values.reduce(0, +) > 0 {
            let sum = p.total.values.reduce(0, +)
            for (name, v) in p.total.sorted(by: { $0.value > $1.value }).prefix(4) {
                let share = 100 * v / sum
                let barW = 80.0, bx = w - pad - 38 - barW
                let nameStr = NSAttributedString(string: name, attributes: [.font: font(12), .foregroundColor: theme.text2,
                                                                            .paragraphStyle: { let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail; return ps }()])
                nameStr.draw(with: CGRect(x: pad, y: y, width: bx - pad - 10, height: 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                theme.off.setFill()
                NSBezierPath(roundedRect: CGRect(x: bx, y: y + 6, width: barW, height: 4), xRadius: 2, yRadius: 2).fill()
                clawdColor.setFill()
                NSBezierPath(roundedRect: CGRect(x: bx, y: y + 6, width: max(2, barW * share / 100), height: 4), xRadius: 2, yRadius: 2).fill()
                text(String(format: "%.0f%%", share), w - pad, y, font(11.5, mono: true), theme.muted, right: true)
                y += 19
            }
        } else {
            text(app.projectScanner.running ? L("집계 중…", "counting…") : L("최근 7일 기록 없음", "nothing in the last 7 days"), pad, y, font(11), theme.dim); y += 18
        }
        y += 8
        separator(y); y += 10

        // Footer: Claude Code version, update, last refresh, weather.
        var ver = "Claude Code " + (app.verLocal ?? "?")
        if let l = app.verLatest, let v = app.verLocal {
            ver += l.compare(v, options: .numeric) == .orderedDescending ? L("  ·  \(l) 업데이트 있음", "  ·  \(l) is out") : L("  ·  최신", "  ·  latest")
        }
        text(ver, pad, y, font(11), theme.muted)
        y += 16
        var info: [String] = []
        if app.showSky {
            if let wx = app.weather {
                let temp = Int(wx.temp.rounded())
                info.append([app.place?.city, "\(temp > 0 ? "+" : "")\(temp)° \(weatherKind(wx.code).name)"].compactMap { $0 }.joined(separator: " "))
            }
            info.append(moonDescription())
        }
        text(info.joined(separator: "  ·  "), pad, y, font(10.5), theme.faint)
        if let at = app.usageAt { text(clock(at, "HH:mm:ss") + (app.stale ? L(" (갱신 실패)", " (stale)") : ""), w - pad, y, font(10.5, mono: true), theme.faint, right: true) }
        y += 14
        return y
    }

    func drawChart(_ r: CGRect) {
        guard let app else { return }
        let now = Date()
        let t1 = now.timeIntervalSince1970 / 60, t0 = t1 - 7 * 1440
        // Midnights.
        var day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: t0 * 60)).addingTimeInterval(86400)
        NSColor(white: 1, alpha: 0.1).setFill()
        while day < now {
            let x = r.minX + r.width * (day.timeIntervalSince1970 / 60 - t0) / (t1 - t0)
            NSBezierPath(rect: CGRect(x: x, y: r.minY, width: 1, height: r.height)).fill()
            day = day.addingTimeInterval(86400)
        }
        // Runs of samples without gaps; each becomes a figure of its own.
        for (col, color) in [(2, theme.accent), (1, hexColor("#4ADE80"))] {
            var runs: [[CGPoint]] = [], run: [CGPoint] = []
            var prevT: Int? = nil
            for s in app.history.samples where Double(s[0]) >= t0 {
                let v = s[col]
                if v < 0 || (prevT.map { s[0] - $0 > app.history.gapMinutes } ?? false) { if !run.isEmpty { runs.append(run) }; run = [] }
                prevT = s[0]
                if v >= 0 {
                    run.append(CGPoint(x: r.minX + r.width * (Double(s[0]) - t0) / (t1 - t0),
                                       y: r.minY + 1 + (r.height - 2) * (1 - Double(min(100, v)) / 100)))
                }
            }
            if !run.isEmpty { runs.append(run) }
            for var pts in runs {
                if pts.count == 1 { pts.append(CGPoint(x: pts[0].x + 1.5, y: pts[0].y)) }
                if col == 1 {
                    let area = NSBezierPath()
                    area.move(to: CGPoint(x: pts[0].x, y: r.maxY))
                    pts.forEach { area.line(to: $0) }
                    area.line(to: CGPoint(x: pts.last!.x, y: r.maxY)); area.close()
                    color.withAlphaComponent(0.15).setFill(); area.fill()
                }
                let line = NSBezierPath()
                line.move(to: pts[0]); pts.dropFirst().forEach { line.line(to: $0) }
                line.lineWidth = 1.3; line.lineJoinStyle = .round
                color.setStroke(); line.stroke()
            }
        }
        if let hx = hoverX {
            NSColor(white: 1, alpha: 0.4).setFill()
            NSBezierPath(rect: CGRect(x: r.minX + max(0, min(r.width, hx)), y: r.minY, width: 1, height: r.height)).fill()
        }
    }

    // Under the chart: the legend, or the point under the mouse with the busiest project of that hour.
    func chartCaption() -> String {
        guard let app else { return "" }
        if app.history.samples.isEmpty { return L("기록은 지금부터 쌓입니다", "the history starts now") }
        guard let hx = hoverX else { return L("━ 세션 (5시간)    ━ 주간", "━ session (5h)    ━ week") }
        let t1 = Date().timeIntervalSince1970 / 60, t0 = t1 - 7 * 1440
        let t = Int(t0 + (t1 - t0) * max(0, min(chartRect.width, hx)) / chartRect.width)
        var parts = [clock(Date(timeIntervalSince1970: Double(t) * 60), "E HH:mm")]
        if let s = app.history.at(t) {
            if s[1] >= 0 { parts.append(L("세션 \(s[1])%", "session \(s[1])%")) }
            if s[2] >= 0 { parts.append(L("주간 \(s[2])%", "week \(s[2])%")) }
        } else { parts.append(L("기록 없음", "no data")) }
        if let top = app.projects?.hours[t / 60]?.max(by: { $0.value < $1.value }) { parts.append(top.key) }
        return parts.joined(separator: "  ·  ")
    }

    // Soul: a translucent mini-Clawd with a tail; a wiggling thread runs to the mouth at o.
    func drawSoul(_ o: CGPoint, _ h: Double, _ t: Int) {
        let p = 1.4 * S
        let sway = 2.5 * S * sin(Double(t) / 4)
        hexColor("#F4F4F5").withAlphaComponent(0.7 + 0.15 * sin(Double(t) / 1.7)).setFill()
        let n = Int(h / p)
        for i in 0 ..< n {
            let k = Double(i) / Double(max(1, n))
            let dx = sway * k + 1.2 * S * sin(Double(t) / 2 + Double(i) * 0.7) * sin(k * .pi)
            NSBezierPath(rect: CGRect(x: o.x + (dx / p).rounded() * p - p / 2, y: o.y - Double(i + 1) * p, width: p, height: p)).fill()
        }
        let top = o.y - h - Double(soulArt.count) * p
        let x0 = o.x + (sway / p).rounded() * p - 6 * p
        for (y, row) in soulArt.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" {
                NSBezierPath(rect: CGRect(x: x0 + Double(x) * p, y: top + Double(y) * p, width: p, height: p)).fill()
            }
        }
    }

    func fillRects(_ rects: [CGRect], ox: Double, oy: Double) {
        for r in rects { NSBezierPath(rect: CGRect(x: ox + r.minX * px, y: oy + r.minY * py, width: r.width * px, height: r.height * py)).fill() }
    }

    func drawMascot() {
        let area = areaRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: hero.minX, y: hero.minY - 30, width: hero.width, height: hero.height + 30)).setClip()
        // Crisp pixel art: no seams between adjacent pixel rows.
        NSGraphicsContext.current?.shouldAntialias = false

        let f = cf
        let g = geo(f)
        var rx = mx
        if stagger { rx += 1.5 * S * sin(Double(tick) / 3) }
        let ox = area.minX + rx.rounded()
        let top = ground - (f.lift * S - 2 * py) - Double(gridH) * py

        hexColor("#C29E66").setFill()
        fillRects(g.sand, ox: ox, oy: top)
        skin.body.setFill()
        fillRects(g.body, ox: ox, oy: top)
        skin.eyes.setFill()
        fillRects(g.eyes, ox: ox, oy: top)
        for (c, rects) in accessoryRects(skin, f) { c.setFill(); fillRects(rects, ox: ox, oy: top) }
        hexColor("#8C8C94").setFill()
        fillRects(g.fx, ox: ox, oy: top)

        // Sleep: a "z" floats up from behind the head and fades.
        if zzz {
            let p = Double(tick % 30) / 30
            let zb = f.dig > 0 ? 9.0 : (f.off > 0 ? 12.0 : 19.0)
            text("z", area.minX + mx + (28 + 3 * sin(p * 2 * .pi)) * S, ground - (zb + 14 * p + 9) * S,
                 font((7 + 4 * p) * S, .bold), NSColor(white: 1, alpha: 0.8 * (1 - p)))
        }
        // Bubble over the head: "?" a session awaits, "!" celebration, "♪" whistling.
        if !bubble.isEmpty {
            let c = bubble == "?" ? hexColor("#FBBF24") : bubble == "!" ? hexColor("#4ADE80") : hexColor("#93C5FD")
            text(bubble, area.minX + mx + mascotW / 2 - 4 * S, ground - (22 + f.lift + 1.5 * sin(Double(tick) / 3) + 12) * S,
                 font(10 * S, .heavy), c)
        }
        // Limit almost used up: sweats.
        if sweat {
            let p = Double(tick % 20) / 20
            hexColor("#93C5FD").withAlphaComponent(1 - p).setFill()
            NSBezierPath(rect: CGRect(x: area.minX + rx + (f.look < 0 ? 31 : 2) * S, y: top + (-2 + 6 * p) * S, width: 2 * S, height: 3 * S)).fill()
        }
        // Dust from under the feet while running.
        if dust {
            for i in 0 ..< 3 {
                let p = Double((tick + i * 3) % 9) / 9
                let dx = dir > 0 ? 4 - 8 * p - 2 * Double(i) : mascotW / S - 6 + 8 * p + 2 * Double(i)
                hexColor("#8C8C94").withAlphaComponent(0.7 * (1 - p)).setFill()
                NSBezierPath(rect: CGRect(x: area.minX + mx + dx * S, y: ground - 4 * p * S - 2 * S, width: 2 * S, height: 2 * S)).fill()
            }
        }
        // Confetti on the 5-hour reset.
        if confT >= 0 {
            for (i, c) in confetti.enumerated() where c.y > 0 {
                c.c.setFill()
                let cw = ((tick + i) / 2) % 2 == 1 ? 2.5 * S : 1.2 * S
                NSBezierPath(rect: CGRect(x: area.minX + c.x, y: ground - c.y, width: cw, height: 2.5 * S)).fill()
            }
        }
        // A spirit leaves the mouth of the lying Clawd and shimmers.
        if f.soul > 0.5 {
            drawSoul(CGPoint(x: area.minX + mx + 9.5 * px, y: ground - (f.lift * S + 6 * py)), f.soul * S, f.soulT)
        }
        // Petted: a heart floats up.
        if loveT >= 0 {
            let k = Double(loveT) / 20
            let hp = 1.4 * S
            heart(area.minX + mx + mascotW / 2 - 5 * S + 2 * S * sin(k * 6), ground - (23 + f.lift + 14 * k) * S - 6 * hp, hp,
                  fullCols: 6, on: hexColor("#F87171").withAlphaComponent(1 - k), off: .clear)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
