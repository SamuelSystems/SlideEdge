import Foundation
import GestureEngine

/// Recent gestures and simulated levels, shown in the debug window until real controls exist.
@MainActor
final class GestureLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var levels: [Edge: Double] = [.left: 0.5, .right: 0.5, .top: 0.5]

    private let maxEntries = 14

    func record(_ event: GestureEvent) {
        guard !event.isContactEvent else { return }
        if case .slideChanged(let edge, let delta) = event {
            levels[edge] = min(max((levels[edge] ?? 0.5) + delta, 0), 1)
        }
        // Collapse consecutive changes of the same slide into one line.
        if case .slideChanged = event, let last = entries.first, last.text.hasPrefix(event.logPrefix) {
            entries[0] = Entry(date: last.date, text: "\(event.logPrefix) → \(levelText(for: event))")
            return
        }
        let text = if case .slideChanged = event { "\(event.logPrefix) → \(levelText(for: event))" } else { event.logText }
        entries.insert(Entry(date: Date(), text: text), at: 0)
        if entries.count > maxEntries { entries.removeLast() }
    }

    private func levelText(for event: GestureEvent) -> String {
        guard case .slideChanged(let edge, _) = event else { return "" }
        return String(format: "%.3f", levels[edge] ?? 0)
    }
}

extension Edge {
    var title: String {
        switch self {
        case .left: "sinistro"
        case .right: "destro"
        case .top: "superiore"
        case .bottom: "inferiore"
        }
    }
}

private extension GestureEvent {
    var logPrefix: String {
        if case .slideChanged(let edge, _) = self { "Slide bordo \(edge.title)" } else { logText }
    }

    var logText: String {
        switch self {
        case .contactBegan: "Contatto in zona bordo"
        case .contactCancelled: "Contatto annullato"
        case .slideBegan(let edge): "Inizio slide bordo \(edge.title)"
        case .slideChanged(let edge, let delta): "Slide bordo \(edge.title) \(delta)"
        case .slideEnded(let edge): "Fine slide bordo \(edge.title)"
        case .doubleTap(.topLeft): "Doppio tap angolo in alto a sinistra"
        case .doubleTap(.topRight): "Doppio tap angolo in alto a destra"
        case .edgeDoubleTap(let edge): "Doppio tap bordo \(edge.title)"
        case .swipe(let edge, let direction): "Swipe bordo \(edge.title) verso \(direction == .left ? "sinistra" : "destra")"
        }
    }
}
