import AppKit
import SwiftUI

public enum HUDKind: Sendable, Equatable {
    case volume
    case brightness
    case keyboardBacklight
    /// Icon and text, no level bar (media actions).
    case message(symbol: String, text: String)
}

/// On-screen level indicator, drawn by SlideEdge in the style of the system OSD.
@MainActor
public final class HUDController {
    private static let size = NSSize(width: 240, height: 54)
    private static let visibleDuration: TimeInterval = 1.4

    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    public init() {}

    public func show(_ kind: HUDKind, level: Double = 0, muted: Bool = false) {
        model.kind = kind
        model.level = level
        model.muted = muted

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        // canJoinAllApplications (macOS 13+) is what lets the panel appear inside other apps'
        // full-screen spaces; canJoinAllSpaces alone only covers regular desktops.
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.sizingOptions = []
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        panel.contentView = background
        return panel
    }

    /// Bottom centre of the screen under the mouse pointer.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + frame.height * 0.12))
    }
}

@MainActor
private final class HUDModel: ObservableObject {
    @Published var kind = HUDKind.volume
    @Published var level = 0.0
    @Published var muted = false
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 26)
            if case .message(_, let text) = model.kind {
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SegmentBar(level: model.muted ? 0 : model.level)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        switch model.kind {
        case .volume:
            if model.muted || model.level == 0 { return "speaker.slash.fill" }
            if model.level < 0.34 { return "speaker.wave.1.fill" }
            if model.level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return "sun.max.fill"
        case .keyboardBacklight:
            return "light.max"
        case .message(let symbol, _):
            return symbol
        }
    }
}

/// 16 segments, each filled proportionally so quarter steps are visible.
private struct SegmentBar: View {
    let level: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<16, id: \.self) { index in
                let fill = min(max(level * 16 - Double(index), 0), 1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.primary.opacity(0.18))
                        Rectangle().fill(.primary).frame(width: proxy.size.width * fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
        }
        .frame(height: 8)
    }
}
