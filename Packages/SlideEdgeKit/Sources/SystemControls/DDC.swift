import CoreGraphics
import Darwin
import Foundation
import IOKit

/// DDC/CI messages (VESA MCCS over I²C). Pure, so the byte layout is unit-tested.
enum DDCPacket {
    /// VCP code of the luminance (brightness) control.
    static let brightness: UInt8 = 0x10

    /// Bytes after the source address 0x51: length, payload, checksum.
    /// The checksum XORs the destination (0x6E) and source (0x51) addresses with every byte.
    static func message(_ payload: [UInt8]) -> [UInt8] {
        var packet = [0x80 | UInt8(payload.count)] + payload
        packet.append(packet.reduce(UInt8(0x6E ^ 0x51), ^))
        return packet
    }

    /// "Get VCP feature" request.
    static func getVCP(_ code: UInt8) -> [UInt8] {
        message([0x01, code])
    }

    /// "Set VCP feature" request.
    static func setVCP(_ code: UInt8, value: UInt16) -> [UInt8] {
        message([0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Parses an 11-byte "Get VCP feature" reply into (current, maximum).
    static func parseVCPReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count == 11 else { return nil }
        // The reply checksum uses 0x50, the host's virtual address.
        let checksum = reply.dropLast().reduce(UInt8(0x50), ^)
        guard checksum == reply[10], reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return maximum > 0 ? (current, maximum) : nil
    }
}

/// An external monitor reachable over DDC/CI. Apple Silicon only (private IOAVService I²C calls).
/// Calls block for tens of milliseconds: use them off the main thread.
final class DDCDisplay: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    private let service: CFTypeRef
    private(set) var maximum: UInt16 = 100

    private init(displayID: CGDirectDisplayID, service: CFTypeRef) {
        self.displayID = displayID
        self.service = service
    }

    /// The DDC connection for `displayID`, or nil when it is built-in, not found, or does not answer.
    static func connect(to displayID: CGDirectDisplayID) -> DDCDisplay? {
        guard CGDisplayIsBuiltin(displayID) == 0, let functions = IOAV.functions else { return nil }
        guard let service = IOAV.service(for: displayID, functions: functions) else { return nil }
        let display = DDCDisplay(displayID: displayID, service: service)
        // A display that does not answer a brightness read is treated as not controllable.
        return display.readBrightness() != nil ? display : nil
    }

    /// 0...1, nil when the monitor does not answer.
    func readBrightness() -> Double? {
        let request = DDCPacket.getVCP(DDCPacket.brightness)
        guard let reply = exchange(request, replyLength: 11, isValid: { DDCPacket.parseVCPReply($0, code: DDCPacket.brightness) != nil }),
              let value = DDCPacket.parseVCPReply(reply, code: DDCPacket.brightness)
        else { return nil }
        maximum = value.maximum
        return min(Double(value.current) / Double(value.maximum), 1)
    }

    @discardableResult
    func writeBrightness(_ level: Double) -> Bool {
        let value = UInt16((min(max(level, 0), 1) * Double(maximum)).rounded())
        return exchange(DDCPacket.setVCP(DDCPacket.brightness, value: value), replyLength: 0) != nil
    }

    /// Writes a request (twice, as many monitors miss the first) and optionally reads a reply
    /// that passes `isValid`, retrying a few times.
    private func exchange(_ request: [UInt8], replyLength: Int, isValid: ([UInt8]) -> Bool = { _ in true }) -> [UInt8]? {
        guard let functions = IOAV.functions else { return nil }
        var request = request
        for _ in 0..<3 {
            var written = false
            for _ in 0..<2 {
                usleep(10_000)
                if functions.write(service, IOAV.chipAddress, IOAV.sourceAddress, &request, UInt32(request.count)) == kIOReturnSuccess {
                    written = true
                }
            }
            if written && replyLength == 0 { return [] }
            if written {
                usleep(50_000)
                var reply = [UInt8](repeating: 0, count: replyLength)
                if functions.read(service, IOAV.chipAddress, IOAV.sourceAddress, &reply, UInt32(replyLength)) == kIOReturnSuccess,
                   isValid(reply) {
                    return reply
                }
            }
            usleep(20_000)
        }
        return nil
    }
}

// MARK: - IOAVService (private IOKit)

private enum IOAV {
    static let chipAddress: UInt32 = 0x37
    static let sourceAddress: UInt32 = 0x51

    typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    struct Functions: @unchecked Sendable {
        let create: CreateWithService
        let read: Transfer
        let write: Transfer
    }

    static let functions: Functions? = {
        #if arch(arm64)
        guard
            let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
            let create = dlsym(handle, "IOAVServiceCreateWithService"),
            let read = dlsym(handle, "IOAVServiceReadI2C"),
            let write = dlsym(handle, "IOAVServiceWriteI2C")
        else { return nil }
        return Functions(
            create: unsafeBitCast(create, to: CreateWithService.self),
            read: unsafeBitCast(read, to: Transfer.self),
            write: unsafeBitCast(write, to: Transfer.self)
        )
        #else
        return nil  // Intel Macs use a different I²C path, not implemented.
        #endif
    }()

    /// An external AV service found in the registry, with the attributes of the framebuffer before it.
    private struct Candidate {
        let service: CFTypeRef
        let vendor: UInt32?
        let serial: UInt32?
    }

    /// Finds the AV service of `displayID`. In the IOService plane each external
    /// `DCPAVServiceProxy` follows the framebuffer (AppleCLCD2 / IOMobileFramebufferShim)
    /// of its display, whose "DisplayAttributes" identify the monitor.
    static func service(for displayID: CGDirectDisplayID, functions: Functions) -> CFTypeRef? {
        let candidates = externalCandidates(functions: functions)
        guard !candidates.isEmpty else { return nil }

        let vendor = CGDisplayVendorNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        var matches = candidates.filter { $0.vendor == vendor }
        if matches.count > 1, serial != 0 {
            matches = matches.filter { $0.serial == serial }
        }
        if matches.count == 1 { return matches[0].service }

        // Attributes missing or ambiguous: only pair when there is a single external display.
        let externalDisplays = activeDisplays().filter { CGDisplayIsBuiltin($0) == 0 }
        if candidates.count == 1, externalDisplays.count == 1 { return candidates[0].service }
        return nil
    }

    private static func externalCandidates(functions: Functions) -> [Candidate] {
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [Candidate] = []
        var framebufferAttributes: [String: Any]?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuffer)
            let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)

            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                let attributes = property(entry, "DisplayAttributes") as? [String: Any]
                framebufferAttributes = attributes?["ProductAttributes"] as? [String: Any]
            } else if name == "DCPAVServiceProxy" {
                defer { framebufferAttributes = nil }
                guard property(entry, "Location") as? String == "External",
                      let service = functions.create(kCFAllocatorDefault, entry)?.takeRetainedValue()
                else { continue }
                candidates.append(Candidate(
                    service: service,
                    vendor: (framebufferAttributes?["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
                    serial: (framebufferAttributes?["SerialNumber"] as? NSNumber)?.uint32Value
                ))
            }
        }
        return candidates
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
    return Array(displays.prefix(Int(count)))
}
