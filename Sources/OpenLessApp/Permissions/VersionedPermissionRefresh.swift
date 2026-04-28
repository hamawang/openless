import Foundation

struct VersionedPermissionRefresh {
    static let lastResetVersionKey = "openless.permissions.last_tcc_reset_version"

    let currentVersion: String
    let defaults: UserDefaults
    let resetter: TCCPermissionResetter
    let isRunningFromAppBundle: Bool

    init(
        currentVersion: String = VersionedPermissionRefresh.currentBundleVersion(),
        defaults: UserDefaults = .standard,
        resetter: TCCPermissionResetter = TCCPermissionResetter(),
        isRunningFromAppBundle: Bool = VersionedPermissionRefresh.isRunningFromAppBundle()
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.resetter = resetter
        self.isRunningFromAppBundle = isRunningFromAppBundle
    }

    func resetIfNeeded() {
        guard isRunningFromAppBundle else {
            Log.write("[permissions] skip versioned TCC reset outside app bundle")
            return
        }

        guard defaults.string(forKey: Self.lastResetVersionKey) != currentVersion else {
            return
        }

        Log.write("[permissions] bundle version changed; clearing old TCC approvals before permission onboarding")
        resetter.resetAll()
        defaults.set(currentVersion, forKey: Self.lastResetVersionKey)
    }

    static func currentBundleVersion(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let buildNumber = info?["CFBundleVersion"] as? String

        switch (shortVersion, buildNumber) {
        case let (.some(shortVersion), .some(buildNumber)):
            return "\(shortVersion)#\(buildNumber)"
        case let (.some(shortVersion), .none):
            return shortVersion
        case let (.none, .some(buildNumber)):
            return buildNumber
        case (.none, .none):
            return "unknown"
        }
    }

    static func isRunningFromAppBundle(bundle: Bundle = .main) -> Bool {
        bundle.bundleURL.pathExtension == "app"
    }
}
