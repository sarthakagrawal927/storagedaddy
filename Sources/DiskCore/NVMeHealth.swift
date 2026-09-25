import Foundation
import IOKit

/// Reads the NVMe SMART/health log through the NVMeSMARTLib plugin that
/// IOEmbeddedNVMeBlockDevice exposes via IOCFPlugInTypes (the same path
/// smartmontools uses). All constants come from the private-but-stable
/// NVMeSMARTLibExternal interface. Everything fails closed: a missing
/// capability, plugin or read error yields nil, never a guessed value.
public enum NVMeHealthReader {

    // NVMeSMARTLibExternal: plugin type UUID AA0FA6F9-C2D6-457F-B10B-59A13253292F
    private static var plugInType: CFUUID { CFUUIDGetConstantUUIDWithBytes(nil,
        0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)! }
    // Interface ID CCD1DB19-FD9A-4DAF-BF95-12454B230AB6
    private static var interfaceID: CFUUID { CFUUIDGetConstantUUIDWithBytes(nil,
        0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, 0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)! }
    // kIOCFPlugInInterfaceID C244E858-109C-11D4-91D4-0050E4C6426F
    private static var plugInInterfaceID: CFUUID { CFUUIDGetConstantUUIDWithBytes(nil,
        0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)! }

    private typealias QueryInterfaceFn = @convention(c) (UnsafeMutableRawPointer?, CFUUIDBytes, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    private typealias RefFn = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
    private typealias SMARTReadFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32

    /// Mirrors IONVMeSMARTInterface from NVMeSMARTLibExternal.h up to the
    /// members we use. Layout must match: reserved pointer, IUnknown entry
    /// points, version/revision, then the SMART read entry point. The kernel
    /// side only indexes fields that exist on both sides.
    private struct IONVMeSMARTInterface {
        var reserved: UnsafeMutableRawPointer?
        var queryInterface: QueryInterfaceFn?
        var addRef: RefFn?
        var release: RefFn?
        var version: UInt16 = 0
        var revision: UInt16 = 0
        var smartReadData: SMARTReadFn?
    }

    public static let logPageSize = 512

    /// Read the SMART/health log for each SMART-capable NVMe block device.
    /// Devices without the capability, without the plugin, or with a failed
    /// read are skipped entirely.
    public static func collect() -> [NVMeHealthInfo] {
        var results: [NVMeHealthInfo] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOEmbeddedNVMeBlockDevice"), &iterator) == kIOReturnSuccess else { return results }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard IORegistryEntryCreateCFProperty(service, "NVMe SMART Capable" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() != nil else { continue }
            let characteristics = IORegistryEntryCreateCFProperty(service, "Device Characteristics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            let product = (characteristics?["Product Name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            // Virtual DMG devices also report NVMe SMART capability; skip them.
            if product == "Disk Image" { continue }
            guard let handle = openInterface(service) else { continue }
            let log = UnsafeMutableRawBufferPointer.allocate(byteCount: logPageSize, alignment: 8)
            log.initializeMemory(as: UInt8.self, repeating: 0)
            let status = handle.interface.pointee.smartReadData?(handle.handle, log.baseAddress) ?? kIOReturnError
            if status == kIOReturnSuccess {
                results.append(parse(log: UnsafeRawBufferPointer(log), deviceName: product.isEmpty ? "NVMe device" : product))
            }
            log.deallocate()
            _ = handle.interface.pointee.release?(handle.handle)
            IODestroyPlugInInterface(handle.plugin)
        }
        return results
    }

    /// IOCreatePlugInInterfaceForService returns a handle (a pointer to the
    /// interface pointer). The vtable functions take that handle as `this`.
    private static func openInterface(_ service: io_service_t) -> (plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>, handle: UnsafeMutableRawPointer, interface: UnsafeMutablePointer<IONVMeSMARTInterface>)? {
        var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(service, plugInType, plugInInterfaceID, &plugin, &score) == kIOReturnSuccess,
              let plugin, let plugInStruct = plugin.pointee else { return nil }
        var raw: UnsafeMutableRawPointer?
        let status = plugInStruct.pointee.QueryInterface(UnsafeMutableRawPointer(plugin), CFUUIDGetUUIDBytes(interfaceID), &raw)
        guard status == kIOReturnSuccess, let raw else {
            IODestroyPlugInInterface(plugin)
            return nil
        }
        let interface = raw.assumingMemoryBound(to: UnsafeMutablePointer<IONVMeSMARTInterface>.self).pointee
        guard interface.pointee.smartReadData != nil else {
            _ = interface.pointee.release?(raw)
            IODestroyPlugInInterface(plugin)
            return nil
        }
        return (plugin, raw, interface)
    }

    // MARK: - NVMe SMART log parsing (pure, testable)

    /// Parse a 512-byte NVMe SMART / Health Information log (log page 0x02).
    static func parse(log: UnsafeRawBufferPointer, deviceName: String) -> NVMeHealthInfo {
        let b = log.bindMemory(to: UInt8.self)
        func u128le(_ offset: Int) -> UInt64 {
            // NVMe uses 128-bit little-endian counters; read the low 64 bits
            // and saturate if the high half is non-zero.
            var value: UInt64 = 0
            for i in stride(from: 7, through: 0, by: -1) { value = value << 8 | UInt64(b[offset + i]) }
            for i in 8..<16 where b[offset + i] != 0 { return UInt64.max }
            return value
        }
        func u32le(_ offset: Int) -> UInt32 {
            UInt32(b[offset]) | UInt32(b[offset + 1]) << 8 | UInt32(b[offset + 2]) << 16 | UInt32(b[offset + 3]) << 24
        }
        let tempKelvin = u32le(1) & 0xFFFF
        // NVMe reports data units in thousands of 512-byte units.
        let unitBytes: UInt64 = 512_000
        let readUnits = u128le(32), writeUnits = u128le(48)
        return NVMeHealthInfo(
            deviceName: deviceName,
            criticalWarning: b[0],
            temperatureCelsius: tempKelvin == 0 ? nil : Double(tempKelvin) - 273.15,
            availableSparePercent: Int(b[3]),
            availableSpareThreshold: Int(b[4]),
            percentUsed: Int(b[5]),
            dataReadBytes: readUnits == .max ? nil : readUnits &* unitBytes,
            dataWrittenBytes: writeUnits == .max ? nil : writeUnits &* unitBytes,
            powerCycles: u128le(112),
            powerOnHours: u128le(128),
            unsafeShutdowns: u128le(144),
            mediaErrors: u128le(160),
            errorLogEntries: u128le(176),
            warningTemperatureMinutes: u32le(192) == .max ? nil : u32le(192),
            criticalTemperatureMinutes: u32le(196) == .max ? nil : u32le(196)
        )
    }
}

public struct NVMeHealthInfo: Sendable, Equatable {
    public var deviceName: String
    /// NVMe critical-warning bitmask: bit 0 spare below threshold, bit 2
    /// reliability degraded, bit 5 media read-only.
    public var criticalWarning: UInt8
    public var temperatureCelsius: Double?
    public var availableSparePercent: Int
    public var availableSpareThreshold: Int
    /// SMART "Percentage Used": the drive's own endurance wear estimate.
    public var percentUsed: Int
    public var dataReadBytes: UInt64?
    public var dataWrittenBytes: UInt64?
    public var powerCycles: UInt64
    public var powerOnHours: UInt64
    public var unsafeShutdowns: UInt64
    public var mediaErrors: UInt64
    public var errorLogEntries: UInt64
    public var warningTemperatureMinutes: UInt32?
    public var criticalTemperatureMinutes: UInt32?

    public var isHealthy: Bool { criticalWarning == 0 && mediaErrors == 0 }

    public var warningDescriptions: [String] {
        var warnings: [String] = []
        if criticalWarning & 0x01 != 0 { warnings.append("Available spare below threshold") }
        if criticalWarning & 0x02 != 0 { warnings.append("Temperature warning") }
        if criticalWarning & 0x04 != 0 { warnings.append("Reliability degraded") }
        if criticalWarning & 0x08 != 0 { warnings.append("Media in read-only mode") }
        if criticalWarning & 0x10 != 0 { warnings.append("Volatile memory backup failed") }
        if criticalWarning & 0x20 != 0 { warnings.append("Persistent memory region read-only") }
        if mediaErrors > 0 { warnings.append("\(mediaErrors) media \(mediaErrors == 1 ? "error" : "errors") logged") }
        return warnings
    }

    public var statusLabel: String { isHealthy ? "Verified" : "Needs attention" }
}
