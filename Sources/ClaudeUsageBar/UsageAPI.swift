import Foundation

enum UsageAPIError: LocalizedError {
    case signInExpired
    case rateLimited
    case httpError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .signInExpired: return "Sign-in expired. Open Claude Code once to refresh it."
        case .rateLimited: return "Rate limited by Anthropic. Will retry on the next poll."
        case .httpError(let code): return "Usage endpoint returned HTTP \(code)."
        case .invalidResponse: return "Usage endpoint returned an unexpected payload."
        }
    }
}

/// Talks to Anthropic's undocumented `/api/oauth/usage` endpoint, the same
/// one claude.ai's Settings > Usage page and Claude Code's `/usage` command
/// use. It is not a published API: the fields, the auth scheme and the
/// endpoint itself can change without notice.
actor UsageAPI {
    /// Floor between attempts, however often the UI asks. The endpoint
    /// rate-limits after a handful of requests in a minute or two, and
    /// community tools that use it cache for 60-120 s. Inside the window
    /// the previous outcome is replayed, error included, so a failed poll
    /// doesn't turn into a burst of retries.
    static let minimumPollInterval: TimeInterval = 45

    private let session = URLSession(configuration: .ephemeral)
    private let debug = ProcessInfo.processInfo.environment["CLAUDE_USAGE_DEBUG"] == "1"
    private var lastAttempt = Date.distantPast
    private var lastResult: Result<UsageSnapshot, Error>?

    func fetchUsage() async throws -> UsageSnapshot {
        if let lastResult, Date().timeIntervalSince(lastAttempt) < Self.minimumPollInterval {
            return try lastResult.get()
        }
        lastAttempt = Date()
        do {
            let snapshot = try await requestUsage()
            lastResult = .success(snapshot)
            return snapshot
        } catch {
            lastResult = .failure(error)
            throw error
        }
    }

    private func requestUsage() async throws -> UsageSnapshot {
        let token = try KeychainReader.readAccessToken()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)
        if debug {
            print("--- /api/oauth/usage raw response ---")
            print(String(decoding: data, as: UTF8.self))
            print("--------------------------------------")
        }

        guard let http = response as? HTTPURLResponse else { throw UsageAPIError.invalidResponse }
        switch http.statusCode {
        case 200...299:
            break
        case 401:
            // The stored token is only refreshed when Claude Code itself runs,
            // so an expired one means "open Claude Code", not a bug here.
            throw UsageAPIError.signInExpired
        case 429:
            throw UsageAPIError.rateLimited
        default:
            throw UsageAPIError.httpError(http.statusCode)
        }

        guard let snapshot = try? UsageSnapshot.decode(data) else { throw UsageAPIError.invalidResponse }
        return snapshot
    }
}
