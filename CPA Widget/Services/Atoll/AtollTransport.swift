import AtollExtensionKit
import Foundation

private protocol PendingAtollRequest: AnyObject, Sendable {
    func fail(_ error: Error)
}

@MainActor
final class AtollTransport: NSObject {
    static let bundleIdentifier = "vn.ppx.CPA-Widget"
    private let connectionFactory: () -> NSXPCConnection
    private var connection: NSXPCConnection?
    private var connectionGeneration = 0
    private var invalidated = false
    private var pending: [UUID: any PendingAtollRequest] = [:]
    var onAuthorizationChange: ((Bool) -> Void)?
    var onActivityDismiss: ((String) -> Void)?
    var onNotchExperienceDismiss: ((String) -> Void)?
    var onDisconnect: (() -> Void)?
    init(connectionFactory: @escaping () -> NSXPCConnection = {
        NSXPCConnection(machServiceName: "com.ebullioscopic.Atoll.xpc", options: [])
    }) {
        self.connectionFactory = connectionFactory
        super.init()
    }

    func reconnect() {
        failPending(with: AtollIntegrationError.disconnected)
        connectionGeneration += 1
        let oldConnection = connection
        connection = nil
        invalidated = false
        oldConnection?.invalidate()
        connect()
    }

    private func connect() {
        connectionGeneration += 1
        let generation = connectionGeneration
        let connection = connectionFactory()
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: AtollXPCServiceProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: AtollXPCClientProtocol.self)
        connection.exportedObject = self
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }
                self.connectionFailed()
            }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }
                self.connectionFailed()
            }
        }
        connection.resume()
    }

    func requestAuthorization() async throws -> Bool {
        try await call(timeout: .seconds(120)) { proxy, reply in
            proxy.requestAuthorization(bundleIdentifier: Self.bundleIdentifier, reply: { allowed, _ in reply(allowed) })
        }
    }

    func checkAuthorization() async throws -> Bool {
        try await call { proxy, reply in proxy.checkAuthorization(bundleIdentifier: Self.bundleIdentifier, reply: reply) }
    }

    func getVersion() async throws -> String {
        try await call { proxy, reply in proxy.getVersion(reply: reply) }
    }

    func presentLiveActivity(_ descriptor: AtollLiveActivityDescriptor) async throws {
        try await send(descriptor, present: true, activity: true)
    }

    func updateLiveActivity(_ descriptor: AtollLiveActivityDescriptor) async throws {
        try await send(descriptor, present: false, activity: true)
    }

    func dismissLiveActivity(activityID: String) async throws {
        let accepted: Bool = try await call { proxy, reply in
            proxy.dismissLiveActivity(activityID: activityID, bundleIdentifier: Self.bundleIdentifier) { ok, _ in reply(ok) }
        }
        guard accepted else { throw AtollIntegrationError.rejected }
    }

    func presentNotchExperience(_ descriptor: AtollNotchExperienceDescriptor) async throws {
        try await send(descriptor, present: true, activity: false)
    }

    func updateNotchExperience(_ descriptor: AtollNotchExperienceDescriptor) async throws {
        try await send(descriptor, present: false, activity: false)
    }

    func dismissNotchExperience(experienceID: String) async throws {
        let accepted: Bool = try await call { proxy, reply in
            proxy.dismissNotchExperience(experienceID: experienceID, bundleIdentifier: Self.bundleIdentifier) { ok, _ in reply(ok) }
        }
        guard accepted else { throw AtollIntegrationError.rejected }
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        failPending(with: AtollIntegrationError.disconnected)
        connection?.invalidate()
    }

    private func send<T: Encodable>(_ descriptor: T, present: Bool, activity: Bool) async throws {
        let data: Data
        do { data = try JSONEncoder().encode(descriptor) }
        catch { throw AtollIntegrationError.invalidPayload }
        let accepted: Bool = try await call { proxy, reply in
            if activity {
                if present { proxy.presentLiveActivity(descriptorData: data) { ok, _ in reply(ok) } }
                else { proxy.updateLiveActivity(descriptorData: data) { ok, _ in reply(ok) } }
            } else {
                if present { proxy.presentNotchExperience(descriptorData: data) { ok, _ in reply(ok) } }
                else { proxy.updateNotchExperience(descriptorData: data) { ok, _ in reply(ok) } }
            }
        }
        guard accepted else { throw AtollIntegrationError.rejected }
    }

    private func call<T: Sendable>(timeout: Duration = .seconds(5), _ invoke: @escaping (AtollXPCServiceProtocol, @escaping (T) -> Void) -> Void) async throws -> T {
        guard !invalidated, let connection,
              let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
                  Task { @MainActor in self?.connectionFailed() }
              }) as? AtollXPCServiceProtocol else { throw AtollIntegrationError.disconnected }
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = RequestGate<T>(continuation)
                guard !invalidated else {
                    gate.finish(.failure(AtollIntegrationError.disconnected))
                    return
                }
                pending[requestID] = gate
                let timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.failRequest(requestID, with: AtollIntegrationError.timedOut) else { return }
                    self.connectionFailed()
                }
                gate.onFinish = { [weak self] in
                    timeoutTask.cancel()
                    Task { @MainActor [weak self] in self?.pending.removeValue(forKey: requestID) }
                }
                if Task.isCancelled { gate.fail(CancellationError()) }
                else { invoke(proxy) { value in gate.finish(.success(value)) } }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.failRequest(requestID, with: CancellationError()) }
        }
    }

    @discardableResult
    private func failRequest(_ id: UUID, with error: Error) -> Bool {
        guard let request = pending.removeValue(forKey: id) else { return false }
        request.fail(error)
        return true
    }

    private func failPending(with error: Error) {
        let requests = Array(pending.values)
        pending.removeAll()
        requests.forEach { $0.fail(error) }
    }

    private func connectionFailed() {
        guard !invalidated else { return }
        invalidated = true
        failPending(with: AtollIntegrationError.disconnected)
        connection?.invalidate()
        onDisconnect?()
    }

}

private final class RequestGate<Value: Sendable>: PendingAtollRequest, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    var onFinish: (() -> Void)?

    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }

    func fail(_ error: Error) { finish(.failure(error)) }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let finish = onFinish
        onFinish = nil
        lock.unlock()
        guard let continuation else { return }
        finish?()
        continuation.resume(with: result)
    }
}

extension AtollTransport: AtollXPCClientProtocol {
    nonisolated func authorizationDidChange(isAuthorized: Bool) {
        Task { @MainActor [weak self] in self?.onAuthorizationChange?(isAuthorized) }
    }
    nonisolated func activityDidDismiss(activityID: String) {
        Task { @MainActor [weak self] in self?.onActivityDismiss?(activityID) }
    }
    nonisolated func widgetDidDismiss(widgetID: String) {}
    nonisolated func notchExperienceDidDismiss(experienceID: String) {
        Task { @MainActor [weak self] in self?.onNotchExperienceDismiss?(experienceID) }
    }
}
