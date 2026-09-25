import Foundation
import Testing
import DiskCore
@testable import StorageDaddy

private func file(_ id: Int, _ name: String, bytes: Int64) -> DiskNode {
    DiskNode(id: id, parent: 0, name: name, isDirectory: false, logicalBytes: bytes, allocatedBytes: bytes)
}

@Test func statsGroupByExtensionWithKindsAndLargest() {
    var stats = FileTypeStats()
    stats.insert(file(1, "a.dmg", bytes: 100), bytes: 100)
    stats.insert(file(2, "b.dmg", bytes: 300), bytes: 300)
    stats.insert(file(3, "notes.md", bytes: 10), bytes: 10)
    stats.insert(file(4, "Makefile", bytes: 5), bytes: 5)
    stats.insert(file(5, "model.safetensors", bytes: 50), bytes: 50)

    let rows = stats.sort(limit: 48)
    #expect(rows.map(\.ext) == ["dmg", "safetensors", "md", ""])
    #expect(rows[0].kind == .diskImages)
    #expect(rows[0].count == 2)
    #expect(rows[0].bytes == 400)
    #expect(rows[0].largestID == 2)
    #expect(rows[1].kind == .data)
    #expect(rows[2].kind == .documents)
    #expect(rows[3].name == "No extension")
    #expect(stats.totalFiles == 5)
    #expect(stats.totalBytes == 465)
    #expect(stats.overflowFiles == 0)
}

@Test func statsFoldOverflowIntoFooterCounters() {
    var stats = FileTypeStats()
    for i in 0..<10 {
        stats.insert(file(i, "f\(i).e\(i)", bytes: Int64(100 - i)), bytes: Int64(100 - i))
    }
    let rows = stats.sort(limit: 3)
    #expect(rows.count == 3)
    #expect(rows.map(\.bytes) == [100, 99, 98])
    #expect(stats.overflowFiles == 7)
    #expect(stats.overflowBytes == 97 + 96 + 95 + 94 + 93 + 92 + 91)
}

@Test func kindBucketsRecognizeInstallerAndArchiveExtensions() {
    #expect(FileKind(ext: "pkg") == .installers)
    #expect(FileKind(ext: "ipsw") == .installers)
    #expect(FileKind(ext: "zip") == .archives)
    #expect(FileKind(ext: "dmg") == .diskImages)
    #expect(FileKind(ext: "heic") == .media)
    #expect(FileKind(ext: "swift") == .code)
    #expect(FileKind(ext: "dylib") == .binaries)
    #expect(FileKind(ext: "xyzzy") == .other)
}
