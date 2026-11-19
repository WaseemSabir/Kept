import Foundation

/// Kept's version and build, read from the app bundle's Info.plist: the
/// one place the version lives (`Resources/Info.plist`, stamped by
/// `scripts/build-app.sh`).
struct AboutInfo: Equatable, Sendable {
    static let projectURL = URL(string: "https://github.com/WaseemSabir/Kept")

    /// `CFBundleShortVersionString`, e.g. "0.2.0".
    var version: String?
    /// `CFBundleVersion`, the build number.
    var build: String?

    init(version: String?, build: String?) {
        self.version = version
        self.build = build
    }

    init(bundle: Bundle) {
        self.init(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    /// "Version 0.2.0 (142)"; "Development build" for a bare binary, which
    /// has no Info.plist.
    var versionLine: String {
        switch (version, build) {
        case let (version?, build?) where !build.isEmpty && build != version:
            "Version \(version) (\(build))"
        case let (version?, _):
            "Version \(version)"
        case (nil, _):
            "Development build"
        }
    }
}
