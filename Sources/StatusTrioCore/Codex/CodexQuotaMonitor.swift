import AppKit
import Combine

@MainActor
final class CodexQuotaMonitor: ObservableObject {
    enum State: Equatable {
        case disabled, loading
        case ready(CodexQuotaSnapshot)
        case failed(CodexQuotaError)
    }

    @Published private(set) var state: State = .disabled
    @Published private(set) var isRefreshing = false
    private(set) var mode: BottomIndicatorMode = .volume
    private let fetch: @Sendable () async throws -> CodexQuotaSnapshot
    private var pollingTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var generation = 0
    private var wakeSubscription: AnyCancellable?

    init(fetch: @escaping @Sendable () async throws -> CodexQuotaSnapshot = {
        try await CodexQuotaClient().fetch()
    }) {
        self.fetch = fetch
        wakeSubscription = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.mode != .volume else { return }
                self.state = .loading
                self.refresh()
            }
    }

    deinit {
        pollingTask?.cancel()
        requestTask?.cancel()
    }

    func setMode(_ mode: BottomIndicatorMode) {
        guard self.mode != mode else { return }
        stop()
        self.mode = mode
        guard mode != .volume else { return }
        state = .loading
        refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        generation += 1
        pollingTask?.cancel()
        pollingTask = nil
        requestTask?.cancel()
        requestTask = nil
        isRefreshing = false
        mode = .volume
        state = .disabled
    }

    func refresh() {
        guard mode != .volume, !isRefreshing else { return }
        generation += 1
        let currentGeneration = generation
        let fetch = fetch
        isRefreshing = true
        requestTask = Task { [weak self] in
            let result: State
            do {
                result = .ready(try await fetch())
            } catch is CancellationError {
                return
            } catch {
                result = .failed((error as? CodexQuotaError) ?? .network)
            }
            guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
            self.state = result
            self.isRefreshing = false
            self.requestTask = nil
        }
    }

    func indicator(for mode: BottomIndicatorMode, at now: Date = Date()) -> CodexQuotaIndicator? {
        guard mode != .volume else { return nil }
        let window: CodexQuotaWindow?
        if case .ready(let snapshot) = state {
            window = snapshot.window(for: mode, at: now)
        } else {
            window = nil
        }
        return CodexQuotaIndicator(mode: mode, remainingPercent: window?.remainingPercent)
    }
}
