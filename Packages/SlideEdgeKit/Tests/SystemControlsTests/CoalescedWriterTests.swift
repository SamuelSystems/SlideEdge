import Foundation
import Testing
@testable import SystemControls

@Suite struct CoalescedWriterTests {
    private final class Recorder: @unchecked Sendable {
        var values: [Double] = []
    }

    @Test func burstWritesOnlyLatestValue() async throws {
        let queue = DispatchQueue(label: "test")
        let recorder = Recorder()
        let writer = CoalescedWriter(queue: queue, interval: 0.05) { recorder.values.append($0) }

        for value in stride(from: 0.0, through: 1.0, by: 0.01) {
            writer.submit(value)
        }
        try await Task.sleep(for: .milliseconds(200))

        let values = queue.sync { recorder.values }
        #expect(values.count <= 2)
        #expect(values.last == 1.0)
    }

    @Test func spacedWritesAreAllApplied() async throws {
        let queue = DispatchQueue(label: "test")
        let recorder = Recorder()
        let writer = CoalescedWriter(queue: queue, interval: 0.01) { recorder.values.append($0) }

        for value in [0.2, 0.4, 0.6] {
            writer.submit(value)
            try await Task.sleep(for: .milliseconds(40))
        }

        #expect(queue.sync { recorder.values } == [0.2, 0.4, 0.6])
    }
}
