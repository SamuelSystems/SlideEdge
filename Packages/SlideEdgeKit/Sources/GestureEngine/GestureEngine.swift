/// Turns touch frames from one device into edge gestures.
///
/// Pure value type: no clocks, no system calls. The caller passes frame times and
/// calls `tick(at:)` at `nextDeadline` so a slide can end while no frames arrive.
public struct GestureEngine: Sendable {
    public var config: GestureConfig

    private var state = State.idle
    private var tapCandidate: TapCandidate?
    private var lastTap: PendingTap?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    /// When the caller must call `tick(at:)` if no frame arrives earlier.
    public var nextDeadline: Double? {
        guard case .sliding(let slide) = state, let lostAt = slide.lostAt else { return nil }
        return lostAt + config.gracePeriod
    }

    public mutating func process(_ touches: [TouchSample], at time: Double, context: GestureContext = GestureContext()) -> [GestureEvent] {
        let contactBefore = announcedContact
        var events: [GestureEvent] = []
        updateTap(touches, at: time, context: context, events: &events)
        switch touches.count {
        case 0: handleNoTouch(at: time, events: &events)
        case 1: handleSingle(touches[0], at: time, context: context, events: &events)
        default: handleMultiple(events: &events)
        }

        // Contact events are derived from the state change, so every transition out of tracking is covered.
        let contactAfter = announcedContact
        if contactBefore != nil, contactBefore != contactAfter, !events.contains(where: \.isSlideBegan) {
            events.append(.contactCancelled)
        }
        if let contactAfter, contactAfter != contactBefore {
            events.append(.contactBegan)
        }
        return events
    }

    /// The touch being tracked in a zone that can start a slide (the media strip only swipes).
    private var announcedContact: Int32? {
        guard case .tracking(let track) = state, track.zones.contains(where: { $0 != .bottom }) else { return nil }
        return track.id
    }

    public mutating func tick(at time: Double) -> [GestureEvent] {
        guard case .sliding(let slide) = state, let lostAt = slide.lostAt, graceExpired(since: lostAt, at: time) else { return [] }
        state = .idle
        return [.slideEnded(slide.edge)]
    }

    /// Ends any slide in progress and forgets pending taps.
    public mutating func reset() -> [GestureEvent] {
        defer {
            state = .idle
            tapCandidate = nil
            lastTap = nil
        }
        if case .sliding(let slide) = state { return [.slideEnded(slide.edge)] }
        if announcedContact != nil { return [.contactCancelled] }
        return []
    }

    // MARK: - Slides and swipes

    private mutating func handleNoTouch(at time: Double, events: inout [GestureEvent]) {
        switch state {
        case .sliding(var slide):
            if let lostAt = slide.lostAt {
                if graceExpired(since: lostAt, at: time) {
                    events.append(.slideEnded(slide.edge))
                    state = .idle
                }
            } else {
                slide.lostAt = time
                state = .sliding(slide)
            }
        case .idle:
            break
        case .tracking, .swiping, .blocked:
            state = .idle
        }
    }

    private mutating func handleMultiple(events: inout [GestureEvent]) {
        // A second finger cancels: two-finger gestures belong to the system.
        if case .sliding(let slide) = state {
            events.append(.slideEnded(slide.edge))
        }
        state = .blocked
    }

    private mutating func handleSingle(_ touch: TouchSample, at time: Double, context: GestureContext, events: inout [GestureEvent]) {
        switch state {
        case .idle:
            begin(touch, at: time, context: context)
        case .blocked:
            break
        case .tracking(let track):
            guard touch.id == track.id else { state = .blocked; return }
            decide(track, touch, context: context, events: &events)
        case .swiping(let track):
            guard touch.id == track.id else { state = .blocked; return }
            updateSwipe(track, touch, events: &events)
        case .sliding(var slide):
            if let lostAt = slide.lostAt, graceExpired(since: lostAt, at: time) {
                events.append(.slideEnded(slide.edge))
                state = .idle
                begin(touch, at: time, context: context)
                return
            }
            if touch.id != slide.id && distance(touch, slide.last) > config.reacquireDistance {
                events.append(.slideEnded(slide.edge))
                state = .blocked
                return
            }
            let delta = axisDelta(for: slide.edge, from: slide.last, to: touch)
            slide.id = touch.id
            slide.last = touch
            slide.lostAt = nil
            apply(delta, to: &slide, context: context, events: &events)
            state = .sliding(slide)
        }
    }

