import Foundation

struct QuotaGroup: Decodable, Sendable {
    let displayName: String?
    let buckets: [QuotaBucket]?
}
