import CMultitouch
import Testing
@testable import TouchInput

struct TouchInputTests {
    @Test func phaseMapping() {
        #expect(TouchPhase(rawState: Int32(MTTouchStateMakeTouch)) == .began)
        #expect(TouchPhase(rawState: Int32(MTTouchStateTouching)) == .touching)
        #expect(TouchPhase(rawState: Int32(MTTouchStateBreakTouch)) == .ending)
        #expect(TouchPhase(rawState: Int32(MTTouchStateHoverInRange)) == .hovering)
        #expect(TouchPhase(rawState: Int32(MTTouchStateOutOfRange)) == .lifted)
        #expect(TouchPhase(rawState: 42) == .unknown)
        #expect(TouchPhase.began.isContact && TouchPhase.touching.isContact && !TouchPhase.ending.isContact)
    }

    @Test func touchStructLayout() {
        // Offsets from the reverse-engineered layout; the C header also asserts the size.
        #expect(MemoryLayout<MTTouch>.size == 96)
        #expect(MemoryLayout<MTTouch>.offset(of: \MTTouch.timestamp) == 8)
        #expect(MemoryLayout<MTTouch>.offset(of: \MTTouch.normalizedVector) == 32)
        #expect(MemoryLayout<MTTouch>.offset(of: \MTTouch.zTotal) == 48)
    }

    @Test func frameworkLoads() throws {
        // Fails loudly if a macOS update removes one of the required symbols.
        _ = try MultitouchLibrary.load().get()
    }
}
