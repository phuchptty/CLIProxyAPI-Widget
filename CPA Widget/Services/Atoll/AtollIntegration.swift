import AtollExtensionKit
import AppKit
import Observation
import Foundation

@MainActor
@Observable
final class AtollIntegration {
    private let model: AppModel
    private let coordinator: AppRefreshCoordinator
    private let transport: AtollTransport
    private let defaults: UserDefaults
    private let builder = AtollDashboardBuilder()
    private var observerTokens: [NSObjectProtocol] = []
    private var generation = 0
    private var observedRevision = -1
    private var authorized = false
    private var sessionDismissed = false
    private var presentedDashboard = false
    private var presentedSummary = false
    private var currentPage = 0
    private var pageDwellSeconds: [Double] = []
    private var lastEntryIDs: [String] = []
    private var rotationGeneration = 0
    private var pages: [AtollNotchExperienceDescriptor] = []
    private var options: [AtollDashboardBuilder.Entry] = []
    private var worker: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var pendingReconcile = false
    private var connectionTask: Task<Void, Never>?
    private var pendingDismissals: Set<String> = []
    private var shuttingDown = false
    private var selfDismissals: Set<String> = []

    private(set) var enabled: Bool
    private(set) var statusMessage = "Atoll integration is disabled"
    private(set) var isConnecting = false
    private(set) var summarySelection: AtollSummarySelection?
    var summaryOptions: [AtollDashboardBuilder.Entry] { options }

    init(model: AppModel, coordinator: AppRefreshCoordinator, transport: AtollTransport, defaults: UserDefaults = .standard) {
        self.model = model
        self.coordinator = coordinator
        self.transport = transport
        self.defaults = defaults
        enabled = defaults.bool(forKey: "atollEnabled")
        summarySelection = Self.decodeSelection(defaults.data(forKey: "atollSummarySelection"))
    }

