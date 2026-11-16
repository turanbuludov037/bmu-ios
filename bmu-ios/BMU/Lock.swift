import SwiftUI
import LocalAuthentication

/// Face ID / Touch ID / iPhone parolu ilə tətbiq kilidi.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()
    @Published var locked = false
    @Published var authenticating = false
    private var backgroundAt: Date?

    /// Kilid açıqdırsa tətbiq kilidli başlayır.
    private init() { locked = Prefs.shared.lock }

    /// Bu cihazda biometriya varsa onun adı (Face ID / Touch ID), yoxsa "parol".
    static var biometryName: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return t("iPhone parolu", "iPhone passcode")
        }
    }

    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    func wentBackground() { backgroundAt = Date() }

    func becameActive() {
        guard Prefs.shared.lock else { locked = false; return }
        if let at = backgroundAt, Date().timeIntervalSince(at) >= Double(Prefs.shared.lockAfter) { locked = true }
        backgroundAt = nil
        if locked { Task { await unlock() } }
    }

    func unlock() async {
        guard locked, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let ctx = LAContext()
        ctx.localizedCancelTitle = t("Ləğv et", "Cancel")
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: t("myBEU-nu açmaq üçün", "To open myBEU"))
            if ok {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { locked = false }
                Haptic.success()
            }
        } catch {
            Haptic.error()
        }
    }

    /// Kilidi yandırmazdan əvvəl bir dəfə yoxla (Face ID işləyirmi).
    func confirmEnable() async -> Bool {
        let ctx = LAContext()
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: t("Tətbiq kilidini yandırmaq üçün", "To turn on the app lock"))) ?? false
    }
}

struct LockView: View {
    @ObservedObject var lock = AppLock.shared
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppBackground()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 22) {
                LogoBadge(size: 96)
                    .scaleEffect(pulse ? 1.04 : 1)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
                Text("myBEU").font(.largeTitle.weight(.bold))
                Text(t("Tətbiq kilidlidir", "The app is locked")).foregroundStyle(.secondary)
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label(t("\(AppLock.biometryName) ilə aç", "Unlock with \(AppLock.biometryName)"),
                          systemImage: AppLock.biometryName == "Touch ID" ? "touchid" : "faceid")
                        .font(.headline)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .glassButton(prominent: true)
                .tint(C.btn)
                .disabled(lock.authenticating)
            }
            .padding(30)
        }
        .onAppear { pulse = true }
    }
}