    private mutating func begin(_ touch: TouchSample, at time: Double, context: GestureContext) {
        guard !isPalmBlocked(at: time, context: context) else { state = .blocked; return }
        let zones = startZones(for: touch, context: context)
        state = zones.isEmpty ? .blocked : .tracking(Track(id: touch.id, start: touch, zones: zones))
    }

    /// Zones a slide may start from. Only the first contact point counts: dragging into a zone does nothing.
    private func startZones(for touch: TouchSample, context: GestureContext) -> Set<Edge> {
        var zones: Set<Edge> = []
        let band = config.horizontalBand
        if !config.requireModifier || context.modifierHeld {
            if config.enabledEdges.contains(.left), touch.x <= config.edgeWidth, config.leftActiveArea.range.contains(touch.y) {
                zones.insert(.left)
            }
            if config.enabledEdges.contains(.right), touch.x >= 1 - config.edgeWidth, config.rightActiveArea.range.contains(touch.y) {
                zones.insert(.right)
            }
            if config.enabledEdges.contains(.top), touch.y >= 1 - band {
                zones.insert(.top)
            }
        }
        // The media strip uses swipes, not slides, so it does not need the modifier.
        if config.enabledEdges.contains(.bottom), touch.y <= band {
            zones.insert(.bottom)
        }
        return zones
    }

    private mutating func decide(_ track: Track, _ touch: TouchSample, context: GestureContext, events: inout [GestureEvent]) {
        let dx = abs(touch.x - track.start.x)
        let dy = abs(touch.y - track.start.y)
        let travel = max(dx, dy)
        guard travel >= config.minTravel else { return }

        if dy > config.axisRatio * dx {
            if let edge = [Edge.left, .right].first(where: track.zones.contains) {
                startSlide(edge, track: track, touch: touch, context: context, events: &events)
            } else {
                state = .blocked
            }
        } else if dx > config.axisRatio * dy {
            if track.zones.contains(.top) {
                startSlide(.top, track: track, touch: touch, context: context, events: &events)
            } else if track.zones.contains(.bottom) {
                updateSwipe(track, touch, events: &events)
            } else {
                state = .blocked
            }
        } else if travel >= config.minTravel * 3 {
            // Still diagonal well past the threshold: not an edge gesture.
            state = .blocked
        }
    }

    private mutating func startSlide(_ edge: Edge, track: Track, touch: TouchSample, context: GestureContext, events: inout [GestureEvent]) {
        events.append(.slideBegan(edge))
        // Count the travel used to recognize the slide, so it responds immediately.
        var slide = Slide(edge: edge, id: touch.id, last: touch)
        apply(axisDelta(for: edge, from: track.start, to: touch), to: &slide, context: context, events: &events)
        state = .sliding(slide)
    }

    private mutating func updateSwipe(_ track: Track, _ touch: TouchSample, events: inout [GestureEvent]) {
        let dx = touch.x - track.start.x
        let dy = touch.y - track.start.y
        guard abs(dx) >= config.swipeMinDistance else {
            state = .swiping(track)
            return
        }
        if abs(dx) > config.axisRatio * abs(dy) {
            events.append(.swipe(.bottom, dx > 0 ? .right : .left))
        }
        // One swipe per touch.
        state = .blocked
    }

    private func apply(_ delta: Double, to slide: inout Slide, context: GestureContext, events: inout [GestureEvent]) {
        let step = config.preciseSliding || context.preciseModifierHeld ? GestureConfig.fineStep : GestureConfig.coarseStep
        slide.remainder += delta * config.sensitivity
        let steps = (slide.remainder / step).rounded(.towardZero)
        guard steps != 0 else { return }
        slide.remainder -= steps * step
        events.append(.slideChanged(slide.edge, delta: steps * step))
    }

