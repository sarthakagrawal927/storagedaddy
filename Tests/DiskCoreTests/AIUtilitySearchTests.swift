import Foundation
import XCTest
@testable import DiskCore

final class AIUtilitySearchTests: XCTestCase {
    func testDistinguishesSessionsInTheSameProjectByIdentifier() {
        let first = session(id: "alpha-session-123")
        let second = session(id: "beta-session-456")
        XCTAssertTrue(first.matches(search: " ALPHA-SESSION-123\n"))
        XCTAssertFalse(second.matches(search: "alpha-session-123"))
        XCTAssertTrue(first.matches(search: "my-project"))
        XCTAssertTrue(first.matches(search: "codex"))
        XCTAssertTrue(first.matches(search: " \n"))
    }

    func testMissingIdentifierUsesFilenameAndStillFindsFullFilename() {
        let record = session(id: "  ", path: "/history/rollout-2026-unique.jsonl")
        XCTAssertEqual(record.historyIdentifier, "rollout-2026-unique")
        XCTAssertTrue(record.matches(search: "rollout-2026-unique.jsonl"))
        XCTAssertFalse(record.matches(search: "not-found"))
    }

    func testLongIdentifierRemainsSearchableAfterDisplayShortening() {
        let id = "12345678-1234-5678-90ab-123456789012"
        let record = session(id: id)
        XCTAssertEqual(record.historyIdentifier, id)
        XCTAssertLessThan(record.shortHistoryIdentifier.count, id.count)
        XCTAssertTrue(record.matches(search: "5678-90ab"))
    }

    private func session(id: String?, path: String = "/history/session.jsonl") -> AISessionRecord {
        AISessionRecord(path: path, provider: .codex, isArchived: false, project: "/repo/my-project", sessionID: id,
                        modified: .distantPast, allocatedBytes: 4096, logicalBytes: 100)
    }

}
