import Foundation

enum KeychainError: LocalizedError {
    case notSignedIn
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "No Claude Code sign-in found. Open Claude Code and sign in with your Pro, Max or Team account once."
        case .unreadable(let detail):
            return "Couldn't read the Claude Code sign-in: \(detail)"
        }
    }
}

/// Reads the OAuth access token that Claude Code stores in the login
/// Keychain after a subscription sign-in.
///
/// This shells out to `/usr/bin/security` rather than calling the Security
/// framework. Claude Code writes the item through the same tool, so reading
/// it this way normally needs no permission prompt, and any grant the user
/// does make attaches to that tool rather than to one particular build of
/// this app. A direct `SecItemCopyMatching` from an unsigned or ad-hoc-signed
/// binary would prompt again after every rebuild.
enum KeychainReader {
    static let service = "Claude Code-credentials"

    /// The stored item is JSON. Only the access token is needed here:
    /// `{"claudeAiOauth":{"accessToken":"…","refreshToken":"…","expiresAt":…}}`
    private struct StoredCredentials: Decodable {
        struct OAuth: Decodable { let accessToken: String }
        let claudeAiOauth: OAuth
    }

    static func readAccessToken() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        switch process.terminationStatus {
        case 0:
            break
        case 44: // errSecItemNotFound
            throw KeychainError.notSignedIn
        default:
            let detail = String(decoding: errorOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw KeychainError.unreadable(detail.isEmpty ? "security exited with status \(process.terminationStatus)" : detail)
        }

        guard let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: output) else {
            throw KeychainError.unreadable("unexpected credential format")
        }
        return credentials.claudeAiOauth.accessToken
    }
}
