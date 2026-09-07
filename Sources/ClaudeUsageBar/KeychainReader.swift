import Foundation

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "No 'Claude Code-credentials' item in Keychain. Install Claude Code and log in with your Pro/Max/Team account once, then try again."
        case .commandFailed(let detail):
            return "Keychain lookup failed: \(detail)"
        }
    }
}

/// Reads the OAuth credential that Claude Code writes to the macOS Keychain
/// after a successful subscription sign-in.
///
/// This shells out to `/usr/bin/security` rather than calling the Security
/// framework directly, because the item belongs to Claude Code's own
/// keychain access group, not this app's. The command-line tool can still
/// read it, but macOS will show a one-off "ClaudeUsageBar wants to access
/// key 'Claude Code-credentials'" prompt the first time — choose
/// "Always Allow" so subsequent polls don't prompt again.
struct KeychainReader {
    static let service = "Claude Code-credentials"

    /// Returns the raw string stored in the keychain item. This is often a
    /// JSON blob containing the access token, refresh token, and expiry
    /// rather than a bare token — see `OAuthCredential.extract` for parsing.
    static func readRawCredential() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "unknown error"
            if errText.contains("could not be found") {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.commandFailed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let text = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw KeychainError.itemNotFound
        }
        return text
    }
}
