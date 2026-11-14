import AppKit
import Combine
import SwiftUI
import AppSettings
import GestureEngine
import KeyActivity
import Permissions
import TouchInput

/// Owns the long-lived services and the app's auxiliary windows.
@MainActor
final class AppCoordinator: ObservableObject {
    let settings = AppSettings()
    let permissions = PermissionsManager()
    let touchMonitor = TouchMonitor()
    let gestureLog = GestureLog()
    let controlStatus = ControlStatus()
    let liveLevels = LiveLevels()
    let loginItem = LoginItem()
    private let router: ActionRouter
    private let keyActivity = KeyActivityMonitor()
    private let gestures: GesturePipeline
    private let touchInput: TouchInputManager

    private var onboardingWindow: NSWindow?
    private var touchDebugWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var settingsSubscription: AnyCancellable?
    private var permissionsSubscription: AnyCancellable?
    /// Last (enabled, magicMouse) pair applied to the touch input.
    private var appliedInput: (Bool, Bool)?

    init() {
        let monitor = touchMonitor
        let relay = monitor.relay
        let log = gestureLog
        let router = ActionRouter(settings: settings, status: controlStatus, levels: liveLevels)
        self.router = router
        let cursor = router.cursor
        let gestures = GesturePipeline(keyActivity: keyActivity) { events, pointer in
            // One task per frame keeps the events in order.
            Task { @MainActor in
                for event in events {
                    router.handle(event, pointer: pointer)
                    log.record(event)
                }
            }
        }
        self.gestures = gestures
        touchInput = TouchInputManager(
            onFrame: { frame in
                cursor.enforce()
                gestures.process(frame)
                if relay.push(frame) {
                    Task { @MainActor in monitor.flush() }
                }
            },
            onDevicesChanged: { devices, status in
                gestures.update(devices: devices)
                Task { @MainActor in monitor.update(devices: devices, status: status) }
            }
        )
    }

    func start() {
        controlStatus.onChange = { [weak self] in self?.applySettings() }
        applySettings()
        // objectWillChange fires before the new value is stored: read it on the next turn.
        settingsSubscription = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }
        // Input Monitoring may be granted later: start the key monitor as soon as it is.
        permissionsSubscription = permissions.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [touchInput] _ in
            touchInput.restart(after: 1)
        })

        if !permissions.allGranted {
            showOnboarding()
        }
        #if DEBUG
        showPanelPreviewIfRequested()
        if ProcessInfo.processInfo.arguments.contains("-testHUD") {
            // Shows the HUD every 0.5 s for 10 s, to check it over full-screen apps.
            for step in 0..<20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.5) { [router] in
                    router.showTestHUD(level: Double(step % 16) / 16)
                }
            }
        }
        #endif
    }

    #if DEBUG
    private var previewWindow: NSWindow?

    /// `-previewPanel main|settings`: shows the menu bar panel in a window, for screenshots.
    private func showPanelPreviewIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-previewPanel"), index + 1 < arguments.count else { return }
        let view = PanelView(initialPage: arguments[index + 1] == "settings" ? .settings : .main)
            .environmentObject(self)
            .environmentObject(settings)
            .environmentObject(permissions)
            .environmentObject(touchMonitor)
            .environmentObject(controlStatus)
            .environmentObject(liveLevels)
            .environmentObject(loginItem)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.controlActiveState, .key)

        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let window = PreviewWindow(contentViewController: hosting)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.title = "SlideEdge Preview"
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.orderFrontRegardless()
        previewWindow = window
    }
    #endif

    private func applySettings() {
        gestures.update(config: makeGestureConfig())
        router.haptics.isEnabled = settings.haptics
        if settings.enabled && settings.palmRejection && permissions.inputMonitoring {
            keyActivity.start()
        } else {
            keyActivity.stop()
        }

        let wanted = (settings.enabled, settings.magicMouse)
        guard appliedInput.map({ $0 != wanted }) ?? true else { return }
        appliedInput = wanted
        if wanted.0 {
            touchInput.start(includeMagicMouse: wanted.1)
        } else {
            touchInput.stop()
            gestures.reset()
        }
    }

    private func makeGestureConfig() -> GestureConfig {
        var config = GestureConfig()
        config.edgeWidth = settings.edgeWidth
        config.sensitivity = settings.sensitivity
        config.preciseSliding = settings.preciseSliding
        config.requireModifier = settings.requireModifier
        config.leftActiveArea = settings.leftActiveArea
        config.rightActiveArea = settings.rightActiveArea
        config.palmRejection = settings.palmRejection
        // An edge whose control is not available on this Mac stays inert (shown in the menu).
        config.enabledEdges = Set([Edge.left, .right].filter { edge in
            router.control(for: edge) != .brightness || controlStatus.brightness.isAvailable
        })
        if settings.keyboardBacklightEdge && controlStatus.keyboardBacklight { config.enabledEdges.insert(.top) }
        if settings.mediaStrip { config.enabledEdges.insert(.bottom) }
        config.enabledCorners = []
        if settings.quickMute { config.enabledCorners.insert(.topRight) }
        if settings.cornerAction != .none { config.enabledCorners.insert(.topLeft) }
        return config
    }

    func showOnboarding() {
        permissions.startPolling()
        let view = OnboardingView { [weak self] in self?.onboardingWindow?.close() }
            .environmentObject(permissions)
        present(view, title: "Benvenuto in SlideEdge", in: &onboardingWindow)
    }

    func showAbout() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        let credits = NSAttributedString(
            string: "I bordi del trackpad diventano controlli per volume, luminosità, tastiera e musica.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func refreshLevels() {
        router.refreshLevels()
    }

    func showTouchDebug() {
        let isNew = touchDebugWindow == nil
        let view = TouchDebugView()
            .environmentObject(touchMonitor)
            .environmentObject(gestureLog)
            .environmentObject(settings)
        present(view, title: "Tocchi in tempo reale", in: &touchDebugWindow)
        touchMonitor.setVisualizing(true)
        if isNew, let window = touchDebugWindow {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [touchMonitor] _ in
                MainActor.assumeIsolated { touchMonitor.setVisualizing(false) }
            })
        }
    }

    private func present<Content: View>(_ view: Content, title: String, in slot: inout NSWindow?) {
        let window: NSWindow
        if let existing = slot {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: view)
            // Size once. Letting SwiftUI resize the window on every content change
            // (.preferredContentSize) ends in an AppKit update-constraints loop exception.
            hosting.sizingOptions = []
            window = NSWindow(contentViewController: hosting)
            window.setContentSize(hosting.view.fittingSize)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = title
            window.isReleasedWhenClosed = false
            window.center()
            slot = window
        }
        // Menu bar apps are never frontmost on their own.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

#if DEBUG
/// Always draws as the key window, so controls show their active (tinted) look in screenshots.
private final class PreviewWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
#endif
