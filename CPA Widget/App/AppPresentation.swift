import AppKit
import Observation
import SwiftUI

@MainActor
final class AppPresentation: NSObject, NSPopoverDelegate {
    /// Content size of the Settings window, defined once so sizing and centering stay in step.
    private static let settingsContentSize = NSSize(width: 520, height: 660)

    private let model: AppModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsController: NSWindowController?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        observeWidgetEnabled()
    }

    private func observeWidgetEnabled() {
        withObservationTracking {
            _ = model.widgetEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyWidgetEnabled()
                self.observeWidgetEnabled()
            }
        }
        applyWidgetEnabled()
    }

    private func applyWidgetEnabled() {
        if model.widgetEnabled {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let icon = NSImage(named: "MenuBarIcon")
            icon?.isTemplate = true
            item.button?.image = icon
            item.button?.setAccessibilityLabel("CLI Proxy API status")
            item.button?.toolTip = "CLI Proxy API"
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            statusItem = item
        } else {
            if let popover, popover.isShown { popover.performClose(nil) }
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        let panel = NSPopover()
        panel.behavior = .transient
        panel.delegate = self
        let screen = button.window?.screen ?? NSScreen.main
        let usableHeight = screen?.visibleFrame.height ?? 800
        let panelHeight = min((screen?.frame.height ?? 900) * (2.0 / 3.0), usableHeight - 20)
        panel.contentViewController = NSHostingController(rootView: WidgetPanel(showSettings: { [weak self] in self?.showSettings() }, panelHeight: panelHeight).environment(model))
        popover = panel
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        popover.contentViewController = NSHostingController(rootView: EmptyView())
        self.popover = nil
    }

    func showSettings() {
        if settingsController == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.settingsContentSize), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "CPA Widget Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsPanel(close: { [weak self] in self?.hideSettings() }).environment(model))
            settingsController = NSWindowController(window: window)
        }
        guard let window = settingsController?.window else { return }
        // A window controller would otherwise override the centered origin while cascading.
        settingsController?.shouldCascadeWindows = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        settle(window)
    }

    /// The close button behaves like the window's own close control: the window is ordered out but
    /// kept, so Finder reopen and the panel's Settings button bring the same window back.
    private func hideSettings() {
        settingsController?.window?.performClose(nil)
    }

    /// The SwiftUI hosting controller resizes the window only after its first layout pass, and the
    /// window is zero-width until then. Sizing and centering are therefore applied on the next
    /// run-loop turn, once the window has settled, so the centered origin matches the final size.
    private func settle(_ window: NSWindow) {
        DispatchQueue.main.async { [weak self] in
            window.setContentSize(Self.settingsContentSize)
            self?.center(window)
        }
    }

    /// Centers on the usable area of the window's screen. The window is centered on every show,
    /// not only at creation, so a reopened Settings window always returns to the middle.
    private func center(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }
}
