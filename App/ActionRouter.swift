import Combine
import AppSettings
import CornerActions
import CursorControl
import CoreGraphics
import GestureEngine
import Haptics
import HUD
import SystemControls

/// Which system controls are usable right now, for the menu and for enabling edges.
@MainActor
final class ControlStatus: ObservableObject {
    @Published private(set) var brightness = BrightnessController.Status.checking
    @Published private(set) var keyboardBacklight = false
    var onChange: (() -> Void)?

    func update(brightness: BrightnessController.Status) {
        guard brightness != self.brightness else { return }
        self.brightness = brightness
        onChange?()
    }

    func update(keyboardBacklight: Bool) {
        guard keyboardBacklight != self.keyboardBacklight else { return }
        self.keyboardBacklight = keyboardBacklight
        onChange?()
    }
}

/// Current levels shown in the menu bar panel.
@MainActor
final class LiveLevels: ObservableObject {
    @Published var volume: Double?
    @Published var muted = false
    @Published var brightness: Double?
}

/// Maps recognized gestures to system actions.
@MainActor
final class ActionRouter {
    enum Control {
        case volume, brightness, keyboardBacklight, none
    }

    /// State captured when a slide begins, so the system is not queried on every step.
    private struct SlideSession {
        var control: Control
        var level: Double
        var muted = false
        /// False when the level cannot be set directly (volume fallback: media keys).
        var canSet = true
        /// Media-key fallback: travel not yet sent as a key press.
        var keyRemainder = 0.0
    }

    private let settings: AppSettings
    private let volume = VolumeController()
    private let brightness: BrightnessController
    private let keyboardBacklight = KeyboardBacklightController()
    private let hud = HUDController()
    /// Thread-safe: `enforce()` is called on every touch frame.
    nonisolated let cursor = CursorLock()
    let haptics = HapticFeedback()
    private var sessions: [Edge: SlideSession] = [:]
    private let levels: LiveLevels

    init(settings: AppSettings, status: ControlStatus, levels: LiveLevels) {
        self.settings = settings
        self.levels = levels
        brightness = BrightnessController { newStatus in
            Task { @MainActor in status.update(brightness: newStatus) }
        }
        status.update(keyboardBacklight: keyboardBacklight.isAvailable)
    }

    #if DEBUG
    func showTestHUD(level: Double) {
        hud.show(.volume, level: level)
    }
    #endif

    /// Reads the current levels from the system (the panel calls this when it opens).
    func refreshLevels() {
        let state = volume.state()
        levels.volume = state.volume
        levels.muted = state.muted
        levels.brightness = brightness.level()
    }

    func control(for edge: Edge) -> Control {
        switch edge {
        case .left: settings.swapSides ? .volume : .brightness
        case .right: settings.swapSides ? .brightness : .volume
        case .top: .keyboardBacklight
        case .bottom: .none
        }
    }

    /// `pointer` is the pointer position on the frame that produced the event.
    func handle(_ event: GestureEvent, pointer: CGPoint? = nil) {
        // Always process the ends, even after SlideEdge was turned off mid-gesture: they release the cursor.
        switch event {
        case .slideEnded(let edge):
            sessions[edge] = nil
            if sessions.isEmpty { cursor.unlock() }
            return
        case .contactCancelled:
            if sessions.isEmpty { cursor.unlock() }
            return
        default:
            break
        }
        guard settings.enabled else { return }

        switch event {
        case .contactBegan:
            // Freeze before the slide is recognized, so its first millimetres do not move the pointer.
            // Hide only once it is a slide: a click near the edge must not make the pointer vanish.
            if settings.lockCursor { cursor.lock(at: pointer, hidingCursor: false) }
        case .slideBegan(let edge):
            beginSlide(on: edge, pointer: pointer)
        case .slideChanged(let edge, let delta):
            changeSlide(on: edge, by: delta)
        case .doubleTap(.topRight):
            if settings.quickMute {
                toggleMute()
                haptics.action()
            }
        case .doubleTap(.topLeft):
            CornerActionPerformer.perform(settings.cornerAction)
            haptics.action()
        case .edgeDoubleTap(.bottom):
            guard settings.mediaStrip, settings.mediaTapPlayPause else { return }
            MediaKeys.post(.play)
            haptics.action()
            hud.show(.message(symbol: "playpause.fill", text: "Play/Pausa"))
        case .swipe(.bottom, let direction):
            guard settings.mediaStrip else { return }
            // Default: swipe right for the next track.
            let next = (direction == .right) != settings.reverseSwipe
            MediaKeys.post(next ? .next : .previous)
            haptics.action()
            hud.show(.message(symbol: next ? "forward.fill" : "backward.fill", text: next ? "Traccia successiva" : "Traccia precedente"))
        case .slideEnded, .contactCancelled, .edgeDoubleTap, .swipe:
            break
        }
    }

    private func beginSlide(on edge: Edge, pointer: CGPoint?) {
        let control = control(for: edge)
        switch control {
        case .volume:
            let state = volume.state()
            sessions[edge] = SlideSession(control: control, level: state.volume, muted: state.muted, canSet: state.canSetVolume)
        case .brightness:
            guard let level = brightness.level() else { return }
            sessions[edge] = SlideSession(control: control, level: level)
        case .keyboardBacklight:
            guard let level = keyboardBacklight.level() else { return }
            sessions[edge] = SlideSession(control: control, level: level)
        case .none:
            return
        }
        if settings.lockCursor {
            cursor.lock(at: pointer, hidingCursor: false)
            if settings.hideCursor { cursor.hide() }
        }
    }

    private func changeSlide(on edge: Edge, by delta: Double) {
        guard var session = sessions[edge] else { return }
        defer { sessions[edge] = session }

        guard session.canSet else {
            // No software volume on this device: one volume key per whole step; the system shows its own HUD.
            session.keyRemainder += delta
            while abs(session.keyRemainder) >= GestureConfig.coarseStep {
                let up = session.keyRemainder > 0
                MediaKeys.post(up ? .soundUp : .soundDown)
                haptics.step(atLimit: false)
                session.keyRemainder -= up ? GestureConfig.coarseStep : -GestureConfig.coarseStep
            }
            return
        }

        let previous = session.level
        session.level = LevelMath.apply(delta, to: session.level)
        // At a limit the level does not change, but the HUD still shows it, like the system keys.
        let changed = session.level != previous
        if changed {
            haptics.step(atLimit: session.level == 0 || session.level == 1)
        }
        switch session.control {
        case .volume:
            // Like the volume keys: raising the volume unmutes, even when it is already at the maximum.
            if session.muted && delta > 0 {
                volume.setMuted(false)
                session.muted = false
            }
            if changed { volume.setVolume(session.level) }
            hud.show(.volume, level: session.level, muted: session.muted)
            levels.volume = session.level
            levels.muted = session.muted
        case .brightness:
            if changed { brightness.setLevel(session.level) }
            hud.show(.brightness, level: session.level)
            levels.brightness = session.level
        case .keyboardBacklight:
            if changed { keyboardBacklight.setLevel(session.level) }
            hud.show(.keyboardBacklight, level: session.level)
        case .none:
            break
        }
    }

    private func toggleMute() {
        let state = volume.state()
        guard state.canMute else {
            MediaKeys.post(.mute)
            return
        }
        volume.setMuted(!state.muted)
        hud.show(.volume, level: state.volume, muted: !state.muted)
        levels.muted = !state.muted
    }
}
