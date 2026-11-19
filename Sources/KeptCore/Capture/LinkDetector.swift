import Foundation

/// Recognizes text that is a single web or mail link.
enum LinkDetector {
    struct Link: Equatable {
        /// The link as copied, trimmed.
        var url: String
        /// The lowercased host, without user info or port; `nil` for `mailto:`.
        var host: String?
    }

    /// Longer text is never treated as a link; checked before any other
    /// work, so a multi-megabyte clip costs nothing here.
    static let maxLength = 16 * 1024

    /// The link `text` consists of, if it is exactly one `http`, `https` or
    /// `mailto` URL (surrounding whitespace aside).
    static func link(in text: String) -> Link? {
        guard text.utf8.count <= maxLength else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.unicodeScalars.contains(where: \.properties.isWhitespace) else {
            return nil
        }
        // Only the scheme and authority are compared case-insensitively.
        let scheme = trimmed.prefix(8).lowercased()

        if scheme.hasPrefix("mailto:") {
            let address = trimmed.dropFirst("mailto:".count)
            guard let at = address.firstIndex(of: "@"), at != address.startIndex,
                  address.index(after: at) != address.endIndex
            else { return nil }
            return Link(url: trimmed, host: nil)
        }

        for prefix in ["http://", "https://"] where scheme.hasPrefix(prefix) {
            let rest = trimmed.dropFirst(prefix.count)
            let authority = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            guard let host = host(fromAuthority: Substring(authority.lowercased())) else { return nil }
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
