import SwiftUI

@main
struct BMUApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(C.indigo)
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
                MainTabs().transition(.opacity)
            } else {
                LoginView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.restoring)
        .animation(.easeInOut(duration: 0.3), value: app.loggedIn)
        .task { await app.restore() }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                LogoBadge(size: 96)
                Text("BMU Mobil").font(.title.weight(.bold))
                ProgressView()
            }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Ana səhifə", systemImage: "house.fill") }
            ScheduleView()
                .tabItem { Label("Cədvəl", systemImage: "calendar") }
            GradesView()
                .tabItem { Label("Qiymətlər", systemImage: "chart.bar.fill") }
            JournalView()
                .tabItem { Label("Jurnal", systemImage: "checklist") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        .modifier(TabBarMinimize())
    }
}
