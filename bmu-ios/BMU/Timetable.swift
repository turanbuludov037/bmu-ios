import Foundation
import SwiftUI
import UIKit
import Vision

/// Dərs cədvəlinin şəkli (Android Timetable.kt ilə eyni): hər xanada 1) fənn (M/m/L) 2) müəllim 3) otaq.
/// İkiyə bölünmüş xanada üstdəki dərs ÜST həftədə, alttakı ALT həftədə keçirilir.
/// week: "" = hər həftə, "ust" = üst həftə, "alt" = alt həftə.  kind: "Nəzəri" | "Məşğələ" | "Laboratoriya".
struct TtEntry: Codable, Hashable, Sendable {
    var day: Int            // 1 = B.e. … 7 = Bazar
    var start: String       // "13:40"
    var subject: String
    var kind: String
    var teacher: String
    var room: String        // "1244" (ilk rəqəm bina)
    var week: String = ""
}

struct ParsedTimetable: Codable, Sendable {
    var group: String
    var entries: [TtEntry]
}

/// Sıra şəkilçisi: 244 → "244-cü", 202 → "202-ci", 109 → "109-cu", 140 → "140-cı".
func roomOrdinal(_ number: String) -> String {
    let trimmed = number.drop(while: { $0 == "0" })
    guard let n = Int(trimmed) else { return number }
    let suffix: String
    if n % 10 != 0 {
        switch n % 10 { case 3, 4: suffix = "cü"; case 6: suffix = "cı"; case 9: suffix = "cu"; default: suffix = "ci" }
    } else if n % 100 != 0 {
        switch (n / 10) % 10 { case 1, 3: suffix = "cu"; case 4, 6, 9: suffix = "cı"; default: suffix = "ci" }
    } else if n % 1000 != 0 {
        suffix = "cü"
    } else {
        suffix = "ci"
    }
    return "\(number)-\(suffix)"
}

/// Otaq: "1244" → bina 1, otaq 244.
struct Room: Sendable {
    let building: Character
    let number: String

    private static let buildings: [Character: (az: String, en: String, short: String, shortEn: String)] = [
        "1": ("Əsas korpus (Rektorluq binası)", "Main building (Rectorate)", "Əsas korpus", "Main bldg"),
        "2": ("İqtisad binası (İBF)", "Economics building (İBF)", "İBF", "İBF"),
        "7": ("Təzə bina (Yeni korpus)", "New building", "Yeni korpus", "New bldg"),
    ]

    var buildingName: String {
        if let b = Room.buildings[building] { return t(b.az, b.en) }
        return t("\(building) nömrəli bina", "Building \(building)")
    }
    var buildingShort: String {
        if let b = Room.buildings[building] { return t(b.short, b.shortEn) }
        return t("\(building)-ci bina", "Bldg \(building)")
    }
    /// "Əsas korpus, 244-cü otaq"
    var label: String { "\(buildingName), " + t("\(roomOrdinal(number)) otaq", "room \(number)") }
    /// "244 · Əsas korpus"
    var short: String { "\(number) · \(buildingShort)" }

    static func of(_ raw: String) -> Room? {
        let d = raw.filter(\.isNumber)
        guard d.count == 4 else { return nil }
        return Room(building: d.first!, number: String(d.dropFirst()))
    }
}

/// Fənn adlarının müqayisəsi: şəkildəki qısaltma ("Elektro. esas.", "ADIAK") ↔ portaldakı tam ad.
enum Names {
    private static let stop: Set<String> = ["ve", "va", "and"]

