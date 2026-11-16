import SwiftUI
import UIKit

/// Tətbiq ikonuna uzun basanda çıxan qısayollar (Cədvəl, Qiymətlər, Davamiyyət, Kitabxana) və vidcetdən açılış.
enum QuickRoute: String, Hashable {
    case grades, journal, library, transcript, timetablePhoto
}

@MainActor
final class QuickNav: ObservableObject {
    static let shared = QuickNav()
    /// Gözləyən keçid: "schedule" | "grades" | "journal" | "library"
    @Published var pending: String?
    @Published var eduPath: [QuickRoute] = []
    @Published var servicesPath: [QuickRoute] = []
    @Published var schedulePath: [QuickRoute] = []

    /// Qısayollar tətbiqin dilində (dil dəyişəndə yenilənir).
    static func installShortcuts() {
        func item(_ type: String, _ az: String, _ en: String, _ symbol: String) -> UIApplicationShortcutItem {
            UIApplicationShortcutItem(type: type, localizedTitle: t(az, en), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: symbol), userInfo: nil)
        }
        UIApplication.shared.shortcutItems = [
            item("schedule", "Cədvəl", "Schedule", "calendar"),
            item("grades", "Qiymətlər", "Grades", "chart.bar.fill"),
            item("journal", "Davamiyyət", "Attendance", "checklist"),
            item("library", "Kitabxana", "Library", "books.vertical.fill")
        ]
    }

    /// Gözləyən keçidi yerinə yetir (giriş tamamlanandan sonra).
    func perform(_ app: AppState) {
        guard let p = pending else { return }
        pending = nil
        switch p {
        case "schedule":
            app.tab = 1
        case "grades":
            app.tab = 2; eduPath = [.grades]
        case "journal":
            app.tab = 2; eduPath = [.journal]
        case "library":
            app.tab = 3; servicesPath = [.library]
        default:
            break
        }
    }
}

/// Qısayol ekranları.
struct QuickDestination: View {
    let route: QuickRoute

    var body: some View {
        switch route {
        case .grades: GradesView()
        case .journal: JournalView()
        case .library: LibraryView()
        case .transcript: TranscriptView()
        case .timetablePhoto: TimetablePhotoView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            let type = item.type
            Task { @MainActor in QuickNav.shared.pending = type }
        }
        let c = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        Task { @MainActor in QuickNav.shared.pending = type }
        completionHandler(true)
    }
}
