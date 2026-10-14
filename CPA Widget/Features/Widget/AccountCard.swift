import SwiftUI

struct AccountCard: View {
    let account: AccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(account.credential.name ?? account.id)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            if let success = account.credential.success, let failed = account.credential.failed {
                Text("\(success) successful · \(failed) failed requests")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let quota = account.quota {
                if let plan = quota.subscription?.plan ?? quota.subscription?.tierName {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array((quota.summary ?? []).enumerated()), id: \.offset) { _, metric in
                    HStack(spacing: 6) {
                        Text(metric.label).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(metricText(metric)).monospacedDigit()
                    }
                    .font(.caption)
                }
                ForEach(Array((quota.groups ?? []).enumerated()), id: \.offset) { _, group in
                    if let name = group.displayName { Text(name).font(.caption.bold()) }
                    ForEach(Array((group.buckets ?? []).enumerated()), id: \.offset) { _, bucket in
                        QuotaBucketRow(bucket: bucket)
                    }
                }
                if (quota.groups ?? []).allSatisfy({ ($0.buckets ?? []).isEmpty }) && (quota.summary ?? []).isEmpty {
                    Text("No quota metrics returned").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(account.errorMessage ?? "Quota unavailable")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        // Fill the grid cell so both cards in a row end at the same height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var status: String {
        if account.credential.disabled == true { return "Disabled" }
        if account.credential.unavailable == true { return "Unavailable" }
        return account.credential.status?.capitalized ?? "Unknown"
    }

    private func metricText(_ metric: QuotaMetric) -> String {
        if metric.format == "currency", let currency = metric.currency {
            return metric.value.formatted(.currency(code: currency))
        }
        return metric.value.formatted(.number.precision(.fractionLength(0...2))) + (metric.unit.map { " \($0)" } ?? "")
    }
}
