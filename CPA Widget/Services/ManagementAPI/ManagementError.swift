import Foundation

enum ManagementError: LocalizedError {
    case invalidURL, invalidResponse, unsupportedQuota, missingKey
    case providerMetadata(String), providerHTTP(Int), providerResponse(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter an instance origin or /v8/management URL without credentials, query, or fragment."
        case .missingKey: "Enter a management key."
        case .invalidResponse: "The instance returned an invalid response."
        case .unsupportedQuota: "Quota unavailable: this credential has no v8 quota plugin or supported provider probe."
        case .providerMetadata(let field): "Quota unavailable: the instance did not expose this credential's \(field)."
        case .providerHTTP(let code): "The provider returned HTTP \(code) while reading quota."
        case .providerResponse(let reason): "The provider returned an unexpected quota response (\(reason))."
        case .http(401): "Authentication failed. Check the management key. Automatic refresh is paused until settings are saved."
        case .http(403): "Access denied. Check management.allow-remote and the management key. Automatic refresh is paused until settings are saved."
        case .http(404): "Endpoint unavailable. Check v8 support, management enablement, and the quota plugin."
        case .http(let code): "The instance returned HTTP \(code)."
        }
    }

    /// Only management-API authentication failures pause automatic refresh, so a provider probe
    /// that is rejected by an expired upstream token never bans the client's management IP.
    var stopsAuthentication: Bool {
        switch self {
        case .http(401), .http(403): true
        default: false
        }
    }
}
