import XCTest
@testable import DiskCore

final class SystemInventoryTests: XCTestCase {

    // MARK: - APFS container naming

    func testAPFSContainerName() {
        XCTAssertEqual(SystemInventory.apfsContainerName(fsType: "apfs", bsdName: "disk3s1s1"), "disk3")
        XCTAssertEqual(SystemInventory.apfsContainerName(fsType: "apfs", bsdName: "disk3s5"), "disk3")
        XCTAssertEqual(SystemInventory.apfsContainerName(fsType: "apfs", bsdName: "disk10s2"), "disk10")
        XCTAssertNil(SystemInventory.apfsContainerName(fsType: "exfat", bsdName: "disk4s1"))
        XCTAssertNil(SystemInventory.apfsContainerName(fsType: "apfs", bsdName: ""))
        XCTAssertNil(SystemInventory.apfsContainerName(fsType: "apfs", bsdName: "smbfs://share"))
    }

    func testNetworkFilesystems() {
        XCTAssertTrue(SystemInventory.networkFilesystems.contains("smbfs"))
        XCTAssertTrue(SystemInventory.networkFilesystems.contains("nfs"))
        XCTAssertFalse(SystemInventory.networkFilesystems.contains("apfs"))
        XCTAssertFalse(SystemInventory.networkFilesystems.contains("exfat"))
    }

    // MARK: - Volume display

    private func volume(fsType: String = "apfs", available: Int64? = 100, important: Int64? = 130) -> MountedVolumeInfo {
        MountedVolumeInfo(
            name: "Test", mountPoint: "/Volumes/Test", fsType: fsType, bsdName: "disk4s1",
            totalCapacity: 1000, availableCapacity: available, importantAvailableCapacity: important,
            isStartupData: false, isSystem: false, isInternal: false, isRemovable: true,
            isEjectable: true, isReadOnly: false, isNetwork: false, isEncrypted: false,
            isDiskImage: false, apfsContainer: nil
        )
    }

    func testPurgeableCapacity() {
        XCTAssertEqual(volume().purgeableCapacity, 30)
        XCTAssertEqual(volume(important: 90).purgeableCapacity, 0)
        XCTAssertNil(volume(available: nil, important: nil).purgeableCapacity)
    }

    func testFSDisplayName() {
        XCTAssertEqual(volume(fsType: "apfs").fsDisplayName, "APFS")
        XCTAssertEqual(volume(fsType: "exfat").fsDisplayName, "exFAT")
        XCTAssertEqual(volume(fsType: "smbfs").fsDisplayName, "SMB")
        XCTAssertEqual(volume(fsType: "weirdfs").fsDisplayName, "weirdfs")
        XCTAssertEqual(volume(fsType: "").fsDisplayName, "Unknown")
    }

    func testContainerGrouping() {
        var report = SystemStorageReport(collectedAt: Date(), volumes: [], containers: [], devices: [], pressure: PressureInfo())
        var data = volume()
        data.name = "Macintosh HD – Data"; data.mountPoint = "/System/Volumes/Data"
        data.bsdName = "disk3s5"; data.apfsContainer = "disk3"; data.totalCapacity = 500; data.availableCapacity = 120
        var system = volume()
        system.name = "Macintosh HD"; system.mountPoint = "/"
        system.bsdName = "disk3s1s1"; system.apfsContainer = "disk3"; system.totalCapacity = 500; system.availableCapacity = 120
        var external = volume(fsType: "exfat")
        external.name = "USB"; external.mountPoint = "/Volumes/USB"; external.bsdName = "disk4s1"
        report.volumes = [data, system, external]
        let grouped = report.withContainers()
        XCTAssertEqual(grouped.containers.count, 1)
        XCTAssertEqual(grouped.containers[0].name, "disk3")
        XCTAssertEqual(grouped.containers[0].totalCapacity, 500)
        XCTAssertEqual(grouped.containers[0].freeCapacity, 120)
        XCTAssertEqual(grouped.containers[0].usedCapacity, 380)
        XCTAssertEqual(grouped.containers[0].volumeNames.count, 2)
    }

    // MARK: - NVMe SMART log parsing

