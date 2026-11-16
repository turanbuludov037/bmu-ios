import Foundation
import UserNotifications
import BackgroundTasks

/// Yerli bildirişlər: dərs xatırlatması (telefonun özündə planlaşdırılır, internet lazım deyil).
enum Notifier {
    static let refreshID = "com.nexora.beueduaz.refresh"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Növbəti 7 günün dərsləri üçün xatırlatma (iOS ən çox 64 gözləyən bildirişə icazə verir — 50 ilə məhdudlaşdırırıq).
    static func scheduleLessons(_ lessons: [String: [Lesson]], before: Int, enabled: Bool, timetable: [TtEntry] = []) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("lesson-") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard enabled, await authorized() else { return }
        let now = Date()
        var count = 0
        for i in 0..<8 {
            let day = Day.add(i, to: Day.startOfToday())
            for l in lessons[Day.key(day)] ?? [] {
                guard let at = Day.cal.date(byAdding: .minute, value: Day.minutes(l.start) - before, to: day), at > now else { continue }
                let c = UNMutableNotificationContent()
                c.title = l.title
                let room = TimetableStore.match(timetable, day: isoWeekday(day), lesson: l).flatMap { Room.of($0.room) }
                c.body = t("\(before) dəqiqəyə başlayır · \(l.start)–\(l.end) · \(l.typeLabel)",
                           "Starts in \(before) min · \(l.start)–\(l.end) · \(l.typeLabel)") + (room.map { " · " + $0.label } ?? "")
                c.sound = .default
                c.threadIdentifier = "lessons"
                let comps = Day.cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                let req = UNNotificationRequest(identifier: "lesson-\(Day.key(day))-\(l.start)-\(l.code)", content: c,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                try? await center.add(req)
                count += 1
                if count >= 50 { return }
            }
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func show(id: String, title: String, body: String) async {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
}

/// Tətbiq açıq olanda da bildiriş banneri görünsün.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

// MARK: - Qiymət və qaib dəyişikliyi (arxa planda; Android Updates.kt ilə eyni məntiq)

private struct Snapshot: Codable {
    struct J: Codable { var title: String; var p: Double; var m: Int }
    struct G: Codable { var title: String; var s: [String: String] }
    var journal: [String: J] = [:]
    var grades: [String: G] = [:]
}

enum Updates {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("updates_snapshot.json")
    }

    private static var enabled: Bool { UserDefaults.standard.object(forKey: "updates") as? Bool ?? true }

    /// Növbəti arxa plan yoxlamasını sifariş et (iOS özü vaxtını seçir; ən tez 30 dəqiqə sonra).
    static func scheduleRefresh() {
        let r = BGAppRefreshTaskRequest(identifier: Notifier.refreshID)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    /// Arxa plan tapşırığı.
    static func runBackground() async {
        scheduleRefresh()
        await checkAnnouncements()
        guard enabled else { return }
        _ = await check()
        if Keychain.load() != nil { await LibraryDue.sync() }
    }

    // MARK: yeni elan bildirişi (push əvəzinə: iOS arxa planda yoxlayır)

    /// Bu elanlar artıq görülüb/bildirilib — təkrar bildiriş getməsin.
    static func markAnnsNotified(_ ids: [String]) {
        var s = Set(UserDefaults.standard.stringArray(forKey: "notified_anns") ?? [])
        s.formUnion(ids)
        UserDefaults.standard.set(Array(s.suffix(500)), forKey: "notified_anns")
        UserDefaults.standard.set(true, forKey: "anns_baseline")
    }

    static func checkAnnouncements() async {
        guard FirebaseConfig.enabled, let targets = UserDefaults.standard.stringArray(forKey: "ann_targets"), !targets.isEmpty,
              let list = try? await Cloud.shared.announcements(targets: targets) else { return }
        let known = Set(UserDefaults.standard.stringArray(forKey: "notified_anns") ?? [])
        let baseline = UserDefaults.standard.bool(forKey: "anns_baseline")
        let fresh = list.filter { $0.active && !known.contains($0.id) }
        markAnnsNotified(list.map(\.id))
        guard baseline else { return }              // ilk dəfə: köhnə elanlar üçün bildiriş göndərmə
        for a in fresh.prefix(3) {
            await Notifier.show(id: "ann-\(a.id)", title: "📢 " + a.title,
                                body: a.body.isEmpty ? t("Yeni elan", "New announcement") : String(a.body.prefix(220)))
        }
    }

    /// Tətbiq açılanda: son yoxlamadan 15 dəqiqə keçibsə.
    static func checkIfDue() async {
        await checkAnnouncements()
        guard enabled else { return }
        let last = UserDefaults.standard.double(forKey: "updates_last_at")
        if Date().timeIntervalSince1970 - last < 15 * 60 { return }
        _ = await check()
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults.standard.removeObject(forKey: "updates_last_at")
        UserDefaults.standard.removeObject(forKey: "updates_last")
    }

    private static func setStatus(_ s: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "updates_last_at")
        UserDefaults.standard.set(s, forKey: "updates_last")
    }

    /// "Son yoxlama: 16.11 14:05 · dəyişiklik yoxdur"
    static func statusText() -> String {
        let at = UserDefaults.standard.double(forKey: "updates_last_at")
        if at == 0 { return t("Hələ yoxlanmayıb", "Not checked yet") }
        let st = UserDefaults.standard.string(forKey: "updates_last") ?? ""
        let what: String
        switch st {
        case "same": what = t("dəyişiklik yoxdur", "no changes")
        case "base": what = t("ilk yoxlama: indiki qiymət və qaiblər yadda saxlandı", "first check: current grades and absences saved")
        case "login": what = t("portala daxil olmaq alınmadı", "could not sign in")
        case "fetch": what = t("portal cavab vermədi", "portal did not respond")
        case "nocreds": what = t("\"Məni xatırla\" seçilməyib", "\"Remember me\" is off")
        default:
            if st.hasPrefix("n:") { what = t("\(st.dropFirst(2)) dəyişiklik tapıldı", "\(st.dropFirst(2)) changes found") } else { what = st }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM HH:mm"
        return t("Son yoxlama: ", "Last check: ") + f.string(from: Date(timeIntervalSince1970: at)) + " · " + what
    }

    private static func fetchSnapshot() async -> Snapshot? {
        var snap = Snapshot()
        if let page = try? await Portal.shared.fetch("index.php?mod=ejurnal"), let courses = Parsers.journal(page) {
            for c in courses {
                snap.journal[c.code] = .init(title: c.title, p: c.percent, m: c.rows.reduce(0) { $0 + $1.missed })
            }
        }
        if let page = try? await Portal.shared.fetch("index.php?mod=grades") {
            let sems = Parsers.semesters(page, skip: "1#1")
            if let sem = sems.first(where: { $0.selected }) ?? sems.last {
                var rows: [GradeRow]? = nil
                if let body = try? await Portal.shared.ajax("index.php?ajx=1&mod=grades&action=GetGrades&yt=\(sem.value)", referer: "index.php?mod=grades") {
                    rows = Parsers.extractAjaxData(body).flatMap { Parsers.grades($0) }
                }
                if rows == nil, let body = try? await Portal.shared.post("index.php", [("ajx", "1"), ("mod", "grades"), ("action", "GetGrades"), ("yt", sem.value)],
                                                                          referer: "index.php?mod=grades") {
                    rows = Parsers.extractAjaxData(body).flatMap { Parsers.grades($0) }
                }
                for r in rows ?? [] { snap.grades[r.code] = .init(title: r.title, s: r.scores.filter { !$0.value.isEmpty }) }
            }
        }
        return snap.journal.isEmpty && snap.grades.isEmpty ? nil : snap
    }

    private static func pct(_ d: Double) -> String { fmt(d) + "%" }

    private static func diff(_ old: Snapshot, _ new: Snapshot) -> [String] {
        var msgs: [String] = []
        if !old.journal.isEmpty && new.journal.keys.contains(where: { old.journal[$0] != nil }) {
            for (code, n) in new.journal.sorted(by: { $0.key < $1.key }) {
                guard let o = old.journal[code], o.m != n.m || o.p != n.p else { continue }
                var line = "\(n.title.isEmpty ? code : n.title): " + t("qaib", "absence") + " \(pct(o.p)) → \(pct(n.p))"
                if o.m != n.m { line += t(" (\(o.m) → \(n.m) saat)", " (\(o.m) → \(n.m) h)") }
                if n.p > ABSENCE_LIMIT_PERCENT { line += t(" — limit keçib!", " — over the limit!") }
                msgs.append(line)
            }
        }
        if new.grades.keys.contains(where: { old.grades[$0] != nil }) {
            for (code, n) in new.grades.sorted(by: { $0.key < $1.key }) {
                guard let o = old.grades[code] else { continue }
                var changes: [String] = []
                for k in Set(n.s.keys).union(o.s.keys).sorted() {
                    let a = o.s[k] ?? "", b = n.s[k] ?? ""
                    if a != b && !b.isEmpty { changes.append(a.isEmpty ? "\(k) \(b)" : "\(k) \(a) → \(b)") }
                }
                if !changes.isEmpty { msgs.append("\(n.title.isEmpty ? code : n.title): " + changes.joined(separator: ", ")) }
            }
        }
        return msgs
    }

    /// Bir yoxlama: portal → görüntü → köhnə ilə müqayisə → bildiriş. Nəticə kodu qaytarır.
    @discardableResult
    static func check() async -> String {
        guard let creds = Keychain.load() else { setStatus("nocreds"); return "nocreds" }
        let hasSession = await Portal.shared.hasSession
        if !hasSession {
            do { _ = try await Portal.shared.login(creds.0, creds.1) } catch { setStatus("login"); return "login" }
        }
        guard var snap = await fetchSnapshot() else { setStatus("fetch"); return "fetch" }
        let old = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        if let old {
            // bir hissə bu dəfə oxunmayıbsa köhnəsi saxlanır (dəyişiklik "itməsin")
            if snap.journal.isEmpty { snap.journal = old.journal }
            if snap.grades.isEmpty { snap.grades = old.grades }
        }
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        guard let old else { setStatus("base"); return "base" }
        let msgs = diff(old, snap)
        if !msgs.isEmpty {
            await Notifier.show(id: "updates-\(Int(Date().timeIntervalSince1970))",
                                title: t("Qiymət / qaib dəyişdi", "Grade / absence changed") + (msgs.count > 1 ? " · \(msgs.count)" : ""),
                                body: msgs.prefix(6).joined(separator: "\n"))
        }
        let st = msgs.isEmpty ? "same" : "n:\(msgs.count)"
        setStatus(st)
        await examWarning(snap)
        return st
    }

    // MARK: semestr sonu: finaldan 17-dən çox bal lazım olan fənlər (həftədə bir)

    private static let warnMonths: Set<Int> = [12, 5]

    private static func examWarning(_ snap: Snapshot) async {
        let today = Date()
        guard warnMonths.contains(Day.cal.component(.month, from: today)) else { return }
        let last = UserDefaults.standard.double(forKey: "exam_warned_at")
        if today.timeIntervalSince1970 - last < 7 * 24 * 3600 { return }
        let rows = snap.grades.map { GradeRow(code: $0.key, title: $0.value.title, akts: 0, missed: "", scores: $0.value.s) }
        let risks = rows.filter { GradeCalc.exam($0) == nil && !GradeCalc.noEntryYet($0) && !GradeCalc.isSafe($0) }
            .sorted { (GradeCalc.examNeed($0) ?? 99) > (GradeCalc.examNeed($1) ?? 99) }
        guard !risks.isEmpty else { return }
        UserDefaults.standard.set(today.timeIntervalSince1970, forKey: "exam_warned_at")
        let lines = risks.map { r -> String in
            let name = r.title.isEmpty ? r.code : r.title
            if let n = GradeCalc.examNeed(r) { return t("\(name): finaldan minimum \(n) bal lazımdır", "\(name): you need at least \(n) on the final") }
            return t("\(name): finaldan 50 bal belə 51-ə çatmır", "\(name): even 50 on the final won't reach 51")
        }
        let min = GradeRules.examMin
        await Notifier.show(id: "exam-warning", title: risks.count == 1
                            ? t("Final: 1 fənn üçün \(min)-dən çox bal lazımdır", "Final: 1 course needs more than \(min)")
                            : t("Final: \(risks.count) fənn üçün \(min)-dən çox bal lazımdır", "Final: \(risks.count) courses need more than \(min)"),
                            body: lines.prefix(6).joined(separator: "\n"))
    }
}
