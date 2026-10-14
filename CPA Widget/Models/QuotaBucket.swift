import Foundation

struct QuotaBucket: Decodable, Sendable {
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?
    let description: String?

    /// Remaining quota bounded to 0–1. A missing or non-finite value stays unavailable rather
    /// than being read as an empty window.
    var availableFraction: Double? {
        guard let remainingFraction, remainingFraction.isFinite else { return nil }
        return min(1, max(0, remainingFraction))
    }

    var usedFraction: Double? {
        availableFraction.map { 1 - $0 }
    }
}
