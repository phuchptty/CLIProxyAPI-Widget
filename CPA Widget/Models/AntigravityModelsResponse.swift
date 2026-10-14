import Foundation

/// Response of the Antigravity models endpoint (`v1internal:fetchAvailableModels`). Each model
/// carries its own quota either under `quotaInfo` or directly on the entry.
struct AntigravityModelsResponse: Decodable, Sendable {
    let models: [String: Model]?

    struct Model: Decodable, Sendable {
        let quotaInfo: QuotaFields?
        let direct: QuotaFields

        var limits: QuotaFields { quotaInfo ?? direct }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            quotaInfo = try container.decodeIfPresent(QuotaFields.self, forKey: .quotaInfo)
            direct = try QuotaFields(from: decoder)
        }

        private enum CodingKeys: String, CodingKey {
            case quotaInfo
        }
    }

    /// One quota reading. Both camelCase and snake_case spellings are accepted because plugin and
    /// probe payloads use either.
    struct QuotaFields: Decodable, Sendable {
        let remainingFraction: Double?
        let remainingFractionSnake: Double?
        let resetTime: String?
        let resetTimeSnake: String?

        var fraction: Double? { remainingFraction ?? remainingFractionSnake }
        var reset: String? { resetTime ?? resetTimeSnake }

        enum CodingKeys: String, CodingKey {
            case remainingFraction
            case remainingFractionSnake = "remaining_fraction"
            case resetTime
            case resetTimeSnake = "reset_time"
        }
    }
}
