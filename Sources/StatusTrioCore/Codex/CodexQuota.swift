import Foundation

enum BottomIndicatorMode: String, CaseIterable, Identifiable, Sendable {
    case volume
    case codexSession
    case codexWeekly

    var id: String { rawValue }
    var titleKey: LocalizationKey {
        switch self {
        case .volume: .volumeTitlePlain
        case .codexSession: .codexSession
        case .codexWeekly: .codexWeekly
        }
    }
}

struct CodexQuotaWindow: Equatable, Sendable {
    let remainingPercent: Double
    let resetsAt: Date
    let durationSeconds: Int

}

struct CodexQuotaSnapshot: Equatable, Sendable {
    let windows: [CodexQuotaWindow]
    let fetchedAt: Date

    func window(for mode: BottomIndicatorMode, at now: Date) -> CodexQuotaWindow? {
        guard now.timeIntervalSince(fetchedAt) < 120 else { return nil }
        let duration: Int
        switch mode {
        case .volume: return nil
        case .codexSession: duration = 5 * 60 * 60
        case .codexWeekly: duration = 7 * 24 * 60 * 60
        }
        // Identify windows by duration, not primary/secondary position (weekly-only plans exist).
        return windows.first { $0.durationSeconds == duration && $0.resetsAt > now }
    }

    static func decode(_ data: Data, at now: Date) throws -> Self {
        struct Response: Decodable {
            struct Limits: Decodable {
                struct Window: Decodable {
                    let used_percent: Double
                    let reset_at: Double
                    let limit_window_seconds: Int
                }
                let primary_window: Window?
                let secondary_window: Window?
            }
            let rate_limit: Limits?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let limits = response.rate_limit else { throw CodexQuotaError.unsupported }
        let windows = [limits.primary_window, limits.secondary_window].compactMap { value -> CodexQuotaWindow? in
            guard let value, value.used_percent.isFinite,
                  (0...100).contains(value.used_percent), value.reset_at.isFinite,
                  value.reset_at > 0, value.limit_window_seconds > 0 else { return nil }
            return CodexQuotaWindow(
                remainingPercent: 100 - value.used_percent,
                resetsAt: Date(timeIntervalSince1970: value.reset_at),
                durationSeconds: value.limit_window_seconds
            )
        }
        guard !windows.isEmpty else { throw CodexQuotaError.unsupported }
        return Self(windows: windows, fetchedAt: now)
    }
}

enum CodexQuotaError: Error, Equatable, Sendable {
    case signIn, network, unsupported, accountChanged

    var messageKey: LocalizationKey {
        switch self {
        case .signIn: .codexSignIn
        case .network: .codexNetworkError
        case .unsupported: .codexUnsupported
        case .accountChanged: .codexAccountChanged
        }
    }
}

struct CodexQuotaIndicator: Equatable, Sendable {
    let mode: BottomIndicatorMode
    let remainingPercent: Double?

    var dotCount: Int? {
        guard let remainingPercent, remainingPercent.isFinite,
              (0...100).contains(remainingPercent) else { return nil }
        return Int(ceil(remainingPercent / 25))
    }
}
