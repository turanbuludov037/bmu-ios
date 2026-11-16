import SwiftUI
import UserNotifications

@main
struct BMUApp: App {
    @StateObject private var app = AppState()
    @StateObject private var prefs = Prefs.shared
    @StateObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var phase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(prefs)
                .tint(C.indigo)
                .id(prefs.lang)                       // dil dəyişəndə bütün mətnlər yenilənsin
                .overlay {
                    if lock.locked && app.loggedIn {
                        LockView().transition(.opacity.combined(with: .scale(scale: 1.05)))
                    } else if phase != .active && prefs.lock {
                        // tətbiqlər siyahısında məzmun görünməsin
                        ZStack { AppBackground(); LogoBadge(size: 90) }
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: lock.locked)
                .onAppear {
                    prefs.applyTheme()
                    Updates.scheduleRefresh()
                }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .background:
                lock.wentBackground()
                Updates.scheduleRefresh()
            case .active:
                lock.becameActive()
                if app.loggedIn { Task { await Updates.checkIfDue() } }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(Notifier.refreshID)) {
            await Updates.runBackground()
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            if app.restoring {
                SplashView().transition(.opacity)
            } else if app.loggedIn {
                MainTabs().transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                LoginView().transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: app.restoring)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: app.loggedIn)
        .task { await app.restore() }
    }
}

struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                LogoBadge(size: 96)
                    .scaleEffect(pulse ? 1.06 : 0.96)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text("myBEU").font(.largeTitle.weight(.bold))
                ProgressView()
            }
        }
        .onAppear { pulse = true }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.tab) {
            HomeView()
                .tabItem { Label(t("Ana səhifə", "Home"), systemImage: "house.fill") }
                .tag(0)
            ScheduleView()
                .tabItem { Label(t("Cədvəl", "Schedule"), systemImage: "calendar") }
                .tag(1)
            EducationView()
                .tabItem { Label(t("Təhsil", "Study"), systemImage: "graduationcap.fill") }
                .tag(2)
            ServicesView()
                .tabItem { Label(t("Xidmətlər", "Services"), systemImage: "square.grid.2x2.fill") }
                .tag(3)
            ProfileView()
                .tabItem { Label(t("Profil", "Profile"), systemImage: "person.crop.circle") }
                .tag(4)
        }
        .modifier(TabBarMinimize())
        .onChange(of: app.tab) { _, _ in Haptic.select() }
    }
}
