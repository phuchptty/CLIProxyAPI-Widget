import Foundation

struct QuotaSubscription: Decodable, Sendable {
    let plan: String?
    let tierName: String?
}
