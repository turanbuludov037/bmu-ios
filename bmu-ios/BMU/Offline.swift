import Foundation

/// İnternetsiz rejim üçün son yüklənmiş məlumatın nüsxəsi (Android OfflineCache ilə eyni məqsəd):
/// profil, dərs cədvəli, qiymətlər, jurnal və transkript. Şifrəli saxlanılır və yalnız "Məni xatırla" seçiləndə yazılır.
struct OfflineSnapshot: Codable {
    var number = ""
    var savedAt = Date()
    var profile = Profile()
    var lessons: [String: [Lesson]] = [:]
    var gradeSems: [Semester] = []
    var gradeSel = ""
    var grades: [GradeRow] = []
    var journalSems: [Semester] = []
    var journalSel = ""
    var journal: [JournalCourse] = []
    var transcript: Transcript?
}

@MainActor
enum OfflineCache {
    private static let name = "offline"
    private static var snap: OfflineSnapshot?
    private static var pending: Task<Void, Never>?

    /// Yadda saxlanmış nüsxə (yalnız bu tələbənin).
    static func load(number: String) -> OfflineSnapshot? {
        if let s = snap, s.number == number { return s }
        guard let s = SecureStore.readJSON(OfflineSnapshot.self, name), s.number == number else { return nil }
        snap = s
        return s
    }

    /// Nüsxəni yenilə (bir saniyə ərzindəki dəyişikliklər bir yazıya yığılır).
    static func update(number: String, _ change: (inout OfflineSnapshot) -> Void) {
        guard !number.isEmpty, Keychain.load() != nil else { return }           // "Məni xatırla" seçilməyib
        var s = load(number: number) ?? OfflineSnapshot(number: number)
        change(&s)
        s.number = number
        s.savedAt = Date()
        snap = s
        pending?.cancel()
        let copy = s, file = name
        pending = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            await Task.detached(priority: .utility) { SecureStore.writeJSON(copy, file) }.value
        }
    }

    static func clear() {
        pending?.cancel()
        snap = nil
        SecureStore.remove(name)
    }

    /// "16.11 14:05"
    static func savedText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM HH:mm"
        return f.string(from: d)
    }
}
