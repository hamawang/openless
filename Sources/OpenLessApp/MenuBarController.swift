import AppKit
import OpenLessCore
import OpenLessPersistence

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let actions: MenuActions
    private weak var coordinator: DictationCoordinator?

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "OpenLess") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "OL"
            }
            button.toolTip = "OpenLess  —  点击菜单选择模式 / 退出"
        }
        actions = MenuActions(coordinator: coordinator)
        statusItem.menu = buildMenu()
    }

    func refreshMenu() {
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "OpenLess", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "开始 / 停止录音", action: #selector(MenuActions.toggleDictation), keyEquivalent: "")
        toggle.target = actions
        menu.addItem(toggle)

        menu.addItem(.separator())

        let modeHeader = NSMenuItem(title: "润色模式", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)

        let currentMode = UserPreferences.shared.polishMode
        for mode in PolishMode.allCases {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(MenuActions.selectMode(_:)),
                keyEquivalent: ""
            )
            item.target = actions
            item.state = (mode == currentMode) ? .on : .off
            item.representedObject = mode.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let home = NSMenuItem(title: "打开首页…", action: #selector(MenuActions.openHome), keyEquivalent: "")
        home.target = actions
        menu.addItem(home)

        let history = NSMenuItem(title: "打开历史记录…", action: #selector(MenuActions.openHistory), keyEquivalent: "")
        history.target = actions
        menu.addItem(history)

        let dictionary = NSMenuItem(title: "打开词典…", action: #selector(MenuActions.openDictionary), keyEquivalent: "")
        dictionary.target = actions
        menu.addItem(dictionary)

        let settings = NSMenuItem(title: "打开设置…", action: #selector(MenuActions.openSettings), keyEquivalent: ",")
        settings.target = actions
        menu.addItem(settings)

        let revealLog = NSMenuItem(title: "在 Finder 中显示日志", action: #selector(MenuActions.revealLog), keyEquivalent: "l")
        revealLog.target = actions
        menu.addItem(revealLog)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 OpenLess",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        return menu
    }
}

@MainActor
private final class MenuActions: NSObject {
    private weak var coordinator: DictationCoordinator?

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
    }

    @objc func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = PolishMode(rawValue: raw) else { return }
        UserPreferences.shared.polishMode = mode
        Log.write("切换润色模式 → \(mode.displayName)")
        coordinator?.menuBar?.refreshMenu()
    }

    @objc func openSettings() {
        coordinator?.openSettings()
    }

    @objc func openHome() {
        coordinator?.openHome()
    }

    @objc func openHistory() {
        coordinator?.openHistory()
    }

    @objc func openDictionary() {
        coordinator?.openDictionary()
    }

    @objc func toggleDictation() {
        coordinator?.toggleDictationFromMenu()
    }

    @objc func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
    }
}
