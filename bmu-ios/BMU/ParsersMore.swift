import Foundation
import SwiftSoup

/// 2-ci mərhələ: transkript, tədris planı, qeydiyyat, kitabxana, turniket, təhsil haqqı, sənədlər, onlayn sifarişlər, ingiliscə ad.
extension Parsers {

    /// HTML → düz mətn (portalın xəta mesajları üçün).
    static func plain(_ html: String) -> String {
        ((try? SwiftSoup.parse(html).text()) ?? html).trimmed
    }

    private static func tdTexts(_ tr: Element) -> [String] { tds(tr).map { txt($0) } }

    // MARK: tədris planı

    private static func planStatus(_ style: String) -> String {
        switch style.groups(#"color:\s*(#[0-9A-Fa-f]{6})"#)?[1].uppercased() {
        case "#009900": return "passed"
        case "#FF0000": return "failed"
        case "#FF9900": return "current"
        default: return "upcoming"
        }
    }

    /// Tədris proqramı: #tblMufredatProg içində hər semestr üçün [nömrə div] + [dərslər cədvəli].
    static func curriculum(_ html: String) -> Curriculum? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        var sems: [PlanSemester] = []
        for div in select(doc, "#tblMufredatProg div[style*=28px]") {
            guard let no = Int(txt(div)) else { continue }
            guard let tr = div.parents().array().first(where: { $0.tagName() == "tr" }),
                  let next = try? tr.nextElementSibling() else { continue }
            var courses: [PlanCourse] = []
            for row in select(next, "table tr") {
                let td = tds(row)
                if td.count < 7 || Int(txt(td[0])) == nil { continue }
                let code = txt(td[1])
                let tag: String, name: String
                if code.hasPrefix("XXX") {
                    tag = txt(first(td[2], "b")).replacingOccurrences(of: " ", with: "")
                    name = td[2].ownText().trimmed
                } else {
                    tag = code
                    name = txt(td[2])
                }
                let titleAttr = ((try? td[5].attr("title")) ?? "").trimmed
                courses.append(PlanCourse(tag: tag, title: name, theory: txt(td[4]),
                                          practice: titleAttr.isEmpty ? txt(td[5]) : titleAttr,
                                          akts: Int(txt(td[6])) ?? 0,
                                          status: planStatus((try? row.attr("style")) ?? "")))
            }
            if !courses.isEmpty { sems.append(PlanSemester(number: no, courses: courses)) }
        }
        if sems.isEmpty { return nil }
        let raw = txt(first(doc, "h4"))
        var title = raw
        if let m = raw.groups(#"^(\d{4})-(.*)$"#) { title = t("\(m[1]) qəbul", "\(m[1]) intake") + " · " + m[2].trimmed }
        return Curriculum(title: title, semesters: sems)
    }

    // MARK: dərs qeydiyyatı

