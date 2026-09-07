import Foundation

/// The Keychain item Claude Code writes is usually JSON such as
/// `{"accessToken": "...", "refreshToken": "...", "expiresAt": ...}`,
/// but the exact key names aren't documented and have shifted between
/// Claude Code versions before. This tries a handful of likely keys and
/// falls back to treating the whole string as a bare token if it isn't
/// JSON at all.
struct OAuthCredential {
    let accessToken: String

    static func extract(from raw: String) -> OAuthCredential? {
        guard let data = raw.data(using: .utf8) else { return nil }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let candidateKeys = ["accessToken", "access_token", "token", "oauthToken"]

            for key in candidateKeys {
                if let token = json[key] as? String {
                    return OAuthCredential(accessToken: token)
                }
            }
            // Sometimes nested, e.g. {"claudeAiOauth": {"accessToken": "..."}}
            for value in json.values {
                if let nested = value as? [String: Any] {
                    for key in candidateKeys {
                        if let token = nested[key] as? String {
                            return OAuthCredential(accessToken: token)
                        }
                    }
                }
            }
            return nil
        }

        // Not JSON — assume the keychain item is the bare token string.
        return OAuthCredential(accessToken: raw)
    }
}

/// A view over `/api/oauth/usage`, matched against a real captured payload:
///
///     {"five_hour":{"utilization":0.0,"resets_at":"2026-09-07T12:49:59.865922+00:00",...},
///      "seven_day":{"utilization":0.0,"resets_at":"2026-09-14T06:59:59.865947+00:00",...},
///      "limits":[
///        {"kind":"session","group":"session","percent":0,"severity":"normal",
///         "resets_at":"2026-09-07T12:49:59.865922+00:00","scope":null,"is_active":true},
///        {"kind":"weekly_all","group":"weekly","percent":0,"severity":"normal",
///         "resets_at":"2026-09-14T06:59:59.865947+00:00","scope":null,"is_active":false},
///        {"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal",
///         "resets_at":null,"scope":{"model":{"id":null,"display_name":"Fable"},...},"is_active":false}
///      ], ...}
///
/// `limits` entries already carry a 0-100 `percent` plus their own
/// `resets_at`, so that's used as the primary source. `five_hour`/
/// `seven_day` are kept as a fallback, but note their `utilization` is a
/// 0-1 fraction, not a percentage — it's scaled by 100 below.
///
/// Still unverified: whether `percent` stays 0-100 once usage is nonzero,
/// and what `weekly_scoped` (per-model, e.g. the "Fable" entry above) is
/// for. If Anthropic reshuffles this again, rerun with
/// `CLAUDE_USAGE_DEBUG=1 swift run` and compare against this comment block.
struct UsageSnapshot {
    let raw: [String: Any]

    struct LimitEntry {
        let kind: String
        let percent: Double
        let severity: String
        let resetsAt: Date?
        let isActive: Bool
    }

    var limits: [LimitEntry] {
        guard let arr = raw["limits"] as? [[String: Any]] else { return [] }
        return arr.compactMap { entry in
            guard let kind = entry["kind"] as? String else { return nil }
            let percent = (entry["percent"] as? Double) ?? (entry["percent"] as? Int).map(Double.init) ?? 0
            let severity = entry["severity"] as? String ?? "normal"
            let isActive = entry["is_active"] as? Bool ?? false
            let resetsAt = (entry["resets_at"] as? String).flatMap(Self.parseDate)
            return LimitEntry(kind: kind, percent: percent, severity: severity, resetsAt: resetsAt, isActive: isActive)
        }
    }

    private var sessionLimit: LimitEntry? { limits.first { $0.kind == "session" } }
    private var weeklyLimit: LimitEntry? { limits.first { $0.kind == "weekly_all" } }

    var sessionUsedPercent: Double? {
        sessionLimit?.percent ?? fractionAsPercent(path: ["five_hour", "utilization"])
    }

    var sessionResetsAt: Date? {
        sessionLimit?.resetsAt ?? dateValue(path: ["five_hour", "resets_at"])
    }

    var weeklyUsedPercent: Double? {
        weeklyLimit?.percent ?? fractionAsPercent(path: ["seven_day", "utilization"])
    }

    var weeklyResetsAt: Date? {
        weeklyLimit?.resetsAt ?? dateValue(path: ["seven_day", "resets_at"])
    }

    /// Highest-severity active limit, if any — useful for deciding whether
    /// to show a warning state (e.g. severity moves from "normal" as you
    /// approach a cap).
    var mostSevereActiveLimit: LimitEntry? {
        limits.filter { $0.isActive }.max { lhs, rhs in
            severityRank(lhs.severity) < severityRank(rhs.severity)
        }
    }

    private func severityRank(_ severity: String) -> Int {
        switch severity {
        case "critical": return 3
        case "warning": return 2
        case "normal": return 1
        default: return 0
        }
    }

    // MARK: - Lookup helpers

    private func value(at path: [String]) -> Any? {
        var current: Any? = raw
        for key in path {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[key]
        }
        return current
    }

    private func fractionAsPercent(path: [String]) -> Double? {
        if let v = value(at: path) {
            if let d = v as? Double { return d * 100 }
            if let i = v as? Int { return Double(i) * 100 }
        }
        return nil
    }

    private func dateValue(path: [String]) -> Date? {
        (value(at: path) as? String).flatMap(Self.parseDate)
    }

    /// Timestamps in the payload look like "2026-09-07T12:49:59.865922+00:00"
    /// — microsecond fractional seconds plus a colon-separated offset.
    /// ISO8601DateFormatter needs .withFractionalSeconds explicitly or this
    /// fails to parse; falls back to a plain parse for safety.
    static func parseDate(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
