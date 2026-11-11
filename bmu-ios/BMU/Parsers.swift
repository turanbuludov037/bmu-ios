import Foundation
import SwiftSoup

/// my.beu.edu.az səhifələrinin oxunması (Android-dəki PortalParsers.kt-nin Swift versiyası).
enum Parsers {
    static let slotMinutes = 40          // 1 dərs saatı = 40 dəqiqə
    private static let monthsEn = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    // MARK: köməkçilər

    private static func tds(_ tr: Element) -> [Element] {
        tr.children().array().filter { $0.tagName() == "td" }
    }

    private static func txt(_ e: Element?) -> String {
        guard let e = e else { return "" }
        return ((try? e.text()) ?? "").trimmed
    }

    private static func select(_ root: Element, _ css: String) -> [Element] {
        ((try? root.select(css))?.array()) ?? []
    }

    private static func first(_ root: Element, _ css: String) -> Element? {
        select(root, css).first
    }

    /// "11-Jun-2008" → "11.06.2008"
    private static func date(_ raw: String) -> String {
        guard let g = raw.groups(#"(\d{1,2})-([A-Za-z]{3})-(\d{4})"#),
              let mi = monthsEn.firstIndex(of: g[2].lowercased()), let d = Int(g[1]) else { return raw }
        return String(format: "%02d.%02d.%@", d, mi + 1, g[3])
    }

    // MARK: profil

    /// Profil səhifəsi: hər sətirdə [etiket] [dəyər] cütü olan cədvəl. Tapılmasa nil.
    static func profile(_ html: String) -> Profile? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        var rows: [(String, Element)] = []
        for tr in select(doc, "tr") {
            let t = tds(tr)
            if t.count < 2 { continue }
            rows.append((txt(t[t.count - 2]), t[t.count - 1]))
        }
        func el(_ prefix: String) -> Element? {
            let p = prefix.lowercased()
            return rows.first { $0.0.lowercased().hasPrefix(p) }?.1
        }
        func get(_ prefix: String) -> String { txt(el(prefix)) }

        let number = get("Tələbə nömrəniz")
        if number.isEmpty { return nil }

        var p = Profile()
        p.number = number
        p.fullName = get("Ad soyad")
        p.birth = date(get("Doğum tarixi"))

        // "Kompüter mühəndisliyi-AZ / 2"
        let prog = get("İxtisas").components(separatedBy: "/")
        let progRaw = (prog.first ?? "").trimmed
        if let m = progRaw.groups(#"^(.*)-([A-Za-z]{2})$"#) {
            p.program = m[1].trimmed
            p.programLang = m[2].uppercased()
        } else {
            p.program = progRaw
        }
        p.course = prog.count > 1 ? prog[1].trimmed : ""
        p.group = get("Qrup kodu")
        p.advisor = get("Akademik məsləhətçi")
        p.status = get("Status")

        // "Təhsil haqqı borcunuz [2026 - 1]" + "Yoxdur (1 AZN avans ödənib)"
        let key = "Təhsil haqqı borcunuz".lowercased()
        if let row = rows.first(where: { $0.0.lowercased().hasPrefix(key) }) {
            if let term = row.0.groups(#"\[(\d{4})\s*-\s*(\d)\]"#) {
                p.termYear = term[1]; p.termNo = term[2]
            }
            p.tuitionDebt = txt(first(row.1, "b"))
            var adv = txt(first(row.1, "span"))
            if adv.hasPrefix("(") { adv.removeFirst() }
            if adv.hasSuffix(")") { adv.removeLast() }
            p.advance = adv.trimmed
        }
        p.dormDebt = get("Yataqxana borcunuz")
        p.annualFee = get("İllik Təhsil haqqı")
        p.payForm = get("Təhsil haqqı ödəniş forması")
        p.score = get("Qəbul balı")
        p.email = get("BMU Mail")
        p.regDate = get("Qeydiyyat tarixi")
        return p
    }

    /// Ana səhifədəki tələbə şəkli: <img src="stud_photo.php?ses=...">
    static func photoPath(_ html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        return select(doc, "img[src*=stud_photo]").compactMap { try? $0.attr("src") }.first { !$0.isEmpty }
    }

    // MARK: cədvəl

    private struct Ev { let date: String, time: String, code: String, name: String, type: String }

