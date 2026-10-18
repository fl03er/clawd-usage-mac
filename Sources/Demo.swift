// Debug and demo hooks, used to make the README images (tools/record.sh).
//   CLAWD_DEMO=1            fake sessions, projects, history and weather; own settings
//   CLAWD_FAKE_USAGE=<file> /usage text to show instead of the probe
//   CLAWD_SCRIPT="1:mood=work;4:act=jump;6:pct=100"  timed changes (seconds after launch)
//   CLAWD_SNAPSHOT=<png>    save the widget after CLAWD_SNAPSHOT_DELAY seconds (8)
//   CLAWD_RECORD=<dir>      save every frame from CLAWD_RECORD_AT for CLAWD_RECORD_SECONDS
//   CLAWD_SKY_MINUTES=<m>   draw the sky at this time of day
//   CLAWD_THEME, CLAWD_SKIN, CLAWD_DETAILS=0|1, CLAWD_MOOD

import AppKit

var skyClockOverride: Double? = nil

final class Recorder {
    let dir: URL
    let start: Date, end: Date
    var n = 0
    var times: [Double] = []
    init(dir: String, at: Double, seconds: Double) {
        self.dir = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true)
        start = Date().addingTimeInterval(at); end = start.addingTimeInterval(seconds)
    }
    func capture(_ v: NSView) {
        let now = Date()
        guard now >= start else { return }
        if now > end {
            try? times.map { String(format: "%.3f", $0) }.joined(separator: "\n").write(to: dir.appendingPathComponent("times.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(String(format: "f%04d.png", n)))
        times.append(now.timeIntervalSince(start))
        n += 1
    }
}

extension AppDelegate {
    var demoProjects: Projects {
        Projects(total: ["clawd-usage-mac": 39, "pixel-garden": 22, "invoice-bot": 18, "tide-tables": 12, "dotfiles": 9])
    }

    func demoWeather() -> Weather {
        let code = Int(ProcessInfo.processInfo.environment["CLAWD_WX"] ?? "") ?? 1
        return Weather(code: code, temp: 18, wind: 12, sunrise: 400, sunset: 1100, at: Date())
    }

    func demoSessions() -> [Sess] {
        switch demoMood {
        case "work": return [Sess(name: "api", busy: true, waiting: false), Sess(name: "web", busy: false, waiting: false)]
        case "wait": return [Sess(name: "api", busy: false, waiting: true), Sess(name: "web", busy: false, waiting: false)]
        case "sleep": return []
        default: return [Sess(name: "api", busy: false, waiting: false), Sess(name: "web", busy: false, waiting: false)]
        }
    }

    // A week of samples: the 5-hour window climbs and resets, the week creeps up.
    func demoHistory() -> [[Int]] {
        let now = Int(Date().timeIntervalSince1970 / 60)
        var out: [[Int]] = []
        var t = now - 7 * 1440
        var week = 4.0
        while t <= now {
            let h = Double((t / 60) % 24)
            let awake = h >= 9 && h < 24
            if awake {
                let inWindow = Double(t % 300) / 300
                let s = Int(min(100, inWindow * (40 + 30 * sin(Double(t) / 900))))
                week += 0.02
                out.append([t, s, Int(week)])
            }
            t += 10
        }
        return out
    }

    func startDebugHooks(_ env: [String: String]) {
        if let m = env["CLAWD_SKY_MINUTES"], let v = Double(m) { skyClockOverride = v }
        if demo {
            demoMood = env["CLAWD_MOOD"] ?? "work"
            history.samples = demoHistory()
            refreshSessions(); refreshProjects(); refreshVersion(); refreshWeather()
            status = ServiceStatus(indicator: "none", incidents: [], broken: [])
        }
        if let fake = env["CLAWD_FAKE_USAGE"], let t = try? String(contentsOfFile: fake, encoding: .utf8) {
            handleUsage(t)
        }
        if let a = env["CLAWD_ACT"] {   // play an animation 2 s after launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.view.startAct(a) }
        }
        for step in (env["CLAWD_SCRIPT"] ?? "").split(separator: ";") {
            let parts = step.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let at = Double(parts[0]) else { continue }
            let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { self.runScriptStep(kv[0], kv[1]) }
        }
        if let dir = env["CLAWD_RECORD"] {
            recorder = Recorder(dir: dir, at: Double(env["CLAWD_RECORD_AT"] ?? "") ?? 2, seconds: Double(env["CLAWD_RECORD_SECONDS"] ?? "") ?? 5)
        }
        if let out = env["CLAWD_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["CLAWD_SNAPSHOT_DELAY"] ?? "") ?? 8)) {
                self.view.frame.size.height = self.view.contentHeight
                guard let rep = self.view.bitmapImageRepForCachingDisplay(in: self.view.bounds) else { return }
                self.view.cacheDisplay(in: self.view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                if self.demo { NSApp.terminate(nil) }
            }
        }
    }

    func runScriptStep(_ key: String, _ value: String) {
        switch key {
        case "mood": demoMood = value; refreshSessions()
        case "act": view.startAct(value)
        case "click": view.loveT = 0; view.startAct(value)
        case "pct":
            if let p = Int(value) {
                let old = usage?.session?.reset
                usage?.session = Limit(pct: p, reset: old)
                view.setMood(sessions: sessions, usage: usage)
            }
        case "reset":   // the 5-hour window resets: a later reset time, a lower percent
            if let p = Int(value) {
                usage?.session = Limit(pct: p, reset: Date().addingTimeInterval(5 * 3600))
                view.setMood(sessions: sessions, usage: usage)
            }
        case "stop": view.act = nil
        case "x": view.mx = Double(value) ?? view.mx; view.target = nil
        default: break
        }
        view.needsDisplay = true
    }
}
