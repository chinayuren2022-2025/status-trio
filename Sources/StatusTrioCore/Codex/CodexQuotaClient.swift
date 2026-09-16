import Foundation

/// A minimal, read-only implementation of the native OAuth path documented by CodexBar.
/// Never refreshes or writes Codex-owned credentials, imports cookies, or logs response bodies.
struct CodexQuotaClient: Sendable {
    struct Credentials: Decodable, Equatable, Sendable {
        struct Tokens: Decodable, Equatable, Sendable {
            let access_token: String
            let account_id: String?
        }
        let auth_mode: String?
        let tokens: Tokens?

        static func read(from url: URL) throws -> Self {
            guard let data = try? Data(contentsOf: url), data.count < 1_048_576,
                  let value = try? JSONDecoder().decode(Self.self, from: data),
                  value.auth_mode == nil || value.auth_mode == "chatgpt",
                  let tokens = value.tokens, !tokens.access_token.isEmpty else {
                throw CodexQuotaError.signIn
            }
            return value
        }
    }

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    let credentialsURL: URL
    let transport: Transport

    init(
        credentialsURL: URL = Self.credentialsURL(),
        transport: @escaping Transport = { request in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    ) {
        self.credentialsURL = credentialsURL
        self.transport = transport
    }

    static func credentialsURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let path = environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("auth.json")
        }
        return home.appendingPathComponent(".codex/auth.json")
    }

    func fetch() async throws -> CodexQuotaSnapshot {
        let credentials = try Credentials.read(from: credentialsURL)
        guard let tokens = credentials.tokens else { throw CodexQuotaError.signIn }
        // Fixed first-party destination; do not send credentials to configurable hosts or redirects.
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
        request.setValue(tokens.account_id, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StatusTrio", forHTTPHeaderField: "User-Agent")
        let data: Data
        let status: Int
        do {
            (data, status) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CodexQuotaError.network
        }
        try Task.checkCancellation()
        guard status != 401 && status != 403 else { throw CodexQuotaError.signIn }
        guard status == 200, data.count < 1_048_576 else { throw CodexQuotaError.network }
        // Do not publish a response for credentials that were replaced during the request.
        guard (try? Credentials.read(from: credentialsURL)) == credentials else {
            throw CodexQuotaError.accountChanged
        }
        return try CodexQuotaSnapshot.decode(data, at: Date())
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
