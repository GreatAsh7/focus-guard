import SwiftUI

@main
struct FocusGuardApp: App {
    @StateObject private var engine = Engine.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .task { engine.requestNotifications() }
                .onChange(of: phase) { _, newPhase in
                    if newPhase == .active {
                        Task { await engine.appBecameActive() }
                    }
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "chart.bar.fill") }
            ModesView()
                .tabItem { Label("Modes", systemImage: "scope") }
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            SetupView()
                .tabItem { Label("Setup", systemImage: "wrench.and.screwdriver") }
        }
    }
}
