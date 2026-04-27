import AppKit
import OpenLessHotkey
import OpenLessPersistence
import OpenLessRecorder

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: DictationCoordinator?
    private var menuBar: MenuBarController?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 不依赖 UserPreferences flag：每次启动直接查实际权限。
        // ad-hoc 签名下每次 rebuild 二进制 hash 都变，TCC 会自动失效，
        // 必须在那种情况下重新进引导，否则用户看不到 menu bar 也就罢了，
        // 还会无声地拿不到快捷键和麦克风。
        if !AccessibilityPermission.isGranted() || !MicrophonePermission.isGranted() {
            showOnboarding()
            return
        }
        ApplicationMenu.install()
        let coordinator = DictationCoordinator()
        let menuBar = MenuBarController(coordinator: coordinator)
        coordinator.menuBar = menuBar
        coordinator.bootstrap()
        self.coordinator = coordinator
        self.menuBar = menuBar
        coordinator.openHome()
        runLaunchActions(coordinator: coordinator)
    }

    private func showOnboarding() {
        let controller = OnboardingWindowController { [weak self] in
            // 留 flag=true 仅作"用户走过引导"的标记；启动门是实际权限状态。
            UserPreferences.shared.hasCompletedOnboarding = true
            // 必须重启：CGEventTap 只在进程获得辅助功能权限后下一次创建时才生效。
            self?.showRestartAlertAndQuit()
        }
        self.onboarding = controller
        controller.show()
    }

    private func showRestartAlertAndQuit() {
        let alert = NSAlert()
        alert.messageText = "权限已就绪"
        alert.informativeText = "OpenLess 需要重启以让快捷键生效。点击「退出」后，请重新打开 OpenLess。"
        alert.addButton(withTitle: "退出")
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.openHome()
        return true
    }

    private func runLaunchActions(coordinator: DictationCoordinator) {
        let arguments = Set(CommandLine.arguments.dropFirst())
        if arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                coordinator.openSettings()
            }
        }
        if arguments.contains("--start-recording") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                coordinator.toggleDictationFromMenu()
            }
        }
    }
}
