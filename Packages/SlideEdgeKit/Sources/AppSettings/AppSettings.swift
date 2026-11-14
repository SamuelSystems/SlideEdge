import GestureEngine
import SwiftUI

extension ActiveArea {
    public var title: String {
        switch self {
        case .full: "Tutto il bordo"
        case .bottomThreeQuarters: "¾ inferiori"
        case .bottomHalf: "½ inferiore"
        case .bottomQuarter: "¼ inferiore"
        case .topThreeQuarters: "¾ superiori"
        case .topHalf: "½ superiore"
        case .topQuarter: "¼ superiore"
        }
    }
}

/// Action bound to a double tap in the top-left corner.
public enum CornerAction: String, CaseIterable, Identifiable, Sendable {
    case none, missionControl, showDesktop, launchpad, screenshot, lockScreen

    public var id: String { rawValue }

    private static let launchpadPath = "/System/Applications/Launchpad.app"

    /// Launchpad, or the "Apps" launcher that replaced it in newer macOS.
    public static var launcherAppPath: String {
        FileManager.default.fileExists(atPath: launchpadPath) ? launchpadPath : "/System/Applications/Apps.app"
    }

    public var title: String {
        switch self {
        case .none: "Nessuna"
        case .missionControl: "Mission Control"
        case .showDesktop: "Mostra scrivania"
        case .launchpad: FileManager.default.fileExists(atPath: Self.launchpadPath) ? "Launchpad" : "App"
        case .screenshot: "Istantanea schermo"
        case .lockScreen: "Blocca schermo"
        }
    }
}

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Chiaro"
        case .dark: "Scuro"
        }
    }

    /// nil follows the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum HUDStyle: String, CaseIterable, Identifiable, Sendable {
    case custom, system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .custom: "SlideEdge"
        case .system: "Sistema (sperimentale)"
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
@MainActor
public final class AppSettings: ObservableObject {
    public enum Defaults {
        public static let enabled = true
        public static let edgeWidth = 0.05
        public static let sensitivity = 1.0
        public static let preciseSliding = false
        public static let requireModifier = false
        public static let swapSides = false
        public static let leftActiveArea = ActiveArea.full
        public static let rightActiveArea = ActiveArea.full
        public static let palmRejection = true
        public static let keyboardBacklightEdge = true
        public static let mediaStrip = true
        public static let reverseSwipe = false
        public static let mediaTapPlayPause = true
        public static let quickMute = true
        public static let cornerAction = CornerAction.missionControl
        public static let haptics = true
        public static let lockCursor = true
        public static let hideCursor = true
        public static let magicMouse = false
        public static let hudStyle = HUDStyle.custom
        public static let appearance = AppearanceMode.system
    }

    @AppStorage public var enabled: Bool
    /// Edge zone width as a fraction of the trackpad surface.
    @AppStorage public var edgeWidth: Double
    /// Multiplier applied to finger travel before mapping to a level change.
    @AppStorage public var sensitivity: Double
    @AppStorage public var preciseSliding: Bool
    @AppStorage public var requireModifier: Bool
    @AppStorage public var swapSides: Bool
    @AppStorage public var leftActiveArea: ActiveArea
    @AppStorage public var rightActiveArea: ActiveArea
    @AppStorage public var palmRejection: Bool
    @AppStorage public var keyboardBacklightEdge: Bool
    @AppStorage public var mediaStrip: Bool
    @AppStorage public var reverseSwipe: Bool
    /// Double tap on the media strip toggles play/pause.
    @AppStorage public var mediaTapPlayPause: Bool
    @AppStorage public var quickMute: Bool
    @AppStorage public var cornerAction: CornerAction
    @AppStorage public var haptics: Bool
    @AppStorage public var lockCursor: Bool
    /// Hide the pointer while it is locked.
    @AppStorage public var hideCursor: Bool
    /// Also read touches from a Magic Mouse.
    @AppStorage public var magicMouse: Bool
    @AppStorage public var hudStyle: HUDStyle
    @AppStorage public var appearance: AppearanceMode

    public init(defaults: UserDefaults = .standard) {
        _enabled = AppStorage(wrappedValue: Defaults.enabled, "enabled", store: defaults)
        _edgeWidth = AppStorage(wrappedValue: Defaults.edgeWidth, "edgeWidth", store: defaults)
        _sensitivity = AppStorage(wrappedValue: Defaults.sensitivity, "sensitivity", store: defaults)
        _preciseSliding = AppStorage(wrappedValue: Defaults.preciseSliding, "preciseSliding", store: defaults)
        _requireModifier = AppStorage(wrappedValue: Defaults.requireModifier, "requireModifier", store: defaults)
        _swapSides = AppStorage(wrappedValue: Defaults.swapSides, "swapSides", store: defaults)
        _leftActiveArea = AppStorage(wrappedValue: Defaults.leftActiveArea, "leftActiveArea", store: defaults)
        _rightActiveArea = AppStorage(wrappedValue: Defaults.rightActiveArea, "rightActiveArea", store: defaults)
        _palmRejection = AppStorage(wrappedValue: Defaults.palmRejection, "palmRejection", store: defaults)
        _keyboardBacklightEdge = AppStorage(wrappedValue: Defaults.keyboardBacklightEdge, "keyboardBacklightEdge", store: defaults)
        _mediaStrip = AppStorage(wrappedValue: Defaults.mediaStrip, "mediaStrip", store: defaults)
        _reverseSwipe = AppStorage(wrappedValue: Defaults.reverseSwipe, "reverseSwipe", store: defaults)
        _mediaTapPlayPause = AppStorage(wrappedValue: Defaults.mediaTapPlayPause, "mediaTapPlayPause", store: defaults)
        _quickMute = AppStorage(wrappedValue: Defaults.quickMute, "quickMute", store: defaults)
        _cornerAction = AppStorage(wrappedValue: Defaults.cornerAction, "cornerAction", store: defaults)
        _haptics = AppStorage(wrappedValue: Defaults.haptics, "haptics", store: defaults)
        _lockCursor = AppStorage(wrappedValue: Defaults.lockCursor, "lockCursor", store: defaults)
        _hideCursor = AppStorage(wrappedValue: Defaults.hideCursor, "hideCursor", store: defaults)
        _magicMouse = AppStorage(wrappedValue: Defaults.magicMouse, "magicMouse", store: defaults)
        _hudStyle = AppStorage(wrappedValue: Defaults.hudStyle, "hudStyle", store: defaults)
        _appearance = AppStorage(wrappedValue: Defaults.appearance, "appearance", store: defaults)
    }

    public func resetToDefaults() {
        enabled = Defaults.enabled
        edgeWidth = Defaults.edgeWidth
        sensitivity = Defaults.sensitivity
        preciseSliding = Defaults.preciseSliding
        requireModifier = Defaults.requireModifier
        swapSides = Defaults.swapSides
        leftActiveArea = Defaults.leftActiveArea
        rightActiveArea = Defaults.rightActiveArea
        palmRejection = Defaults.palmRejection
        keyboardBacklightEdge = Defaults.keyboardBacklightEdge
        mediaStrip = Defaults.mediaStrip
        reverseSwipe = Defaults.reverseSwipe
        mediaTapPlayPause = Defaults.mediaTapPlayPause
        quickMute = Defaults.quickMute
        cornerAction = Defaults.cornerAction
        haptics = Defaults.haptics
        lockCursor = Defaults.lockCursor
        hideCursor = Defaults.hideCursor
        magicMouse = Defaults.magicMouse
        hudStyle = Defaults.hudStyle
        appearance = Defaults.appearance
    }
}
