import AppKit
import CoreGraphics
import IOKit

// Private IOKit symbols used for DDC/CI over I2C on Apple Silicon, the same
// approach MonitorControl and m1ddc use. Not App Store safe by design.
typealias IOAVServiceRef = CFTypeRef

/// Resolved with `dlsym` rather than hard-linked via `@_silgen_name`: if a
/// macOS update drops these private symbols, a hard link fails the whole app
/// at launch, while this only turns DDC off. The `@convention(c)` types also
/// give the calls the C ABI they actually have.
enum IOAVService {
    typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<IOAVServiceRef>?
    typealias TransferI2C = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    struct Functions: @unchecked Sendable {
        let create: CreateWithService
        let readI2C: TransferI2C
        let writeI2C: TransferI2C
    }

    /// Nil when any symbol is missing; DDC then reports no capable displays.
    static let functions: Functions? = {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = dlsym(iokit, "IOAVServiceCreateWithService"),
              let read = dlsym(iokit, "IOAVServiceReadI2C"),
              let write = dlsym(iokit, "IOAVServiceWriteI2C")
        else { return nil }
        return Functions(
            create: unsafeBitCast(create, to: CreateWithService.self),
            readI2C: unsafeBitCast(read, to: TransferI2C.self),
            writeI2C: unsafeBitCast(write, to: TransferI2C.self)
        )
    }()
}

/// Snapshot of one external display handed to the UI layer.
struct DDCDisplayInfo: Identifiable, Sendable {
    let id: CGDirectDisplayID
    let name: String
    let supportsDDC: Bool
    /// Current brightness as 0...100 percent (50 when unreadable).
    let brightnessPercent: Int
}

/// Owns the IOAVService handles and serializes all I2C traffic.
actor DDCService {
    static let shared = DDCService()

    private enum VCP {
        static let brightness: UInt8 = 0x10
    }

    private var services: [CGDirectDisplayID: IOAVServiceRef] = [:]
    /// VCP max value per display, learned from the first successful read.
    private var maxValues: [CGDirectDisplayID: Int] = [:]

    // MARK: Discovery

    /// Matches DCPAVServiceProxy registry entries to the given external
    /// displays (by EDID UUID, falling back to a 1:1 pairing) and reads the
    /// current brightness of each.
    ///
    /// Deliberately free of suspension points: the actor is reentrant across
    /// an `await`, so a brightness write could otherwise land between a read
    /// request and its reply, or hit a half-built `services` map.
    func refresh(displays: [(id: CGDirectDisplayID, name: String)]) -> [DDCDisplayInfo] {
        var matched: [CGDirectDisplayID: IOAVServiceRef] = [:]
        var avServices = externalAVServices()
        for display in displays {
            let uuid = Self.uuidString(for: display.id)
            if let index = avServices.firstIndex(where: { $0.edidUUID != nil && $0.edidUUID!.caseInsensitiveCompare(uuid ?? "") == .orderedSame }) {
                matched[display.id] = avServices.remove(at: index).service
            }
        }
        let unmatched = displays.filter { matched[$0.id] == nil }
        if unmatched.count == 1, avServices.count == 1 {
            matched[unmatched[0].id] = avServices[0].service
        }
        services = matched

        var infos: [DDCDisplayInfo] = []
        for display in displays {
            guard services[display.id] != nil else {
                infos.append(DDCDisplayInfo(id: display.id, name: display.name, supportsDDC: false, brightnessPercent: 50))
                continue
            }
            if let (current, max) = readVCP(VCP.brightness, display: display.id), max > 0 {
                maxValues[display.id] = max
                infos.append(DDCDisplayInfo(
                    id: display.id,
                    name: display.name,
                    supportsDDC: true,
                    brightnessPercent: DDCPacket.percent(current: current, max: max)
                ))
            } else {
                // Writes may still work on monitors that reject reads.
                maxValues[display.id] = 100
                infos.append(DDCDisplayInfo(id: display.id, name: display.name, supportsDDC: true, brightnessPercent: 50))
            }
        }
        return infos
    }

    private func externalAVServices() -> [(edidUUID: String?, service: IOAVServiceRef)] {
        guard let io = IOAVService.functions else { return [] }
        var result: [(String?, IOAVServiceRef)] = []
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard registryString(entry, key: "Location") == "External",
                  let service = io.create(kCFAllocatorDefault, entry)?.takeRetainedValue()
            else { continue }
            result.append((registryString(entry, key: "EDID UUID"), service))
        }
        return result
    }

    private func registryString(_ entry: io_service_t, key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func uuidString(for display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }

    // MARK: DDC I/O

    func setBrightnessPercent(_ percent: Int, display: CGDirectDisplayID) {
        let max = maxValues[display] ?? 100
        writeVCP(VCP.brightness, value: percent * max / 100, display: display)
    }

    private func writeVCP(_ code: UInt8, value: Int, display: CGDirectDisplayID) {
        guard let service = services[display], let io = IOAVService.functions else { return }
        var packet = DDCPacket.setVCP(code, value: value)
        _ = packet.withUnsafeMutableBytes { buffer in
            io.writeI2C(service, DDCPacket.chipAddress, DDCPacket.hostAddress, buffer.baseAddress!, UInt32(buffer.count))
        }
    }

    /// Blocks the actor for the reply delay (a plain `usleep`, not
    /// `Task.sleep`) so no other I2C transaction can interleave.
    private func readVCP(_ code: UInt8, display: CGDirectDisplayID) -> (current: Int, max: Int)? {
        guard let service = services[display], let io = IOAVService.functions else { return nil }
        var request = DDCPacket.readRequest(code)

        for _ in 0..<3 {
            let wrote = request.withUnsafeMutableBytes { buffer in
                io.writeI2C(service, DDCPacket.chipAddress, DDCPacket.hostAddress, buffer.baseAddress!, UInt32(buffer.count))
            }
            guard wrote == kIOReturnSuccess else { continue }
            usleep(15_000)

            var reply = [UInt8](repeating: 0, count: 12)
            let read = reply.withUnsafeMutableBytes { buffer in
                io.readI2C(service, DDCPacket.chipAddress, DDCPacket.hostAddress, buffer.baseAddress!, UInt32(buffer.count))
            }
            guard read == kIOReturnSuccess, let parsed = DDCPacket.parseReply(reply, code: code) else { continue }
            return parsed
        }
        return nil
    }
}
