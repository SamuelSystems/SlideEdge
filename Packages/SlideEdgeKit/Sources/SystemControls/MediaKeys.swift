import AppKit

/// Special keys, as defined by NX_KEYTYPE_* in IOKit/hidsystem/ev_keymap.h.
public enum MediaKey: Int32, Sendable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
    case illuminationUp = 21
    case illuminationDown = 22
}

public enum MediaKeys {
    /// Posts a key press and release, exactly like the keyboard's function row.
    /// Requires Accessibility permission; without it the events are silently dropped.
    @MainActor
    public static func post(_ key: MediaKey) {
        for keyDown in [true, false] {
            let state: Int32 = keyDown ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: Int((key.rawValue << 16) | (state << 8)),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
