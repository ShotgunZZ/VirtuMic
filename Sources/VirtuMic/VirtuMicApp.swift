import SwiftUI
import AVFoundation
import os

private let logger = Logger(subsystem: "com.shotgunzz.virtumic", category: "app")

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var engine: AudioEngine!
    var windowController: MixerWindowController?
    var allowTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("VirtuMic menu bar app")
        ProcessInfo.processInfo.disableSuddenTermination()

        engine = AudioEngine()

        // Create status bar item using NSStatusItem (reliable for unsigned apps)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        // Build menu
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "Status: Stopped", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Start Engine", action: #selector(toggleEngine), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 101
        menu.addItem(toggleItem)

        let monitorItem = NSMenuItem(title: "Monitor (Speakers)", action: #selector(toggleMonitor), keyEquivalent: "")
        monitorItem.target = self
        monitorItem.tag = 102
        menu.addItem(monitorItem)

        let mixerItem = NSMenuItem(title: "Show Mixer", action: #selector(showMixer), keyEquivalent: "m")
        mixerItem.target = self
        menu.addItem(mixerItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit VirtuMic", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self

        logger.info("Status bar item created, auto-starting in 1s")

        // Auto-start after a brief delay (2s gives audio devices time to initialize)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.requestMicAndStart()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return allowTermination ? .terminateNow : .terminateCancel
    }

    func updateIcon() {
        if let button = statusItem?.button {
            let running = engine?.isRunning == true
            button.image = makeMenuBarIcon(running: running)
        }
    }

    func makeMenuBarIcon(running: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cyan = NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 1.0)
            let dim = NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 0.35)
            let color = running ? cyan : dim

            color.setStroke()

            let lw: CGFloat = 1.5

            // Mic capsule (hollow rounded rect)
            let capsule = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 7, width: 7, height: 10), xRadius: 3.5, yRadius: 3.5)
            capsule.lineWidth = lw
            capsule.stroke()

            // Cradle arc
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 9, y: 7), radius: 6.5, startAngle: 180, endAngle: 0, clockwise: true)
            arc.lineWidth = lw
            arc.stroke()

            // Stand
            let stand = NSBezierPath()
            stand.move(to: NSPoint(x: 9, y: 0.5))
            stand.line(to: NSPoint(x: 9, y: 3))
            stand.lineWidth = lw
            stand.lineCapStyle = .round
            stand.stroke()

            // Base
            let base = NSBezierPath()
            base.move(to: NSPoint(x: 5.5, y: 0.5))
            base.line(to: NSPoint(x: 12.5, y: 0.5))
            base.lineWidth = lw
            base.lineCapStyle = .round
            base.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    func updateMenu() {
        guard let menu = statusItem?.menu else { return }

        // Update status
        if let statusItem = menu.item(withTag: 100) {
            if engine.isRunning {
                statusItem.title = "Status: Running"
            } else if let error = engine.errorMessage {
                statusItem.title = "Error: \(error)"
            } else {
                statusItem.title = "Status: Stopped"
            }
        }

        // Update toggle button
        if let toggleItem = menu.item(withTag: 101) {
            toggleItem.title = engine.isRunning ? "Stop Engine" : "Start Engine"
        }

        // Update monitor button
        if let monitorItem = menu.item(withTag: 102) {
            monitorItem.title = engine.isMonitoring ? "Stop Monitor" : "Monitor (Speakers)"
            monitorItem.state = engine.isMonitoring ? .on : .off
        }
    }

    @objc func toggleEngine() {
        if engine.isRunning {
            engine.stop()
        } else {
            requestMicAndStart()
        }
        updateIcon()
        updateMenu()
    }

    @objc func toggleMonitor() {
        engine.toggleMonitoring()
        updateMenu()
    }

    @objc func showMixer() {
        if windowController == nil {
            windowController = MixerWindowController(engine: engine)
        }
        windowController?.toggle()
        if !engine.isRunning {
            requestMicAndStart()
        }
    }

    @objc func quitApp() {
        engine.stop()
        allowTermination = true
        NSApplication.shared.terminate(nil)
    }

    func requestMicAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.info("Mic authorization status: \(status.rawValue) (3=authorized)")
        switch status {
        case .authorized:
            logger.info("Mic authorized, starting engine")
            engine.start()
        case .notDetermined:
            logger.info("Mic permission not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { [self] in
                    if granted {
                        logger.info("Mic access granted, starting engine")
                        engine.start()
                    } else {
                        logger.error("Mic access denied by user")
                        engine.errorMessage = "Microphone access denied. Check System Settings > Privacy & Security > Microphone."
                    }
                    updateIcon()
                    updateMenu()
                }
            }
        case .denied, .restricted:
            logger.error("Mic access denied/restricted")
            engine.errorMessage = "Microphone access denied. Check System Settings > Privacy & Security > Microphone."
        @unknown default:
            engine.start()
        }
        updateIcon()
        updateMenu()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }
}

@main
struct VirtuMicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            EmptyView()
        }
    }
}
