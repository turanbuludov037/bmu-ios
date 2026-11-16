import SwiftUI
import UIKit

/// İstifadə statistikası (Android Usage.kt ilə eyni format → admin tətbiqində və analitika saytında görünür).
/// usage/<nömrə>_<YYYYMMDD>: ekran vaxtı, hərəkətlər, açılışlar, saatlar, keçidlər, portal sürəti, cihaz, ayarlar.
/// live/<nömrə>: indi tətbiqdədirmi, hansı ekrandadır.
@MainActor
final class Usage {
    static let shared = Usage()

    private struct Stats: Codable {
        var date: String
        var ms = 0
        var sessions = 0
        var screens: [String: [Int]] = [:]       // ekran → [baxış, ms]
        var actions: [String: Int] = [:]
        var opens: [String: Int] = [:]
        var log: [String] = []
        var hours = [Int](repeating: 0, count: 24) // ms
        var paths: [String: Int] = [:]
        var content: [String: Int] = [:]
        var portal: [String: [Int]] = [:]         // açar → [say, uğursuz, ümumi ms, ən uzun]
        var errors: [String: Int] = [:]
        var sessLen: [Int] = []
        var startup: [String: [Int]] = [:]        // növ → [say, ümumi ms, ən uzun]
        var loads: [String: [Int]] = [:]
    }

    private var day: Stats
    private var screen: String?
    private var screenSince = Date()
    private var tickAt = Date()
    private var sessionStart: Date?
    private var foreground = false
    private var lastSent = Date.distantPast
    private var lastLive = Date.distantPast
    private var profile = Profile()
    private var number = ""
    private let mapMax = 80
    static let launchedAt = Date()
    private var coldDone = false

    private init() {
        if let d = UserDefaults.standard.data(forKey: "usage_day"), let saved = try? JSONDecoder().decode(Stats.self, from: d) {
            day = saved
        } else {
            day = Stats(date: Usage.today())
        }
        if UserDefaults.standard.string(forKey: "usage_first") == nil { UserDefaults.standard.set(Usage.today(), forKey: "usage_first") }
    }

