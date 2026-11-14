public enum Edge: String, Sendable, CaseIterable {
    case left, right, top, bottom

    /// Side edges slide vertically, top and bottom horizontally.
    public var isSide: Bool { self == .left || self == .right }
}

public enum Corner: String, Sendable, CaseIterable {
    case topLeft, topRight
}

public enum SwipeDirection: String, Sendable {
    case left, right
}

public enum GestureEvent: Sendable, Equatable {
    /// A finger landed in a slide zone: a slide may follow. Lets the caller freeze the pointer
    /// before the slide is recognized. Always followed by `slideBegan` or `contactCancelled`.
    case contactBegan
    /// The contact announced by `contactBegan` did not become a slide.
    case contactCancelled
    case slideBegan(Edge)
    /// Level change, already scaled by sensitivity and quantized to whole steps.
    case slideChanged(Edge, delta: Double)
    case slideEnded(Edge)
    case doubleTap(Corner)
    case edgeDoubleTap(Edge)
    case swipe(Edge, SwipeDirection)
}

/// A finger in contact with the surface. Coordinates are normalized 0...1, origin bottom-left.
public struct TouchSample: Sendable, Equatable {
    public var id: Int32
    public var x: Double
    public var y: Double

    public init(id: Int32, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// System state sampled by the caller alongside each frame.
public struct GestureContext: Sendable, Equatable {
    /// Fn or Option held (for "Require Fn or Option").
    public var modifierHeld: Bool
    /// Shift+Option held: quarter-step sliding.
    public var preciseModifierHeld: Bool
    /// Time of the last key press, in the same clock as frame times.
    public var lastKeyDown: Double?

    public init(modifierHeld: Bool = false, preciseModifierHeld: Bool = false, lastKeyDown: Double? = nil) {
        self.modifierHeld = modifierHeld
        self.preciseModifierHeld = preciseModifierHeld
        self.lastKeyDown = lastKeyDown
    }
}

/// Portion of a side edge that accepts slides, measured from the bottom of the trackpad (0) to the top (1).
public enum ActiveArea: String, CaseIterable, Identifiable, Sendable {
    case full
    case bottomThreeQuarters, bottomHalf, bottomQuarter
    case topThreeQuarters, topHalf, topQuarter

    public var id: String { rawValue }

    public var range: ClosedRange<Double> {
        switch self {
        case .full: 0...1
        case .bottomThreeQuarters: 0...0.75
        case .bottomHalf: 0...0.5
        case .bottomQuarter: 0...0.25
        case .topThreeQuarters: 0.25...1
        case .topHalf: 0.5...1
        case .topQuarter: 0.75...1
        }
    }
}

public struct GestureConfig: Sendable, Equatable {
    public static let coarseStep = 1.0 / 16
    public static let fineStep = 1.0 / 64

    /// Side zone width as a fraction of the surface width. Top and bottom zones get the same physical width.
    public var edgeWidth = 0.05
    /// Surface width / height, used to keep all zones the same physical size.
    public var surfaceAspect = 1.5
    public var sensitivity = 1.0
    public var preciseSliding = false
    public var requireModifier = false
    public var leftActiveArea = ActiveArea.full
    public var rightActiveArea = ActiveArea.full
    public var enabledEdges: Set<Edge> = Set(Edge.allCases)
    public var enabledCorners: Set<Corner> = Set(Corner.allCases)

    public var palmRejection = true
    public var palmRejectionInterval = 0.5
    /// How long a slide survives with no finger on the surface.
    public var gracePeriod = 0.08
    /// Travel before the slide axis is decided.
    public var minTravel = 0.02
    /// The dominant axis must exceed the other by this factor.
    public var axisRatio = 2.0
    /// A finger reappearing within the grace period further than this is a different finger.
    public var reacquireDistance = 0.1

    public var cornerSize = 0.1
    public var tapMaxDuration = 0.2
    public var tapMaxMovement = 0.015
    /// Maximum gap between the end of the first tap and the start of the second.
    public var doubleTapWindow = 0.35
    public var swipeMinDistance = 0.12

    public init() {}

    var horizontalBand: Double { min(edgeWidth * surfaceAspect, 0.3) }
}

extension GestureEvent {
    var isSlideBegan: Bool {
        if case .slideBegan = self { true } else { false }
    }

    /// `contactBegan` / `contactCancelled`.
    public var isContactEvent: Bool {
        self == .contactBegan || self == .contactCancelled
    }
}
