import AppKit
import AppSettings
import Carbon.HIToolbox
import Darwin

/// Runs the action bound to the top-left corner double tap.
@MainActor
public enum CornerActionPerformer {
    public static func perform(_ action: CornerAction) {
        switch action {
        case .none:
            break
        case .missionControl:
            openSystemApp(at: "/System/Applications/Mission Control.app")
        case .showDesktop:
            sendDockNotification("com.apple.showdesktop.awake")
        case .launchpad:
            openSystemApp(at: CornerAction.launcherAppPath)
        case .screenshot:
            openSystemApp(at: "/System/Applications/Utilities/Screenshot.app")
        case .lockScreen:
            lockScreen()
        }
    }

    private static func openSystemApp(at path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Private APIs, resolved at runtime

    private typealias CoreDockSendNotification = @convention(c) (CFString, Int32) -> Void
    private typealias SACLockScreenImmediate = @convention(c) () -> Int32

    private static let coreDockSendNotification: CoreDockSendNotification? = {
        dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification")  // RTLD_DEFAULT
            .map { unsafeBitCast($0, to: CoreDockSendNotification.self) }
    }()

    private static let lockScreenImmediate: SACLockScreenImmediate? = {
        dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
            .flatMap { dlsym($0, "SACLockScreenImmediate") }
            .map { unsafeBitCast($0, to: SACLockScreenImmediate.self) }
    }()

    private static func sendDockNotification(_ name: String) {
        coreDockSendNotification?(name as CFString, 0)
    }

    private static func lockScreen() {
        if let lockScreenImmediate {
            _ = lockScreenImmediate()
        } else {
            // Fallback: the system shortcut ⌃⌘Q.
            postKey(CGKeyCode(kVK_ANSI_Q), flags: [.maskControl, .maskCommand])
        }
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
