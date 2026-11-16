import SwiftUI
import UIKit

/// Dil: AZ / EN. Bütün mətnlər t("azərbaycanca", "english") ilə yazılır.
func t(_ az: String, _ en: String) -> String {
    UserDefaults.standard.string(forKey: "lang") == "en" ? en : az
}

/// Tətbiqin tənzimləmələri (telefonda saxlanır).
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    /// "system" | "light" | "dark"
    @Published var theme: String { didSet { d.set(theme, forKey: "theme"); applyTheme(animated: true) } }
    /// "az" | "en"
    @Published var lang: String { didSet { d.set(lang, forKey: "lang") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    /// Face ID / Touch ID / parol kilidi
    @Published var lock: Bool { didSet { d.set(lock, forKey: "lock") } }
    /// Arxa fondan qayıdanda neçə saniyədən sonra kilidlənsin (0 = dərhal)
    @Published var lockAfter: Int { didSet { d.set(lockAfter, forKey: "lockAfter") } }
    /// Dərsdən əvvəl xatırlatma
    @Published var reminders: Bool { didSet { d.set(reminders, forKey: "reminders") } }
    @Published var remindBefore: Int { didSet { d.set(remindBefore, forKey: "remindBefore") } }
    /// Qiymət və qaib dəyişəndə bildiriş
    @Published var updates: Bool { didSet { d.set(updates, forKey: "updates") } }
    /// Son tətbiqlər siyahısında məzmunu gizlət
    @Published var hideInSwitcher: Bool { didSet { d.set(hideInSwitcher, forKey: "hideInSwitcher") } }
    /// Tətbiqdə göstərilən öz profil şəkli (yalnız bu cihazda)
    @Published var customPhoto: Data? { didSet { d.set(customPhoto, forKey: "customPhoto") } }

    private init() {
        theme = d.string(forKey: "theme") ?? "system"
        lang = d.string(forKey: "lang") ?? "az"
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        lock = d.object(forKey: "lock") as? Bool ?? false
        lockAfter = d.object(forKey: "lockAfter") as? Int ?? 0
        reminders = d.object(forKey: "reminders") as? Bool ?? true
        remindBefore = d.object(forKey: "remindBefore") as? Int ?? 10
        updates = d.object(forKey: "updates") as? Bool ?? true
        customPhoto = d.data(forKey: "customPhoto")
        hideInSwitcher = d.object(forKey: "hideInSwitcher") as? Bool ?? true
    }

    /// Tema bütün pəncərələrə (açılan vərəqlər də daxil) tətbiq olunur.
    func applyTheme(animated: Bool = false) {
        let style: UIUserInterfaceStyle = theme == "light" ? .light : theme == "dark" ? .dark : .unspecified
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows {
                if animated {
                    UIView.transition(with: w, duration: 0.35, options: .transitionCrossDissolve) { w.overrideUserInterfaceStyle = style }
                } else {
                    w.overrideUserInterfaceStyle = style
                }
            }
        }
    }
}

/// Toxunuş titrəməsi (Tənzimləmələrdə söndürülə bilər).
@MainActor
enum Haptic {
    static func tap() {
        guard Prefs.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func soft() {
        guard Prefs.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    static func select() {
        guard Prefs.shared.haptics else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        guard Prefs.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        guard Prefs.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