    private func axisDelta(for edge: Edge, from start: TouchSample, to end: TouchSample) -> Double {
        edge.isSide ? end.y - start.y : end.x - start.x
    }

    /// Same expression as `nextDeadline`, so ticking exactly at the deadline always ends the slide.
    private func graceExpired(since lostAt: Double, at time: Double) -> Bool {
        time >= lostAt + config.gracePeriod
    }

    private func isPalmBlocked(at time: Double, context: GestureContext) -> Bool {
        guard config.palmRejection, let lastKeyDown = context.lastKeyDown else { return false }
        return time - lastKeyDown < config.palmRejectionInterval
    }

    // MARK: - Taps

    private mutating func updateTap(_ touches: [TouchSample], at time: Double, context: GestureContext, events: inout [GestureEvent]) {
        if var candidate = tapCandidate {
            if touches.isEmpty {
                tapCandidate = nil
                if candidate.valid && time - candidate.startTime <= config.tapMaxDuration {
                    registerTap(candidate, endedAt: time, events: &events)
                } else {
                    lastTap = nil
                }
                return
            }
            let touch = touches[0]
            if touches.count > 1
                || touch.id != candidate.id
                || distance(touch, candidate.start) > config.tapMaxMovement
                || time - candidate.startTime > config.tapMaxDuration {
                candidate.valid = false
                tapCandidate = candidate
            }
        } else if touches.count == 1, case .idle = state, !isPalmBlocked(at: time, context: context) {
            let target = tapTarget(at: touches[0])
            tapCandidate = TapCandidate(id: touches[0].id, start: touches[0], startTime: time, target: target, valid: target != nil)
        }
    }

    private mutating func registerTap(_ tap: TapCandidate, endedAt time: Double, events: inout [GestureEvent]) {
        guard let target = tap.target else { lastTap = nil; return }
        if let last = lastTap, last.target == target, tap.startTime - last.end <= config.doubleTapWindow {
            lastTap = nil
            switch target {
            case .corner(let corner): events.append(.doubleTap(corner))
            case .bottomEdge: events.append(.edgeDoubleTap(.bottom))
            }
        } else {
            lastTap = PendingTap(target: target, end: time)
        }
    }

    private func tapTarget(at point: TouchSample) -> TapTarget? {
        let cornerX = config.cornerSize
        let cornerY = min(config.cornerSize * config.surfaceAspect, 0.4)
        if point.y >= 1 - cornerY {
            if point.x <= cornerX, config.enabledCorners.contains(.topLeft) { return .corner(.topLeft) }
            if point.x >= 1 - cornerX, config.enabledCorners.contains(.topRight) { return .corner(.topRight) }
        }
        if config.enabledEdges.contains(.bottom), point.y <= config.horizontalBand { return .bottomEdge }
        return nil
    }

    private func distance(_ a: TouchSample, _ b: TouchSample) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}

// MARK: - State

private enum State: Sendable {
    case idle
    /// One finger down in an edge zone, axis not decided yet.
    case tracking(Track)
    /// Horizontal movement on the bottom edge, waiting for enough travel.
    case swiping(Track)
    case sliding(Slide)
    /// Ignore everything until all fingers lift.
    case blocked
}

private struct Track: Sendable {
    var id: Int32
    var start: TouchSample
    var zones: Set<Edge>
}

private struct Slide: Sendable {
    var edge: Edge
    var id: Int32
    var last: TouchSample
    /// Scaled travel not yet emitted as a whole step.
    var remainder = 0.0
    /// Time the finger disappeared, while within the grace period.
    var lostAt: Double?
}

private enum TapTarget: Sendable, Equatable {
    case corner(Corner)
    case bottomEdge
}

private struct TapCandidate: Sendable {
    var id: Int32
    var start: TouchSample
    var startTime: Double
    var target: TapTarget?
    var valid: Bool
}

private struct PendingTap: Sendable {
    var target: TapTarget
    var end: Double
}
