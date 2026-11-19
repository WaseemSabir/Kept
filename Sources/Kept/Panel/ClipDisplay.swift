import Foundation
import KeptCore

/// Turns clip data into the strings the panel shows. Pure, so it's tested
/// without views.
enum ClipDisplay {
    /// A link split for display: `github.com` and `/kept/issues/12`, without
    /// the scheme or a leading `www.`. Mail links come back whole as `host`.
    static func linkParts(of url: String) -> (host: String, rest: String) {
        var remainder = Substring(url)
        for scheme in ["https://", "http://"] where remainder.lowercased().hasPrefix(scheme) {
            remainder = remainder.dropFirst(scheme.count)
            break
        }
        if remainder.lowercased().hasPrefix("www.") {
            remainder = remainder.dropFirst(4)
        }
        let hostEnd = remainder.firstIndex { "/?#".contains($0) } ?? remainder.endIndex
        let rest = remainder[hostEnd...]
        return (String(remainder[..<hostEnd]), rest == "/" ? "" : String(rest))
    }

    /// A file clip's row text: its name, or "3 files".
    static func fileSummary(of clip: Clip) -> String {
        let count = clip.metadata.fileCount ?? 1
        return count > 1 ? "\(count) files" : clip.title
    }

    /// The first file name in a file clip's title (names are joined by ", ").
    static func firstFileName(of clip: Clip) -> String {
        clip.title.components(separatedBy: ", ").first ?? clip.title
    }

    /// A path with the user's home folder shown as `~`. Works from the
    /// sandbox, where `NSHomeDirectory()` is the container.
    static func abbreviatedPath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        // ["", "Users", "<name>", …]
        guard components.count > 3, components[0].isEmpty, components[1] == "Users" else { return path }
        return "~/" + components.dropFirst(3).joined(separator: "/")
    }

    /// The folder holding `path`, abbreviated; `nil` for a bare name.
    static func folder(of path: String) -> String? {
        let folder = (path as NSString).deletingLastPathComponent
        return folder.isEmpty ? nil : abbreviatedPath(folder)
    }

    /// Red, green, blue and alpha (0–255) from `#RRGGBB` or `#RRGGBBAA`.
    static func rgba(fromHex hex: String) -> (red: Int, green: Int, blue: Int, alpha: Int)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        let channel = { (shift: UInt32) in Int((value >> shift) & 0xFF) }
        return digits.count == 8
            ? (channel(24), channel(16), channel(8), channel(0))
            : (channel(16), channel(8), channel(0), 255)
    }

    /// "1 character", "1,204 characters".
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value.formatted()) \(value == 1 ? singular : plural)"
    }

    /// The image format's short name, e.g. "PNG".
    static func imageFormatName(_ type: PasteboardType?) -> String? {
        switch type {
        case .some(.png): "PNG"
        case .some(.tiff): "TIFF"
        case .some(.jpeg): "JPEG"
        case .some(.heic): "HEIC"
        default: nil
        }
    }

    /// What a filter holds, for empty-state copy: "links", "pinned clips".
    static func noun(for filter: ClipFilter) -> String {
        switch filter {
        case .all: "clips"
        case .pinned: "pinned clips"
        case .text: "text clips"
        case .links: "links"
        case .images: "images"
        case .files: "files"
        }
    }

    /// The filter's name on its token.
    static func title(for filter: ClipFilter) -> String {
        switch filter {
        case .all: "All"
        case .pinned: "Pinned"
        case .text: "Text"
        case .links: "Links"
        case .images: "Images"
        case .files: "Files"
        }
    }
}