    static func norm(_ s: String) -> String {
        let lower = s.lowercased().replacingOccurrences(of: "ə", with: "e").replacingOccurrences(of: "ı", with: "i")
        return lower.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func tokens(_ s: String) -> [String] {
        norm(s).split(whereSeparator: { !(("a"..."z").contains($0) || ("0"..."9").contains($0)) }).map(String.init)
    }

    /// 0…1: qısaltmanın sözlərinin neçəsi tam adın sözlərinin başlanğıcıdır (və ya baş hərflər qısaltması).
    static func score(_ abbr: String, _ full: String) -> Double {
        let a = tokens(abbr).filter { $0.count >= 2 }
        let f = tokens(full)
        if a.isEmpty || f.isEmpty { return 0 }
        let acro = f.filter { !stop.contains($0) }.compactMap { $0.first }.map { String($0) }.joined()
        if a.count == 1 && (2...7).contains(a[0].count) && acro.hasPrefix(a[0]) { return 1 }
        let hit = a.filter { tk in f.contains { $0.hasPrefix(tk) || (tk.count >= 4 && $0.hasPrefix(String(tk.prefix(4)))) } }.count
        return Double(hit) / Double(a.count)
    }
}

private func kindOf(_ lessonType: String) -> String {
    switch lessonType {
    case "Məşğələ": return "Məşğələ"
    case "Laboratoriya": return "Laboratoriya"
    default: return "Nəzəri"
    }
}

private func pad5(_ s: String) -> String {
    let x = s.trimmed
    return x.count == 4 ? "0" + x : x
}

/// 1 = bazar ertəsi … 7 = bazar
func isoWeekday(_ d: Date) -> Int { Day.weekdayIndex(d) + 1 }

// MARK: - Yaddaş

@MainActor
final class TimetableStore: ObservableObject {
    static let shared = TimetableStore()
    @Published private(set) var entries: [TtEntry] = []
    @Published private(set) var group = ""
    private var number = ""

    private var fileName: String { "timetable_\(number)" }

    /// Girişdən sonra: bu tələbənin yüklədiyi cədvəl.
    func load(number: String, group portalGroup: String) {
        self.number = number
        guard let p = SecureStore.readJSON(ParsedTimetable.self, fileName) else { entries = []; group = ""; return }
        if !portalGroup.isEmpty && !TimetableStore.sameGroup(p.group, portalGroup) && !TimetableStore.groupCode(p.group).isEmpty {
            SecureStore.remove(fileName); entries = []; group = ""; return
        }
        entries = p.entries; group = p.group
    }

    func save(_ p: ParsedTimetable) {
        SecureStore.writeJSON(p, fileName)
        entries = p.entries; group = p.group
        afterChange()
    }

    func clear() {
        SecureStore.remove(fileName); entries = []; group = ""
        afterChange()
    }

    func reset() { entries = []; group = ""; number = "" }

    private func afterChange() {
        NotificationCenter.default.post(name: .timetableChanged, object: nil)
    }

    // MARK: dərs ↔ xana

