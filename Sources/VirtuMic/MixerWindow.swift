import AppKit
import SwiftUI

final class MixerWindowController {
    private var panel: NSPanel?
    private let engine: AudioEngine

    init(engine: AudioEngine) {
        self.engine = engine
    }

    func toggle() {
        if let panel = panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        if panel == nil {
            let hostingView = NSHostingView(rootView: MixerView(engine: engine))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "VirtuMic"
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.contentView = hostingView
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.isMovableByWindowBackground = true
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}