    func start() {
        transport.onAuthorizationChange = { [weak self] authorized in
            guard let self else { return }
            if authorized { self.resumeIfEligible() } else { self.authorizationRevoked() }
        }
        transport.onActivityDismiss = { [weak self] id in self?.didDismiss(id) }
        transport.onNotchExperienceDismiss = { [weak self] id in self?.didDismiss(id) }
        transport.onDisconnect = { [weak self] in self?.handleDisconnect() }
        observerTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier?.lowercased() == "com.ebullioscopic.atoll" else { return }
            Task { @MainActor in self?.hostStopped() }
        })
        observerTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier?.lowercased() == "com.ebullioscopic.atoll" else { return }
            Task { @MainActor in await self?.checkOnHostLaunch() }
        })
        observedRevision = model.settingsRevision
        watchModel()
        if enabled, isHostRunning { Task { await checkAuthorizationAtStartup() } }
        else if enabled { statusMessage = "Open Atoll to connect" }
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        defaults.set(enabled, forKey: "atollEnabled")
        generation += 1
        sessionDismissed = false
        if enabled {
            beginConnect()
        } else {
            connectionTask?.cancel()
            stopLease()
            statusMessage = "Atoll integration is disabled"
            queueDismissal()
        }
    }

    func beginConnect() {
        if isConnecting {
            guard connectionTask?.isCancelled == true, let previous = connectionTask else { return }
            connectionTask = Task { [weak self] in
                await previous.value
                guard let self, self.enabled else { return }
                await self.connect()
            }
            return
        }
        connectionTask = Task { [weak self] in await self?.connect() }
    }
    func connect() async {
        guard enabled else { setEnabled(true); return }
        guard !isConnecting else { return }
        guard isHostInstalled else { statusMessage = AtollIntegrationError.notInstalled.localizedDescription; return }
        guard isHostRunning else { statusMessage = AtollIntegrationError.notRunning.localizedDescription; return }
        isConnecting = true
        defer { isConnecting = false }
        transport.reconnect()
        generation += 1
        let requestGeneration = generation
        do {
            authorized = try await transport.requestAuthorization()
            guard requestGeneration == generation else { return }
            guard authorized else { statusMessage = AtollIntegrationError.denied.localizedDescription; stopLease(); return }
            sessionDismissed = false
            statusMessage = "Connected to Atoll"
            coordinator.setActive(.atoll, true)
            queueReconcile()
        } catch {
            guard requestGeneration == generation else { return }
            statusMessage = readable(error)
            stopLease()
        }
    }

    func openAtoll() {
        guard let url = installedAtollURL else { statusMessage = "Atoll is not installed"; return }
        NSWorkspace.shared.open(url)
        if enabled { statusMessage = "Open Atoll to connect" }
    }

    func selectSummary(_ selection: AtollSummarySelection?) {
        summarySelection = selection
        if let selection, let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: "atollSummarySelection") }
        else { defaults.removeObject(forKey: "atollSummarySelection") }
        queueReconcile()
    }

    func shutdown() async {
        shuttingDown = true
        authorized = false
        generation += 1
        connectionTask?.cancel()
        connectionTask = nil
        stopLease()
        rotationTask?.cancel()
        queueDismissal()
        await worker?.value
        transport.invalidate()
        observerTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observerTokens.removeAll()
    }

    private var isHostRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.Ebullioscopic.Atoll").isEmpty == false ||
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.ebullioscopic.Atoll").isEmpty == false
    }

    private var isHostInstalled: Bool { installedAtollURL != nil }


    func forceInvalidate() {
        generation += 1
        stopLease()
        transport.invalidate()
    }
    private var installedAtollURL: URL? {
        let ids = ["com.Ebullioscopic.Atoll", "com.ebullioscopic.Atoll"]
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ids[0]) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: ids[1]),
           let bundle = Bundle(url: url), ids.contains(bundle.bundleIdentifier ?? "") { return url }
        let candidates = [URL(fileURLWithPath: "/Applications/Atoll.app"), FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/Atoll.app")]
        return candidates.first { url in
            guard let bundle = Bundle(url: url) else { return false }
            return ids.contains(bundle.bundleIdentifier ?? "")
        }
    }

    private func watchModel() {
        withObservationTracking {
            _ = model.settingsRevision
            _ = model.providers
            _ = model.lastUpdated
            _ = model.errorMessage
            _ = model.isRefreshing
        } onChange: { [weak self] in
            Task { @MainActor in self?.modelChanged() }
        }
    }

    private func modelChanged() {
        let changedRevision = model.settingsRevision != observedRevision
        if changedRevision {
            observedRevision = model.settingsRevision
            pages = []
            currentPage = 0
            generation += 1
            queueDismissal()
        }
        if !model.isRefreshing { queueReconcile() }
        watchModel()
    }

    private func queueReconcile() {
        pendingReconcile = true
        startWorkerIfNeeded()
    }

    private func queueDismissal() {
        if presentedDashboard { pendingDismissals.insert("cpa-widget-quotas") }
        if presentedSummary { pendingDismissals.insert("cpa-widget-summary") }
        pendingReconcile = true
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while self.pendingReconcile, !Task.isCancelled {
                self.pendingReconcile = false
                await self.processPendingDismissals()
                if self.enabled, self.authorized, !self.sessionDismissed, !self.shuttingDown {
                    await self.reconcileOnce()
                }
            }
            self.worker = nil
            if self.pendingReconcile { self.startWorkerIfNeeded() }
        }
    }

    private func processPendingDismissals() async {
        let ids = pendingDismissals
        pendingDismissals.removeAll()
        for id in ids {
            selfDismissals.insert(id)
            if id == "cpa-widget-quotas" {
                try? await transport.dismissNotchExperience(experienceID: id)
                presentedDashboard = false
            } else {
                try? await transport.dismissLiveActivity(activityID: id)
                presentedSummary = false
            }
            selfDismissals.remove(id)
        }
    }

    private func reconcileOnce() async {
        guard enabled, authorized, !sessionDismissed, isHostRunning else { return }
        let revision = model.settingsRevision
        let life = generation
        let dashboard = builder.build(model: model)
        guard revision == model.settingsRevision else { return }
        let entryIDs = dashboard.entries.map(\.id)
        if entryIDs != lastEntryIDs {
            lastEntryIDs = entryIDs
            currentPage = 0
            rotationTask?.cancel()
            rotationGeneration += 1
            rotationTask = nil
        }
        pages = dashboard.pages
        pageDwellSeconds = dashboard.pageDwellSeconds
        options = dashboard.summaryOptions
        normalizeSelection()
        guard pages.allSatisfy(\.isValid) else {
            statusMessage = AtollIntegrationError.invalidPayload.localizedDescription
            stopLease()
            return
        }
        guard !pages.isEmpty else { return }
        let page = pages[min(currentPage, pages.count - 1)]
        do {
            if presentedDashboard { try await transport.updateNotchExperience(page) }
            else { try await transport.presentNotchExperience(page); presentedDashboard = true }
            guard revision == model.settingsRevision, life == generation else {
                if enabled, authorized, !sessionDismissed {
                    pendingReconcile = true
                } else {
                    presentedDashboard = false
                    pendingDismissals.insert("cpa-widget-quotas")
                    pendingReconcile = true
                    startWorkerIfNeeded()
                }
                return
            }
            let selection = options.first { $0.selection == summarySelection } ?? options.first(where: { $0.fraction != nil }) ?? options.first
            let summary = builder.summaryDescriptor(entry: selection, stale: model.errorMessage != nil && model.lastUpdated != nil, updated: model.lastUpdated)
            if presentedSummary {
                try await transport.updateLiveActivity(summary)
            } else {
                try await transport.presentLiveActivity(summary)
                presentedSummary = true
            }
            guard revision == model.settingsRevision, life == generation else {
                if enabled, authorized, !sessionDismissed {
                    pendingReconcile = true
                } else {
                    presentedSummary = false
                    pendingDismissals.insert("cpa-widget-summary")
                    pendingReconcile = true
                    startWorkerIfNeeded()
                }
                return
            }
            statusMessage = "Connected to Atoll"
            startRotation()
        } catch {
            statusMessage = readable(error)
            stopLease()
            queueDismissal()
        }
    }

    private func normalizeSelection() {
        guard !options.contains(where: { $0.selection == summarySelection }) else { return }
        summarySelection = options.first(where: { $0.fraction != nil })?.selection ?? options.first?.selection
        if let summarySelection, let data = try? JSONEncoder().encode(summarySelection) { defaults.set(data, forKey: "atollSummarySelection") }
        else { defaults.removeObject(forKey: "atollSummarySelection") }
    }

    private func startRotation() {
        guard pages.count > 1, rotationTask == nil else { return }
        rotationGeneration += 1
        let rotation = rotationGeneration
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let dwell = self.pageDwellSeconds.indices.contains(self.currentPage) ? self.pageDwellSeconds[self.currentPage] : 15
                do { try await Task.sleep(for: .seconds(dwell)) } catch { break }
                guard self.enabled, !self.sessionDismissed else { break }
                self.currentPage = (self.currentPage + 1) % self.pages.count
                self.queueReconcile()
            }
            if self?.rotationGeneration == rotation { self?.rotationTask = nil }
        }
    }

    private func didDismiss(_ id: String) {
        guard id == "cpa-widget-quotas" || id == "cpa-widget-summary" else { return }
        if selfDismissals.remove(id) != nil { return }
        sessionDismissed = true
        generation += 1
        stopLease()
        statusMessage = "Dismissed — choose Show in Atoll to resume"
        if id != "cpa-widget-quotas" && presentedDashboard { pendingDismissals.insert("cpa-widget-quotas") }
        if id != "cpa-widget-summary" && presentedSummary { pendingDismissals.insert("cpa-widget-summary") }
        presentedDashboard = false
        presentedSummary = false
        pendingReconcile = true
        startWorkerIfNeeded()
    }


    private func stopLease() {
        coordinator.setActive(.atoll, false)
        rotationGeneration += 1
        rotationTask?.cancel()
        rotationTask = nil
        pendingReconcile = false
    }

    private func checkAuthorizationAtStartup() async {
        transport.reconnect()
        do {
            authorized = try await transport.checkAuthorization()
            if authorized { resumeIfEligible() } else { authorizationRevoked() }
        } catch { statusMessage = readable(error) }
    }

    private func checkOnHostLaunch() async {
        guard enabled else { return }
        transport.reconnect()
        do {
            authorized = try await transport.checkAuthorization()
            if authorized { resumeIfEligible() } else { authorizationRevoked() }
        } catch { statusMessage = readable(error) }
    }

    private func resumeIfEligible() {
        guard enabled, !sessionDismissed else { return }
        authorized = true
        coordinator.setActive(.atoll, true)
        queueReconcile()
    }


    private func authorizationRevoked() {
        authorized = false
        statusMessage = "Approve CPA Widget in Atoll Settings → Extensions"
        generation += 1
        stopLease()
        queueDismissal()
    }

    private func hostStopped() {
        authorized = false
        presentedDashboard = false
        presentedSummary = false
        statusMessage = "Open Atoll to connect"
        generation += 1
        stopLease()
    }

    private func handleDisconnect() {
        presentedDashboard = false
        presentedSummary = false
        statusMessage = "Atoll extension service is unavailable — update Atoll and retry"
        generation += 1
        stopLease()
    }

    private func readable(_ error: Error) -> String {
        guard let integration = error as? AtollIntegrationError else { return AtollIntegrationError.disconnected.localizedDescription }
        return integration.localizedDescription
    }

    private static func decodeSelection(_ data: Data?) -> AtollSummarySelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AtollSummarySelection.self, from: data)
    }
}
