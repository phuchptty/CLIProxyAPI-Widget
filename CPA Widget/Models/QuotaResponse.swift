import Foundation

struct QuotaResponse: Decodable, Sendable {
    let groups: [QuotaGroup]?
    let summary: [QuotaMetric]?
    let subscription: QuotaSubscription?
}
