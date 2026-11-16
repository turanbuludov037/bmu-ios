import Foundation

/// Tətbiq ilə ana ekran vidceti arasında ortaq məlumat (App Group).
/// Tətbiq cədvəli yükləyəndə növbəti 8 günün dərslərini bura yazır, vidcet buradan oxuyur.
struct WidgetLesson: Codable, Hashable {
    let day: String          // "yyyy-MM-dd"
    let start: String        // "09:00"
    let end: String
    let title: String
    let type: String         // "Nəzəri" | "Məşğələ" | "Laboratoriya"
    let room: String         // "244 · Əsas korpus" və ya boş
}

enum WidgetShared {
    static let group = "group.com.nexora.beueduaz"
    static let lessonsKey = "widget_lessons"
    static let langKey = "widget_lang"
    static let updatedKey = "widget_updated"

    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    static func read() -> [WidgetLesson] {
        guard let d = defaults?.data(forKey: lessonsKey) else { return [] }
        return (try? JSONDecoder().decode([WidgetLesson].self, from: d)) ?? []
    }

    static func write(_ lessons: [WidgetLesson], lang: String) {
        guard let ud = defaults else { return }
        if let d = try? JSONEncoder().encode(lessons) { ud.set(d, forKey: lessonsKey) }
        ud.set(lang, forKey: langKey)
        ud.set(Date().timeIntervalSince1970, forKey: updatedKey)
    }

    static func clear() {
        defaults?.removeObject(forKey: lessonsKey)
        defaults?.removeObject(forKey: updatedKey)
    }

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func minutes(_ s: String) -> Int {
        let p = s.split(separator: ":")
        return (Int(p.first ?? "") ?? 0) * 60 + (p.count > 1 ? Int(p[1]) ?? 0 : 0)
    }
}
