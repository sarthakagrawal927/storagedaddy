import Foundation
import XCTest
@testable import DiskCore

final class ProjectDependencyDiscoveryTests: XCTestCase {
    func testPromptAvoidanceOmitsProtectedRootBeforeWalkingIt() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let desktop = home.appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: desktop.appendingPathComponent("project/node_modules"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("code/node_modules"), withIntermediateDirectories: true)

        let result = try await ProjectDependencyDiscovery.discover(
            home: home, promptAvoidanceFolders: [desktop.path]
        )

        XCTAssertEqual(result.paths, [home.appendingPathComponent("code/node_modules").path])
        XCTAssertEqual(result.skippedDirectories, 1)
        XCTAssertTrue(result.complete)
    }

    func testFindsVisibleProjectDependenciesWithoutFollowingLinksOrExcludedFolders() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let files = FileManager.default
        for path in ["Desktop/workspace/app/node_modules/nested/node_modules", "Documents/other/node_modules", "Library/Caches/node_modules", ".private/project/node_modules", "Desktop/excluded/node_modules", "Desktop/workspace/.worktrees/branch/node_modules"] {
            try files.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try files.createSymbolicLink(at: home.appendingPathComponent("Desktop/link"), withDestinationURL: home.appendingPathComponent("Documents"))

        let result = try await ProjectDependencyDiscovery.discover(
            home: home, excludedFolders: [home.appendingPathComponent("Desktop/excluded").path]
        )

        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.paths, [
            home.appendingPathComponent("Desktop/workspace/.worktrees/branch/node_modules").path,
            home.appendingPathComponent("Desktop/workspace/app/node_modules").path,
            home.appendingPathComponent("Documents/other/node_modules").path
        ])
        XCTAssertGreaterThan(result.skippedDirectories, 0)
    }

    func testReportsWhenDirectoryLimitEndsSearch() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("project/node_modules"), withIntermediateDirectories: true)

        let result = try await ProjectDependencyDiscovery.discover(home: home, directoryLimit: 1)

        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.directoriesVisited, 1)
    }
}
