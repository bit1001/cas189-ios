import Foundation

/// Haijiao wraps every payload in up to five layers of plain Base64.
/// Verified against the live API: 5 iterations unwrap node lists and topic pages.
public enum Base64Peel {
    public static func peel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        for _ in 0..<5 {
            let compact = text.filter { !$0.isWhitespace }
            guard compact.count >= 8, compact.count % 4 == 0 else { break }
            guard let data = Data(base64Encoded: compact),
                  let decoded = String(data: data, encoding: .utf8) else { break }
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Base64 → JSON value (object or array).
    public static func peelJSON(_ raw: String) throws -> Any {
        let text = peel(raw)
        guard let data = text.data(using: .utf8) else { throw QHError.decode("not utf8") }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