    /// load_course_schedule.php (FullCalendar JSON): [{"title":"RİY 257 (məş) - Riyazi analiz","start":"09/16/2026 15:10"}, ...]
    /// Ardıcıl 40 dəqiqəlik parçalar bir dərsə birləşdirilir. JSON deyilsə nil.
    static func schedule(_ json: String) -> [String: [Lesson]]? {
        guard let data = json.trimmed.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        var evs: [Ev] = []
        for o in arr {
            let start = (o["start"] as? String) ?? ""
            let day: String
            if let us = start.groups(#"(\d{1,2})/(\d{1,2})/(\d{4})"#), let mo = Int(us[1]), let d = Int(us[2]) {
                day = String(format: "%@-%02d-%02d", us[3], mo, d)          // portal: ay/gün/il
            } else if let iso = start.groups(#"(\d{4})-(\d{2})-(\d{2})"#) {
                day = "\(iso[1])-\(iso[2])-\(iso[3])"
            } else { continue }
            var time = ""
            if let t = start.groups(#"(\d{1,2}):(\d{2})"#), let h = Int(t[1]) { time = String(format: "%02d:%@", h, t[2]) }
            if time.isEmpty { continue }

            let title = ((o["title"] as? String) ?? "").trimmed
            let head: String, name: String
            if let r = title.range(of: " - ") {
                head = String(title[..<r.lowerBound]).trimmed
                name = String(title[r.upperBound...]).trimmed
            } else { head = title; name = "" }
            let type = head.contains("(məş)") ? "Məşğələ" : head.contains("(lab)") ? "Laboratoriya" : "Nəzəri dərs"
            let code = head.regexReplace(#"\s*\(.*?\)"#, with: "").trimmed
            evs.append(Ev(date: day, time: time, code: code, name: name.isEmpty ? code : name, type: type))
        }

        func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }
        var out: [String: [Lesson]] = [:]
        let groups = Dictionary(grouping: evs) { "\($0.date)|\($0.code)|\($0.type)" }
        for (_, list) in groups {
            var seen = Set<String>()
            let sorted = list.sorted { Day.minutes($0.time) < Day.minutes($1.time) }.filter { seen.insert($0.time).inserted }
            var run: [Ev] = []
            func flush() {
                guard let f = run.first, let l = run.last else { return }
                let lesson = Lesson(start: hhmm(Day.minutes(f.time)), end: hhmm(Day.minutes(l.time) + slotMinutes),
                                    code: f.code, title: f.name, type: f.type, count: run.count)
                out[f.date, default: []].append(lesson)
                run = []
            }
            for e in sorted {
                if let last = run.last, Day.minutes(e.time) - Day.minutes(last.time) > 45 { flush() }
                run.append(e)
            }
            flush()
        }
        for k in out.keys { out[k]?.sort { $0.start < $1.start } }
        return out
    }

    // MARK: qiymətlər

    /// "İl və semestr" siyahısı (select#ysem). Qiymətlərdə "1#1", jurnalda "0#0" çıxarılır.
    static func semesters(_ html: String, skip: String) -> [Semester] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }
        return select(doc, "select#ysem option").compactMap { o in
            let v = ((try? o.attr("value")) ?? "").trimmed
            if v.isEmpty || v == skip { return nil }
            return Semester(value: v, label: txt(o), selected: o.hasAttr("selected"))
        }
    }

    /// Ajax cavabı: {"CODE":1,"DATA":"<html>"}. Birbaşa HTML gəlibsə cədvəl hissəsini qaytarır.
    static func extractAjaxData(_ body: String) -> String? {
        var t = body.trimmed
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        if t.hasPrefix("{"), let data = t.data(using: .utf8),
           let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let code = (o["CODE"] as? Int) ?? Int("\(o["CODE"] ?? "")") ?? 0
            return code == 1 ? (o["DATA"] as? String) : nil
        }
        guard let lo = t.range(of: "<table", options: .caseInsensitive),
              let hi = t.range(of: "</table>", options: [.caseInsensitive, .backwards]),
              lo.lowerBound < hi.upperBound else { return nil }
        return unescapeJs(String(t[lo.lowerBound..<hi.upperBound]))
    }

    private static func unescapeJs(_ s: String) -> String {
        if !s.contains("\\") { return s }
        var r = s
        // \uXXXX
        if let re = try? NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})"#) {
            let ns = r as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: r, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1))
                if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { result += String(Character(u)) }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            r = result
        }
        r = r.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t").replacingOccurrences(of: "\\r", with: "")
        return r.replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Qiymət cədvəli: başlıq sətrindəki adlara görə sütunlar (Dərs kodu, Dərsin adı, AKTS, Qaib, SDF1 ...).
    static func grades(_ html: String) -> [GradeRow]? {
        guard let doc = try? SwiftSoup.parse(html),
              let table = first(doc, "table.box") ?? first(doc, "table") else { return nil }
        let trs = select(table, "tr")
        guard let head = trs.first else { return nil }
        let headers = head.children().array().filter { $0.tagName() == "td" || $0.tagName() == "th" }.map { txt($0) }
        guard let iCode = headers.firstIndex(of: "Dərs kodu"), let iName = headers.firstIndex(of: "Dərsin adı") else { return nil }
        let iAkts = headers.firstIndex(of: "AKTS"), iMissed = headers.firstIndex(of: "Qaib")
        var rows: [GradeRow] = []
        for tr in trs.dropFirst() {
            let td = tds(tr)
            if td.count <= max(iName, iCode) { continue }
            let code = txt(td[iCode])
            if code.isEmpty || code.localizedCaseInsensitiveContains("Cəmi") { continue }
            func col(_ h: String) -> String {
                guard let i = headers.firstIndex(of: h), i < td.count else { return "" }
                return txt(td[i])
            }
            var scores: [String: String] = [:]
            for k in ["SDF1"] + OTHER_SCORES { scores[k] = col(k) }
            rows.append(GradeRow(
                code: code, title: txt(td[iName]),
                akts: iAkts.flatMap { $0 < td.count ? Int(txt(td[$0])) : nil } ?? 0,
                missed: iMissed.map { $0 < td.count ? txt(td[$0]) : "" } ?? "",
                scores: scores, n: col("N"), m: col("M"), l: col("L")))
        }
        return rows
    }

    // MARK: elektron jurnal

    /// Elektron jurnal: hər şöbə ayrı sətirdir ("EM 220", "EM 220-lab", "RİY 257-məş"); eyni fənn birləşdirilir.
    /// Sütunlar: № | Kodu | Dərsin adı | Müəllim | Kre. | Saat | Lim | + | q | % | zolaq
    static func journal(_ html: String) -> [JournalCourse]? {
        guard let doc = try? SwiftSoup.parse(html),
              let table = first(doc, "#divCont table.box") ?? first(doc, "table.box") else { return nil }
        struct Part { let base, kind, name, teacher: String; let att, miss: Int; let pct: Double; let hours: Int; let lim: Double }
        var parts: [Part] = []
        for tr in select(table, "tr") {
            let td = tds(tr)
            if td.count < 10 || Int(txt(td[0])) == nil { continue }
            let raw = txt(td[1])
            var base = raw, kind = "Nəzəri"
            if raw.hasSuffix("-məş") { kind = "Məşğələ"; base = String(raw.dropLast(4)) }
            else if raw.hasSuffix("-lab") { kind = "Laboratoriya"; base = String(raw.dropLast(4)) }
            func dbl(_ s: String) -> Double { Double(s.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".").trimmed) ?? 0 }
            parts.append(Part(base: base.trimmed, kind: kind, name: txt(td[2]), teacher: txt(td[3]),
                              att: Int(txt(td[7])) ?? 0, miss: Int(txt(td[8])) ?? 0, pct: dbl(txt(td[9])),
                              hours: Int(txt(td[5])) ?? 0, lim: dbl(txt(td[6]))))
        }
        if parts.isEmpty { return nil }
        let order = ["Nəzəri", "Məşğələ", "Laboratoriya"]
        var keys: [String] = []
        var byBase: [String: [Part]] = [:]
        for p in parts {
            if byBase[p.base] == nil { keys.append(p.base) }
            byBase[p.base, default: []].append(p)
        }
        return keys.compactMap { k in
            guard let list = byBase[k], let f = list.first else { return nil }
            let rows = list.sorted { (order.firstIndex(of: $0.kind) ?? 9) < (order.firstIndex(of: $1.kind) ?? 9) }
                .map { JournalRow(label: $0.kind, attended: $0.att, missed: $0.miss, hours: $0.hours, limit: $0.lim) }
            return JournalCourse(code: k, title: f.name, teacher: f.teacher, rows: rows, percent: list.map(\.pct).max() ?? 0)
        }
    }
}
