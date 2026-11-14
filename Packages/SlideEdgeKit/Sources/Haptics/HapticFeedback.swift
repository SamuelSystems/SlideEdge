import AppKit

/// Trackpad haptics (Force Touch trackpads only; a no-op elsewhere).
@MainActor
public final class HapticFeedback {
    /// Fast slides can cross several steps per frame: keep ticks distinguishable.
    private static let minimumInterval: TimeInterval = 0.03

    public var isEnabled = true
    private var lastTick: TimeInterval = 0

    public init() {}

    /// One level step; `atLimit` when the level just reached 0 or 1.
    public func step(atLimit: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard atLimit || now - lastTick >= Self.minimumInterval else { return }
        lastTick = now
        perform(atLimit ? .generic : .levelChange)
    }

    /// A discrete action: mute, media command, corner action.
    public func action() {
        perform(.generic)
    }

    private func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
