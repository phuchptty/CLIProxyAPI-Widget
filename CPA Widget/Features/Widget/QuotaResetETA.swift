import Foundation

/// Quota resets are shown as a countdown — "in 2 hours", "in 2 minutes" — because what a monitor
/// answers is how much of a window is left, not when on the clock it ends. The absolute local time
/// stays one hover away.
///
/// Main-actor isolated: both formatters are reference types that are neither `Sendable` nor cheap
/// to build, and every caller is a view body.
@MainActor
enum QuotaResetETA {
    private static let iso = ISO8601DateFormatter()
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter
    }()

    /// "Resets in 2 hours", "Reset 3 minutes ago", or the instance's own string when it is not a
    /// parseable ISO 8601 instant.
    static func text(for value: String) -> String {
        guard let date = date(from: value) else { return unparsed(value) }
        let eta = etaText(until: date)
        return date > Date.now ? "Resets \(eta)" : "Reset \(eta)"
    }

    /// The absolute reset time, in local time.
    static func help(for value: String) -> String {
        guard let date = date(from: value) else { return unparsed(value) }
        return "Resets \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private static func unparsed(_ value: String) -> String { "Reset: \(value)" }

    /// Rounds to a whole unit before formatting. The formatter itself truncates, so a window that
    /// resets 1 h 59 m from now would otherwise be reported as "in 1 hour" instead of "in 2 hours".
    private static func etaText(until date: Date) -> String {
        let now = Date.now
        let seconds = date.timeIntervalSince(now)
        let magnitude = abs(seconds)
        let unit: Double = magnitude < 60 ? 1 : magnitude < 3600 ? 60 : magnitude < 86_400 ? 3600 : 86_400
        let offset = max(unit, (magnitude / unit).rounded() * unit) * (seconds < 0 ? -1 : 1)
        return relative.localizedString(for: now.addingTimeInterval(offset), relativeTo: now)
    }

    /// Reset strings arrive as ISO 8601 with or without fractional seconds.
    private static func date(from value: String) -> Date? {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }
}
