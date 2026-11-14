import Testing
@testable import GestureEngine

/// Feeds simulated frames at 100 Hz and collects the events.
private struct Harness {
    var engine: GestureEngine
    var time = 100.0
    var context = GestureContext()
    /// Every event, including contact events.
    var allEvents: [GestureEvent] = []
    let frameInterval = 0.01

    /// Gesture events without contact events, which most tests do not care about.
    var events: [GestureEvent] { allEvents.filter { !$0.isContactEvent } }

    init(_ configure: (inout GestureConfig) -> Void = { _ in }) {
        var config = GestureConfig()
        configure(&config)
        engine = GestureEngine(config: config)
    }

    mutating func frame(_ touches: [TouchSample]) {
        allEvents += engine.process(touches, at: time, context: context)
        time += frameInterval
    }

    mutating func drag(from start: (Double, Double), to end: (Double, Double), frames: Int = 20, id: Int32 = 1) {
        for i in 0...frames {
            let t = Double(i) / Double(frames)
            frame([TouchSample(id: id, x: start.0 + (end.0 - start.0) * t, y: start.1 + (end.1 - start.1) * t)])
        }
    }

    mutating func hold(at point: (Double, Double), for duration: Double, id: Int32 = 1) {
        for _ in 0..<max(Int((duration / frameInterval).rounded()), 1) {
            frame([TouchSample(id: id, x: point.0, y: point.1)])
        }
    }

    /// Lifts all fingers and lets the grace period run out.
    mutating func lift() {
        frame([])
        frame([])
        if let deadline = engine.nextDeadline {
            time = max(time, deadline)
            allEvents += engine.tick(at: time)
        }
        time += 0.5
    }

    mutating func tap(at point: (Double, Double), duration: Double = 0.05) {
        hold(at: point, for: duration)
        frame([])
    }

    mutating func wait(_ seconds: Double) {
        time += seconds
    }

    var deltas: [Double] {
        events.compactMap { if case .slideChanged(_, let delta) = $0 { delta } else { nil } }
    }

    var total: Double { deltas.reduce(0, +) }

    var began: [Edge] {
        events.compactMap { if case .slideBegan(let edge) = $0 { edge } else { nil } }
    }
}

// MARK: - Smart Edges

@Suite struct SlideTests {
    @Test func slideUpOnLeftEdge() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.57))
        h.lift()
        #expect(h.events.first == .slideBegan(.left))
        #expect(h.events.last == .slideEnded(.left))
        #expect(h.total == 0.25)  // 0.27 of travel → 4 whole steps of 1/16
        #expect(h.deltas.allSatisfy { $0 > 0 })
    }

    @Test func slideDownOnRightEdgeIsNegative() {
        var h = Harness()
        h.drag(from: (0.98, 0.8), to: (0.98, 0.53))
        h.lift()
        #expect(h.began == [.right])
        #expect(h.total == -0.25)
    }

    @Test func dragIntoZoneDoesNothing() {
        var h = Harness()
        h.drag(from: (0.3, 0.5), to: (0.02, 0.5))
        h.drag(from: (0.02, 0.5), to: (0.02, 0.9))
        h.lift()
        #expect(h.events.isEmpty)
    }

    @Test func horizontalSwipeFromRightEdgeDoesNothing() {
        // Notification Center / page swipes start on the right edge but move horizontally.
        var h = Harness()
        h.drag(from: (0.98, 0.5), to: (0.7, 0.53))
        h.lift()
        #expect(h.events.isEmpty)
    }

    @Test func diagonalMovementDoesNothing() {
        var h = Harness()
        h.drag(from: (0.98, 0.5), to: (0.85, 0.63))
        h.lift()
        #expect(h.events.isEmpty)
    }

    @Test func twoFingerGestureDoesNothing() {
        var h = Harness()
        for i in 0...20 {
            let y = 0.3 + Double(i) * 0.02
            h.frame([TouchSample(id: 1, x: 0.98, y: y), TouchSample(id: 2, x: 0.9, y: y)])
        }
        h.lift()
        #expect(h.events.isEmpty)
    }

    @Test func secondFingerCancelsSlide() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.5))
        let beforeSecondFinger = h.events.count
        for i in 0...10 {
            let y = 0.5 + Double(i) * 0.02
            h.frame([TouchSample(id: 1, x: 0.02, y: y), TouchSample(id: 2, x: 0.3, y: 0.5)])
        }
        h.drag(from: (0.02, 0.7), to: (0.02, 0.9))  // second finger lifted: still blocked
        h.lift()
        #expect(h.events[beforeSecondFinger] == .slideEnded(.left))
        #expect(h.events.count == beforeSecondFinger + 1)
    }

    @Test func movementBelowThresholdDoesNotBegin() {
        var h = Harness()
        h.drag(from: (0.02, 0.5), to: (0.02, 0.515))
        h.lift()
        #expect(h.began.isEmpty)
    }

    @Test func disabledEdgeDoesNothing() {
        var h = Harness { $0.enabledEdges = [.right] }
        h.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        h.lift()
        #expect(h.events.isEmpty)
    }

    @Test func edgeWidthIsConfigurable() {
        var narrow = Harness { $0.edgeWidth = 0.03 }
        narrow.drag(from: (0.04, 0.3), to: (0.04, 0.6))
        #expect(narrow.began.isEmpty)

        var wide = Harness { $0.edgeWidth = 0.08 }
        wide.drag(from: (0.04, 0.3), to: (0.04, 0.6))
        #expect(wide.began == [.left])
    }

    @Test func topEdgeSlidesHorizontally() {
        var h = Harness()
        h.drag(from: (0.3, 0.98), to: (0.57, 0.97))
        h.lift()
        #expect(h.began == [.top])
        #expect(h.total == 0.25)
    }

    @Test func topEdgeIgnoresVerticalMovement() {
        var h = Harness()
        h.drag(from: (0.5, 0.98), to: (0.5, 0.7))
        h.lift()
        #expect(h.events.isEmpty)
    }
}

