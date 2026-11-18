/// The preferences that capture depends on, as a plain value, so
/// `CapturePolicy` and `ClipBuilder` stay pure. `Preferences.captureSettings`
/// produces one.
public struct CaptureSettings: Sendable, Hashable {
    public var isPaused: Bool
    /// Bundle IDs whose copies are ignored, compared case-insensitively.
    public var excludedBundleIDs: Set<String>
    public var ignoreRemoteClipboard: Bool
    public var captureImages: Bool
    public var captureFiles: Bool
    /// The most bytes one clip may hold across all its representations.
    public var maxItemBytes: Int

    public init(
        isPaused: Bool = PreferenceDefaults.isPaused,
        excludedBundleIDs: Set<String> = Set(PreferenceDefaults.excludedBundleIDs),
        ignoreRemoteClipboard: Bool = PreferenceDefaults.ignoreRemoteClipboard,
        captureImages: Bool = PreferenceDefaults.captureImages,
        captureFiles: Bool = PreferenceDefaults.captureFiles,
        maxItemBytes: Int = PreferenceDefaults.maxItemBytes
    ) {
        self.isPaused = isPaused
        self.excludedBundleIDs = Set(excludedBundleIDs.map { $0.lowercased() })
        self.ignoreRemoteClipboard = ignoreRemoteClipboard
        self.captureImages = captureImages
        self.captureFiles = captureFiles
        self.maxItemBytes = maxItemBytes
    }

    public func excludes(bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID.lowercased())
    }
}
