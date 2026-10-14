import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var instanceURL: String
    var widgetEnabled: Bool {
        didSet { defaults.set(widgetEnabled, forKey: "widgetEnabled") }
    }
    private(set) var providers: [ProviderSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var requestHistory: [RequestLogEntry] = []
    private(set) var requestHistoryError: String?
    private(set) var requestHistoryUpdated: Date?
    private(set) var isLoadingRequestHistory = false
    /// Models per request ID. A nil value means the instance kept no file for that request, so the
    /// row reports the model as unavailable instead of asking again on every poll.
    private(set) var requestModels: [String: String?] = [:]
    /// Zero-based page of the request history currently shown; zero is the newest 20 requests.
    private(set) var requestPage = 0
    private(set) var isLoadingRequestModels = false
    private var authenticationPaused = false
    /// Set when the instance reports that it keeps no file log, so the panel stops asking.
    private var requestLogUnavailable = false
    private var revision = 0

    /// Lines read per history refresh, and requests kept from them. The instance's log holds every
    /// route it serves, so the tail has to be wide enough to cover a burst of client traffic.
    private static let requestLogLines = 500
    private static let requestHistoryLimit = 200
    private let defaults: UserDefaults
    private let keychain = KeychainStore()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        instanceURL = defaults.string(forKey: "instanceURL") ?? "http://localhost:8317"
        widgetEnabled = defaults.object(forKey: "widgetEnabled") as? Bool ?? true
    }

    func loadKey() throws -> String { try keychain.load() }

    func testConnection(instanceURL: String, key: String) async throws {
        let url = try ManagementClient.validatedURL(instanceURL)
        let managementKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !managementKey.isEmpty else { throw ManagementError.missingKey }
        let client = ManagementClient(baseURL: url, key: managementKey)
        _ = try await client.credentials()
    }

    func saveSettings(instanceURL: String, key: String) throws {
        let url = try ManagementClient.validatedURL(instanceURL)
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManagementError.missingKey
        }
        try keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        self.instanceURL = url.absoluteString
        defaults.set(self.instanceURL, forKey: "instanceURL")
        revision += 1
        authenticationPaused = false
        providers = []
        lastUpdated = nil
        errorMessage = nil
        requestHistory = []
        requestHistoryError = nil
        requestHistoryUpdated = nil
        requestModels = [:]
        requestPage = 0
        requestLogUnavailable = false
    }

    func refresh() async {
        guard !isRefreshing, !authenticationPaused else { return }
        isRefreshing = true
        let currentRevision = revision
        defer { isRefreshing = false }
        do {
            let key = try loadKey()
            guard !key.isEmpty else {
                errorMessage = "Open Settings to enter your instance and management key."
                return
            }
            let client = ManagementClient(baseURL: try ManagementClient.validatedURL(instanceURL), key: key)
            // Disabled credentials are skipped entirely: they are neither fetched nor displayed.
            let credentials = try await client.credentials().filter(\.isEnabled)
            let indexedAccounts = try await withThrowingTaskGroup(of: (Int, AccountSnapshot).self) { group in
                var nextIndex = 0
                var results: [(Int, AccountSnapshot)] = []
                let initialCount = min(6, credentials.count)
                for index in 0..<initialCount {
                    let credential = credentials[index]
                    group.addTask { (index, try await Self.accountSnapshot(for: credential, client: client)) }
                    nextIndex += 1
                }
                while let result = try await group.next() {
                    results.append(result)
                    if nextIndex < credentials.count {
                        let index = nextIndex
                        let credential = credentials[index]
                        group.addTask { (index, try await Self.accountSnapshot(for: credential, client: client)) }
                        nextIndex += 1
                    }
                }
                // Order the way the instance routes: priority tier descending, then weight
                // descending, then the inventory's own order as a stable tie-break.
                return results.sorted { lhs, rhs in
                    let leftPriority = lhs.1.credential.routingPriority
                    let rightPriority = rhs.1.credential.routingPriority
                    if leftPriority != rightPriority { return leftPriority > rightPriority }
                    let leftWeight = lhs.1.credential.routingWeight
                    let rightWeight = rhs.1.credential.routingWeight
                    if leftWeight != rightWeight { return leftWeight > rightWeight }
                    return lhs.0 < rhs.0
                }.map(\.1)
            }
            try Task.checkCancellation()
            guard revision == currentRevision else { return }
            let grouped = Dictionary(grouping: indexedAccounts, by: { $0.credential.provider })
            providers = grouped.keys.sorted().map { ProviderSnapshot(id: $0, accounts: grouped[$0]!) }
            lastUpdated = .now
            errorMessage = nil
        } catch is CancellationError {
            // Closing the panel cancels its refresh without replacing the last snapshot.
        } catch {
            guard revision == currentRevision else { return }
            if let managementError = error as? ManagementError, managementError.stopsAuthentication {
                authenticationPaused = true
            }
            if (error as? URLError)?.code != .cancelled { errorMessage = error.localizedDescription }
        }
    }

    /// Reads the tail of the instance's file log and keeps the proxied API requests in it. This is
    /// a read of the log the instance writes; nothing is drained, reset, or reconfigured.
    func refreshRequestHistory() async {
        guard !isLoadingRequestHistory, !authenticationPaused, !requestLogUnavailable else { return }
        isLoadingRequestHistory = true
        let currentRevision = revision
        defer { isLoadingRequestHistory = false }
        do {
            let key = try loadKey()
            guard !key.isEmpty else {
                requestHistoryError = "Open Settings to enter your instance and management key."
                return
            }
            let client = ManagementClient(baseURL: try ManagementClient.validatedURL(instanceURL), key: key)
            let lines = try await client.logs(limit: Self.requestLogLines)
            try Task.checkCancellation()
            guard revision == currentRevision else { return }
            requestHistory = RequestLogEntry.history(from: lines, limit: Self.requestHistoryLimit)
            requestPage = min(requestPage, requestPageCount - 1)
            requestHistoryUpdated = .now
            requestHistoryError = nil
        } catch is CancellationError {
            // Leaving the tab cancels the read without replacing the last list.
        } catch {
            guard revision == currentRevision else { return }
            if let managementError = error as? ManagementError {
                if managementError.stopsAuthentication { authenticationPaused = true }
                if case .requestLogsUnavailable = managementError { requestLogUnavailable = true }
            }
            if (error as? URLError)?.code != .cancelled { requestHistoryError = error.localizedDescription }
        }
    }

    /// Requests shown per page of the history tab.
    static let requestPageSize = 20

    var requestPageCount: Int {
        max(1, Int((Double(requestHistory.count) / Double(Self.requestPageSize)).rounded(.up)))
    }

    /// The requests on the current page, newest first.
    var requestPageEntries: ArraySlice<RequestLogEntry> {
        let start = min(requestPage * Self.requestPageSize, requestHistory.count)
        let end = min(start + Self.requestPageSize, requestHistory.count)
        return requestHistory[start..<end]
    }

    func showRequestPage(_ page: Int) {
        requestPage = min(max(0, page), requestPageCount - 1)
    }

    /// Fills in the model for the visible page only, one request file at a time. Requests already
    /// resolved, including those the instance keeps no file for, are not read again. Each read checks
    /// the authentication pause first, and a 401/403 pauses the rest of the page, so a wrong key costs
    /// one failed call rather than a burst that could reach the instance's IP-ban threshold.
    func loadModelsForRequestPage() async {
        guard !isLoadingRequestModels, !authenticationPaused else { return }
        let pending = requestPageEntries.compactMap(\.requestID).filter { requestModels[$0] == nil }
        guard !pending.isEmpty else { return }
        isLoadingRequestModels = true
        let currentRevision = revision
        defer { isLoadingRequestModels = false }
        do {
            let key = try loadKey()
            let client = ManagementClient(baseURL: try ManagementClient.validatedURL(instanceURL), key: key)
            for id in pending {
                // Re-check before every call: a 401/403 from an earlier call or from the quota
                // refresh must stop this loop before it sends another request.
                guard !authenticationPaused, revision == currentRevision else { return }
                let model = try await Self.model(forRequest: id, client: client)
                guard revision == currentRevision else { return }
                requestModels[id] = .some(model)
            }
        } catch is CancellationError {
            // Leaving the tab cancels the reads; resolved models stay cached.
        } catch {
            guard revision == currentRevision else { return }
            if let managementError = error as? ManagementError, managementError.stopsAuthentication {
                authenticationPaused = true
            }
            if (error as? URLError)?.code != .cancelled { requestHistoryError = error.localizedDescription }
        }
    }

    /// A missing file is recorded as unavailable (nil). Any other failure is rethrown so the page
    /// reports it instead of silently caching a wrong answer.
    private static func model(forRequest id: String, client: ManagementClient) async throws -> String? {
        do {
            return try await client.requestModel(requestID: id)
        } catch ManagementError.http(404) {
            return nil
        }
    }

    private static func accountSnapshot(for credential: Credential, client: ManagementClient) async throws -> AccountSnapshot {
        do {
            return AccountSnapshot(credential: credential, quota: try await quota(for: credential, client: client), errorMessage: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let managementError = error as? ManagementError, managementError.stopsAuthentication { throw error }
            return AccountSnapshot(credential: credential, quota: nil, errorMessage: error.localizedDescription)
        }
    }

    /// A published quota plugin always wins; otherwise a known provider probe reads quota through
    /// the instance. Credentials that satisfy neither stay unavailable instead of guessing.
    private static func quota(for credential: Credential, client: ManagementClient) async throws -> QuotaResponse {
        if credential.hasPluginQuota { return try await client.quota(for: credential) }
        guard credential.hasAuthIndex, let probe = QuotaProbeRegistry.probe(for: credential.provider) else {
            throw ManagementError.unsupportedQuota
        }
        return try await probe.quota(for: credential, using: client)
    }
}