// MARK: - Options

@Suite struct OptionTests {
    @Test(arguments: [
        (ActiveArea.bottomHalf, 0.8, false),
        (ActiveArea.bottomHalf, 0.2, true),
        (ActiveArea.topQuarter, 0.6, false),
        (ActiveArea.topQuarter, 0.8, true),
        (ActiveArea.full, 0.95, true),
    ])
    func activeArea(area: ActiveArea, startY: Double, slides: Bool) {
        var h = Harness { $0.leftActiveArea = area }
        h.drag(from: (0.02, startY), to: (0.02, startY - 0.15))
        #expect(h.began.isEmpty == !slides)
    }

    @Test func activeAreaIsPerSide() {
        var h = Harness { $0.leftActiveArea = .bottomQuarter }
        h.drag(from: (0.98, 0.8), to: (0.98, 0.6))
        #expect(h.began == [.right])
    }

    @Test func requireModifier() {
        var without = Harness { $0.requireModifier = true }
        without.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        #expect(without.began.isEmpty)

        var with = Harness { $0.requireModifier = true }
        with.context.modifierHeld = true
        with.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        #expect(with.began == [.left])
    }

    @Test func palmRejectionBlocksRecentKeyPress() {
        var h = Harness()
        h.context.lastKeyDown = h.time - 0.2
        h.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        h.lift()
        #expect(h.events.isEmpty)
    }

    @Test func palmRejectionExpires() {
        var h = Harness()
        h.context.lastKeyDown = h.time - 0.6
        h.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        #expect(h.began == [.left])
    }

    @Test func palmRejectionCanBeDisabled() {
        var h = Harness { $0.palmRejection = false }
        h.context.lastKeyDown = h.time - 0.1
        h.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        #expect(h.began == [.left])
    }

    @Test func keyPressDuringSlideDoesNotCancelIt() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.45))
        h.context.lastKeyDown = h.time
        h.drag(from: (0.02, 0.45), to: (0.02, 0.6))
        h.lift()
        #expect(h.began == [.left])
        #expect(h.total == 0.25)
    }
}

// MARK: - Mapping and quantization

@Suite struct QuantizationTests {
    private func isMultiple(_ value: Double, of step: Double) -> Bool {
        let ratio = value / step
        return abs(ratio - ratio.rounded()) < 1e-9
    }

    @Test func coarseStepsAreSixteenths() {
        var h = Harness()
        h.drag(from: (0.02, 0.2), to: (0.02, 0.73), frames: 53)
        #expect(h.deltas.allSatisfy { isMultiple($0, of: 1.0 / 16) })
        #expect(h.total == 0.5)
    }

    @Test func preciseSlidingUsesQuarterSteps() {
        var h = Harness { $0.preciseSliding = true }
        h.drag(from: (0.02, 0.3), to: (0.02, 0.57))
        #expect(h.deltas.allSatisfy { isMultiple($0, of: 1.0 / 64) })
        #expect(h.total == 17.0 / 64)
    }

    @Test func shiftOptionUsesQuarterSteps() {
        var h = Harness()
        h.context.preciseModifierHeld = true
        h.drag(from: (0.02, 0.3), to: (0.02, 0.57))
        #expect(h.total == 17.0 / 64)
    }

    @Test func sensitivityScalesTravel() {
        var h = Harness { $0.sensitivity = 2 }
        h.drag(from: (0.02, 0.3), to: (0.02, 0.57))
        #expect(h.total == 0.5)
    }

