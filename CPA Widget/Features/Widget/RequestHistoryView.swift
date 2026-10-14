import SwiftUI

/// Second widget tab: the proxied API requests the instance has logged, newest first, 20 per page.
struct RequestHistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Proxied API requests").font(.caption).foregroundStyle(.secondary)
                if model.isLoadingRequestHistory || model.isLoadingRequestModels { ProgressView().controlSize(.small) }
                Spacer(minLength: 8)
                if let updated = model.requestHistoryUpdated {
                    Text(updated, style: .relative)
                        .font(.caption).foregroundStyle(.secondary)
                        .help("Last successful read of the instance's file log: \(updated.formatted())")
                }
                Button("Reload requests", systemImage: "arrow.clockwise") {
                    Task {
                        await model.refreshRequestHistory()
                        await model.loadModelsForRequestPage()
                    }
                }
                .labelStyle(.iconOnly).disabled(model.isLoadingRequestHistory)
                .help("Re-read the instance's file log")
            }
            if let error = model.requestHistoryError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.requestHistory.isEmpty {
                ContentUnavailableView(
                    "No request history",
                    systemImage: "list.bullet.rectangle",
                    description: Text("The instance's file log holds no proxied API requests yet.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(model.requestPageEntries.enumerated()), id: \.offset) { _, entry in
                            RequestLogRow(entry: entry, model: modelState(for: entry))
                        }
                    }
                    .padding(.trailing, 4)
                }
                pager
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await pollWhileVisible() }
        .task(id: model.requestPage) { await model.loadModelsForRequestPage() }
    }

    private var pager: some View {
        HStack {
            Button("Newer", systemImage: "chevron.left") { model.showRequestPage(model.requestPage - 1) }
                .disabled(model.requestPage == 0)
            Spacer()
            Text("Page \(model.requestPage + 1) of \(model.requestPageCount)")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Older", systemImage: "chevron.right") { model.showRequestPage(model.requestPage + 1) }
                .disabled(model.requestPage >= model.requestPageCount - 1)
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private func modelState(for entry: RequestLogEntry) -> RequestModelState {
        guard let requestID = entry.requestID else { return .unavailable }
        guard let resolved = model.requestModels[requestID] else { return .unloaded }
        guard let name = resolved else { return .unavailable }
        return .known(name)
    }

    private func pollWhileVisible() async {
        while !Task.isCancelled {
            await model.refreshRequestHistory()
            await model.loadModelsForRequestPage()
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
        }
    }
}
