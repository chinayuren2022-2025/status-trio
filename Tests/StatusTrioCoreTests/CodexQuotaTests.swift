import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

private let quotaFixture = Data("""
{"rate_limit": {
  "primary_window": {"used_percent": 26, "reset_at": 2000000000, "limit_window_seconds": 18000},
  "secondary_window": {"used_percent": 80, "reset_at": 2000500000, "limit_window_seconds": 604800}
}}
""".utf8)
private let fixtureNow = Date(timeIntervalSince1970: 1900000000)

struct CodexQuotaTests {
    @Test func decodesRemainingRatherThanUsedAndRespectsFreshness() throws {
        let snapshot = try CodexQuotaSnapshot.decode(quotaFixture, at: fixtureNow)
        #expect(snapshot.window(for: .codexSession, at: fixtureNow)?.remainingPercent == 74)
        #expect(snapshot.window(for: .codexWeekly, at: fixtureNow)?.remainingPercent == 20)
        #expect(snapshot.window(for: .volume, at: fixtureNow) == nil)
        #expect(snapshot.window(for: .codexSession, at: fixtureNow.addingTimeInterval(120)) == nil)
    }

    @Test(arguments: [(0.0, 0), (0.1, 1), (25.0, 1), (25.1, 2), (50.0, 2), (50.1, 3), (75.0, 3), (75.1, 4), (100.0, 4)])
    func dotBoundaries(value: Double, count: Int) {
        #expect(CodexQuotaIndicator(mode: .codexSession, remainingPercent: value).dotCount == count)
        #expect(CodexQuotaIndicator(mode: .codexSession, remainingPercent: nil).dotCount == nil)
    }

    @Test func weeklyOnlyWindowIsNotMislabelledAsSession() throws {
        let data = Data("""
        {"rate_limit":{"primary_window":{"used_percent":10,"reset_at":2000000000,"limit_window_seconds":604800}}}
        """.utf8)
        let snapshot = try CodexQuotaSnapshot.decode(data, at: fixtureNow)
        #expect(snapshot.window(for: .codexSession, at: fixtureNow) == nil)
        #expect(snapshot.window(for: .codexWeekly, at: fixtureNow)?.remainingPercent == 90)
    }

    @Test func resetIsNotAssumedToRefillWithoutFreshReading() {
        let snapshot = CodexQuotaSnapshot(windows: [
            .init(remainingPercent: 0, resetsAt: fixtureNow, durationSeconds: 18000)
        ], fetchedAt: fixtureNow)
        #expect(snapshot.window(for: .codexSession, at: fixtureNow) == nil)
    }

