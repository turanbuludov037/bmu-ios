import SwiftUI
import UIKit

/// "Aşağı çək → yenilə": iş ayrıca tapşırıqda gedir ki, ekran yenilənəndə sorğu yarımçıq kəsilməsin
/// (əks halda iOS sorğunu ləğv edir və "interneti yoxlayın" xətası çıxırdı).
func refreshWork(_ work: @escaping @MainActor () async -> Void) async {
    await Task { @MainActor in await work() }.value
}

/// Ağır HTML oxunuşu əsas axından kənarda (ekran donmasın).
func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await Task.detached(priority: .userInitiated, operation: work).value
}

/// Bütün tətbiqin vəziyyəti: giriş, profil, cədvəl, qiymətlər, jurnal.
@MainActor
final class AppState: ObservableObject {
    // giriş
    @Published var restoring = true
    @Published var loggedIn = false
    @Published var restoreError = ""
    private var didRestore = false
    /// İnternetsiz rejim: portala daxil olmaq alınmadı, son saxlanan nüsxə göstərilir.
    @Published var offline = false
    @Published var offlineSavedAt: Date?
    @Published var reconnecting = false

    // profil
    @Published var profile = Profile()
    @Published var photo: UIImage?
    @Published var birthdays: Int?
    /// Seçilmiş tab (dil dəyişəndə ekran yenidən qurulur, tab yerində qalsın)
    @Published var tab = 0

    // cədvəl: "yyyy-MM-dd" → dərslər
    @Published var lessons: [String: [Lesson]] = [:]
    @Published var loadingMonths: Set<String> = []
    @Published var scheduleError = ""
    private var loadedMonths: Set<String> = []

    // qiymətlər
    @Published var gradeSems: [Semester] = []
    @Published var gradeSel = ""
    @Published var grades: [GradeRow] = []
    @Published var gradesLoading = false
    @Published var gradesError = ""

    // jurnal
    @Published var journalSems: [Semester] = []
    @Published var journalSel = ""
    @Published var journal: [JournalCourse] = []
    @Published var journalLoading = false
    @Published var journalError = ""
    private var journalDefault = ""
    private var journalDefaultCourses: [JournalCourse] = []

    var savedNumber: String { UserDefaults.standard.string(forKey: "lastNumber") ?? "" }

    // MARK: giriş / çıxış

    /// Tətbiq açılanda: saxlanmış nömrə/şifrə ilə avtomatik daxil ol.
    func restore() async {
        if didRestore { return }
        didRestore = true
        guard let c = Keychain.load() else { restoring = false; return }
        do {
            try await login(c.0, c.1, remember: true)
        } catch PortalError.wrongCredentials {
            Keychain.clear()
            OfflineCache.clear()
            restoreError = t("Saxlanmış şifrə köhnəlib, yenidən daxil olun", "Saved password is outdated, please sign in again")
        } catch {
            // internet yoxdur / portal cavab vermir: son saxlanan nüsxə ilə aç
            if let snap = OfflineCache.load(number: c.0) {
                enterOffline(snap)
            } else {
                restoreError = error.localizedDescription
            }
        }
        restoring = false
    }

    /// İnternetsiz rejimə keçid: hər şey son saxlanan nüsxədən.
    private func enterOffline(_ snap: OfflineSnapshot) {
        profile = snap.profile
        lessons = snap.lessons
        gradeSems = snap.gradeSems; gradeSel = snap.gradeSel; grades = snap.grades
        journalSems = snap.journalSems; journalSel = snap.journalSel; journal = snap.journal
        journalDefault = snap.journalSel; journalDefaultCourses = snap.journal
        offline = true
        offlineSavedAt = snap.savedAt
        loggedIn = true
        TimetableStore.shared.load(number: snap.profile.number, group: snap.profile.group)
        LibraryDue.loadState()
        WidgetData.publish(lessons)
    }