    nonisolated static func match(_ list: [TtEntry], day: Int, lesson: Lesson) -> TtEntry? {
        let slot = list.filter { $0.day == day && $0.start == pad5(lesson.start) }
        if slot.isEmpty { return nil }
        let kind = kindOf(lesson.type)
        let scored = slot.map { ($0, ($0.kind == kind ? 1.0 : 0.0) + Names.score($0.subject, lesson.title)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else { return nil }
        return slot.count == 1 || best.1 >= 0.5 ? best.0 : nil
    }

    func entry(for date: Date, lesson: Lesson) -> TtEntry? { TimetableStore.match(entries, day: isoWeekday(date), lesson: lesson) }
    func room(for date: Date, lesson: Lesson) -> Room? { entry(for: date, lesson: lesson).flatMap { Room.of($0.room) } }

    // MARK: üst / alt həftə

    /// Bölünmüş xanaların hansı yarısındakı dərs bu həftə portal cədvəlində varsa, həftə odur.
    /// Bu həftə aydın deyilsə qonşu həftədən tərsinə götürülür. "ust" / "alt" / nil.
    nonisolated static func weekOf(_ day: Date, list: [TtEntry], lessons: [String: [Lesson]]) -> String? {
        if let w = direct(day, list, lessons) { return w }
        for k in 1...2 {
            let flip = k % 2 == 1
            for d in [Day.add(-7 * k, to: day), Day.add(7 * k, to: day)] {
                if let w = direct(d, list, lessons) { return flip ? (w == "ust" ? "alt" : "ust") : w }
            }
        }
        return nil
    }

    func weekOf(_ day: Date, lessons: [String: [Lesson]]) -> String? { TimetableStore.weekOf(day, list: entries, lessons: lessons) }

    private nonisolated static func direct(_ day: Date, _ list: [TtEntry], _ lessonsByDay: [String: [Lesson]]) -> String? {
        let monday = Day.monday(of: day)
        var ust = 0.0, alt = 0.0
        let halves = Dictionary(grouping: list.filter { !$0.week.isEmpty }) { "\($0.day)|\($0.start)" }
        for (_, hs) in halves {
            guard let first = hs.first else { continue }
            let date = Day.add(first.day - 1, to: monday)
            guard let dayLessons = lessonsByDay[Day.key(date)] else { continue }      // yüklənməyib → bilinmir
            let lessons = dayLessons.filter { pad5($0.start) == first.start }
            if lessons.isEmpty {
                if hs.count == 1 { if hs[0].week == "ust" { alt += 0.5 } else { ust += 0.5 } }
                continue
            }
            for l in lessons {
                guard let e = match(hs, day: first.day, lesson: l) else { continue }
                let w = l.count >= 2 ? 1.0 : 0.5
                if e.week == "ust" { ust += w } else { alt += w }
            }
        }
        if ust > alt { return "ust" }
        if alt > ust { return "alt" }
        return nil
    }

    nonisolated static func weekLabel(_ w: String) -> String { w == "ust" ? t("Üst həftə", "Upper week") : t("Alt həftə", "Lower week") }

    // MARK: qrup yoxlaması

    /// "135A1", "135a1 (20)", "Qrup: 135a1" → "135a1".
    nonisolated static func groupCode(_ raw: String) -> String {
        raw.replacingOccurrences(of: " ", with: "").groups(#"\d{2,4}[A-Za-z][0-9lIoO|]*"#)?.first?.lowercased() ?? ""
    }

    private nonisolated static func canon(_ code: String) -> String {
        String(code.map { c -> Character in
            switch c { case "l", "i", "|": return "1"; case "o": return "0"; default: return c }
        })
    }

    nonisolated static func sameGroup(_ a: String, _ b: String) -> Bool {
        let x = canon(groupCode(a)), y = canon(groupCode(b))
        return !x.isEmpty && x == y
    }

    /// Yalnız öz qrupunun cədvəli yüklənə bilər.
    nonisolated static func checkGroup(_ imageGroup: String, _ portalGroup: String) throws {
        let pg = groupCode(portalGroup)
        if pg.isEmpty { return }
        let ig = groupCode(imageGroup)
        if ig.isEmpty {
            throw PortalError.message(t("Şəkildə qrup nömrəsi tapılmadı. Cədvəlin ən yuxarısındakı qrup nömrəsi (məs. \(pg)) aydın görünən şəkil seçin.",
                                        "No group number found in the picture. Choose one where the group number at the top (e.g. \(pg)) is clearly visible."))
        }
        if !sameGroup(imageGroup, portalGroup) {
            throw PortalError.message(t("Bu cədvəl \(ig) qrupunundur, sənin qrupun isə \(pg). Yalnız öz qrupunun cədvəlini yükləyə bilərsən.",
                                        "This timetable belongs to group \(ig), but your group is \(pg). You can only upload your own group's timetable."))
        }
    }

    /// Oxunmuş cədvəlin portaldakı dərslərə uyğunluğu (0…1).
    nonisolated static func portalFit(_ entries: [TtEntry], lessons: [String: [Lesson]]) -> Double {
        if entries.isEmpty { return 0 }
        var byDay: [Int: [Lesson]] = [:]
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        for (k, ls) in lessons {
            guard let d = f.date(from: k) else { continue }
            byDay[isoWeekday(d), default: []] += ls
        }
        if byDay.isEmpty { return 0 }
        let hit = entries.filter { e in
            (byDay[e.day] ?? []).contains { pad5($0.start) == e.start && Names.score(e.subject, $0.title) >= 0.5 }
        }.count
        return Double(hit) / Double(entries.count)
    }

    // MARK: şəklin oxunması (Vision, telefonda)

    static func read(_ image: UIImage, portalGroup: String, lessons: [String: [Lesson]]) async throws -> ParsedTimetable {
        let words = try await ocr(image)
        let parsed = await offMain { TimetableParser.parse(words, fit: { portalFit($0, lessons: lessons) }) }
        guard let parsed else {
            throw PortalError.message(t("Şəkildə dərs cədvəli tanınmadı. Cədvəlin tam və aydın göründüyü şəkil seçin.",
                                        "No timetable was recognised. Choose a clear picture showing the whole timetable."))
        }
        try checkGroup(parsed.group, portalGroup)
        return parsed
    }

    /// Şəkildəki sözlər və onların çərçivələri (piksel, yuxarı-sol başlanğıc).
    private nonisolated static func ocr(_ image: UIImage) async throws -> [OcrBox] {
        // fırlanmanı düzəlt (kamera şəkilləri yan saxlanıla bilər)
        let upright: UIImage
        if image.imageOrientation == .up { upright = image } else {
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            upright = UIGraphicsImageRenderer(size: image.size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        }
        guard let cg = upright.cgImage else { throw PortalError.message(t("Şəkil oxunmadı", "The picture could not be read")) }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = false
                let wanted = ["tr-TR", "en-US", "ru-RU"]
                if let supported = try? req.supportedRecognitionLanguages() {
                    let langs = wanted.filter { supported.contains($0) }
                    if !langs.isEmpty { req.recognitionLanguages = langs }
                }
                do {
                    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
                } catch {
                    cont.resume(throwing: error); return
                }
                var out: [OcrBox] = []
                for obs in req.results ?? [] {
                    guard let cand = obs.topCandidates(1).first else { continue }
                    let str = cand.string
                    var idx = str.startIndex
                    // hər söz ayrıca (ML Kit-in "element"-ləri kimi)
                    while idx < str.endIndex {
                        while idx < str.endIndex && str[idx].isWhitespace { idx = str.index(after: idx) }
                        if idx >= str.endIndex { break }
                        var end = idx
                        while end < str.endIndex && !str[end].isWhitespace { end = str.index(after: end) }
                        let range = idx..<end
                        let box = (try? cand.boundingBox(for: range))?.boundingBox ?? obs.boundingBox
                        let l = box.minX * w, r = box.maxX * w
                        let top = (1 - box.maxY) * h, bottom = (1 - box.minY) * h
                        out.append(OcrBox(text: String(str[range]), l: l, t: top, r: r, b: bottom))
                        idx = end
                    }
                }
                cont.resume(returning: out)
            }
        }
    }
}

extension Notification.Name {
    static let timetableChanged = Notification.Name("timetableChanged")
}

// MARK: - Şəkildən oxunmuş sözlərdən cədvəlin qurulması (Android TimetableParser ilə eyni)

struct OcrBox: Hashable, Sendable {
    let text: String
    let l: CGFloat, t: CGFloat, r: CGFloat, b: CGFloat
    var cx: CGFloat { (l + r) / 2 }
    var cy: CGFloat { (t + b) / 2 }
    var h: CGFloat { b - t }
}

enum TimetableParser {
    /// BMU-nun dərs saatları: başlıqda saat yerinə "1-ci dərs", "I para", "1" yazılanda istifadə olunur.
    static let slots = ["09:00", "10:30", "12:00", "13:40", "15:10", "16:40", "18:10", "19:40"]

    private static let roman = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii"]
    private static let lessonWords = ["ders", "dars", "para", "lesson", "class", "пара", "урок"]
    private static let dayWords = ["gun", "day", "день"]

    fileprivate struct Line {
        let words: [OcrBox]
        var text: String { words.map(\.text).joined(separator: " ") }
        var l: CGFloat { words.map(\.l).min() ?? 0 }
        var r: CGFloat { words.map(\.r).max() ?? 0 }
        var t: CGFloat { words.map(\.t).min() ?? 0 }
        var b: CGFloat { words.map(\.b).max() ?? 0 }
        var cx: CGFloat { (l + r) / 2 }
        var cy: CGFloat { (t + b) / 2 }
        var h: CGFloat { b - t }
    }

    private static func lines(_ words: [OcrBox]) -> [Line] {
        var out: [[OcrBox]] = []
        for w in words.sorted(by: { $0.cy < $1.cy }) {
            if let i = out.lastIndex(where: { ln in
                let c = ln.map(\.cy).reduce(0, +) / CGFloat(ln.count)
                return abs(w.cy - c) < 0.5 * max(w.h, ln.map(\.h).max() ?? 0)
            }) {
                out[i].append(w)
            } else {
                out.append([w])
            }
        }
        return out.map { Line(words: $0.sorted { $0.l < $1.l }) }
    }

    private static func median(_ xs: [CGFloat]) -> CGFloat {
        let s = xs.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }

    // MARK: 1) başlıq yazıları

    fileprivate struct Label: Equatable {
        let line: Line
        let start: String?
        let lesson: Int?
        let days: Set<Int>
        let sureTime: Bool
        let sureDay: Bool
        var timeOk: Bool { start != nil || lesson != nil }
        var dayOk: Bool { !days.isEmpty }
        func startFor(_ slots: [String]) -> String? {
            if let start { return start }
            if let lesson, lesson >= 1, lesson <= slots.count { return slots[lesson - 1] }
            return nil
        }
        static func == (a: Label, b: Label) -> Bool { a.line.words == b.line.words }
    }

    static func dayCandidates(_ raw: String) -> Set<Int> {
        let s = String(Names.norm(raw).filter(\.isLetter))
        if s.isEmpty { return [] }
        let full: [(String, Int)] = [
            ("bazarert", 1), ("carsenbeax", 2), ("cersenbeax", 2), ("carsenbe", 3), ("cersenbe", 3),
            ("cumeax", 4), ("cume", 5), ("senbe", 6), ("bazar", 7),
            ("monday", 1), ("tuesday", 2), ("wednesday", 3), ("thursday", 4), ("friday", 5), ("saturday", 6), ("sunday", 7),
            ("понед", 1), ("вторн", 2), ("сред", 3), ("четв", 4), ("пятн", 5), ("суббот", 6), ("воскр", 7)
        ]
        if let f = full.first(where: { s.hasPrefix($0.0) }) { return [f.1] }
        if s.count > 4 { return [] }
        switch s {
        case "be": return [1]
        case "ca": return [2, 4]
        case "c": return [3, 5]
        case "cu", "cum": return [5]
        case "s", "se", "sen": return [6]
        case "b", "ba", "baz": return [7]
        case "mon", "mo": return [1]
        case "tue", "tu": return [2]
        case "wed", "we": return [3]
        case "thu", "th": return [4]
        case "fri", "fr": return [5]
        case "sat", "sa": return [6]
        case "sun", "su": return [7]
        case "пн": return [1]
        case "вт": return [2]
        case "ср": return [3]
        case "чт": return [4]
        case "пт": return [5]
        case "сб": return [6]
        case "вс": return [7]
        default: return []
        }
    }

    private static func two(_ h: Int) -> String { h < 10 ? "0\(h)" : "\(h)" }

    private static func classify(_ line: Line) -> Label? {
        let raw = line.text.trimmed
        let compact = raw.replacingOccurrences(of: " ", with: "")
        if let m = compact.groups(#"^(\d{1,2})[:.](\d{2})\s*[-–—]\s*(\d{1,2})[:.](\d{2})$"#), let h = Int(m[1]) {
            return Label(line: line, start: "\(two(h)):\(m[2])", lesson: nil, days: [], sureTime: true, sureDay: false)
        }
        if let m = compact.groups(#"^(\d{1,2})[:.](\d{2})$"#), let h = Int(m[1]), (7...21).contains(h) {
            return Label(line: line, start: "\(two(h)):\(m[2])", lesson: nil, days: [], sureTime: true, sureDay: false)
        }
        let n = Names.norm(raw).trimmed
        let letters = n.filter(\.isLetter)
        var value: Int?
        var rest = ""
        if let m = n.groups(#"^(\d)(?!\d)\s*[-.]?\s*(?:nci|ncu|ci|cu|st|nd|rd|th|й|я)?\.?\s*(.*)$"#) {
            value = Int(m[1]); rest = m[2].trimmed
        } else if let m = n.groups(#"^([ivx]{1,4})\.?\s*(.*)$"#), let ri = roman.firstIndex(of: m[1]),
                  m[2].isEmpty || lessonWords.contains(where: { m[2].hasPrefix($0) }) || dayWords.contains(where: { m[2].hasPrefix($0) }) {
            value = ri + 1; rest = m[2].trimmed
        }
        if let v = value, v >= 1 {
            let restL = String(rest.filter(\.isLetter))
            if lessonWords.contains(where: { restL.hasPrefix($0) }) {
                return v <= 8 ? Label(line: line, start: nil, lesson: v, days: [], sureTime: true, sureDay: false) : nil
            }
            if dayWords.contains(where: { restL.hasPrefix($0) }) {
                return v <= 7 ? Label(line: line, start: nil, lesson: nil, days: [v], sureTime: false, sureDay: true) : nil
            }
            if restL.isEmpty && v <= 8 {
                return Label(line: line, start: nil, lesson: v, days: v <= 7 ? [v] : [], sureTime: false, sureDay: false)
            }
            return nil
        }
        if letters.isEmpty || raw.contains(where: \.isNumber) { return nil }
        let days = dayCandidates(raw)
        if days.isEmpty { return nil }
        return Label(line: line, start: nil, lesson: nil, days: days, sureTime: false, sureDay: days.count == 1 && letters.count >= 3)
    }

    /// Sətirdən başlıqları ayırır: yaxın 1–3 sözü birləşdirməyə çalışır.
    private static func labelsIn(_ ln: Line) -> [Label] {
        let ws = ln.words
        let h = max(median(ws.map(\.h)), 1)
        var out: [Label] = []
        var i = 0
        while i < ws.count {
            var hit: Label?
            var used = 1
            var k = min(3, ws.count - i)
            while k >= 1 {
                let part = Array(ws[i..<(i + k)])
                let far = zip(part, part.dropFirst()).contains { $1.l - $0.r > 1.5 * h }
                if !far, let lb = classify(Line(words: part)) { hit = lb; used = k; break }
                k -= 1
            }
            if let hit { out.append(hit) }
            i += used
        }
        return out
    }

    // MARK: 2) oxlar

    private static func dedup(_ ls: [Label], by key: (Label) -> CGFloat) -> [Label] {
        var seen = Set<Int>()
        return ls.filter { seen.insert(Int((key($0) / 4).rounded())).inserted }
    }

    private static func rowsOf(_ all: [Label]) -> [[Label]] {
        var groups: [[Label]] = []
        for lb in all.sorted(by: { $0.line.cy < $1.line.cy }) {
            if let i = groups.lastIndex(where: { g in
                let c = g.map(\.line.cy).reduce(0, +) / CGFloat(g.count)
                return abs(c - lb.line.cy) < 0.6 * max(lb.line.h, g.map(\.line.h).max() ?? 0)
            }) {
                groups[i].append(lb)
            } else {
                groups.append([lb])
            }
        }
        return groups.map { dedup($0.sorted { $0.line.cx < $1.line.cx }, by: { $0.line.cx }) }.filter { $0.count >= 2 }
    }

    private static func columnsOf(_ all: [Label]) -> [[Label]] {
        var groups: [[Label]] = []
        for lb in all.sorted(by: { $0.line.l < $1.line.l }) {
            if let i = groups.firstIndex(where: { g in
                lb.line.l <= (g.map(\.line.r).max() ?? 0) && lb.line.r >= (g.map(\.line.l).min() ?? 0)
            }) {
                groups[i].append(lb)
            } else {
                groups.append([lb])
            }
        }
        return groups.map { dedup($0.sorted { $0.line.cy < $1.line.cy }, by: { $0.line.cy }) }.filter { $0.count >= 2 }
    }

    /// Gün oxu: hər yazının mümkün günləri + aralarındakı məsafə → ən uyğun ardıcıllıq.
    private static func assignDays(_ pos: [CGFloat], _ cands: [Set<Int>]) -> [Int?] {
        guard let p0 = pos.first else { return [] }
        let step = pos.count >= 2 ? median(zip(pos, pos.dropFirst()).map { $1 - $0 }) : 1
        let k = pos.map { step > 0 ? Int((($0 - p0) / step).rounded()) : 0 }
        var best = 1, bestScore = -1
        for d0 in 1...7 {
            if d0 + (k.last ?? 0) > 7 { break }
            let sc = k.indices.filter { cands[$0].contains(d0 + k[$0]) }.count
            if sc > bestScore { bestScore = sc; best = d0 }
        }
        return k.map { (1...7).contains(best + $0) ? best + $0 : nil }
    }

    // MARK: 3) ümumi oxuma

    static func parse(_ words: [OcrBox], fit: (([TtEntry]) -> Double)? = nil, slots: [String] = slots) -> ParsedTimetable? {
        if words.isEmpty { return nil }
        let all = lines(words)
        let labels = all.flatMap { labelsIn($0) }
        if labels.count < 4 { return nil }
        let hRows = rowsOf(labels)
        let vCols = columnsOf(labels)
        let maxH = labels.map(\.line.h).max() ?? 1

        var best: ParsedTimetable?
        var bestScore = -Double.infinity
        for h in hRows {
            for v in vCols {
                if h.contains(where: { v.contains($0) }) { continue }
                for transposed in [false, true] {
                    let top = h.filter { transposed ? $0.dayOk : $0.timeOk }
                    let side = v.filter { transposed ? $0.timeOk : $0.dayOk }
                    if top.count < 2 || side.count < 2 { continue }
                    if CGFloat(top.count) < CGFloat(h.count) * 0.6 || CGFloat(side.count) < CGFloat(v.count) * 0.6 { continue }
                    let colW = median(zip(top, top.dropFirst()).map { $1.line.cx - $0.line.cx })
                    let rowH = median(zip(side, side.dropFirst()).map { $1.line.cy - $0.line.cy })
                    if colW <= 0 || rowH <= 0 { continue }
                    if (side.map(\.line.r).max() ?? 0) > (top.map(\.line.cx).min() ?? 0) - colW * 0.25 { continue }
                    let topMeanCy = top.map(\.line.cy).reduce(0, +) / CGFloat(top.count)
                    if (side.map(\.line.cy).min() ?? 0) <= topMeanCy { continue }

                    let colKeys: [AnyHashable?], rowKeys: [AnyHashable?]
                    if !transposed {
                        colKeys = top.map { $0.startFor(slots).map { AnyHashable($0) } }
                        rowKeys = assignDays(side.map(\.line.cy), side.map(\.days)).map { $0.map { AnyHashable($0) } }
                    } else {
                        colKeys = assignDays(top.map(\.line.cx), top.map(\.days)).map { $0.map { AnyHashable($0) } }
                        rowKeys = side.map { $0.startFor(slots).map { AnyHashable($0) } }
                    }
                    let entries = grid(words, top, side, colW, rowH, colKeys, rowKeys, transposed)
                    if entries.isEmpty { continue }

                    let sure = top.filter { transposed ? $0.sureDay : $0.sureTime }.count + side.filter { transposed ? $0.sureTime : $0.sureDay }.count
                    let avgH = top.map(\.line.h).reduce(0, +) / CGFloat(top.count)
                    var score = Double(top.count + side.count) + 2.0 * Double(sure) + Double(avgH / maxH) + Double(entries.count) * 0.05
                    if let fit { score += 10.0 * fit(entries) }
                    if score > bestScore {
                        bestScore = score
                        let gridTop = side[0].line.cy - rowH / 2
                        let group = all.filter { $0.cy < gridTop }.lazy.compactMap {
                            $0.text.replacingOccurrences(of: " ", with: "").groups(#"(\d{2,4}[A-Za-z]\d*)\s*\(\s*\d+\s*\)"#)?[1]
                        }.first ?? ""
                        best = ParsedTimetable(group: group, entries: entries.sorted {
                            ($0.day, $0.start, $0.week) < ($1.day, $1.start, $1.week)
                        })
                    }
                }
            }
        }
        return best
    }

    private struct CellKey: Hashable { let r: Int, c: Int }

    private static func grid(_ words: [OcrBox], _ top: [Label], _ side: [Label], _ colW: CGFloat, _ rowH: CGFloat,
                             _ colKeys: [AnyHashable?], _ rowKeys: [AnyHashable?], _ transposed: Bool) -> [TtEntry] {
        let used = Set((top + side).flatMap { $0.line.words })
        let gridLeft = top[0].line.cx - colW / 2
        let gridTop = side[0].line.cy - rowH / 2
        var cells: [CellKey: [OcrBox]] = [:]
        for w in words {
            if used.contains(w) || w.cy <= gridTop || w.cx < gridLeft { continue }
            guard let ci = top.indices.min(by: { abs(top[$0].line.cx - w.cx) < abs(top[$1].line.cx - w.cx) }),
                  abs(top[ci].line.cx - w.cx) <= colW / 2,
                  let ri = side.indices.min(by: { abs(side[$0].line.cy - w.cy) < abs(side[$1].line.cy - w.cy) }),
                  abs(side[ri].line.cy - w.cy) <= rowH / 2 else { continue }
            cells[CellKey(r: ri, c: ci), default: []].append(w)
        }
        var out: [TtEntry] = []
        for (key, ws) in cells {
            guard let day = (transposed ? colKeys[key.c] : rowKeys[key.r]) as? Int,
                  let start = (transposed ? rowKeys[key.r] : colKeys[key.c]) as? String else { continue }
            out += cell(day, start, lines(ws), side[key.r].line.cy - rowH / 2, rowH)
        }
        return out
    }

    /// Bir xananın sətirlərindən dərs(lər). Bölünmüş xanada iki fənn: üstdəki üst, alttakı alt həftə.
    private static func cell(_ day: Int, _ start: String, _ ls: [Line], _ top: CGFloat, _ h: CGFloat) -> [TtEntry] {
        struct Draft { var subjectLine: Line; var subject = ""; var kind = "Nəzəri"; var teacher = ""; var room = ""; var parts: [Line] }
        let kindRx = #"\(\s*([MmLl])\s*\)"#
        let roomRx = #"(?<!\d)\d{4}(?!\d)"#
        var drafts: [Draft] = []
        for ln in ls.sorted(by: { $0.cy < $1.cy }) {
            let text = ln.text
            let kindM = text.groups(kindRx)
            let rooms = allMatches(text, roomRx)
            let rest = text.regexReplace(roomRx, with: "").trimmed
            let isSubject = kindM != nil || (drafts.isEmpty && rooms.isEmpty)
            if isSubject {
                var d = Draft(subjectLine: ln, parts: [ln])
                var sub = text.regexReplace(kindRx, with: "").regexReplace(#"\s+"#, with: " ").trimmed
                while sub.hasSuffix(".") || sub.hasSuffix(",") { sub.removeLast() }
                d.subject = sub.isEmpty ? text : sub
                switch kindM?[1] {
                case "m": d.kind = "Məşğələ"
                case "L", "l": d.kind = "Laboratoriya"
                default: d.kind = "Nəzəri"
                }
                drafts.append(d)
                continue
            }
            guard !drafts.isEmpty else { continue }
            drafts[drafts.count - 1].parts.append(ln)
            if let r = rooms.first, drafts[drafts.count - 1].room.isEmpty { drafts[drafts.count - 1].room = r }
            if rest.contains(where: \.isLetter) && drafts[drafts.count - 1].teacher.isEmpty { drafts[drafts.count - 1].teacher = rest }
        }
        if drafts.isEmpty { return [] }
        func rel(_ y: CGFloat) -> CGFloat { (y - top) / h }
        return drafts.enumerated().map { (i, d) -> TtEntry in
            let week: String
            if drafts.count >= 2 { week = i == 0 ? "ust" : "alt" }
            else if d.parts.allSatisfy({ rel($0.cy) < 0.62 }) && d.parts.count >= 2 { week = "ust" }
            else if rel(d.subjectLine.cy) > 0.45 { week = "alt" }
            else { week = "" }
            return TtEntry(day: day, start: start, subject: d.subject, kind: d.kind, teacher: d.teacher, room: d.room, week: week)
        }
    }

    private static func allMatches(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}
