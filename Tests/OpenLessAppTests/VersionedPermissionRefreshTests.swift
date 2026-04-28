import XCTest
@testable import OpenLessApp

final class VersionedPermissionRefreshTests: XCTestCase {
    func test_resetIfNeededClearsPermissionsAndStoresCurrentVersionWhenVersionChanged() {
        let defaults = makeDefaults()
        defaults.set("1.0.0#1", forKey: VersionedPermissionRefresh.lastResetVersionKey)
        var didReset = false

        let refresh = VersionedPermissionRefresh(
            currentVersion: "1.0.1#2",
            defaults: defaults,
            resetter: TCCPermissionResetter(resetService: { _, _ in didReset = true }),
            isRunningFromAppBundle: true
        )

        refresh.resetIfNeeded()

        XCTAssertTrue(didReset)
        XCTAssertEqual(defaults.string(forKey: VersionedPermissionRefresh.lastResetVersionKey), "1.0.1#2")
    }

    func test_resetIfNeededDoesNothingWhenVersionWasAlreadyHandled() {
        let defaults = makeDefaults()
        defaults.set("1.0.1#2", forKey: VersionedPermissionRefresh.lastResetVersionKey)
        var resetCount = 0

        let refresh = VersionedPermissionRefresh(
            currentVersion: "1.0.1#2",
            defaults: defaults,
            resetter: TCCPermissionResetter(resetService: { _, _ in resetCount += 1 }),
            isRunningFromAppBundle: true
        )

        refresh.resetIfNeeded()

        XCTAssertEqual(resetCount, 0)
        XCTAssertEqual(defaults.string(forKey: VersionedPermissionRefresh.lastResetVersionKey), "1.0.1#2")
    }

    func test_resetIfNeededSkipsWhenNotRunningFromAppBundle() {
        let defaults = makeDefaults()
        var resetCount = 0

        let refresh = VersionedPermissionRefresh(
            currentVersion: "1.0.1#2",
            defaults: defaults,
            resetter: TCCPermissionResetter(resetService: { _, _ in resetCount += 1 }),
            isRunningFromAppBundle: false
        )

        refresh.resetIfNeeded()

        XCTAssertEqual(resetCount, 0)
        XCTAssertNil(defaults.string(forKey: VersionedPermissionRefresh.lastResetVersionKey))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "OpenLessAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