    static func registration(_ html: String) -> Registration? {
        guard let doc = try? SwiftSoup.parse(html), let titleEl = first(doc, "font.moduleTitle") else { return nil }
        let title = txt(titleEl)
        var term = ""
        if let m = title.groups(#"\((\d{4})-(\d{4})\s+(\d)\)"#) { term = "\(m[1])–\(m[2]) · \(m[3])" }
        let closed = select(doc, ".errorMsg").map { txt($0) }.joined(separator: " ").localizedCaseInsensitiveContains("bağlıdır")
        let confirmed = ((try? doc.text()) ?? "").localizedCaseInsensitiveContains("təsdiqlənmişdir")
        var courses: [RegCourse] = []
        var total = 0
        for tr in select(doc, "table.box tr") {
            let td = tds(tr)
            if td.count < 10 { continue }
            let akts = Int(txt(td[9]))
            if Int(txt(td[0])) != nil {
                courses.append(RegCourse(code: txt(td[1]), title: txt(td[5]), akts: akts ?? 0))
            } else if let akts {
                total = akts
            }
        }
        if courses.isEmpty && !closed { return nil }
        if total == 0 { total = courses.reduce(0) { $0 + $1.akts } }
        return Registration(term: term, closed: closed, confirmed: confirmed, courses: courses, totalAkts: total)
    }

    // MARK: transkript

    static func transcript(_ html: String) -> Transcript? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        var header: [KV] = []
        for tr in select(doc, "table.simple-table tr") {
            let cells = tdTexts(tr)
            var i = 0
            while i < cells.count - 1 {
                if cells[i].hasSuffix(":") {
                    header.append(KV(key: String(cells[i].dropLast()).trimmed, value: cells[i + 1]))
                    i += 2
                } else { i += 1 }
            }
        }
        final class Sem {
            let year: String, year2: String, no: String
            var rows: [TranscriptRow] = []
            var sUomg = "", uomg = "", sqk = "", tak = "", tqk = ""
            init(_ y: String, _ y2: String, _ n: String) { year = y; year2 = y2; no = n }
        }
        func kredit(_ text: String, _ key: String) -> String { text.groups("\(key)\\s*:\\s*(\\d+)")?[1] ?? "" }
        func sUomgOf(_ s: String) -> String { s.groups(#"S-ÜOMG\s*:\s*([\d.]+)"#)?[1] ?? "" }
        func uomgOf(_ s: String) -> String { s.groups(#"(?<!-)ÜOMG\s*:\s*([\d.]+)"#)?[1] ?? "" }

        var sems: [Sem] = []
        var overall = "", credits = ""
        for tr in select(doc, "table.table tr") {
            let td = tds(tr)
            if td.isEmpty { continue }
            let text = txt(tr)
            if td.count == 1 {
                if td[0].hasAttr("colspan"), !text.contains("ÜOMG"), let m = text.groups(#"(\d{4})\s*-\s*(\d{4})\.\s*(\d)"#) {
                    sems.append(Sem(m[1], m[2], m[3]))
                    continue
                }
                if text.localizedCaseInsensitiveContains("Tamamlanmış akts") { credits = text.groups(#"(\d+)\s*$"#)?[1] ?? "" }
                else if text.hasPrefix("ÜOMG") { let u = uomgOf(text); if !u.isEmpty { overall = u } }
                continue
            }
            guard td.count >= 7, let last = sems.last else { continue }
            let code = txt(td[0])
            if code.isEmpty {
                last.sUomg = sUomgOf(txt(td[4]))
                last.uomg = uomgOf(txt(td[5]))
                let k = txt(td[1])
                last.sqk = kredit(k, "SQK"); last.tak = kredit(k, "TAK"); last.tqk = kredit(k, "TQK")
                continue
            }
            if code.uppercased().hasPrefix("DƏRS") { continue }
            last.rows.append(TranscriptRow(code: code, title: txt(td[1]), hours: txt(td[2]), credit: Int(txt(td[3])) ?? 0,
                                           score: txt(td[4]), letter: txt(td[5]), repeatMark: txt(td[6])))
        }
        if sems.isEmpty { return nil }
        return Transcript(sems: sems.map { TranscriptSem(year: $0.year, year2: $0.year2, no: $0.no, rows: $0.rows, sUomg: $0.sUomg,
                                                          uomg: $0.uomg, sqk: $0.sqk, tak: $0.tak, tqk: $0.tqk) },
                          uomg: overall, credits: credits, header: header)
    }

    // MARK: turniket

    static func turnstile(_ html: String) -> (gates: [Gate], total: String)? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let root: Element = first(doc, "#div_results") ?? doc.body() ?? doc
        guard let table = first(root, "table.table") else { return nil }
        let gates = select(table, "tr").compactMap { tr -> Gate? in
            let td = tdTexts(tr)
            if td.count < 7 || Int(td[0]) == nil { return nil }
            return Gate(date: td[2], day: td[3], inTime: td[4].isEmpty ? "-" : td[4], outTime: td[5].isEmpty ? "-" : td[5], stay: td[6])
        }
        let total = (txt(root).groups("Toplam vaxt:[^<]*")?[0] ?? "").trimmed
        return (gates, total)
    }

    // MARK: kitabxana

    static func books(_ html: String) -> (items: [LibBook], total: Int)? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let found = ((try? doc.text()) ?? "").groups(#"(\d+)\s+nəticə tapıldı"#).flatMap { Int($0[1]) }
        let table = first(doc, "table.table.box")
        let items: [LibBook] = table.map { tb in
            select(tb, "tr").compactMap { tr -> LibBook? in
                let td = tds(tr)
                if td.count < 5 || Int(txt(td[0])) == nil { return nil }
                let href = first(td[1], "a[href]").flatMap { try? $0.attr("href") } ?? ""
                return LibBook(title: txt(td[1]), author: txt(td[2]), publisher: txt(td[3]), year: txt(td[4]), href: href)
            }
        } ?? []
        if table == nil && found == nil { return nil }
        return (items, found ?? items.count)
    }

    static func libRows(_ html: String) -> LibRows? {
        guard let doc = try? SwiftSoup.parse(html),
              let table = first(doc, "div.tab-content table.table.box") ?? first(doc, "table.table.box") else { return nil }
        var rows: [[String]] = []
        var empty = ""
        for tr in select(table, "tr") {
            let td = tds(tr)
            if td.isEmpty { continue }
            if td.count == 1 || td.contains(where: { $0.hasAttr("colspan") }) { empty = txt(td[0]) }
            else if Int(txt(td[0])) != nil { rows.append(td.map { txt($0) }) }
        }
        return LibRows(rows: rows, empty: empty)
    }

    static func libDetail(_ html: String) -> LibDetail? {
        guard let doc = try? SwiftSoup.parse(html), let info = first(doc, "#table1") else { return nil }
        let fields: [KV] = select(info, "tr").compactMap { tr -> KV? in
            let td = tds(tr)
            if td.count < 2 { return nil }
            var k = txt(td[0])
            while k.hasSuffix(":") { k.removeLast() }
            let v = txt(td[1]).regexReplace(#"\s+"#, with: " ")
            return k.trimmed.isEmpty || v.isEmpty ? nil : KV(key: k.trimmed, value: v)
        }
        let queue = select(doc, "div[align=right] span").map { txt($0) }.joined(separator: " ").trimmed
        let inv: [LibInv] = select(doc, "table.table.box tr").compactMap { tr -> LibInv? in
            let td = tds(tr)
            let n = td.first.map { txt($0) } ?? ""
            if td.count < 4 || n.isEmpty || n.hasPrefix("İnventar") { return nil }
            var form: [String: String]? = nil
            if let f = first(tr, "form"), select(f, "input[name=action]").contains(where: { ((try? $0.attr("value")) ?? "") == "insert_inv_request" }) {
                var m: [String: String] = [:]
                for input in select(f, "input[type=hidden]") {
                    let name = (try? input.attr("name")) ?? ""
                    if !name.isEmpty { m[name] = (try? input.attr("value")) ?? "" }
                }
                form = m
            }
            return LibInv(number: n, status: txt(td[1]), returnDate: txt(td[2]), place: txt(td[3]), orderForm: form)
        }
        return LibDetail(fields: fields, queueNote: queue, inventory: inv)
    }

    // MARK: onlayn xidmətlər → sifarişlərim

    static func onlineOrders(_ html: String) -> [OnlOrder]? {
        guard let doc = try? SwiftSoup.parse(html), let table = first(doc, "table.table.box") else { return nil }
        return select(table, "tr").compactMap { tr -> OnlOrder? in
            let td = tds(tr)
            if td.count < 8 || Int(txt(td[0])) == nil { return nil }
            let dateAttr = ((try? td[4].attr("title")) ?? "").trimmed
            return OnlOrder(title: txt(td[1]), semester: txt(td[2]), place: txt(td[3]),
                            date: dateAttr.isEmpty ? txt(td[4]) : dateAttr, status: txt(td[5]), note: txt(td[6]), lang: txt(td[7]))
        }
    }

    // MARK: ingiliscə ad

    static func englishName(_ html: String) -> (name: String, surname: String, father: String)? {
        guard let doc = try? SwiftSoup.parse(html), let n = first(doc, "#nameEn") else { return nil }
        func val(_ e: Element?) -> String { ((e.flatMap { try? $0.attr("value") }) ?? "").trimmed }
        return (val(n), val(first(doc, "#snameEn")), val(first(doc, "#fnameEn")))
    }

    // MARK: təhsil haqqı

    static func tuition(_ html: String) -> (title: String, rows: [TuitionRow])? {
        guard let doc = try? SwiftSoup.parse(html), let table = first(doc, "table.table.box") else { return nil }
        let rows: [TuitionRow] = select(table, "tr").compactMap { tr -> TuitionRow? in
            let td = tdTexts(tr)
            if td.count < 11 || Int(td[0]) == nil { return nil }
            return TuitionRow(year: td[1], semester: td[2], extra: td[3], fee: td[4], debt: td[5],
                              totalDebt: td[6], paid: td[7], remaining: td[8], status: td[9], kind: td[10])
        }
        if rows.isEmpty { return nil }
        return (txt(first(doc, "font.moduleTitle")), rows)
    }

    // MARK: sənədlər

    static func docCategories(_ html: String, parent: String) -> [DocCat]? {
        guard let doc = try? SwiftSoup.parse(html), let table = first(doc, "table.table.box") else { return nil }
        return select(table, "tr").compactMap { tr -> DocCat? in
            let td = tds(tr)
            if td.count < 2 || Int(txt(td[0])) == nil { return nil }
            let sub = ((try? td[1].html()) ?? "").groups(#"GetDocCategories\((\d+)"#)?[1]
            let docs = td.count > 2 ? ((try? td[2].html()) ?? "").groups(#"GetDocsByCat\((\d+)"#)?[1] : nil
            return DocCat(name: txt(td[1]), subId: sub, docsCat: docs, parent: parent)
        }
    }

    static func docList(_ html: String) -> (headers: [String], items: [DocItem])? {
        guard let doc = try? SwiftSoup.parse(html), let table = first(doc, "#doc_table") ?? first(doc, "table") else { return nil }
        let headers = select(table, "thead th, thead td").map { txt($0) }
        let items: [DocItem] = select(table, "tr").filter { $0.parent()?.tagName() != "thead" }.compactMap { tr -> DocItem? in
            let td = tds(tr)
            if td.isEmpty || td.allSatisfy({ txt($0).isEmpty && select($0, "a").isEmpty }) { return nil }
            var links: [DocLink] = []
            for a in select(tr, "a") {
                let href = ((try? a.attr("href")) ?? "").trimmed
                let prev = ((try? a.attr("onclick")) ?? "").groups(#"PreviewForm\(['"]([^'"]+)['"]"#)?[1]
                var target: String? = nil
                if !href.isEmpty && !href.hasPrefix("javascript") && href != "#" { target = href } else if let prev { target = prev }
                if let target {
                    let name = txt(a)
                    links.append(DocLink(title: name.isEmpty ? t("Aç", "Open") : name, target: target))
                }
            }
            return DocItem(cells: td.map { txt($0) }, links: links)
        }
        return (headers, items)
    }

    // MARK: ad günü

    /// Ana səhifədəki "Bu gün (09 Noyabr) 19 BMU tələbəsinin doğum günüdür."
    static func birthdays(_ html: String) -> Int? {
        let text = plain(html).replacingOccurrences(of: "\u{00A0}", with: " ")
        return text.groups(#"(\d+)\s*BMU\s+tələbəsinin\s+doğum\s+günüdür"#, options: .caseInsensitive).flatMap { Int($0[1]) }
    }

    /// "Aşağıdakı məlumatlar doğrudurmu?" təsdiq səhifəsindəki ad/dəyər sətirləri.
    static func onlineConfirm(_ html: String) -> [KV] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }
        return select(doc, "table.simple-table tr").compactMap { tr -> KV? in
            let td = tds(tr)
            if td.count != 2 || td.contains(where: { $0.hasAttr("colspan") }) { return nil }
            var k = txt(td[0])
            while k.hasSuffix(":") { k.removeLast() }
            let v = txt(td[1])
            return k.trimmed.isEmpty || v.isEmpty ? nil : KV(key: k.trimmed, value: v)
        }
    }
}
