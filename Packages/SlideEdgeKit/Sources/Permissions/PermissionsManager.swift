import AppKit
import ApplicationServices

public enum Permission: String, CaseIterable, Identifiable, Sendable {
    /// Needed to post media/brightness keys and to lock the cursor.
    case accessibility
    /// Needed by the listen-only key tap used for palm rejection.
    case inputMonitoring

    public var id: String { rawValue }

    var settingsURL: URL {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }
}

/// Tracks TCC permissions and polls until they are granted.
@MainActor
public final class PermissionsManager: ObservableObject {
    @Published public private(set) var accessibility = false
    @Published public private(set) var inputMonitoring = false

    private var timer: Timer?

    public var allGranted: Bool { accessibility && inputMonitoring }

    public init() {
        refresh()
    }

    public func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }

    public func refresh() {
        let ax = AXIsProcessTrusted()
        let listen = CGPreflightListenEventAccess()
        if ax != accessibility { accessibility = ax }
        if listen != inputMonitoring { inputMonitoring = listen }
        if allGranted { stopPolling() }
    }

    /// Registers the app in the privacy list (system prompt) and opens the matching Settings pane.
    public func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            // String literal instead of kAXTrustedCheckOptionPrompt: that global is not concurrency-safe.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        }
        NSWorkspace.shared.open(permission.settingsURL)
        startPolling()
    }

    public func startPolling(interval: TimeInterval = 1) {
        guard timer == nil, !allGranted else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
