import XCTest
@testable import OpenLessApp

final class TCCPermissionResetterTests: XCTestCase {
    func test_resetAllClearsEveryTCCServiceForBundleIdentifier() {
        var resetCalls: [(service: String, bundleIdentifier: String)] = []
        let resetter = TCCPermissionResetter(
            bundleIdentifier: "com.example.openless",
            resetService: { service, bundleIdentifier in
                resetCalls.append((service, bundleIdentifier))
            }
        )

        resetter.resetAll()

        XCTAssertEqual(resetCalls.map(\.service), [
            "Accessibility",
            "Microphone",
            "AppleEvents",
            "ListenEvent",
        ])
        XCTAssertEqual(resetCalls.map(\.bundleIdentifier), Array(repeating: "com.example.openless", count: 4))
    }
}
