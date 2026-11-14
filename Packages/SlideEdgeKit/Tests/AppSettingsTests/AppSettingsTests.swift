import Foundation
import GestureEngine
import Testing
@testable import AppSettings

@MainActor
struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsMatchSpec() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.enabled)
        #expect(settings.edgeWidth == 0.05)
        #expect(settings.sensitivity == 1.0)
        #expect(settings.leftActiveArea == .full)
        #expect(settings.palmRejection)
        #expect(!settings.swapSides)
        #expect(settings.hudStyle == .custom)
        #expect(!settings.magicMouse)
    }

    @Test func valuesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = AppSettings(defaults: defaults)
        first.edgeWidth = 0.08
        first.swapSides = true
        first.rightActiveArea = .topHalf
        first.cornerAction = .lockScreen

        let second = AppSettings(defaults: defaults)
        #expect(second.edgeWidth == 0.08)
        #expect(second.swapSides)
        #expect(second.rightActiveArea == .topHalf)
        #expect(second.cornerAction == .lockScreen)
    }

    @Test func resetRestoresDefaults() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.sensitivity = 2.5
        settings.preciseSliding = true
        settings.resetToDefaults()
        #expect(settings.sensitivity == AppSettings.Defaults.sensitivity)
        #expect(settings.preciseSliding == AppSettings.Defaults.preciseSliding)
    }
}
