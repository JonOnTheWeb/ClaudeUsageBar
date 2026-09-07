import Foundation

/// The parts of `/api/oauth/usage` this app reads. The endpoint is
/// undocumented; the shape below is from a captured payload:
///
///     {"limits":[
///        {"kind":"session","group":"session","percent":0,"severity":"normal",
///         "resets_at":"2026-09-07T12:49:59.865922+00:00","scope":null,"is_active":true},
///        {"kind":"weekly_all","group":"weekly","percent":0,"severity":"normal",
///         "resets_at":"2026-09-14T06:59:59.865947+00:00","scope":null,"is_active":false},
///        {"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal",
///         "resets_at":null,"scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}
///      ],
///      "five_hour":{"utilization":0.0,"resets_at":"2026-09-07T12:49:59.865922+00:00", …},
///      "seven_day":{"utilization":0.0,"resets_at":"2026-09-14T06:59:59.865947+00:00", …},
///      …}
///
/// Only `limits` is used. `five_hour`/`seven_day` describe the same two
/// windows, but whether their `utilization` is 0-1 or 0-100 has never been
/// confirmed against nonzero usage, whereas `percent` is unambiguous. If
/// Anthropic reshapes the payload, run with `CLAUDE_USAGE_DEBUG=1` and
/// compare the output against this comment.
struct UsageSnapshot: Decodable {
    struct Limit: Decodable {
        let kind: String
        let percent: Double
        let resetsAt: Date?
    }

    let limits: [Limit]

    var session: Limit? { limits.first { $0.kind == "session" } }
    var weekly: Limit? { limits.first { $0.kind == "weekly_all" } }

    static func decode(_ data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let string = try valueDecoder.singleValueContainer().decode(String.self)
            guard let date = parseTimestamp(string) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: valueDecoder.codingPath,
                    debugDescription: "Unrecognised timestamp \(string)"))
            }
            return date
        }
        return try decoder.decode(UsageSnapshot.self, from: data)
    }

    /// Timestamps look like `2026-09-07T12:49:59.865922+00:00`. The
    /// fractional-seconds formatter rejects a value with no fraction, which
    /// Python-style serialisers emit when the microseconds are zero, so try
    /// both.
    private static func parseTimestamp(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
