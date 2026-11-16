import Foundation
import SwiftUI
import SwiftSoup
import UserNotifications

/// Kitabxana: qaytarma vaxtı xatırlatması (Android LibraryDue ilə eyni).
/// "İstifadəçi kartım"-dan (mod=lib&type=6) götürülmüş kitabların qaytarma tarixi şifrəli saxlanılır;
/// tarixə 2 gün və 1 gün qalmış (10:00), bir də həmin gün səhər (09:00) bildiriş gəlir.
struct Loan: Codable, Identifiable, Hashable, Sendable {
    var id: String { title + due }
    let title: String
    let due: String          // "yyyy-MM-dd"

    var dueDate: Date? { LibraryDue.keyDate(due) }
}

@MainActor
final class LibraryDue: ObservableObject {
    static let shared = LibraryDue()
    @Published private(set) var current: [Loan] = []

    private static let file = "library_due"
    private static let lastKey = "library_sync_at"

    nonisolated static func keyDate(_ k: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: k)
    }

    /// Girişdən sonra: yadda saxlanmış tarixləri ekrana ver.
    static func loadState() {
        shared.current = SecureStore.readJSON([Loan].self, file) ?? []
    }

    /// Portaldan oxu (girişdə və gündə bir dəfə). Uğursuzluq heç nəyi pozmur.
    static func sync(force: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: lastKey)
        if !force && Date().timeIntervalSince1970 - last < 20 * 3600 { await reschedule(); return }
        guard let html = try? await Portal.shared.fetch("index.php?mod=lib&type=6"),
              let loans = await offMain({ parseLoans(html) }) else { return }
        SecureStore.writeJSON(loans, file)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)
        shared.current = loans
        await reschedule()
    }

    /// Yadda saxlanmış tarixlərdən bildirişləri yenidən qurur.
    static func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("lib-") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        if shared.current.isEmpty { shared.current = SecureStore.readJSON([Loan].self, file) ?? [] }
        guard await Notifier.authorized() else { return }
        let now = Date()
        for loan in shared.current {
            guard let due = loan.dueDate else { continue }
            let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"; df.locale = Locale(identifier: "en_US_POSIX")
            let text = "\(loan.title) · " + t("son tarix ", "due ") + df.string(from: due)
            let plan: [(Int, Int, String)] = [
                (-2, 10, t("Kitabı 2 gün sonra qaytarmalısan", "Return your book in 2 days")),
                (-1, 10, t("Kitabı sabah qaytarmalısan", "Return your book tomorrow")),
                (0, 9, t("Kitabı bu gün qaytarmalısan", "Return your book today"))
            ]
            for (i, (offset, hour, title)) in plan.enumerated() {
                guard let at = Day.cal.date(bySettingHour: hour, minute: 0, second: 0, of: Day.add(offset, to: due)), at > now else { continue }
                let c = UNMutableNotificationContent()
                c.title = "📚 " + title
                c.body = text
                c.sound = .default
                c.threadIdentifier = "library"
                let comps = Day.cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                let id = "lib-\(loan.due)-\(i)-\(abs(loan.title.hashValue % 100000))"
                try? await center.add(UNNotificationRequest(identifier: id, content: c,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
    }

    static func clear() {
        shared.current = []
        SecureStore.remove(file)
        UserDefaults.standard.removeObject(forKey: lastKey)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            center.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix("lib-") })
        }
    }

    // MARK: portal cədvəli → götürülmüş kitablar

    nonisolated static func parseLoans(_ html: String) -> [Loan]? {
        guard let doc = try? SwiftSoup.parse(html),
              let table = Parsers.first(doc, "div.tab-content table.table.box") ?? Parsers.first(doc, "table.table.box") else { return nil }
        func date(_ s: String) -> String? {
            if let m = s.groups(#"(\d{4})-(\d{2})-(\d{2})"#) { return "\(m[1])-\(m[2])-\(m[3])" }
            if let m = s.groups(#"(\d{1,2})[./-](\d{1,2})[./-](\d{4})"#), let d = Int(m[1]), let mo = Int(m[2]) {
                return String(format: "%@-%02d-%02d", m[3], mo, d)
            }
            return nil
        }
        let trs = Parsers.select(table, "tr")
        let headRow = trs.first { tr in
            !Parsers.select(tr, "th").isEmpty ||
            (tr.children().array().allSatisfy { date(Parsers.txt($0)) == nil } && Parsers.txt(tr).lowercased().contains("tarix"))
        }
        let head = headRow?.children().array().map { Parsers.txt($0).lowercased() } ?? []
        func idx(_ p: (String) -> Bool) -> Int? { head.firstIndex(where: p) }
        let returnedIdx = idx { $0.contains("qaytardı") || $0.contains("qaytarıl") || $0.contains("təhvil") }
        let dueIdx = idx { ($0.contains("qaytarma") || $0.contains("son tarix") || $0.contains("müddət")) && !$0.contains("qaytardı") && !$0.contains("qaytarıl") }
        let titleIdx = idx { $0.contains("kitab") || $0.contains("ad") || $0.contains("material") }
        var out: [Loan] = []
        for tr in trs {
            let td = tr.children().array().filter { $0.tagName() == "td" }.map { Parsers.txt($0) }
            if td.count < 2 { continue }
            let dates = td.enumerated().compactMap { i, v in date(v).map { (i, $0) } }
            if dates.isEmpty { continue }
            let due: String
            if let dueIdx {
                if let r = returnedIdx, r < td.count, date(td[r]) != nil { continue }      // artıq qaytarılıb
                guard dueIdx < td.count, let d = date(td[dueIdx]) else { continue }
                due = d
            } else {
                if dates.count >= 3 { continue }
                due = dates[dates.count - 1].1
            }
            var title = ""
            if let ti = titleIdx, ti < td.count, !td[ti].trimmed.isEmpty, date(td[ti]) == nil { title = td[ti] }
            if title.isEmpty { title = td.filter { date($0) == nil && Int($0) == nil }.max(by: { $0.count < $1.count }) ?? "" }
            out.append(Loan(title: title.isEmpty ? t("Kitab", "Book") : title, due: due))
        }
        return out
    }
}

