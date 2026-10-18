// Data sources: `claude -p /usage`, the session registry, usage history,
// per-project usage from transcripts, Anthropic status, versions and weather.

import AppKit
import Darwin

// MARK: - /usage

struct Limit { var pct: Int; var reset: Date? }
struct Period { var requests: Int; var sessions: Int; var lines: [String] }
struct Usage { var session: Limit?; var week: Limit?; var fable: Limit?; var day: Period?; var week7: Period? }
struct Sess { var name: String; var busy: Bool; var waiting: Bool }

func firstMatch(_ text: String, _ pattern: String, _ opts: NSRegularExpression.Options = []) -> [String?]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: opts),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0 ..< m.numberOfRanges).map { i in
        Range(m.range(at: i), in: text).map { String(text[$0]) }
    }
}

// "Oct 17, 5:19am (Europe/Moscow)", "Oct 19, 6am" or "Oct 18 at 9:30pm" -> local Date. The output is always English.
func parseReset(_ s: String?) -> Date? {
    guard let s, let m = firstMatch(s, "([A-Za-z]{3})\\s+(\\d{1,2}),?\\s*(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*([ap]m)") else { return nil }
    let year = Calendar.current.component(.year, from: Date())
    let stamp = "\(m[1]!) \(m[2]!) \(year) \(m[3]!):\(m[4] ?? "00") \(m[5]!.uppercased())"
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "MMM d yyyy h:mm a"
    guard var d = df.date(from: stamp) else { return nil }
    // No year in the stamp: around New Year it lands in the past - then it is next year.
    if d < Date().addingTimeInterval(-30 * 86400) { d = Calendar.current.date(byAdding: .year, value: 1, to: d)! }
    return d
}

// The "Last 24h · 298 requests · 12 sessions" block and the indented lines below it.
func parsePeriod(_ text: String, _ label: String) -> Period? {
    guard let m = firstMatch(text, "^\(label)[^\\n]*?(\\d+)\\s+requests?\\b[^\\n]*?(\\d+)\\s+sessions?\\b[^\\n]*\\n((?:[ \\t]+[^\\n]*\\n?)*)",
                             .anchorsMatchLines),
          let r = Int(m[1] ?? ""), let s = Int(m[2] ?? "") else { return nil }
    let lines = (m[3] ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return Period(requests: r, sessions: s, lines: lines)
}

func parseUsage(_ text: String) -> Usage? {
    func lim(_ label: String) -> Limit? {
        // No "resets" means the window has not started: 0%, not "no data".
        guard let m = firstMatch(text, label + ":\\s*(\\d+)%(?:[^\\r\\n]*?resets\\s*([^\\r\\n]+))?"),
              let p = Int(m[1] ?? "") else { return nil }
        return Limit(pct: p, reset: parseReset(m[2] ?? nil))
    }
    let u = Usage(session: lim("Current session"), week: lim("Current week \\(all models\\)"),
                  fable: lim("Current week \\(Fable\\)"),
                  day: parsePeriod(text, "Last 24h"), week7: parsePeriod(text, "Last 7d"))
    return (u.session != nil || u.week != nil) ? u : nil
}

// Stats lines are shortened; unknown ones are kept as is, so new metrics are not lost.
var statRules: [(String, String)] { [
    ("^(\\d+)% of your usage was at >(\\S+) context", L("%1%는 >%2 컨텍스트", "%1% at >%2 context")),
    ("^(\\d+)% of your usage went to always-on context over (\\S+)", L("%1% 상시 컨텍스트 >%2", "%1% always-on context >%2")),
    ("^(\\d+)% of your usage came from subagent-heavy", L("%1% 서브에이전트 위주 세션", "%1% subagent-heavy sessions")),
    ("^(\\d+)% of your usage came from sessions active for (\\d+)\\+? hours", L("%1% %2시간+ 세션", "%1% sessions %2h+")),
    ("^Top MCP servers:\\s*(.+)$", "MCP: %1"),
    ("^Top skills:\\s*(.+)$", L("스킬: %1", "skills: %1")),
    ("^Top subagents:\\s*(.+)$", L("서브에이전트: %1", "subagents: %1")),
] }
func formatStat(_ line: String) -> String {
    for (re, out) in statRules {
        if let m = firstMatch(line, re) {
            var s = out
            for i in stride(from: m.count - 1, through: 1, by: -1) { s = s.replacingOccurrences(of: "%\(i)", with: m[i] ?? "") }
            return s
        }
    }
    return line
}

// MARK: - Sessions

func processStart(_ pid: Int32) -> Date? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let tv = info.kp_proc.p_un.__p_starttime
    return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
}

