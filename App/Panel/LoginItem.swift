import ServiceManagement
import os

/// "Open at login", backed by the system login items (SMAppService).
@MainActor
final class LoginItem: ObservableObject {
    private static let log = Logger(subsystem: "io.github.samuelsystems.slideedge", category: "login")

    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.log.error("login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
