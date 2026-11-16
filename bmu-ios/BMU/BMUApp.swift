import SwiftUI
import UserNotifications

@main
struct BMUApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @StateObject private var prefs = Prefs.shared
    @StateObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var phase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        _ = Usage.launchedAt                        // soyuq açılış vaxtının başlanğıcı
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
                    } else if phase != .active && (prefs.lock || prefs.hideInSwitcher) {
                        // tətbiqlər siyahısında məzmun görünməsin
                        ZStack { AppBackground(); LogoBadge(size: 90) }
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: lock.locked)
                .onAppear {
                    prefs.applyTheme()
                    Updates.scheduleRefresh()
                    QuickNav.installShortcuts()
                }
                .onChange(of: prefs.lang) { _, _ in
                    QuickNav.installShortcuts()
                    if app.loggedIn { WidgetData.publish(app.lessons) }
                }
                .onOpenURL { url in
                    if url.scheme == "mybeu" { QuickNav.shared.pending = url.host ?? "schedule" }
                }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .background:
                lock.wentBackground()
                Updates.scheduleRefresh()
                Usage.shared.pause()
                Task.detached { await Cloud.shared.setOnline(false) }
            case .active:
                lock.becameActive()
                Usage.shared.resume()
                if app.offline { Task { await app.goOnline() } }
                if app.loggedIn {
                    Task { await Updates.checkIfDue() }
                    Task.detached { await Cloud.shared.setOnline(true) }
                }
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
        .task {
            // hər dəqiqə: analitika saxlanır və göndərilir
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                Usage.shared.heartbeat()
            }
        }
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
    @ObservedObject private var nav = QuickNav.shared
    @AppStorage("intro_seen") private var introSeen = false
    @State private var showIntro = false

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
        .onChange(of: app.tab) { _, tab in
            Haptic.select()
            Usage.shared.screen(MainTabs.names[tab] ?? "home")
        }
        .onAppear {
            Usage.shared.homeReady()
            Usage.shared.screen(MainTabs.names[app.tab] ?? "home")
            nav.perform(app)
            if !introSeen { showIntro = true }
        }
        .onChange(of: nav.pending) { _, p in if p != nil { nav.perform(app) } }
        .fullScreenCover(isPresented: $showIntro) {
            IntroView { introSeen = true; showIntro = false }
        }
    }

    static let names = [0: "home", 1: "schedule", 2: "education", 3: "services", 4: "profile"]
}
