import Foundation

/// Response of the Codex usage endpoint (`/backend-api/wham/usage`), which the instance itself
/// does not parse. Field names match the payload the Management Center probe reads.
struct CodexUsageResponse: Decodable, Sendable {
    let planType: String?
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable, Sendable {
        let limitReached: Bool?
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case limitReached = "limit_reached"
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Double?
        let resetAfterSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAfterSeconds = "reset_after_seconds"
        }
    }
}
