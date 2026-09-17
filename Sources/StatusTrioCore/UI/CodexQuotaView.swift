import AppKit
import SwiftUI

struct CodexQuotaView: View {
    @ObservedObject var monitor: CodexQuotaMonitor
    @EnvironmentObject private var localization: Localization

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(localization.string(.codexTitle)).font(.headline)
                    Spacer()
                    Button { monitor.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(monitor.isRefreshing)
                    .help(localization.string(.codexRefresh))
                    .accessibilityLabel(localization.string(.codexRefresh))
                }
                if case .ready(let snapshot) = monitor.state {
                    quotaRow(.codexSession, snapshot: snapshot, now: timeline.date)
                    quotaRow(.codexWeekly, snapshot: snapshot, now: timeline.date)
                    HStack {
                        Text(localization.string(.codexUpdated))
                        Text(snapshot.fetchedAt, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if case .failed(let error) = monitor.state {
                    Text(localization.string(error.messageKey))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(localization.string(.codexLoading))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .environment(\.locale, localization.resolvedLanguage.locale)
    }

    private func quotaRow(_ mode: BottomIndicatorMode, snapshot: CodexQuotaSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(localization.string(mode.titleKey))
                Spacer()
                if let window = snapshot.window(for: mode, at: now) {
                    Text(localization.format(.codexRemaining, Int(window.remainingPercent.rounded())))
                        .monospacedDigit()
                } else {
                    Text(localization.string(.codexUnknown)).foregroundStyle(.secondary)
                }
            }
            if let window = snapshot.window(for: mode, at: now) {
                HStack {
                    Text(localization.string(.codexResets))
                    Text(window.resetsAt, format: .dateTime.month().day().hour().minute())
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct CodexIconPreview: View {
    @ObservedObject var monitor: CodexQuotaMonitor
    @ObservedObject var settings: SettingsStore
    let snapshot: StatusSnapshot
    let isDark: Bool

    var body: some View {
        var status = MenuBarStatus(snapshot: snapshot)
        status.codexIndicator = monitor.indicator(for: settings.bottomIndicatorMode)
        return Image(nsImage: StatusIconRenderer.image(
            menuBarStatus: status, size: settings.iconSize,
            options: settings.batteryIconOptions, connectionOptions: settings.connectionIconOptions,
            volumeOptions: settings.volumeIconOptions,
            appearance: NSAppearance(named: isDark ? .darkAqua : .aqua)
        ))
    }
}
