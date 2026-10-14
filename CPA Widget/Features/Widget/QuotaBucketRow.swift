import SwiftUI

struct QuotaBucketRow: View {
    let bucket: QuotaBucket

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let remaining = bucket.availableFraction {
                QuotaRing(remainingFraction: remaining)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.window ?? "Quota window")
                    .font(.caption)
                    .lineLimit(2)
                if bucket.availableFraction == nil {
                    Text("Unavailable").font(.caption2).foregroundStyle(.secondary)
                }
                if let description = bucket.description, !description.isEmpty {
                    Text(description)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let reset = bucket.resetTime, !reset.isEmpty {
                    Text(QuotaResetETA.text(for: reset))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(QuotaResetETA.help(for: reset))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(bucket.window ?? "Quota window")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let remaining = bucket.availableFraction, let used = bucket.usedFraction else { return "Unavailable" }
        return "\(remaining.formatted(.percent)) remaining, \(used.formatted(.percent)) used"
    }
}
