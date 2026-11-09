import SwiftUI
import UIKit

@main
struct WakeGuardApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var store = WakeStore.shared
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .tint(Color.accentColor)
                .task { await store.refresh() }
                .task { await store.observe() }
                .task { await store.observeAccess() }
                .onChange(of: phase) { _, phase in
                    if phase == .active { Task { await store.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await store.refresh() }
                }
        }
    }
}

