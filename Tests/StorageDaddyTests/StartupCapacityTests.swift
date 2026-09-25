@testable import DiskCore
import Testing
@testable import StorageDaddy

private func volume(path: String, total: Int64?, available: Int64?) -> MountedVolumeInfo {
    MountedVolumeInfo(
        name: path, mountPoint: path, fsType: "apfs", bsdName: "disk3s1",
        totalCapacity: total, availableCapacity: available, importantAvailableCapacity: nil,
        isStartupData: path == "/System/Volumes/Data", isSystem: path == "/",
        isInternal: true, isRemovable: false, isEjectable: false, isReadOnly: false,
        isNetwork: false, isEncrypted: nil, isDiskImage: false, apfsContainer: "disk3"
    )
}

@Test func welcomeCapacityUsesStartupDataWithoutCountingTheSystemVolumeTwice() throws {
    let capacity = try #require(StartupCapacity(volumes: [
        volume(path: "/", total: 1_000, available: 400),
        volume(path: "/System/Volumes/Data", total: 1_000, available: 375),
    ]))
    #expect(capacity.total == 1_000)
    #expect(capacity.used == 625)
    #expect(capacity.usedPercent == 63)
    #expect(capacity.availablePercent == 37)
}

@Test func welcomeCapacityOmitsInvalidMeasurements() {
    #expect(StartupCapacity(volumes: []) == nil)
    #expect(StartupCapacity(volumes: [volume(path: "/", total: 0, available: 0)]) == nil)
    #expect(StartupCapacity(volumes: [volume(path: "/", total: 100, available: 110)]) == nil)
}