    @Test(arguments: ["{}", "null", "{\"rate_limit\":null}", "{\"rate_limit\":{}}", "not JSON",
                     "{\"rate_limit\":{\"primary_window\":{\"used_percent\":101,\"reset_at\":2000000000,\"limit_window_seconds\":18000}}}"])
    func missingOrInvalidDataIsNotZeroQuota(json: String) {
        #expect(throws: CodexQuotaError.unsupported) {
            try CodexQuotaSnapshot.decode(Data(json.utf8), at: fixtureNow)
        }
    }

    @Test @MainActor func unknownAndZeroQuotaRenderDifferently() throws {
        var status = MenuBarStatus.placeholder
        status.codexIndicator = .init(mode: .codexSession, remainingPercent: nil)
        let unknown = try #require(StatusIconRenderer.render(
            menuBarStatus: status, size: 100, scale: 2, foreground: CGColor(gray: 1, alpha: 1)
        )?.dataProvider?.data)
        status.codexIndicator = .init(mode: .codexSession, remainingPercent: 0)
        let zero = try #require(StatusIconRenderer.render(
            menuBarStatus: status, size: 100, scale: 2, foreground: CGColor(gray: 1, alpha: 1)
        )?.dataProvider?.data)
        #expect((unknown as Data) != (zero as Data))
        let suite = "CodexQuotaAccessibility.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let summary = StatusPresentation.statusItemAccessibilityValue(status, localization: localization)
        #expect(summary.contains("Codex"))
        #expect(summary.contains("0% remaining"))
        #expect(!summary.contains("Volume"))
    }

    @Test @MainActor func quotaUsesDotsOnBothSurfacesRegardlessOfVolumeStyle() throws {
        var status = MenuBarStatus.placeholder
        status.codexIndicator = .init(mode: .codexWeekly, remainingPercent: 37)
        let menuDots = try #require(StatusIconRenderer.render(
            menuBarStatus: status, size: 100, scale: 2, foreground: CGColor(gray: 1, alpha: 1),
            volumeOptions: .init(displayStyle: .dots)
        )?.dataProvider?.data)
        let menuArc = try #require(StatusIconRenderer.render(
            menuBarStatus: status, size: 100, scale: 2, foreground: CGColor(gray: 1, alpha: 1),
            volumeOptions: .init(displayStyle: .arc)
        )?.dataProvider?.data)
        #expect((menuDots as Data) == (menuArc as Data))
        let dockDots = try #require(DockIconRenderer.image(status: status,
            volumeOptions: .init(displayStyle: .dots))?.tiffRepresentation)
        let dockArc = try #require(DockIconRenderer.image(status: status,
            volumeOptions: .init(displayStyle: .arc))?.tiffRepresentation)
        #expect(dockDots == dockArc)
        status.codexIndicator = .init(mode: .codexWeekly, remainingPercent: nil)
        let unknown = try #require(DockIconRenderer.image(status: status)?.tiffRepresentation)
        #expect(unknown != dockDots)
        status.codexIndicator = .init(mode: .codexWeekly, remainingPercent: 0)
        let empty = try #require(DockIconRenderer.image(status: status)?.tiffRepresentation)
        #expect(empty != unknown)
    }

    @Test func dockCacheDistinguishesQuotaStatesWithoutRedrawingWithinABucket() {
        func key(_ indicator: CodexQuotaIndicator?) -> DockIconRenderKey {
            var status = MenuBarStatus.placeholder
            status.codexIndicator = indicator
            return DockIconRenderKey(status: status, options: .standard,
                                     connectionOptions: .standard, backgroundStyle: .dark)
        }
        let volume = key(nil)
        let unknown = key(.init(mode: .codexWeekly, remainingPercent: nil))
        let empty = key(.init(mode: .codexWeekly, remainingPercent: 0))
        let two = key(.init(mode: .codexWeekly, remainingPercent: 37))
        #expect(volume != unknown)
        #expect(unknown != empty)
        #expect(empty != two)
        #expect(two == key(.init(mode: .codexWeekly, remainingPercent: 40)))
        #expect(two != key(.init(mode: .codexWeekly, remainingPercent: 51)))
    }

    @Test func credentialsPathHonorsExplicitHome() {
        let home = URL(fileURLWithPath: "/example/user")
        #expect(CodexQuotaClient.credentialsURL(environment: [:], home: home).path == "/example/user/.codex/auth.json")
        #expect(CodexQuotaClient.credentialsURL(environment: ["CODEX_HOME": "/example/profile"], home: home).path == "/example/profile/auth.json")
    }

    @Test func authenticatesOnlyToFirstPartyAndDoesNotModifyCredentials() async throws {
        let file = try FixtureAuth()
        defer { file.remove() }
        let before = try Data(contentsOf: file.url)
        let client = CodexQuotaClient(credentialsURL: file.url) { request in
            #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-test-token")
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "fake-account")
            #expect(request.timeoutInterval == 20)
            return (quotaFixture, 200)
        }
        let result = try await client.fetch()
        #expect(result.windows.count == 2)
        #expect(try Data(contentsOf: file.url) == before)
    }

    @Test(arguments: [(401, CodexQuotaError.signIn), (403, .signIn), (429, .network), (500, .network), (302, .network)])
    func mapsHTTPFailuresWithoutLeakingBody(status: Int, expected: CodexQuotaError) async throws {
        let file = try FixtureAuth()
        defer { file.remove() }
        let client = CodexQuotaClient(credentialsURL: file.url) { _ in
            (Data("sensitive body must not be displayed".utf8), status)
        }
        await #expect(throws: expected) { try await client.fetch() }
    }

    @Test func rejectsResponseAfterAccountChanges() async throws {
        let file = try FixtureAuth()
        defer { file.remove() }
        let url = file.url
        let client = CodexQuotaClient(credentialsURL: url) { _ in
            try Data("{}".utf8).write(to: url)
            return (quotaFixture, 200)
        }
        await #expect(throws: CodexQuotaError.accountChanged) { try await client.fetch() }
    }

    @Test func APIKeyLoginDoesNotSendAnyRequest() async throws {
        let file = try FixtureAuth(contents: "{\"auth_mode\":\"apikey\",\"OPENAI_API_KEY\":\"fake-key\"}")
        defer { file.remove() }
        let client = CodexQuotaClient(credentialsURL: file.url) { _ in
            Issue.record("API key accounts must not send a request")
            return (quotaFixture, 200)
        }
        await #expect(throws: CodexQuotaError.signIn) { try await client.fetch() }
    }

    @Test @MainActor func settingsDefaultAndPersistSelection() throws {
        let suite = "CodexQuotaTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SettingsStore(defaults: defaults).bottomIndicatorMode == .volume)
        SettingsStore(defaults: defaults).bottomIndicatorMode = .codexWeekly
        #expect(SettingsStore(defaults: defaults).bottomIndicatorMode == .codexWeekly)
        defaults.set("future-mode", forKey: "bottomIndicatorMode")
        #expect(SettingsStore(defaults: defaults).bottomIndicatorMode == .volume)
    }

    @Test @MainActor func disablingDiscardsAnInFlightResponse() async throws {
        let gate = QuotaFetchGate()
        let monitor = CodexQuotaMonitor { await gate.fetch() }
        #expect(monitor.state == .disabled)
        #expect(await gate.calls == 0)
        monitor.setMode(.codexSession)
        for _ in 0..<1000 {
            if await gate.calls == 1 { break }
            await Task.yield()
        }
        #expect(await gate.calls == 1)
        monitor.refresh()
        #expect(await gate.calls == 1) // deduplicates manual and timer refreshes
        monitor.setMode(.volume)
        try await gate.complete()
        for _ in 0..<20 { await Task.yield() }
        #expect(monitor.state == .disabled)
        #expect(!monitor.isRefreshing)
        #expect(monitor.indicator(for: .volume) == nil)
    }

    @Test @MainActor func failedRefreshClearsPreviouslyUsableQuota() async throws {
        let fetcher = FailingSecondFetch()
        let monitor = CodexQuotaMonitor { try await fetcher.fetch() }
        defer { monitor.stop() }
        monitor.setMode(.codexSession)
        for _ in 0..<1000 {
            if !monitor.isRefreshing { break }
            await Task.yield()
        }
        #expect(monitor.indicator(for: .codexSession)?.remainingPercent == 74)
        monitor.refresh()
        for _ in 0..<1000 {
            if !monitor.isRefreshing { break }
            await Task.yield()
        }
        #expect(monitor.state == .failed(.network))
        #expect(monitor.indicator(for: .codexSession)?.dotCount == nil)
    }
}

private struct FixtureAuth {
    let url: URL
    init(contents: String = "{\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"fake-test-token\",\"account_id\":\"fake-account\"}}") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(contents.utf8).write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: url) }
}

private actor QuotaFetchGate {
    private var continuation: CheckedContinuation<CodexQuotaSnapshot, Never>?
    private(set) var calls = 0
    func fetch() async -> CodexQuotaSnapshot {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func complete() throws {
        continuation?.resume(returning: try CodexQuotaSnapshot.decode(quotaFixture, at: Date()))
        continuation = nil
    }
}

private actor FailingSecondFetch {
    private var calls = 0
    func fetch() throws -> CodexQuotaSnapshot {
        calls += 1
        if calls > 1 { throw CodexQuotaError.network }
        return try CodexQuotaSnapshot.decode(quotaFixture, at: Date())
    }
}
