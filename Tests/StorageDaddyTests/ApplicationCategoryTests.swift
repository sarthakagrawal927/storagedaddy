import XCTest
@testable import StorageDaddy

final class ApplicationCategoryTests: XCTestCase {
    func testExistingDaddyAppsWithMissingMetadataAreUtilities() {
        XCTAssertEqual(ApplicationCategory.title(for: nil, bundleIdentifier: "com.significanthobbies.performancedaddy"), "Utilities")
        XCTAssertEqual(ApplicationCategory.title(for: nil, bundleIdentifier: "com.significanthobbies.browserdaddy"), "Utilities")
        XCTAssertEqual(ApplicationCategory.title(for: nil, bundleIdentifier: "com.example.other"), "Uncategorized")
    }

    func testDeclaredCategoryStillWins() {
        XCTAssertEqual(ApplicationCategory.title(for: "public.app-category.utilities", bundleIdentifier: "com.significanthobbies.browserdaddy"), "Utilities")
        XCTAssertEqual(ApplicationCategory.title(for: "public.app-category.developer-tools", bundleIdentifier: "com.significanthobbies.browserdaddy"), "Developer Tools")
    }
}
