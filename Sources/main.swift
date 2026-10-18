// Clawd Usage for macOS: a port of github.com/Enhed/clawd-usage-winwidget.
// Menu bar item (animated Clawd + session %); clicking it drops the widget down.
// Data: `claude -p /usage` (no tokens spent), ~/.claude/sessions/*.json and the
// transcripts in ~/.claude/projects; status.claude.com, Claude Code releases and
// Open-Meteo for the extras.

import AppKit
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var view: ClawdView!
    // Demo mode (README images) keeps its settings apart from the real ones.
    let demo = ProcessInfo.processInfo.environment["CLAWD_DEMO"] == "1"
    lazy var defaults: UserDefaults = demo ? UserDefaults(suiteName: "local.clawd-usage-mac.demo")! : .standard
    var demoMood = "work"
    var recorder: Recorder?
    let panelW = 320.0

    var usage: Usage?
    var usageAt: Date?
    var stale = false
    var errorText: String?
    var sessions: [Sess] = []
    var claudePath: String?
    var probe: Process?
    let history = History()
    let projectScanner = ProjectScanner()
    var projects: Projects?
    var projectsAt: Date?
    var status: ServiceStatus?
    var verLocal: String?, verLatest: String?
    var place: Place?
    var weather: Weather?
    var skins: [Skin] = []
    var iconCache: [String: NSImage] = [:]

    var pinned: Bool { defaults.bool(forKey: "pinned") }
    var detailsOn: Bool { defaults.bool(forKey: "details") }
    var showSky: Bool { defaults.object(forKey: "showSky") as? Bool ?? true }
    var themeId: String { defaults.string(forKey: "theme") ?? "classic" }
    var skinId: String { defaults.string(forKey: "skin") ?? "classic" }
    var alertsOn: Bool { defaults.object(forKey: "alerts") as? Bool ?? true }
    var loginOn: Bool { SMAppService.mainApp.status == .enabled }

    func applicationDidFinishLaunching(_ n: Notification) {
        let env = ProcessInfo.processInfo.environment
        if let t = env["CLAWD_THEME"] { defaults.set(t, forKey: "theme") }
        if let s = env["CLAWD_SKIN"] { defaults.set(s, forKey: "skin") }
        if let d = env["CLAWD_DETAILS"] { defaults.set(d == "1", forKey: "details") }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        // Left click: the widget drops down under the icon. Right click: menu.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        uiLang = env["CLAWD_LANG"] ?? defaults.string(forKey: "lang") ?? "auto"
        skins = loadSkins()
        view = ClawdView(frame: NSRect(x: 0, y: 0, width: panelW, height: 300))
        view.app = self
        applyLook()
        panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        applyPinned()
        // Dropdown mode: a click anywhere else closes the widget.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.pinned, self.panel.isVisible else { return }
            self.panel.orderOut(nil)
        }

        updateStatusIcon(Frame())
        updateStatusTitle()
        view.start()

        UNUserNotificationCenter.current().delegate = self
        if alertsOn { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }

        refreshSessions()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshSessions() }
        DispatchQueue.global().async {
            let p = findClaude()
            DispatchQueue.main.async {
                self.claudePath = p
                if p == nil { self.errorText = L("claude CLI를 찾지 못했습니다. Claude Code를 설치하세요.", "Couldn't find the claude CLI. Install Claude Code."); self.view.needsDisplay = true }
                self.runProbe()
                self.refreshVersion()
            }
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.runProbe() }
        refreshStatus()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refreshStatus() }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.refreshVersion() }
        refreshWeather()
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.refreshWeather() }
        refreshProjects()
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in self?.refreshProjects() }

        startDebugHooks(env)
    }

    // MARK: panel

    func resizePanel() {
        let h = view.contentHeight
        if abs(panel.frame.height - h) < 0.5 { return }
        var f = panel.frame
        f.origin.y += f.height - h; f.size.height = h
        panel.setFrame(f, display: true)
    }

    // Pinned: the widget stays on the desktop where you drag it. Otherwise it is
    // a dropdown under the menu bar icon.
    func applyPinned() {
        if pinned {
            panel.level = .floating
            panel.setFrameAutosaveName("")
            if !panel.setFrameUsingName("ClawdWidgetPinned"), let vf = NSScreen.main?.visibleFrame {
                panel.setFrame(NSRect(x: vf.maxX - panelW - 20, y: vf.maxY - 20 - view.contentHeight, width: panelW, height: view.contentHeight), display: true)
            }
            panel.setFrameAutosaveName("ClawdWidgetPinned")
            panel.orderFrontRegardless()
        } else {
            panel.setFrameAutosaveName("")
            panel.level = .statusBar
            panel.orderOut(nil)
        }
    }

    func showDropdown() {
        guard let button = statusItem.button, let bw = button.window else { return }
        let r = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let vf = bw.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(r.midX - panelW / 2, vf.minX + 8), vf.maxX - panelW - 8)
        let h = view.contentHeight
        panel.setFrame(NSRect(x: x, y: r.minY - 6 - h, width: panelW, height: h), display: true)
        panel.orderFrontRegardless()
        view.needsDisplay = true
        // Opening refreshes numbers older than 30 s.
        if usageAt.map({ Date().timeIntervalSince($0) > 30 }) ?? true { runProbe() }
        if detailsOn { refreshProjects() }
    }

    @objc func statusClicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if pinned { panel.orderFrontRegardless(); return }
        if panel.isVisible { panel.orderOut(nil) } else { showDropdown() }
    }

    // MARK: data

    // `claude -p /usage`: same numbers as /usage, no model call, ~2-3 s.
    func runProbe() {
        if demo { return }
        guard probe == nil, let exe = claudePath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["-p", "/usage", "--output-format", "text", "--no-session-persistence"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { stale = true; return }
        probe = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { if p.isRunning { p.terminate() } }
        DispatchQueue.global().async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self.probe = nil; self.handleUsage(text) }
        }
    }

    func handleUsage(_ text: String) {
        if let u = parseUsage(text) {
            checkAlerts(old: usage, new: u)
            usage = u; usageAt = Date(); stale = false; errorText = nil
            if !demo { history.add(u) }
        } else {
            // Keep the last numbers and mark them stale.
            stale = usage != nil
            if usage == nil {
                errorText = L("사용량 한도를 받지 못했습니다. 터미널에서 `claude auth login`으로 Claude 구독 계정에 로그인하세요.",
                               "No limits from /usage. Log in with your Claude subscription: run `claude auth login` in a terminal.")
            }
        }
        view.setMood(sessions: sessions, usage: usage)
        updateStatusTitle()
        view.needsDisplay = true
    }

    // MARK: alerts

    // Once per limit window and threshold: 80%, 95% and used up. A window is told
    // apart by its reset time. Also: the 5-hour window reset after a busy stretch.
    func checkAlerts(old: Usage?, new u: Usage) {
        guard alertsOn, ProcessInfo.processInfo.environment["CLAWD_FAKE_USAGE"] == nil else { return }
        for (key, label, lim) in [("session", L("현재 세션", "Session"), u.session), ("week", L("주간 한도", "Weekly limit"), u.week)] {
            guard let l = lim, let reset = l.reset else { continue }
            let window = Int(reset.timeIntervalSince1970 / 60)
            for th in [100, 95, 80] where l.pct >= th {
                if defaults.integer(forKey: "alert.\(key).\(th)") == window { break }
                // The highest threshold crossed speaks; the lower ones count as told.
                for lower in [100, 95, 80] where lower <= th { defaults.set(window, forKey: "alert.\(key).\(lower)") }
                let left = key == "session" ? L("\(leftText(reset)) 후 리셋 (\(clock(reset)))", "resets in \(leftText(reset)) (\(clock(reset)))")
                    : L("\(clock(reset, "E HH:mm")) 리셋", "resets \(clock(reset, "E HH:mm"))")
                notify(th >= 100 ? L("\(label) 한도를 다 썼어요", "\(label) used up") : L("\(label) \(l.pct)% 사용", "\(label) at \(l.pct)%"), left)
                break
            }
        }
        if let o = old?.session, let n = u.session, let or = o.reset, let nr = n.reset,
           nr > or.addingTimeInterval(60), n.pct < o.pct, o.pct >= 50 {
            notify(L("5시간 세션이 리셋됐어요", "The 5-hour window reset"), L("현재 세션 \(n.pct)% · 다음 리셋 \(clock(nr))", "session \(n.pct)% · next reset \(clock(nr))"))
        }
    }

    func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    func refreshSessions() {
        if demo { sessions = demoSessions(); view.setMood(sessions: sessions, usage: usage); view.needsDisplay = true; return }
        var own = Set<Int32>([getpid()])
        if let p = probe { own.insert(p.processIdentifier) }
        let ss = readSessions(excluding: own)
        let changed = ss.map { "\($0.name)\($0.busy)\($0.waiting)" } != sessions.map { "\($0.name)\($0.busy)\($0.waiting)" }
        sessions = ss
        view.setMood(sessions: sessions, usage: usage)
        if changed { view.needsDisplay = true }
    }

    func refreshProjects() {
        if demo { projects = demoProjects; return }
        if let at = projectsAt, Date().timeIntervalSince(at) < 300 { return }
        projectScanner.scan { p in
            self.projects = p; self.projectsAt = Date()
            self.view.needsDisplay = true
        }
        view.needsDisplay = true
    }

    func refreshStatus() {
        fetchJSON("https://status.claude.com/api/v2/summary.json") { j in
            if let j { self.status = parseStatus(j); self.view.needsDisplay = true }
        }
    }

    // Local version from `claude --version`; the latest from where the official installer looks.
    func refreshVersion() {
        if demo { verLocal = "2.1.302"; verLatest = "2.1.302"; return }
        if let exe = claudePath {
            DispatchQueue.global().async {
                let out = runCommand(exe, ["--version"])
                let v = firstMatch(out, "(\\d+\\.\\d+\\.\\d+)")?[1] ?? nil
                DispatchQueue.main.async { self.verLocal = v; self.view.needsDisplay = true }
            }
        }
        var channel = "latest"
        let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        if let d = try? Data(contentsOf: settings), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let c = j["autoUpdatesChannel"] as? String, ["stable", "latest"].contains(c) { channel = c }
        fetchText("https://downloads.claude.ai/claude-code-releases/\(channel)") { s in
            if let s, let v = firstMatch(s, "^\\s*(\\d+\\.\\d+\\.\\d+)")?[1] { self.verLatest = v; self.view.needsDisplay = true }
        }
    }

    // Location by IP once (ipwho.is), then the weather from Open-Meteo.
    func refreshWeather() {
        if demo { weather = demoWeather(); return }
        guard showSky else { return }
        guard let pl = place else {
            fetchJSON("https://ipwho.is/?lang=ko") { j in
                guard let j, j["success"] as? Bool != false, let lat = j["latitude"] as? Double, let lon = j["longitude"] as? Double else { return }
                self.place = Place(lat: lat, lon: lon, city: j["city"] as? String)
                self.refreshWeather()
            }
            return
        }
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(pl.lat)&longitude=\(pl.lon)"
            + "&current=weather_code,temperature_2m,wind_speed_10m&daily=sunrise,sunset&timezone=auto&forecast_days=1"
        fetchJSON(url) { j in
            guard let j, let cur = j["current"] as? [String: Any], let code = cur["weather_code"] as? Int else { return }
            func minutes(_ key: String) -> Double? {
                guard let s = ((j["daily"] as? [String: Any])?[key] as? [String])?.first,
                      let m = firstMatch(s, "T(\\d{2}):(\\d{2})"), let h = Double(m[1] ?? ""), let mm = Double(m[2] ?? "") else { return nil }
                return h * 60 + mm
            }
            self.weather = Weather(code: code, temp: cur["temperature_2m"] as? Double ?? 0, wind: cur["wind_speed_10m"] as? Double ?? 8,
                                   sunrise: minutes("sunrise"), sunset: minutes("sunset"), at: Date())
            self.view.needsDisplay = true
        }
    }

    // MARK: menu bar

    func updateStatusTitle() {
        guard let s = usage?.session else { statusItem.button?.title = stale ? " –" : ""; return }
        statusItem.button?.title = " \(s.pct)%" + (s.reset.map { " \(clock($0))" } ?? "")
    }

    // The menu bar crab mirrors the widget's current frame, in the current skin.
    func updateStatusIcon(_ f: Frame) {
        var f = f
        f.x = 0; f.lift = 0
        let key = skin().id + f.key
        if let img = iconCache[key] { statusItem.button?.image = img; return }
        let g = buildGeo(f)
        let sk = skin()
        let acc = accessoryRects(sk, f)
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            let oy = 3.5
            func fill(_ rects: [CGRect]) {
                for r in rects { NSBezierPath(rect: CGRect(x: 1 + r.minX, y: oy + r.minY * 1.1, width: r.width, height: r.height * 1.1)).fill() }
            }
            hexColor("#C29E66").setFill(); fill(g.sand)
            sk.body.setFill(); fill(g.body)
            sk.eyes.setFill(); fill(g.eyes)
            for (c, rects) in acc { c.setFill(); fill(rects) }
            return true
        }
        iconCache[key] = img
        statusItem.button?.image = img
    }

    func skin() -> Skin { skins.first { $0.id == skinId } ?? skins.first ?? Skin(id: "classic", fileName: "Classic") }

    func applyLook() {
        view.theme = currentTheme(themeId)
        view.skin = skin()
        view.geoCache = [:]
        updateStatusIconIfReady()
        view.needsDisplay = true
    }
    func updateStatusIconIfReady() { if statusItem != nil { updateStatusIcon(view.cf) } }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        func info(_ s: String) { let it = NSMenuItem(title: s, action: nil, keyEquivalent: ""); it.isEnabled = false; m.addItem(it) }
        if let u = usage {
            if let s = u.session { info(L("현재 세션", "Session") + " \(s.pct)%" + (s.reset.map { L(" · \(clock($0)) 리셋", " · resets \(clock($0))") } ?? "")) }
            if let w = u.week { info(L("주간 한도", "Week") + " \(w.pct)%" + (w.reset.map { L(" · \(clock($0, "E HH:mm")) 리셋", " · resets \(clock($0, "E HH:mm"))") } ?? "")) }
            if let fb = u.fable { info(L("주간 (Fable)", "Fable · week") + " \(fb.pct)%") }
        } else {
            info(errorText == nil ? L("불러오는 중…", "Loading…") : L("사용량 없음: 터미널에서 claude auth login 필요", "No usage: run claude auth login in a terminal"))
        }
        m.addItem(.separator())
        if sessions.isEmpty { info(L("실행 중인 Claude Code 세션 없음", "No Claude Code sessions running")) }
        for s in sessions { info("\(s.waiting ? "?" : s.busy ? "▶" : "○")  \(s.name)") }
        m.addItem(.separator())
        func item(_ title: String, _ sel: Selector, _ on: Bool? = nil, _ rep: Any? = nil, in menu: NSMenu? = nil) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            it.representedObject = rep
            if let on { it.state = on ? .on : .off }
            (menu ?? m).addItem(it)
        }
        item(L("지금 새로고침", "Refresh now"), #selector(refreshNow))
        item(L("자세히 보기", "Details"), #selector(toggleDetails), detailsOn)
        let tm = NSMenu()
        item(L("계절 따라 (가을엔 할로윈)", "By season (Halloween in autumn)"), #selector(pickTheme(_:)), themeId == "auto", "auto", in: tm)
        tm.addItem(.separator())
        for t in themes { item(t.name, #selector(pickTheme(_:)), themeId == t.id, t.id, in: tm) }
        let ti = NSMenuItem(title: L("테마", "Theme"), action: nil, keyEquivalent: ""); ti.submenu = tm; m.addItem(ti)
        let sm = NSMenu()
        for s in skins { item(s.name, #selector(pickSkin(_:)), skinId == s.id, s.id, in: sm) }
        sm.addItem(.separator())
        item(L("내 스킨 폴더 열기", "Open my skins folder"), #selector(openSkinFolder), nil, nil, in: sm)
        let si = NSMenuItem(title: L("Clawd 스킨", "Clawd's skin"), action: nil, keyEquivalent: ""); si.submenu = sm; m.addItem(si)
        item(L("하늘과 날씨", "Sky and weather"), #selector(toggleSky), showSky)
        item(L("바탕화면에 고정", "Pin to desktop"), #selector(togglePinned), pinned)
        m.addItem(.separator())
        item(L("한도 알림 (80% · 95% · 소진 · 리셋)", "Limit alerts (80% · 95% · used up · reset)"), #selector(toggleAlerts), alertsOn)
        item(L("로그인 시 자동 실행", "Start at login"), #selector(toggleLogin), loginOn)
        let lm = NSMenu()
        for (id, title) in [("auto", L("시스템 설정 따라", "System")), ("ko", "한국어"), ("en", "English")] {
            item(title, #selector(pickLang(_:)), uiLang == id, id, in: lm)
        }
        let li = NSMenuItem(title: L("언어", "Language"), action: nil, keyEquivalent: ""); li.submenu = lm; m.addItem(li)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: L("종료", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return m
    }

    @objc func refreshNow() { runProbe(); refreshStatus(); projectsAt = nil; refreshProjects() }
    @objc func toggleDetails() {
        defaults.set(!detailsOn, forKey: "details")
        if detailsOn { refreshProjects() }
        view.needsDisplay = true
    }
    @objc func pickTheme(_ s: NSMenuItem) { defaults.set(s.representedObject as? String, forKey: "theme"); applyLook() }
    @objc func pickSkin(_ s: NSMenuItem) { defaults.set(s.representedObject as? String, forKey: "skin"); applyLook() }
    @objc func openSkinFolder() {
        let dir = appSupport.appendingPathComponent("skins")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
    @objc func toggleSky() {
        defaults.set(!showSky, forKey: "showSky")
        if showSky { refreshWeather() }
        view.needsDisplay = true
    }
    @objc func pickLang(_ s: NSMenuItem) {
        uiLang = s.representedObject as? String ?? "auto"
        defaults.set(uiLang, forKey: "lang")
        updateStatusTitle()
        view.needsDisplay = true
    }
    @objc func toggleAlerts() {
        defaults.set(!alertsOn, forKey: "alerts")
        if alertsOn {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                if ok { DispatchQueue.main.async { self.notify(L("한도 알림을 켰어요", "Limit alerts are on"), L("세션·주간 한도가 80%, 95%를 넘거나 다 쓰면 알려 드릴게요.", "You'll be told when the session or the week passes 80% and 95% or runs out.")) } }
            }
        }
    }
    // Registers this app as a login item; macOS may ask to approve it in System Settings.
    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let a = NSAlert()
            a.messageText = L("로그인 항목을 바꾸지 못했습니다", "Couldn't change the login item")
            a.informativeText = "\(error.localizedDescription)\n\n" + L("앱을 응용 프로그램 폴더에서 실행했는지 확인하세요.", "Make sure the app runs from an Applications folder.")
            a.runModal()
        }
        if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    @objc func togglePinned() {
        defaults.set(!pinned, forKey: "pinned")
        applyPinned()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