// Claude Code's own registry of running sessions. Files outlive their processes,
// so only count a file whose pid is alive and started when the file says.
func readSessions(excluding own: Set<Int32>) -> [Sess] {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
    guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "EEE MMM d HH:mm:ss yyyy"
    df.timeZone = TimeZone(identifier: "UTC")   // procStart is written in UTC
    var out: [Sess] = []
    for f in files where f.pathExtension == "json" {
        guard let data = try? Data(contentsOf: f),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pidN = j["pid"] as? Int else { continue }
        let pid = Int32(pidN)
        if own.contains(pid) { continue }
        guard let started = processStart(pid) else { continue }
        if let ps = j["procStart"] as? String, let d = df.date(from: ps), abs(d.timeIntervalSince(started)) > 5 { continue }
        var name = j["name"] as? String ?? ""
        if name.isEmpty, let cwd = j["cwd"] as? String { name = (cwd as NSString).lastPathComponent }
        let st = j["status"] as? String ?? ""
        out.append(Sess(name: name, busy: st == "busy", waiting: st == "waiting"))
    }
    return out.sorted { $0.name < $1.name }
}

func findClaude() -> String? {
    let home = NSHomeDirectory()
    for p in ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    where FileManager.default.isExecutableFile(atPath: p) { return p }
    let out = runCommand("/bin/zsh", ["-lic", "command -v claude"])
    let s = out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").last ?? ""
    return FileManager.default.isExecutableFile(atPath: s) ? s : nil
}

