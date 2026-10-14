import Foundation

struct QuotaMetric: Decodable, Sendable {
    let key: String
    let label: String
    let value: Double
    let unit: String?
    let format: String?
    let currency: String?
}
