import Foundation

enum UsageAPIError: Error, LocalizedError {
    case notAuthenticated
    case httpError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Could not extract a usable OAuth token from Keychain."
        case .httpError(let code): return "Usage endpoint returned HTTP \(code)."
        case .invalidResponse: return "Usage endpoint returned an unexpected payload."
        }
    }
}

/// Talks to Anthropic's undocumented `/api/oauth/usage` endpoint — the same
/// one claude.ai's Settings > Usage page and Claude Code's `/usage` command
/// call. This is NOT a published or supported API: field names, the auth
/// scheme, and its very existence can change without notice. Treat this
/// client as disposable and expect to adjust it.
final class UsageAPI {
    private let session = URLSession(configuration: .ephemeral)
    private var lastGoodSnapshot: UsageSnapshot?
    private var lastFetchTime: Date?

    // Be polite — the endpoint rate-limits aggressively (existing
    // community tools cache for 60-120s). This enforces a floor regardless
    // of how often the UI layer asks for a refresh.
    private let minimumPollInterval: TimeInterval = 45

    func fetchUsage() async throws -> UsageSnapshot {
        if let last = lastFetchTime, Date().timeIntervalSince(last) < minimumPollInterval,
           let cached = lastGoodSnapshot {
            return cached
        }

        let raw = try KeychainReader.readRawCredential()
        guard let credential = OAuthCredential.extract(from: raw) else {
            throw UsageAPIError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)

        if ProcessInfo.processInfo.environment["CLAUDE_USAGE_DEBUG"] == "1" {
            print("--- /api/oauth/usage raw response ---")
            print(String(data: data, encoding: .utf8) ?? "<binary>")
            print("--------------------------------------")
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.invalidResponse
        }

        if http.statusCode == 429, let cached = lastGoodSnapshot {
            return cached // serve stale data rather than surfacing an error on rate limit
        }
        guard (200...299).contains(http.statusCode) else {
            throw UsageAPIError.httpError(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.invalidResponse
        }

        let snapshot = UsageSnapshot(raw: json)
        lastGoodSnapshot = snapshot
        lastFetchTime = Date()
        return snapshot
    }
}
