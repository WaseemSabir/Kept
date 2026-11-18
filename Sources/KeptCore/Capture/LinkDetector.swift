import Foundation

/// Recognizes text that is a single web or mail link.
enum LinkDetector {
    struct Link: Equatable {
        /// The link as copied, trimmed.
        var url: String
        /// The lowercased host, without user info or port; `nil` for `mailto:`.
        var host: String?
    }

    /// The link `text` consists of, if it is exactly one `http`, `https` or
    /// `mailto` URL (surrounding whitespace aside).
    static func link(in text: String) -> Link? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.unicodeScalars.contains(where: \.properties.isWhitespace) else {
            return nil
        }
        let lowercased = trimmed.lowercased()

        if lowercased.hasPrefix("mailto:") {
            let address = trimmed.dropFirst("mailto:".count)
            guard let at = address.firstIndex(of: "@"), at != address.startIndex,
                  address.index(after: at) != address.endIndex
            else { return nil }
            return Link(url: trimmed, host: nil)
        }

        for scheme in ["http://", "https://"] where lowercased.hasPrefix(scheme) {
            let rest = lowercased.dropFirst(scheme.count)
            let authority = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            guard let host = host(fromAuthority: authority) else { return nil }
            return Link(url: trimmed, host: host)
        }
        return nil
    }

    private static func host(fromAuthority authority: Substring) -> String? {
        var host = authority
        if let at = host.lastIndex(of: "@") {
            host = host[host.index(after: at)...]
        }
        if host.hasPrefix("[") {
            // IPv6 literal: keep through the closing bracket.
            guard let close = host.firstIndex(of: "]") else { return nil }
            host = host[...close]
        } else if let colon = host.firstIndex(of: ":") {
            host = host[..<colon]
        }
        let allowed = host.allSatisfy { $0.isLetter || $0.isNumber || "-._[]:".contains($0) }
        guard !host.isEmpty, allowed, host.contains(where: { $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return String(host)
    }
}
