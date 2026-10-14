import Observation

@MainActor
@Observable
final class AppRefreshCoordinator {
    enum Consumer: Hashable { case panel, atoll }

    private let model: AppModel
    private var consumers: Set<Consumer> = []
    private var pollingTask: Task<Void, Never>?
    private var generation = 0

    init(model: AppModel) { self.model = model }

    func setActive(_ consumer: Consumer, _ active: Bool) {
        if active { consumers.insert(consumer) } else { consumers.remove(consumer) }
        guard consumers.isEmpty else {
            if pollingTask == nil || pollingTask?.isCancelled == true { startAfterPriorCycle() }
            return
        }
        generation += 1
        pollingTask?.cancel()
    }

    func shutdown() {
        consumers.removeAll()
        generation += 1
        pollingTask?.cancel()
    }

    private func startAfterPriorCycle() {
        let oldTask = pollingTask
        generation += 1
        let currentGeneration = generation
        pollingTask = Task { [weak self] in
            await oldTask?.value
            guard let self, !Task.isCancelled, self.generation == currentGeneration, !self.consumers.isEmpty else { return }
            while !Task.isCancelled, !self.consumers.isEmpty {
                await self.model.refresh()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
            if self.generation == currentGeneration { self.pollingTask = nil }
            if !self.consumers.isEmpty { self.startAfterPriorCycle() }
        }
    }
}
