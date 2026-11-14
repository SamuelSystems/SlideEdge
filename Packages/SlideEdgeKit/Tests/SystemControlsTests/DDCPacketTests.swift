import Testing
@testable import SystemControls

/// Reference packets from the DDC/CI specification (bytes after the 0x6E 0x51 addresses).
@Suite struct DDCPacketTests {
    @Test func getBrightnessRequest() {
        // 6E 51 82 01 10 AC
        #expect(DDCPacket.getVCP(0x10) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func setBrightnessTo50() {
        // 6E 51 84 03 10 00 32 9A
        #expect(DDCPacket.setVCP(0x10, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    }

    @Test func parsesReply() {
        // 6E 88 02 00 10 00 00 64 00 32 + checksum (seeded with 0x50): current 50, maximum 100.
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32]
        reply.append(reply.reduce(UInt8(0x50), ^))
        let value = DDCPacket.parseVCPReply(reply, code: 0x10)
        #expect(value?.current == 50)
        #expect(value?.maximum == 100)
    }

    @Test func rejectsBadChecksum() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00]
        #expect(DDCPacket.parseVCPReply(reply, code: 0x10) == nil)
    }

    @Test func rejectsUnsupportedCode() {
        // Result code 01: the monitor does not support the feature.
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32]
        reply.append(reply.reduce(UInt8(0x50), ^))
        #expect(DDCPacket.parseVCPReply(reply, code: 0x10) == nil)
    }
}