    /// "Yenidən qoşul" — internet gələndə portala yenidən daxil olur.
    func goOnline() async {
        guard let c = Keychain.load(), !reconnecting else { return }
        reconnecting = true
        defer { reconnecting = false }
        do {
            try await login(c.0, c.1, remember: true)
            loadedMonths = []
            gradeSems = []
            journalDefaultCourses = []
            await ensureMonth(Date(), force: true)
            await ensureMonth(Day.add(7, to: Date()))
            Haptic.success()
        } catch PortalError.wrongCredentials {
            logout()
        } catch {
            Haptic.error()
        }
    }

    private var number: String { profile.number.isEmpty ? savedNumber : profile.number }

    /// Bir hissə oxunmadı: son saxlanan qiymətlər (eyni semestr).
    private func cachedGrades(_ yt: String?) -> Bool {
        guard let snap = OfflineCache.load(number: number), !snap.grades.isEmpty else { return false }
        if let yt, !yt.isEmpty, yt != snap.gradeSel { return false }
        if gradeSems.isEmpty { gradeSems = snap.gradeSems }
        gradeSel = snap.gradeSel
        grades = snap.grades
        gradesError = t("Portal cavab vermədi — son saxlanan nüsxə göstərilir (\(OfflineCache.savedText(snap.savedAt)))",
                        "The portal did not respond — showing the last saved copy (\(OfflineCache.savedText(snap.savedAt)))")
        return true
    }

    func login(_ number: String, _ password: String, remember: Bool) async throws {
        if number.isEmpty || password.isEmpty { throw PortalError.message(t("Tələbə nömrəsini və şifrəni daxil edin", "Enter your student number and password")) }
        let html = try await Portal.shared.login(number, password)
        var prof = await offMain { Parsers.profile(html) }
        if prof == nil {
            let index = try await Portal.shared.fetch("index.php")
            prof = await offMain { Parsers.profile(index) }
        }
        guard let p = prof else { throw PortalError.message(t("Giriş oldu, amma profil məlumatı oxunmadı", "Signed in, but the profile could not be read")) }
        profile = p
        UserDefaults.standard.set(number, forKey: "lastNumber")
        if remember { Keychain.save(number, password) } else { Keychain.clear() }
        restoreError = ""
        offline = false
        offlineSavedAt = nil
        loggedIn = true
        OfflineCache.update(number: number) { $0.profile = p }
        TimetableStore.shared.load(number: number, group: p.group)
        LibraryDue.loadState()
        Task { await LibraryDue.sync() }
        Usage.shared.setUser(p)
        UserDefaults.standard.set(Cloud.targets(p), forKey: "ann_targets")
        Task { await AnnStore.shared.load(p) }
        Task.detached { await Cloud.shared.connect(number: number, password: password, profile: p) }
        Task { await loadPhoto() }
        Task { await ensureMonth(Date()); await ensureMonth(Day.add(7, to: Date())) }
        if remember { Task { await Updates.checkIfDue() } }
    }

    func logout() {
        Keychain.clear()
        OfflineCache.clear()
        SecureStore.wipe()
        LibraryDue.clear()
        TimetableStore.shared.reset()
        WidgetData.clear()
        offline = false; offlineSavedAt = nil
        Updates.clear()
        Notifier.cancelAll()
        Classroom.clearOnLogout()
        UserDefaults.standard.removeObject(forKey: "ann_targets")
        AnnStore.shared.all = []
        Task.detached { await Cloud.shared.signOut() }
        birthdays = nil; tab = 0
        Task { await Portal.shared.logout() }
        profile = Profile(); photo = nil
        lessons = [:]; loadedMonths = []; loadingMonths = []
        gradeSems = []; gradeSel = ""; grades = []; gradesError = ""
        journalSems = []; journalSel = ""; journal = []; journalError = ""; journalDefault = ""; journalDefaultCourses = []
        loggedIn = false
    }

    private func loadPhoto() async {
        guard let home = try? await Portal.shared.fetch("index.php?mod=home") else { return }
        birthdays = await offMain { Parsers.birthdays(home) }
        guard let path = await offMain({ Parsers.photoPath(home) }) else { return }
        guard let data = try? await Portal.shared.fetchData(path), let img = UIImage(data: data) else { return }
        photo = img
    }

