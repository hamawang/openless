import AppKit
import SwiftUI
import OpenLessUI

@MainActor
final class CapsuleWindowController {
    private let window: NSPanel
    private let hostingView: NSHostingView<CapsuleView>
    private var currentState: CapsuleState = .hidden
    private var currentLevel: Float = 0
    private let panelSize = NSSize(width: 196, height: 56)

    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}

    init() {
        let initialView = CapsuleView(state: .hidden, level: 0)
        hostingView = NSHostingView(rootView: initialView)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // 必须接受鼠标点击，否则胶囊上的叉/勾按钮无法响应。
        // .nonactivatingPanel 保证点击不会抢走前台 app 的焦点。
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView
        self.window = panel

        repositionToBottomCenter()
    }

    func update(state: CapsuleState, level: Float = 0) {
        currentState = state
        currentLevel = level
        hostingView.rootView = CapsuleView(
            state: state,
            level: level,
            onCancel: { [weak self] in self?.onCancel() },
            onConfirm: { [weak self] in self?.onConfirm() }
        )
        if state == .hidden {
            window.orderOut(nil)
        } else {
            if !window.isVisible {
                repositionToBottomCenter()
                window.orderFrontRegardless()
            }
        }
    }

    private func repositionToBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let size = window.frame.size
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.minY + 24
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
