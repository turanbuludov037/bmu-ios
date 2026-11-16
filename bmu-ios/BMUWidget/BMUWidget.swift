import WidgetKit
import SwiftUI

/// Ana ekran vidceti: bugünkü (bitməmiş) dərslər; bu gün dərs qalmayıbsa növbəti dərs günü.
/// Məlumatı tətbiq yazır (cədvəl yüklənəndə), vidcet hər 30 dəqiqədən bir yenilənir.

private func tw(_ az: String, _ en: String) -> String {
    WidgetShared.defaults?.string(forKey: WidgetShared.langKey) == "en" ? en : az
}

struct DayEntry: TimelineEntry {
    let date: Date
    let title: String            // "Bu gün" / "Sabah" / "Çərşənbə, 18 noyabr"
    let lessons: [WidgetLesson]
    let empty: Bool              // tətbiqdən heç məlumat yoxdur
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: Date(), title: tw("Bu gün", "Today"), lessons: [
            WidgetLesson(day: "", start: "09:00", end: "10:20", title: "Riyazi analiz", type: "Nəzəri", room: "244 · Əsas korpus"),
            WidgetLesson(day: "", start: "10:30", end: "11:50", title: "Proqramlaşdırma", type: "Laboratoriya", room: "")
        ], empty: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()
        var entries: [DayEntry] = []
        // növbəti 12 saat üçün hər 30 dəqiqədən bir (bitən dərs siyahıdan düşsün)
        for i in 0..<24 {
            let at = now.addingTimeInterval(Double(i) * 30 * 60)
            entries.append(entry(at: at))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func entry(at now: Date) -> DayEntry {
        let all = WidgetShared.read()
        if all.isEmpty { return DayEntry(date: now, title: tw("Dərs cədvəli", "Schedule"), lessons: [], empty: true) }
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let todayKey = WidgetShared.dayKey(now)
        let today = all.filter { $0.day == todayKey && WidgetShared.minutes($0.end) > nowMin }
        if !today.isEmpty { return DayEntry(date: now, title: tw("Bu gün", "Today"), lessons: today, empty: false) }
        // növbəti dərs günü
        for i in 1...7 {
            guard let d = cal.date(byAdding: .day, value: i, to: now) else { continue }
            let k = WidgetShared.dayKey(d)
            let list = all.filter { $0.day == k }
            if !list.isEmpty {
                return DayEntry(date: now, title: i == 1 ? tw("Sabah", "Tomorrow") : dayTitle(d), lessons: list, empty: false)
            }
        }
        return DayEntry(date: now, title: tw("Bu gün", "Today"), lessons: [], empty: false)
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let wd = (cal.component(.weekday, from: d) + 5) % 7
        let az = ["Bazar ertəsi", "Çərşənbə axşamı", "Çərşənbə", "Cümə axşamı", "Cümə", "Şənbə", "Bazar"]
        let en = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return tw(az[wd], en[wd]) + ", \(cal.component(.day, from: d))"
    }
}

private let indigo = Color(red: 0x45 / 255, green: 0x58 / 255, blue: 0xB8 / 255)
private let lime = Color(red: 0xD6 / 255, green: 0xF5 / 255, blue: 0x7A / 255)
private let navy = Color(red: 0x1B / 255, green: 0x28 / 255, blue: 0x50 / 255)

private func color(_ type: String) -> Color {
    switch type {
    case "Laboratoriya": return .orange
    case "Məşğələ": return .green
    default: return indigo
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            default: card
            }
        }
        .widgetURL(URL(string: "mybeu://schedule"))
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 7
        default: return 1
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.title).font(.caption.weight(.bold)).foregroundStyle(lime)
                Spacer()
                Text("myBEU").font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
            }
            if entry.empty {
                Spacer()
                Text(tw("Cədvəli görmək üçün tətbiqi aç", "Open the app to load your schedule"))
                    .font(.footnote).foregroundStyle(.white)
                Spacer()
            } else if entry.lessons.isEmpty {
                Spacer()
                Text(tw("Yaxın günlərdə dərs yoxdur 🎉", "No classes coming up 🎉")).font(.footnote).foregroundStyle(.white)
                Spacer()
            } else {
                ForEach(entry.lessons.prefix(maxRows), id: \.self) { l in
                    HStack(alignment: .top, spacing: 6) {
                        Capsule().fill(color(l.type)).frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.title).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(([l.start + "–" + l.end] + (l.room.isEmpty || family == .systemSmall ? [] : [l.room])).joined(separator: " · "))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if entry.lessons.count > maxRows {
                    Text(tw("+\(entry.lessons.count - maxRows) dərs", "+\(entry.lessons.count - maxRows) more"))
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [navy, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let l = entry.lessons.first {
                Text("\(l.start) · " + entry.title).font(.caption2.weight(.bold))
                Text(l.title).font(.caption.weight(.semibold)).lineLimit(1)
                if !l.room.isEmpty { Text(l.room).font(.caption2).lineLimit(1) }
            } else {
                Text("myBEU").font(.caption2.weight(.bold))
                Text(entry.empty ? tw("Tətbiqi aç", "Open the app") : tw("Dərs yoxdur", "No classes")).font(.caption)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayLessons", provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName(tw("Bugünkü dərslər", "Today's classes"))
        .description(tw("Bu günün qalan dərsləri, otaqları ilə", "Today's remaining classes with rooms"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

@main
struct BMUWidgetBundle: WidgetBundle {
    var body: some Widget { TodayWidget() }
}
