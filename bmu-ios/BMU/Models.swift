import Foundation

struct Profile: Sendable {
    var number = "", fullName = "", birth = ""
    var program = "", programLang = "", course = "", group = ""
    var advisor = "", status = "", tuitionDebt = "", advance = "", dormDebt = ""
    var annualFee = "", payForm = "", score = "", email = ""
    var regDate = "", termYear = "", termNo = ""

    var initials: String {
        fullName.split(separator: " ").prefix(2).compactMap { w in w.first.map { String($0) } }.joined()
    }
}

struct Lesson: Identifiable, Hashable, Sendable {
    let id = UUID()
    let start: String, end: String, code: String, title: String, type: String
    let count: Int

    var symbol: String {
        switch type {
        case "Laboratoriya": return "testtube.2"
        case "Məşğələ": return "pencil.and.ruler"
        default: return "book"
        }
    }
}

struct Semester: Identifiable, Hashable, Sendable {
    var id: String { value }
    let value: String, label: String, selected: Bool
}

/// scores — portal sütunları: SDF1, SDF2, SEM, LAB, TSI, IGB, SSI, ƏI, TI, ORT (boş ola bilər).
/// n / m / l — mühazirə, məşğələ, laboratoriya bölmələri (boşdursa o hissə yoxdur).
struct GradeRow: Identifiable, Sendable {
    var id: String { code }
    let code: String, title: String, akts: Int, missed: String
    let scores: [String: String]
    var n = "", m = "", l = ""
    func score(_ key: String) -> String { scores[key] ?? "" }
}

let OTHER_SCORES = ["SDF2", "SEM", "LAB", "TSI", "IGB", "SSI", "ƏI", "TI", "ORT"]

struct JournalRow: Identifiable, Sendable {
    var id: String { label }
    let label: String, attended: Int, missed: Int, hours: Int, limit: Double
}

struct JournalCourse: Identifiable, Sendable {
    var id: String { code }
    let code: String, title: String, teacher: String
    let rows: [JournalRow]
    let percent: Double
}

/// Qaibdən kəsilmə həddi: fənn üzrə auditoriya saatlarının 25 faizi.
let ABSENCE_LIMIT_PERCENT = 25.0

// MARK: - Qiymətləndirmə qaydası (BMU) — Android-dəki GradeRules / GradeCalc ilə eyni

enum GradeRules {
    static let entryMax = 50, entryMin = 34, examMax = 50, examMin = 17, part = 10
    static let letters: [(String, Int)] = [("A", 91), ("B", 81), ("C", 71), ("D", 61), ("E", 51)]
}

enum GradeCalc {
    struct Part: Identifiable {
        var id: String { key }
        let key: String, max: Int
        let value: Double?
    }

    static func num(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    static func hasSem(_ r: GradeRow) -> Bool { !r.m.isEmpty || !r.score("SEM").isEmpty }
    static func hasLab(_ r: GradeRow) -> Bool { !r.l.isEmpty || !r.score("LAB").isEmpty }

    /// Giriş balının hissələri (SEM/LAB yoxdursa onların balı SDF1 və SDF2-yə keçir).
    static func parts(_ r: GradeRow) -> [Part] {
        let sem = hasSem(r), lab = hasLab(r)
        let free = (sem ? 0 : GradeRules.part) + (lab ? 0 : GradeRules.part)
        let sdf = GradeRules.part + free / 2
        var p = [Part(key: "SDF1", max: sdf, value: num(r.score("SDF1"))),
                 Part(key: "SDF2", max: sdf + free % 2, value: num(r.score("SDF2")))]
        if sem { p.append(Part(key: "SEM", max: GradeRules.part, value: num(r.score("SEM")))) }
        if lab { p.append(Part(key: "LAB", max: GradeRules.part, value: num(r.score("LAB")))) }
        p.append(Part(key: "TSI", max: GradeRules.part, value: num(r.score("TSI"))))
        return p
    }

    /// Final imtahanının sayılan nəticəsi: təkrar → əlavə → semestr sonu.
    static func exam(_ r: GradeRow) -> Double? { num(r.score("TI")) ?? num(r.score("ƏI")) ?? num(r.score("SSI")) }

    static func letter(entry: Double, exam: Double) -> String {
        let total = entry + exam
        if entry < Double(GradeRules.entryMin) - 1e-9 || exam < Double(GradeRules.examMin) - 1e-9 { return "F" }
        return GradeRules.letters.first { total >= Double($0.1) - 1e-9 }?.0 ?? "F"
    }

    /// Hədəf bal üçün finaldan lazım olan minimum (17-dən az ola bilməz). Mümkün deyilsə nil.
    static func neededExam(entry: Double, target: Int) -> Int? {
        if entry < Double(GradeRules.entryMin) - 1e-9 { return nil }
        let n = Swift.max(GradeRules.examMin, Int((Double(target) - entry - 1e-9).rounded(.up)))
        return n > GradeRules.examMax ? nil : n
    }

    /// İndiki giriş balı: portal IGB yazıbsa o, yoxsa yazılmış hissələrin cəmi.
    static func entryNow(_ r: GradeRow) -> Double {
        num(r.score("IGB")) ?? parts(r).reduce(0) { $0 + ($1.value ?? 0) }
    }

    /// Hələ yazılmamış hissələrdən yığıla biləcək maksimum bal.
    static func entryOpen(_ r: GradeRow) -> Int { parts(r).filter { $0.value == nil }.reduce(0) { $0 + $1.max } }
}

/// 28 → "28", 28.5 → "28.5"
func fmt(_ d: Double) -> String {
    d.rounded() == d ? String(Int(d)) : String(format: "%.1f", d)
}

// MARK: - Tarix köməkçiləri

enum Day {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }()

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let weekdays = ["B.e", "Ç.a", "Çər", "C.a", "Cüm", "Şən", "Baz"]
    static let weekdaysLong = ["Bazar ertəsi", "Çərşənbə axşamı", "Çərşənbə", "Cümə axşamı", "Cümə", "Şənbə", "Bazar"]
    static let months = ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avqust", "sentyabr", "oktyabr", "noyabr", "dekabr"]

    static func key(_ d: Date) -> String { keyFormatter.string(from: d) }
    static func startOfToday() -> Date { cal.startOfDay(for: Date()) }
    static func add(_ n: Int, to d: Date) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }
    /// 0 = bazar ertəsi … 6 = bazar
    static func weekdayIndex(_ d: Date) -> Int { (cal.component(.weekday, from: d) + 5) % 7 }
    static func monday(of d: Date) -> Date { add(-weekdayIndex(d), to: cal.startOfDay(for: d)) }
    static func monthKey(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }
    /// "11 noyabr, Çərşənbə"
    static func title(_ d: Date) -> String {
        "\(cal.component(.day, from: d)) \(months[cal.component(.month, from: d) - 1]), \(weekdaysLong[weekdayIndex(d)])"
    }
    /// "14:20" → dəqiqə
    static func minutes(_ t: String) -> Int {
        let p = t.split(separator: ":")
        return (Int(p.first ?? "") ?? 0) * 60 + (p.count > 1 ? Int(p[1]) ?? 0 : 0)
    }
    static func nowMinutes() -> Int {
        let c = cal.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Regex-in ilk uyğunluğunun qrupları ([0] = bütün uyğunluq). Tapılmasa nil.
    func groups(_ pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    func regexReplace(_ pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return self }
        let ns = self as NSString
        return re.stringByReplacingMatches(in: self, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
}
