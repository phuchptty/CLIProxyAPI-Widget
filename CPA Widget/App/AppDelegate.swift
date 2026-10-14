import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var presentation: AppPresentation?
    private var refreshCoordinator: AppRefreshCoordinator?
    private var atoll: AtollIntegration?
    private var terminationStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel()
        let coordinator = AppRefreshCoordinator(model: model)
        let transport = AtollTransport()
        let atoll = AtollIntegration(model: model, coordinator: coordinator, transport: transport)
        let presentation = AppPresentation(model: model, refreshCoordinator: coordinator, atoll: atoll)
        self.refreshCoordinator = coordinator
        self.atoll = atoll
        self.presentation = presentation
        atoll.start()
        presentation.start()
        presentation.showSettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationStarted else { return .terminateLater }
        terminationStarted = true
        refreshCoordinator?.shutdown()
        guard let atoll else { return .terminateNow }
        Task { @MainActor in
            await atoll.shutdown()
            guard terminationStarted else { return }
            terminationStarted = false
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.terminationStarted else { return }
            self.atoll?.forceInvalidate()
            self.terminationStarted = false
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentation?.showSettings()
        return false
    }
}
