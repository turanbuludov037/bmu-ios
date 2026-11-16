import Foundation
import WidgetKit

/// Vidcet üçün: növbəti 8 günün dərsləri (otaq məlumatı ilə) ortaq yaddaşa yazılır.
@MainActor
enum WidgetData {
    static func publish(_ lessons: [String: [Lesson]]) {
        guard WidgetShared.defaults != nil else { return }
        let store = TimetableStore.shared
        var out: [WidgetLesson] = []
        for i in 0..<8 {
            let d = Day.add(i, to: Day.startOfToday())
            for l in (lessons[Day.key(d)] ?? []).sorted(by: { Day.minutes($0.start) < Day.minutes($1.start) }) {
                out.append(WidgetLesson(day: Day.key(d), start: l.start, end: l.end, title: l.title, type: l.type,
                                        room: store.room(for: d, lesson: l)?.short ?? ""))
            }
        }
        WidgetShared.write(out, lang: UserDefaults.standard.string(forKey: "lang") ?? "az")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetShared.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
