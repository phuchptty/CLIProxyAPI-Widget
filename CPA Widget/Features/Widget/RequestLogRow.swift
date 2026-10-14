import SwiftUI

/// What the history tab knows about a request's model.
enum RequestModelState: Equatable {
    /// The request file has not been read yet.
    case unloaded
    /// The instance kept no request file for this request, so the model is not known.
    case unavailable
    case known(String)
}

/// One proxied API request: when it was logged, which model it asked for, and how it ended.
struct RequestLogRow: View {
    let entry: RequestLogEntry
    let model: RequestModelState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.timeOfDay)
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .fixedSize()
                Text("\(entry.method) \(entry.path)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Text(entry.status.formatted())
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(statusTint)
                    .fixedSize()
            }
            Text(modelText)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text(entry.latency)
                Text(entry.clientIP)
                if let requestID = entry.requestID { Text(requestID) }
                if let note = entry.note { Text(note).foregroundStyle(.orange) }
            }
            .font(.caption2).foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var modelText: String {
        switch model {
        case .unloaded: "Model: loading…"
        case .unavailable: "Model: unavailable"
        case .known(let name): "Model: \(name)"
        }
    }

    private var accessibilityLabel: String {
        var parts = [entry.timeOfDay, "\(entry.method) \(entry.path)", "HTTP \(entry.status)", modelText, entry.latency, entry.clientIP]
        if let requestID = entry.requestID { parts.append("request \(requestID)") }
        if let note = entry.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    /// Failures carry the colour; a successful request is the quiet default.
    private var statusTint: Color {
        if entry.status >= 500 { return .red }
        if entry.status >= 400 { return .orange }
        return .secondary
    }
}