    private func makeLog() -> [UInt8] {
        var log = [UInt8](repeating: 0, count: 512)
        log[0] = 0                       // critical warning
        log[1] = 0x41; log[2] = 0x01     // 321 K ≈ 47.85 °C
        log[3] = 100                     // available spare %
        log[4] = 99                      // spare threshold
        log[5] = 9                       // percent used
        // data units read = 2, written = 3 (little-endian u128)
        log[32] = 2; log[48] = 3
        log[112] = 10                    // power cycles
        log[128] = 0x58; log[129] = 0x02 // 600 power-on hours
        log[144] = 5                     // unsafe shutdowns
        log[160] = 0                     // media errors
        log[176] = 7                     // error log entries
        return log
    }

    func testNVMeSMARTParse() {
        var bytes = makeLog()
        let info = bytes.withUnsafeMutableBytes { raw in
            NVMeHealthReader.parse(log: UnsafeRawBufferPointer(raw), deviceName: "APPLE SSD TEST")
        }
        XCTAssertEqual(info.deviceName, "APPLE SSD TEST")
        XCTAssertEqual(info.criticalWarning, 0)
        XCTAssertEqual(info.temperatureCelsius!, 47.85, accuracy: 0.01)
        XCTAssertEqual(info.availableSparePercent, 100)
        XCTAssertEqual(info.availableSpareThreshold, 99)
        XCTAssertEqual(info.percentUsed, 9)
        XCTAssertEqual(info.dataReadBytes, 2 * 512_000)
        XCTAssertEqual(info.dataWrittenBytes, 3 * 512_000)
        XCTAssertEqual(info.powerCycles, 10)
        XCTAssertEqual(info.powerOnHours, 600)
        XCTAssertEqual(info.unsafeShutdowns, 5)
        XCTAssertEqual(info.mediaErrors, 0)
        XCTAssertEqual(info.errorLogEntries, 7)
        XCTAssertTrue(info.isHealthy)
        XCTAssertEqual(info.statusLabel, "Verified")
        XCTAssertTrue(info.warningDescriptions.isEmpty)
    }

    func testNVMeSMARTWarnings() {
        var bytes = makeLog()
        bytes[0] = 0x01 | 0x20 // spare below threshold + PMR read-only
        bytes[160] = 3         // 3 media errors
        let info = bytes.withUnsafeMutableBytes { raw in
            NVMeHealthReader.parse(log: UnsafeRawBufferPointer(raw), deviceName: "d")
        }
        XCTAssertFalse(info.isHealthy)
        XCTAssertEqual(info.statusLabel, "Needs attention")
        XCTAssertEqual(info.warningDescriptions.count, 3)
        XCTAssertTrue(info.warningDescriptions.contains("Available spare below threshold"))
        XCTAssertTrue(info.warningDescriptions.contains("Persistent memory region read-only"))
        XCTAssertTrue(info.warningDescriptions.contains("3 media errors logged"))
    }

    func testNVMeSMARTU128SaturationAndZeroTemp() {
        var bytes = makeLog()
        bytes[1] = 0; bytes[2] = 0       // temperature 0K → nil
        bytes[32 + 15] = 0xFF            // high byte set → saturate read units
        let info = bytes.withUnsafeMutableBytes { raw in
            NVMeHealthReader.parse(log: UnsafeRawBufferPointer(raw), deviceName: "d")
        }
        XCTAssertNil(info.temperatureCelsius)
        XCTAssertNil(info.dataReadBytes)
        XCTAssertEqual(info.dataWrittenBytes, 3 * 512_000)
    }

    // MARK: - Live probes (host-dependent but should never crash)

    func testMountedVolumesOnThisMac() {
        let volumes = SystemInventory.mountedVolumes()
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertTrue(volumes.contains { $0.isStartupData || $0.mountPoint == "/" })
    }

    func testPressureProbe() {
        let pressure = PressureProbe.collect()
        XCTAssertNotNil(pressure.swapTotalBytes)
        XCTAssertNotNil(pressure.memoryHeadroomPercent)
        XCTAssertNotNil(pressure.bootTime)
        XCTAssertNotNil(pressure.localSnapshotNames)
    }
}
