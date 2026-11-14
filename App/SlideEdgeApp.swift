import SwiftUI

@main
struct SlideEdgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            let coordinator = appDelegate.coordinator
            PanelView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
                .environmentObject(coordinator.permissions)
                .environmentObject(coordinator.touchMonitor)
                .environmentObject(coordinator.controlStatus)
                .environmentObject(coordinator.liveLevels)
                .environmentObject(coordinator.loginItem)
        } label: {
            Image("MenuBarGlyph")
                .accessibilityLabel("SlideEdge")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }
}