    @Test func remainderCarriesAcrossFrames() {
        // 40 frames of 0.005 each: no single frame reaches a step, the sum must.
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.5), frames: 40)
        #expect(h.total == 0.1875)
    }

    @Test func reversingDirection() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        h.drag(from: (0.02, 0.6), to: (0.02, 0.3))
        #expect(abs(h.total) <= 1.0 / 16)
        #expect(h.began.count == 1)
    }
}

// MARK: - Grace period

@Suite struct GracePeriodTests {
    @Test func shortDropoutKeepsSlide() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.45))
        h.frame([])
        h.frame([])
        h.frame([])
        h.frame([])  // 40 ms without a finger
        h.drag(from: (0.02, 0.45), to: (0.02, 0.6))
        h.lift()
        #expect(h.began == [.left])
        #expect(h.events.filter { $0 == .slideEnded(.left) }.count == 1)
        #expect(h.total == 0.25)
    }

    @Test func dropoutWithNewIDIsReacquired() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.45), id: 1)
        h.frame([])
        h.drag(from: (0.02, 0.45), to: (0.02, 0.6), id: 7)
        h.lift()
        #expect(h.began == [.left])
        #expect(h.events.filter { $0 == .slideEnded(.left) }.count == 1)
    }

    @Test func longDropoutEndsSlide() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.45))
        for _ in 0..<10 { h.frame([]) }  // 100 ms
        #expect(h.events.last == .slideEnded(.left))
        h.drag(from: (0.02, 0.45), to: (0.02, 0.6))
        #expect(h.began == [.left, .left])
    }

    @Test func tickEndsSlideWhenFramesStop() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.45))
        h.frame([])
        let deadline = try! #require(h.engine.nextDeadline)
        #expect(h.engine.tick(at: deadline - 0.01).isEmpty)
        #expect(h.engine.tick(at: deadline) == [.slideEnded(.left)])
        #expect(h.engine.nextDeadline == nil)
    }

    @Test func resetEndsSlide() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.45))
        #expect(h.engine.reset() == [.slideEnded(.left)])
        #expect(h.engine.reset().isEmpty)
    }
}

// MARK: - Taps and swipes

@Suite struct TapTests {
    @Test func doubleTapTopRight() {
        var h = Harness()
        h.tap(at: (0.97, 0.97))
        h.wait(0.1)
        h.tap(at: (0.97, 0.97))
        #expect(h.events == [.doubleTap(.topRight)])
    }

    @Test func doubleTapTopLeft() {
        var h = Harness()
        h.tap(at: (0.03, 0.95))
        h.wait(0.1)
        h.tap(at: (0.04, 0.96))
        #expect(h.events == [.doubleTap(.topLeft)])
    }

    @Test func tapsTooFarApartInTime() {
        var h = Harness()
        h.tap(at: (0.97, 0.97))
        h.wait(0.5)
        h.tap(at: (0.97, 0.97))
        #expect(h.events.isEmpty)
    }

    @Test func longPressIsNotATap() {
        var h = Harness()
        h.tap(at: (0.97, 0.97), duration: 0.3)
        h.wait(0.1)
        h.tap(at: (0.97, 0.97))
        #expect(h.events.isEmpty)
    }

    @Test func movingTapIsNotATap() {
        var h = Harness()
        // Moves 0.03: too far for a tap (it is a short top-edge slide instead).
        h.drag(from: (0.95, 0.97), to: (0.92, 0.97), frames: 4)
        h.frame([])
        h.wait(0.1)
        h.tap(at: (0.97, 0.97))
        #expect(!h.events.contains(.doubleTap(.topRight)))
    }

    @Test func tapsInDifferentCornersDoNotPair() {
        var h = Harness()
        h.tap(at: (0.03, 0.97))
        h.wait(0.1)
        h.tap(at: (0.97, 0.97))
        #expect(h.events.isEmpty)
    }

    @Test func tripleTapFiresOnce() {
        var h = Harness()
        for _ in 0..<3 {
            h.tap(at: (0.97, 0.97))
            h.wait(0.1)
        }
        #expect(h.events == [.doubleTap(.topRight)])
    }

    @Test func disabledCornerDoesNothing() {
        var h = Harness { $0.enabledCorners = [.topLeft] }
        h.tap(at: (0.97, 0.97))
        h.wait(0.1)
        h.tap(at: (0.97, 0.97))
        #expect(h.events.isEmpty)
    }

    @Test func doubleTapInMiddleDoesNothing() {
        var h = Harness()
        h.tap(at: (0.5, 0.5))
        h.wait(0.1)
        h.tap(at: (0.5, 0.5))
        #expect(h.events.isEmpty)
    }

    @Test func palmRejectionBlocksTaps() {
        var h = Harness()
        h.context.lastKeyDown = h.time
        h.tap(at: (0.97, 0.97))
        h.wait(0.05)
        h.tap(at: (0.97, 0.97))
        #expect(h.events.isEmpty)
    }

