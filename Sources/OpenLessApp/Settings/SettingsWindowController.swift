import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let navigation = SettingsNavigationModel()

    func show(tab: OpenLessMainTab = .home) {
        navigation.selection = tab
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(navigation: navigation))
        let win = NSWindow(contentViewController: hosting)
        win.title = "OpenLess"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = false
        win.toolbarStyle = .unified
        win.setContentSize(NSSize(width: 1040, height: 700))
        win.contentMinSize = NSSize(width: 960, height: 640)
        win.tabbingMode = .disallowed
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
