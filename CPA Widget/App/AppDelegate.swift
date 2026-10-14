import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var presentation: AppPresentation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel()
        let presentation = AppPresentation(model: model)
        self.presentation = presentation
        presentation.start()
        presentation.showSettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentation?.showSettings()
        return false
    }
}