    private static func today() -> String { Day.key(Date()) }
    private static func clock() -> String {
        let c = Day.cal.dateComponents([.hour, .minute, .second], from: Date())
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    private func rollIfNeeded() {
        let d = Usage.today()
        if day.date != d {
            send(force: true)
            day = Stats(date: d)
        }
    }

    private func log(_ kind: String, _ text: String) {
        day.log.append("\(Usage.clock())|\(kind)|\(String(text.prefix(60)))")
        if day.log.count > 200 { day.log.removeFirst(day.log.count - 200) }
    }

    private func bump(_ m: inout [String: Int], _ k: String, by n: Int = 1) {
        if m[k] == nil && m.count >= mapMax { return }
        m[k, default: 0] += n
    }

    /// Keçən vaxtı cari ekrana və saata yaz.
    private func tick() {
        let now = Date()
        guard foreground else { tickAt = now; return }
        let ms = Int(now.timeIntervalSince(tickAt) * 1000)
        tickAt = now
        guard ms > 0, ms < 30 * 60_000 else { return }
        day.ms += ms
        day.hours[Day.cal.component(.hour, from: now)] += ms
        if let s = screen, var v = day.screens[s] { v[1] += ms; day.screens[s] = v }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(day) { UserDefaults.standard.set(d, forKey: "usage_day") }
    }

    // MARK: hadisələr

    func setUser(_ p: Profile) {
        profile = p
        number = p.number.trimmed.lowercased()
    }

    func screen(_ name: String) {
        rollIfNeeded()
        tick()
        if name == screen { return }
        if let prev = screen { bump(&day.paths, "\(prev)>\(name)") }
        screen = name
        screenSince = Date()
        if day.screens[name] == nil && day.screens.count >= mapMax { return }
        var v = day.screens[name] ?? [0, 0]
        v[0] += 1
        day.screens[name] = v
        log("s", name)
        live(force: false)
    }

    func action(_ name: String, _ detail: String = "") {
        rollIfNeeded()
        bump(&day.actions, name)
        if !detail.isEmpty { bump(&day.content, "\(name)|\(String(detail.prefix(40)))") }
        log("a", detail.isEmpty ? name : "\(name):\(detail)")
    }

    func opened(_ source: String) {
        bump(&day.opens, source)
        log("o", source)
    }

    func error(_ text: String) {
        bump(&day.errors, String(text.prefix(40)))
        log("e", text)
    }

    func portal(_ key: String, ms: Int, ok: Bool) {
        if day.portal[key] == nil && day.portal.count >= mapMax { return }
        var v = day.portal[key] ?? [0, 0, 0, 0]
        v[0] += 1
        if !ok { v[1] += 1 }
        v[2] += ms
        v[3] = max(v[3], ms)
        day.portal[key] = v
    }

    func startup(_ kind: String, ms: Int) {
        var v = day.startup[kind] ?? [0, 0, 0]
        v[0] += 1; v[1] += ms; v[2] = max(v[2], ms)
        day.startup[kind] = v
    }

    /// Ana ekran ilk dəfə göründü: soyuq açılış müddəti.
    func homeReady() {
        guard !coldDone else { return }
        coldDone = true
        startup("cold", ms: Int(Date().timeIntervalSince(Usage.launchedAt) * 1000))
    }

    func resume() {
        rollIfNeeded()
        foreground = true
        tickAt = Date()
        sessionStart = Date()
        day.sessions += 1
        opened("icon")
        live(force: true)
    }

    func pause() {
        tick()
        foreground = false
        if let s = sessionStart {
            day.sessLen.append(Int(Date().timeIntervalSince(s)))
            if day.sessLen.count > 100 { day.sessLen.removeFirst() }
        }
        sessionStart = nil
        persist()
        live(force: true)
        send(force: true)
    }

    /// Hər dəqiqə: saxla və göndər.
    func heartbeat() {
        tick()
        persist()
        send(force: false)
    }

    // MARK: göndərmə

    private func settings() -> [String: Any] {
        let p = Prefs.shared
        var m: [String: Any] = [:]
        m["theme"] = p.theme
        m["lang"] = p.lang
        m["haptics"] = p.haptics
        m["lock"] = p.lock
        m["lockTimeout"] = p.lockAfter
        m["noScreenshots"] = false
        m["reminders"] = p.reminders
        m["notifications"] = p.updates || p.reminders
        m["location"] = false
        m["classroom"] = Classroom.isConnected
        m["matesVisible"] = UserDefaults.standard.bool(forKey: "mates_visible")
        return m
    }

    private func device() -> [String: Any] {
        var sys = utsname()
        uname(&sys)
        let model = withUnsafeBytes(of: &sys.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = Int(info?["CFBundleVersion"] as? String ?? "") ?? 0
        var m: [String: Any] = [:]
        m["brand"] = "Apple"
        m["model"] = String(model.prefix(40))
        m["android"] = "iOS " + UIDevice.current.systemVersion
        m["sdk"] = 0
        m["app"] = version + "-ios"
        m["build"] = build
        return m
    }

    private func send(force: Bool) {
        guard !number.isEmpty, day.ms > 0 || !day.screens.isEmpty else { return }
        if !force && Date().timeIntervalSince(lastSent) < 60 { return }
        lastSent = Date()
        let p = profile
        var live = day.sessLen
        if let s = sessionStart { live.append(Int(Date().timeIntervalSince(s))) }
        var data: [String: Any] = [:]
        data["number"] = number
        data["name"] = String(p.fullName.prefix(110))
        data["group"] = String(Cloud.groupCode(p.group).prefix(18))
        data["stream"] = String(Cloud.stream(p.group).prefix(18))
        data["course"] = String(p.course.filter(\.isNumber).prefix(2))
        data["date"] = day.date
        data["seconds"] = day.ms / 1000
        data["sessions"] = day.sessions
        var screens: [String: Any] = [:]
        for (k, v) in day.screens { screens[k] = ["v": v[0], "s": v[1] / 1000] }
        data["screens"] = screens
        data["actions"] = day.actions
        data["opens"] = day.opens
        data["device"] = device()
        data["settings"] = settings()
        data["log"] = day.log
        data["hours"] = day.hours.map { $0 / 1000 }
        data["paths"] = day.paths
        data["content"] = day.content
        var portal: [String: Any] = [:]
        for (k, v) in day.portal { portal[k] = ["n": v[0], "fail": v[1], "ms": v[2], "max": v[3]] }
        data["portal"] = portal
        data["errors"] = day.errors
        data["sessLen"] = live
        data["first"] = UserDefaults.standard.string(forKey: "usage_first") ?? day.date
        var startup: [String: Any] = [:]
        for (k, v) in day.startup { startup[k] = ["n": v[0], "ms": v[1], "max": v[2]] }
        data["startup"] = startup
        var loads: [String: Any] = [:]
        for (k, v) in day.loads { loads[k] = ["n": v[0], "ms": v[1], "max": v[2]] }
        data["loads"] = loads
        let id = "\(number)_\(day.date.replacingOccurrences(of: "-", with: ""))"
        Task.detached { await Cloud.shared.saveUsage(id, data) }
    }

    private func live(force: Bool) {
        guard !number.isEmpty else { return }
        if !force && Date().timeIntervalSince(lastLive) < 15 { return }
        lastLive = Date()
        let p = profile
        var data: [String: Any] = [:]
        data["number"] = number
        data["name"] = String(p.fullName.prefix(110))
        data["group"] = String(Cloud.groupCode(p.group).prefix(18))
        data["course"] = String(p.course.filter(\.isNumber).prefix(2))
        data["online"] = foreground
        data["screen"] = String((screen ?? "").prefix(40))
        data["since"] = Int(screenSince.timeIntervalSince1970 * 1000)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        data["app"] = version + "-ios"
        Task.detached { await Cloud.shared.saveLive(data) }
    }
}

extension View {
    /// Ekran göründükdə analitikaya yazılır.
    func track(_ name: String) -> some View {
        onAppear { Usage.shared.screen(name) }
    }
}
