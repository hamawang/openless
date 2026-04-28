import Foundation

struct TCCPermissionResetter {
    static let services = [
        "Accessibility",
        "Microphone",
        "AppleEvents",
        "ListenEvent",
    ]

    let bundleIdentifier: String
    let resetService: (String, String) -> Void

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.openless.app",
        resetService: @escaping (String, String) -> Void = TCCPermissionResetter.runTCCUtilReset
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.resetService = resetService
    }

    func resetAll() {
        for service in Self.services {
            resetService(service, bundleIdentifier)
        }
    }

    private static func runTCCUtilReset(service: String, bundleIdentifier: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleIdentifier]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                Log.write("[permissions] reset TCC \(service) for \(bundleIdentifier)")
            } else {
                Log.write("[permissions] tccutil reset \(service) for \(bundleIdentifier) exited with \(process.terminationStatus)")
            }
        } catch {
            Log.write("[permissions] failed to run tccutil for \(service): \(error.localizedDescription)")
        }
    }
}
