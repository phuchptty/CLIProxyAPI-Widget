import Foundation

enum AtollIntegrationError: Error, LocalizedError {
    case notInstalled
    case notRunning
    case denied
    case timedOut
    case disconnected
    case rejected
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .notInstalled: "Atoll is not installed"
        case .notRunning: "Open Atoll to connect"
        case .denied: "Approve CPA Widget in Atoll Settings → Extensions"
        case .timedOut: "Atoll extension service did not respond — retry"
        case .disconnected: "Atoll extension service is unavailable — update Atoll and retry"
        case .rejected: "Atoll rejected the dashboard — check Extensions settings and retry"
        case .invalidPayload: "Atoll dashboard could not be prepared"
        }
    }
}