    @Test func bottomEdgeDoubleTap() {
        var h = Harness()
        h.tap(at: (0.5, 0.03))
        h.wait(0.1)
        h.tap(at: (0.5, 0.03))
        #expect(h.events == [.edgeDoubleTap(.bottom)])
    }

    @Test func swipeRightOnBottomEdge() {
        var h = Harness()
        h.drag(from: (0.3, 0.03), to: (0.55, 0.04))
        h.lift()
        #expect(h.events == [.swipe(.bottom, .right)])
    }

    @Test func swipeLeftOnBottomEdge() {
        var h = Harness()
        h.drag(from: (0.7, 0.03), to: (0.45, 0.03))
        h.lift()
        #expect(h.events == [.swipe(.bottom, .left)])
    }

    @Test func shortBottomSwipeDoesNothing() {
        var h = Harness()
        h.drag(from: (0.5, 0.03), to: (0.58, 0.03))
        h.lift()
        #expect(h.events.isEmpty)
    }

    @Test func verticalMoveFromBottomDoesNothing() {
        var h = Harness()
        h.drag(from: (0.5, 0.03), to: (0.5, 0.4))
        h.lift()
        #expect(h.events.isEmpty)
    }

    @Test func bottomEdgeDisabled() {
        var h = Harness { $0.enabledEdges = [.left, .right, .top] }
        h.drag(from: (0.3, 0.03), to: (0.6, 0.03))
        h.tap(at: (0.5, 0.03))
        h.wait(0.1)
        h.tap(at: (0.5, 0.03))
        #expect(h.events.isEmpty)
    }
}

@Test func activeAreaRanges() {
    #expect(ActiveArea.full.range == 0...1)
    #expect(ActiveArea.bottomQuarter.range == 0...0.25)
    #expect(ActiveArea.topThreeQuarters.range == 0.25...1)
}

@Suite struct LevelMathTests {
    @Test func coarseDeltaSnapsToSixteenths() {
        #expect(LevelMath.apply(1.0 / 16, to: 0.37) == 7.0 / 16)
        #expect(LevelMath.apply(-1.0 / 16, to: 0.37) == 5.0 / 16)
    }

    @Test func fineDeltaSnapsToSixtyFourths() {
        #expect(LevelMath.apply(1.0 / 64, to: 0.37) == 25.0 / 64)
    }

    @Test func clampsToRange() {
        #expect(LevelMath.apply(2.0 / 16, to: 0.95) == 1)
        #expect(LevelMath.apply(-2.0 / 16, to: 0.05) == 0)
    }
}

// MARK: - Contact events (pointer freeze before recognition)

@Suite struct ContactTests {
    private func contacts(_ h: Harness) -> [GestureEvent] {
        h.allEvents.filter { $0.isContactEvent || $0 == .slideBegan(.left) || $0 == .slideBegan(.right) }
    }

    @Test func contactThenSlide() {
        var h = Harness()
        h.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        h.lift()
        #expect(contacts(h) == [.contactBegan, .slideBegan(.left)])
    }

    @Test func contactCancelledByHorizontalMove() {
        var h = Harness()
        h.drag(from: (0.98, 0.5), to: (0.7, 0.5))
        h.lift()
        #expect(h.allEvents == [.contactBegan, .contactCancelled])
    }

    @Test func contactCancelledByLiftWithoutSlide() {
        var h = Harness()
        h.tap(at: (0.02, 0.5))
        #expect(h.allEvents == [.contactBegan, .contactCancelled])
    }

    @Test func contactCancelledBySecondFinger() {
        var h = Harness()
        h.frame([TouchSample(id: 1, x: 0.98, y: 0.5)])
        h.frame([TouchSample(id: 1, x: 0.98, y: 0.5), TouchSample(id: 2, x: 0.8, y: 0.5)])
        #expect(h.allEvents == [.contactBegan, .contactCancelled])
    }

    @Test func noContactOutsideZones() {
        var h = Harness()
        h.drag(from: (0.5, 0.5), to: (0.5, 0.8))
        h.lift()
        #expect(h.allEvents.isEmpty)
    }

    @Test func mediaStripOnlyDoesNotAnnounceContact() {
        var h = Harness()
        h.drag(from: (0.3, 0.03), to: (0.6, 0.03))
        h.lift()
        #expect(h.allEvents == [.swipe(.bottom, .right)])
    }

    @Test func palmRejectedTouchDoesNotAnnounceContact() {
        var h = Harness()
        h.context.lastKeyDown = h.time
        h.drag(from: (0.02, 0.3), to: (0.02, 0.6))
        #expect(h.allEvents.isEmpty)
    }

    @Test func resetCancelsContact() {
        var h = Harness()
        h.frame([TouchSample(id: 1, x: 0.02, y: 0.5)])
        #expect(h.engine.reset() == [.contactCancelled])
    }
}
