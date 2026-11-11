import SwiftUI
import UIKit

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

    // profil
    @Published var profile = Profile()
    @Published var photo: UIImage?

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
            restoreError = "Saxlanmış şifrə köhnəlib, yenidən daxil olun"
        } catch {
            restoreError = error.localizedDescription
        }
        restoring = false
    }

    func login(_ number: String, _ password: String, remember: Bool) async throws {
        if number.isEmpty || password.isEmpty { throw PortalError.message("Tələbə nömrəsini və şifrəni daxil edin") }
        let html = try await Portal.shared.login(number, password)
        var prof = await offMain { Parsers.profile(html) }
        if prof == nil {
            let index = try await Portal.shared.fetch("index.php")
            prof = await offMain { Parsers.profile(index) }
        }
        guard let p = prof else { throw PortalError.message("Giriş oldu, amma profil məlumatı oxunmadı") }
        profile = p
        UserDefaults.standard.set(number, forKey: "lastNumber")
        if remember { Keychain.save(number, password) } else { Keychain.clear() }
        restoreError = ""
        loggedIn = true
        Task { await loadPhoto() }
        Task { await ensureMonth(Date()) }
    }

    func logout() {
        Keychain.clear()
        Task { await Portal.shared.logout() }
        profile = Profile(); photo = nil
        lessons = [:]; loadedMonths = []; loadingMonths = []
        gradeSems = []; gradeSel = ""; grades = []; gradesError = ""
        journalSems = []; journalSel = ""; journal = []; journalError = ""; journalDefault = ""; journalDefaultCourses = []
        loggedIn = false
    }

    private func loadPhoto() async {
        guard let home = try? await Portal.shared.fetch("index.php?mod=home") else { return }
        guard let path = await offMain({ Parsers.photoPath(home) }) else { return }
        guard let data = try? await Portal.shared.fetchData(path), let img = UIImage(data: data) else { return }
        photo = img
    }

    /// Ana səhifəni aşağı çəkəndə: profil və bu ayın cədvəli yenilənir.
    func refreshHome() async {
        if let html = try? await Portal.shared.fetch("index.php"), let p = await offMain({ Parsers.profile(html) }) {
            profile = p
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
                scheduleError = "Cədvəl oxunmadı"
                return
            }
            lessons = lessons.filter { $0.key < sk || $0.key >= ek }.merging(parsed) { _, new in new }
            loadedMonths.insert(mk)
            scheduleError = ""
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
                guard !list.isEmpty else { gradesError = "Semestr siyahısı tapılmadı"; return }
                gradeSems = list
                if gradeSel.isEmpty { gradeSel = (list.first { $0.selected } ?? list[list.count - 1]).value }
            } catch {
                gradesError = error.localizedDescription
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
        if let parsed { grades = parsed } else { gradesError = "Qiymətlər oxunmadı. Aşağı çəkib yenidən yoxla." }
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
                    journalError = "Jurnal oxunmadı"
                    return
                }
                journalSems = sems
                journalDefault = def.value
                journalDefaultCourses = parsed
                if journalSel.isEmpty { journalSel = def.value }
            }
            let want = value ?? journalSel
            journalSel = want
            if want == journalDefault { journal = journalDefaultCourses; return }
            // başqa semestr: portalın getCourses() ajax sorğusu
            let body = try await Portal.shared.ajax("index.php?ajx=1&mod=ejurnal&action=getCourses&ysem=\(want)", referer: "index.php?mod=ejurnal")
            let parsed = await offMain { Parsers.journal(Parsers.extractAjaxData(body) ?? body) }
            guard want == journalSel else { return }
            if let parsed { journal = parsed } else { journal = []; journalError = "Bu semestrin jurnalı oxunmadı" }
        } catch {
            journalError = error.localizedDescription
        }
    }
}