func runCommand(_ exe: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// MARK: - Usage history (lib/history.ps1)

let appSupport: URL = {
    let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClawdUsage")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}()

// A sample is [unix minute, session %, week %]; -1 - no value.
final class History {
    var samples: [[Int]] = []
    let url = appSupport.appendingPathComponent("usage-history.json")
    let stepMinutes = 5      // an unchanged value is sampled this often
    let gapMinutes = 20      // a longer pause between samples - the app was off: the line breaks

    init() {
        if let d = try? Data(contentsOf: url), let a = try? JSONSerialization.jsonObject(with: d) as? [[Int]] { samples = a }
    }

    func add(_ u: Usage) {
        let s = u.session?.pct ?? -1, w = u.week?.pct ?? -1
        let now = Int(Date().timeIntervalSince1970 / 60)
        if let last = samples.last, last[1] == s, last[2] == w, now - last[0] < stepMinutes { return }
        samples.append([now, s, w])
        let cut = now - 8 * 1440
        samples.removeAll { $0[0] < cut }
        if let d = try? JSONSerialization.data(withJSONObject: samples) { try? d.write(to: url) }
    }

    // Nearest sample at or before t, if it is not across a gap.
    func at(_ t: Int) -> [Int]? {
        var lo = 0, hi = samples.count - 1
        var hit: [Int]? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if samples[mid][0] <= t { hit = samples[mid]; lo = mid + 1 } else { hi = mid - 1 }
        }
        if let h = hit, t - h[0] <= gapMinutes { return h }
        return nil
    }
}

// MARK: - Projects (tokens weighted by model price, from transcripts)

struct Projects { var total: [String: Double] = [:]; var hours: [Int: [String: Double]] = [:]; var paths: [String: String] = [:] }

final class ProjectScanner {
    struct FileState { var pos: UInt64 = 0; var ids = Set<String>(); var dir: String; var cwd: String?; var w: [Int: Double] = [:] }
    private var cache: [String: FileState] = [:]
    private let queue = DispatchQueue(label: "clawd.projects", qos: .utility)
    private(set) var running = false
    // Price of a million input tokens; the first match wins, so versions go first.
    let prices: [(String, Double)] = [("fable", 10), ("mythos", 10), ("opus-5-5", 4), ("opus", 5),
                                      ("sonnet-5", 2), ("sonnet", 3), ("haiku-5", 0.1), ("haiku", 1)]
    // Cache writes, cache reads and output relative to input.
    let kinds: [(String, Double)] = [("\"input_tokens\":", 1), ("\"cache_creation_input_tokens\":", 1.25),
                                     ("\"cache_read_input_tokens\":", 0.1), ("\"output_tokens\":", 5)]

    func scan(_ done: @escaping (Projects) -> Void) {
        if running { return }
        running = true
        queue.async {
            let r = self.run()
            DispatchQueue.main.async { self.running = false; done(r) }
        }
    }

    private func str(_ line: Substring, _ key: String) -> Substring? {
        guard let r = line.range(of: "\"\(key)\":\"") else { return nil }
        let rest = line[r.upperBound...]
        guard let e = rest.firstIndex(of: "\"") else { return nil }
        return rest[..<e]
    }
    private func num(_ line: Substring, _ key: String) -> Double {
        guard let r = line.range(of: key) else { return 0 }
        let digits = line[r.upperBound...].prefix { $0.isNumber }
        return Double(digits) ?? 0
    }

    private func run() -> Projects {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let since = Date().addingTimeInterval(-7 * 86400)
        let firstHour = Int(since.timeIntervalSince1970 / 3600)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var seen = Set<String>()
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for pd in dirs {
            guard let en = fm.enumerator(at: pd, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { continue }
            for case let f as URL in en where f.pathExtension == "jsonl" {
                let rv = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let mod = rv?.contentModificationDate, mod >= since else { continue }
                let size = UInt64(rv?.fileSize ?? 0)
                seen.insert(f.path)
                var c = cache[f.path] ?? FileState(dir: pd.lastPathComponent)
                if size < c.pos { c = FileState(dir: pd.lastPathComponent) }
                if size == c.pos { cache[f.path] = c; continue }
                guard let h = try? FileHandle(forReadingFrom: f) else { continue }
                try? h.seek(toOffset: c.pos)
                let data = (try? h.readToEnd()) ?? Data()
                try? h.close()
                // A line still being written waits for the next scan.
                guard let end = data.lastIndex(of: 0x0A) else { cache[f.path] = c; continue }
                let chunk = data[data.startIndex ... end]
                c.pos += UInt64(chunk.count)
                let text = String(decoding: chunk, as: UTF8.self)
                for line in text.split(separator: "\n") {
                    if c.cwd == nil, let cwd = str(line, "cwd") { c.cwd = String(cwd).replacingOccurrences(of: "\\\\", with: "\\") }
                    guard line.contains("\"usage\":{\"input_tokens\"") else { continue }
                    if let id = str(line, "id"), id.hasPrefix("msg_") {
                        if c.ids.contains(String(id)) { continue }
                        c.ids.insert(String(id))
                    }
                    let model = str(line, "model").map(String.init) ?? ""
                    if model == "<synthetic>" { continue }
                    guard let ts = str(line, "timestamp"), let at = iso.date(from: String(ts)) else { continue }
                    let hour = Int(at.timeIntervalSince1970 / 3600)
                    if hour < firstHour { continue }
                    let price = prices.first { model.contains($0.0) }?.1 ?? 3
                    var tok = 0.0
                    for (k, m) in kinds { tok += m * num(line, k) }
                    c.w[hour, default: 0] += price * tok
                }
                cache[f.path] = c
            }
        }
        // Transcripts that fell out of the week are forgotten.
        for k in cache.keys where !seen.contains(k) { cache.removeValue(forKey: k) }

        var cwds: [String: String] = [:]
        for c in cache.values { if let cwd = c.cwd, cwds[c.dir] == nil { cwds[c.dir] = cwd } }
        let home = NSHomeDirectory()
        var r = Projects()
        for c in cache.values {
            let cwd = cwds[c.dir] ?? c.dir
            let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
            let name = trimmed == home ? "~" : (trimmed as NSString).lastPathComponent
            r.paths[name] = cwd
            for (h, w) in c.w where h >= firstHour {
                r.total[name, default: 0] += w
                r.hours[h, default: [:]][name, default: 0] += w
            }
        }
        return r
    }
}

// MARK: - Network: status, version, weather

func fetchText(_ url: String, _ done: @escaping (String?) -> Void) {
    guard let u = URL(string: url) else { done(nil); return }
    var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    req.setValue("clawd-usage-mac", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: req) { d, resp, _ in
        let ok = (resp as? HTTPURLResponse).map { (200 ..< 300).contains($0.statusCode) } ?? false
        let s = ok ? d.map { String(decoding: $0, as: UTF8.self) } : nil
        DispatchQueue.main.async { done(s) }
    }.resume()
}
func fetchJSON(_ url: String, _ done: @escaping ([String: Any]?) -> Void) {
    fetchText(url) { s in
        done(s.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    }
}

struct ServiceStatus { var indicator: String; var incidents: [String]; var broken: [String] }

func parseStatus(_ j: [String: Any]) -> ServiceStatus {
    let ind = (j["status"] as? [String: Any])?["indicator"] as? String ?? "none"
    let inc = (j["incidents"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    var broken: [String] = []
    for c in j["components"] as? [[String: Any]] ?? [] {
        if c["group"] as? Bool == true || c["status"] as? String == "operational" { continue }
        // "Claude API (api.anthropic.com)" -> "Claude API"
        if let n = c["name"] as? String { broken.append(n.replacingOccurrences(of: "\\s*\\(.*\\)\\s*$", with: "", options: .regularExpression)) }
    }
    return ServiceStatus(indicator: ind, incidents: inc, broken: broken)
}

struct Weather { var code: Int; var temp: Double; var wind: Double; var sunrise: Double?; var sunset: Double?; var at: Date }
struct Place { var lat: Double; var lon: Double; var city: String? }

struct WeatherKind { var name: String; var cover: Double; var fog = false; var storm = false; var rain = 0; var snow = 0 }

// WMO weather codes. rain/snow - drops or flakes at medium intensity; three codes - light, moderate, heavy.
func weatherKind(_ code: Int) -> WeatherKind {
    let table: [([Int], String, Double, Bool, Bool, Int, Int)] = [
        ([0], L("맑음", "clear"), 0, false, false, 0, 0), ([1], L("대체로 맑음", "mostly clear"), 0.2, false, false, 0, 0),
        ([2], L("구름 조금", "partly cloudy"), 0.5, false, false, 0, 0), ([3], L("흐림", "overcast"), 0.85, false, false, 0, 0),
        ([45, 48], L("안개", "fog"), 0.7, true, false, 0, 0), ([51, 53, 55], L("이슬비", "drizzle"), 0.8, false, false, 6, 0),
        ([56, 57], L("어는 이슬비", "freezing drizzle"), 0.8, false, false, 6, 0), ([61, 63, 65], L("비", "rain"), 0.9, false, false, 12, 0),
        ([66, 67], L("어는 비", "freezing rain"), 0.9, false, false, 12, 0), ([71, 73, 75], L("눈", "snow"), 0.85, false, false, 0, 10),
        ([77], L("싸락눈", "snow grains"), 0.85, false, false, 0, 8), ([80, 81, 82], L("소나기", "showers"), 0.85, false, false, 16, 0),
        ([85, 86], L("눈 소나기", "snow showers"), 0.9, false, false, 0, 14), ([95, 96, 99], L("뇌우", "thunderstorm"), 1.0, false, true, 16, 0),
    ]
    for (codes, name, cover, fog, storm, rain, snow) in table {
        guard let i = codes.firstIndex(of: code) else { continue }
        let mul = codes.count == 3 ? [0.6, 1.0, 1.35][i] : 1.0
        return WeatherKind(name: name, cover: cover, fog: fog, storm: storm,
                           rain: Int((Double(rain) * mul).rounded()), snow: Int((Double(snow) * mul).rounded()))
    }
    return WeatherKind(name: L("날씨 코드 \(code)", "weather code \(code)"), cover: 0.5)
}

// Sunrise and sunset from coordinates (NOAA formulas), local time, minutes from midnight.
func sunCalc(_ lat: Double, _ lon: Double) -> (Double, Double) {
    let now = Date()
    let doy = Double(Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1)
    let gm = 2 * Double.pi / 365 * (doy - 0.5)
    let eq = 229.18 * (0.000075 + 0.001868 * cos(gm) - 0.032077 * sin(gm) - 0.014615 * cos(2 * gm) - 0.040849 * sin(2 * gm))
    let dec = 0.006918 - 0.399912 * cos(gm) + 0.070257 * sin(gm) - 0.006758 * cos(2 * gm) + 0.000907 * sin(2 * gm)
        - 0.002697 * cos(3 * gm) + 0.00148 * sin(3 * gm)
    let la = lat * .pi / 180
    var c = cos(90.833 * .pi / 180) / (cos(la) * cos(dec)) - tan(la) * tan(dec)
    c = max(-0.999, min(0.999, c))   // polar day or night
    let ha = acos(c) * 180 / .pi
    let tz = Double(TimeZone.current.secondsFromGMT(for: now)) / 60
    func wrap(_ v: Double) -> Double { (v.truncatingRemainder(dividingBy: 1440) + 1440).truncatingRemainder(dividingBy: 1440) }
    return (wrap(720 - 4 * (lon + ha) - eq + tz), wrap(720 - 4 * (lon - ha) - eq + tz))
}

// Moon age in days, with the main periodic terms (good to about an hour).
let moonMonth = 29.530588853
func moonAge() -> Double {
    let j2000 = Date(timeIntervalSince1970: 946_728_000)
    let d = Date().timeIntervalSince(j2000) / 86400
    let rad = Double.pi / 180
    let g = (357.528 + 0.9856003 * d) * rad
    let sun = 280.460 + 0.9856474 * d + 1.915 * sin(g) + 0.020 * sin(2 * g)
    let Lm = 218.316 + 13.176396 * d
    let Mm = (134.963 + 13.064993 * d) * rad
    let D = (Lm - (280.460 + 0.9856474 * d)) * rad
    let moon = Lm + 6.289 * sin(Mm) - 1.274 * sin(2 * D - Mm) + 0.658 * sin(2 * D) - 0.186 * sin(g)
        - 0.059 * sin(2 * D - 2 * Mm) - 0.057 * sin(2 * D - Mm - g)
    let e = ((moon - sun).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return e / 360 * moonMonth
}

// MARK: - Formatting

func levelColor(_ pct: Int) -> NSColor {
    if pct >= 85 { return hexColor("#F87171") }
    if pct >= 60 { return hexColor("#FBBF24") }
    return hexColor("#4ADE80")
}

func leftText(_ d: Date?) -> String {
    guard let d else { return "" }
    let m = max(0, Int(d.timeIntervalSinceNow / 60))
    if m >= 1440 { return L("\(m / 1440)일 \(m % 1440 / 60)시간", "\(m / 1440)d \(m % 1440 / 60)h") }
    if m >= 60 { return L("\(m / 60)시간 \(m % 60)분", "\(m / 60)h \(m % 60)m") }
    return L("\(m)분", "\(m)m")
}

func clock(_ d: Date, _ fmt: String = "HH:mm") -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: isKo ? "ko_KR" : "en_US")
    df.dateFormat = fmt
    return df.string(from: d)
}

func hexColor(_ s: String) -> NSColor {
    var h = s.trimmingCharacters(in: .whitespaces)
    if h.hasPrefix("#") { h.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: h).scanHexInt64(&v)
    if h.count == 8 {   // #AARRGGBB, as in the original
        return NSColor(srgbRed: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255,
                       blue: Double(v & 0xFF) / 255, alpha: Double(v >> 24 & 0xFF) / 255)
    }
    return NSColor(srgbRed: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255, alpha: 1)
}