    /// Ana səhifəni aşağı çəkəndə: profil və bu ayın cədvəli yenilənir.
    func refreshHome() async {
        if let html = try? await Portal.shared.fetch("index.php"), let p = await offMain({ Parsers.profile(html) }) {
            profile = p
            OfflineCache.update(number: profile.number) { $0.profile = p }
        }
        await ensureMonth(Date(), force: true)
        let tomorrow = Day.add(1, to: Date())
        if Day.monthKey(tomorrow) != Day.monthKey(Date()) { await ensureMonth(tomorrow, force: true) }
    }

    // MARK: cədvəl

    var scheduleLoaded: Bool { loadedMonths.contains(Day.monthKey(Date())) }

    /// Ayın cədvəli (həftə bazar ertəsindən başlayır). Bir dəfə yüklənir, force ilə yenilənir.
    func ensureMonth(_ date: Date, force: Bool = false) async {
        let mk = Day.monthKey(date)
        if !force && (loadedMonths.contains(mk) || loadingMonths.contains(mk)) { return }
        let comps = Day.cal.dateComponents([.year, .month], from: date)
        guard let first = Day.cal.date(from: comps),
              let next = Day.cal.date(byAdding: .month, value: 1, to: first) else { return }
        let start = Day.monday(of: first)
        let end = Day.add(7, to: Day.monday(of: Day.add(-1, to: next)))
        let sk = Day.key(start), ek = Day.key(end)
        loadingMonths.insert(mk)
        defer { loadingMonths.remove(mk) }
        do {
            let body = try await Portal.shared.fetch("load_course_schedule.php?start=\(sk)&end=\(ek)")
            guard let parsed = await offMain({ Parsers.schedule(body) }) else {
                scheduleError = t("Cədvəl oxunmadı", "Schedule could not be loaded")
                return
            }
            lessons = lessons.filter { $0.key < sk || $0.key >= ek }.merging(parsed) { _, new in new }
            loadedMonths.insert(mk)
            scheduleError = ""
            rescheduleReminders()
            let from = Day.key(Day.add(-7, to: Date()))
            let keep = lessons.filter { $0.key >= from }
            OfflineCache.update(number: profile.number) { $0.lessons = keep }
            WidgetData.publish(lessons)
        } catch is CancellationError {
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    // MARK: qiymətlər

    func loadGrades(_ value: String? = nil) async {
        gradesLoading = true
        gradesError = ""
        defer { gradesLoading = false }
        if gradeSems.isEmpty {
            do {
                let page = try await Portal.shared.fetch("index.php?mod=grades")
                let list = await offMain { Parsers.semesters(page, skip: "1#1") }
                guard !list.isEmpty else { gradesError = t("Semestr siyahısı tapılmadı", "Semester list not found"); return }
                gradeSems = list
                if gradeSel.isEmpty { gradeSel = (list.first { $0.selected } ?? list[list.count - 1]).value }
            } catch is CancellationError {
                return
            } catch {
                if !cachedGrades(nil) { gradesError = error.localizedDescription }
                return
            }
        }
        if let value { gradeSel = value }
        let yt = gradeSel
        var parsed: [GradeRow]? = nil
        // 1) portalın öz Ajax.ajax-ının eynisi; 2) ehtiyat: kodlaşdırılmış form
        if let body = try? await Portal.shared.ajax("index.php?ajx=1&mod=grades&action=GetGrades&yt=\(yt)", referer: "index.php?mod=grades") {
            parsed = await offMain { Parsers.extractAjaxData(body).flatMap { Parsers.grades($0) } }
        }
        if parsed == nil, let body = try? await Portal.shared.post("index.php",
            [("ajx", "1"), ("mod", "grades"), ("action", "GetGrades"), ("yt", yt)], referer: "index.php?mod=grades") {
            parsed = await offMain { Parsers.extractAjaxData(body).flatMap { Parsers.grades($0) } }
        }
        guard yt == gradeSel else { return }          // bu arada başqa semestr seçilib
        if let parsed {
            grades = parsed
            let sems = gradeSems
            OfflineCache.update(number: profile.number) { $0.grades = parsed; $0.gradeSel = yt; $0.gradeSems = sems }
        } else if !cachedGrades(yt) {
            gradesError = t("Qiymətlər oxunmadı. Aşağı çəkib yenidən yoxla.", "Grades could not be loaded. Pull down to retry.")
        }
    }

    // MARK: jurnal

    func loadJournal(_ value: String? = nil, force: Bool = false) async {
        journalLoading = true
        journalError = ""
        defer { journalLoading = false }
        do {
            if force || journalSems.isEmpty || journalDefaultCourses.isEmpty {
                let page = try await Portal.shared.fetch("index.php?mod=ejurnal")
                let sems = await offMain { Parsers.semesters(page, skip: "0#0") }
                let parsed = await offMain { Parsers.journal(page) }
                guard let def = sems.first(where: { $0.selected }) ?? sems.first, let parsed else {
                    journalError = t("Jurnal oxunmadı", "Journal could not be loaded")
                    return
                }
                journalSems = sems
                journalDefault = def.value
                journalDefaultCourses = parsed
                if journalSel.isEmpty { journalSel = def.value }
                OfflineCache.update(number: profile.number) { $0.journal = parsed; $0.journalSel = def.value; $0.journalSems = sems }
            }
            let want = value ?? journalSel
            journalSel = want
            if want == journalDefault { journal = journalDefaultCourses; return }
            // başqa semestr: portalın getCourses() ajax sorğusu
            let body = try await Portal.shared.ajax("index.php?ajx=1&mod=ejurnal&action=getCourses&ysem=\(want)", referer: "index.php?mod=ejurnal")
            let parsed = await offMain { Parsers.journal(Parsers.extractAjaxData(body) ?? body) }
            guard want == journalSel else { return }
            if let parsed { journal = parsed } else { journal = []; journalError = t("Bu semestrin jurnalı oxunmadı", "This semester's journal could not be loaded") }
        } catch is CancellationError {
        } catch {
            if journal.isEmpty, let snap = OfflineCache.load(number: number), !snap.journal.isEmpty {
                if journalSems.isEmpty { journalSems = snap.journalSems }
                journalSel = snap.journalSel
                journal = snap.journal
                journalError = t("Portal cavab vermədi — son saxlanan nüsxə göstərilir (\(OfflineCache.savedText(snap.savedAt)))",
                                 "The portal did not respond — showing the last saved copy (\(OfflineCache.savedText(snap.savedAt)))")
            } else {
                journalError = error.localizedDescription
            }
        }
    }

    // MARK: bildirişlər

    /// Dərs xatırlatmalarını yenidən planlaşdır (cədvəl yüklənəndə və tənzimləmə dəyişəndə).
    func rescheduleReminders() {
        let l = lessons, before = Prefs.shared.remindBefore, on = Prefs.shared.reminders && loggedIn
        let tt = TimetableStore.shared.entries
        Task.detached { await Notifier.scheduleLessons(l, before: before, enabled: on, timetable: tt) }
    }

    /// Öz ad günüdür? birth = "dd.MM.yyyy"
    var isMyBirthday: Bool {
        let p = profile.birth.split(whereSeparator: { ".-/".contains($0) })
        guard p.count >= 2, let d = Int(p[0]), let m = Int(p[1]) else { return false }
        let c = Day.cal.dateComponents([.day, .month], from: Date())
        return c.day == d && c.month == m
    }

    /// "Sabahın xeyir, Turan"
    var greeting: String {
        let h = Day.cal.component(.hour, from: Date())
        let g: String
        switch h {
        case 5..<12: g = t("Sabahın xeyir", "Good morning")
        case 12..<18: g = t("Günortan xeyir", "Good afternoon")
        case 18..<23: g = t("Axşamın xeyir", "Good evening")
        default: g = t("Gecən xeyrə", "Good night")
        }
        // Android-dəki kimi: "Ad soyad" sahəsinin ilk sözü
        let name = profile.fullName.trimmed.split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? g : "\(g), \(name)"
    }
}