private struct DueItem: Identifiable {
    var id: String { loan.id }
    let loan: Loan
    let days: Int
}

/// Ana səhifədə: qaytarma vaxtı 3 gün və ya daha az qalmış (və ya keçmiş) kitablar.
struct LibraryDueCard: View {
    @ObservedObject private var store = LibraryDue.shared

    var body: some View {
        let today = Day.startOfToday()
        let soon = store.current.compactMap { l -> DueItem? in
            guard let d = l.dueDate else { return nil }
            let days = Day.cal.dateComponents([.day], from: today, to: Day.cal.startOfDay(for: d)).day ?? 0
            return days <= 3 ? DueItem(loan: l, days: days) : nil
        }.sorted { $0.days < $1.days }
        if !soon.isEmpty {
            NavigationLink { LibraryView() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(soon) { item in
                        let l = item.loan, days = item.days
                        HStack(spacing: 12) {
                            IconBox(icon: "book.closed.fill", color: days < 0 ? C.rose : C.orange, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(Color.primary)
                                Text(days < 0 ? t("\(-days) gün gecikib!", "\(-days) days overdue!")
                                     : days == 0 ? t("bu gün qaytarılmalıdır", "due today")
                                     : days == 1 ? t("sabah qaytarılmalıdır", "due tomorrow")
                                     : t("\(days) gün sonra qaytarılmalıdır", "due in \(days) days"))
                                    .font(.caption).foregroundStyle(days < 0 ? C.rose : .secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 22, tint: C.orange.opacity(0.15))
            }
            .buttonStyle(PressStyle())
        }
    }
}
