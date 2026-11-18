import Foundation
import Observation

/// Kept's settings, stored in `UserDefaults`. Defaults live in
/// `PreferenceDefaults`; a value is written only once the user changes it.
@MainActor
@Observable
public final class Preferences {
    /// Unpinned clips to keep, clamped to `PreferenceDefaults.historyLimitRange`.
    public var historyLimit: Int {
        didSet {
            let clamped = Self.clamp(historyLimit, to: PreferenceDefaults.historyLimitRange)
            if clamped != historyLimit { historyLimit = clamped }
            defaults.set(clamped, forKey: Key.historyLimit)
        }
    }

    /// Paste into the previous app (`true`) or only copy (`false`).
    public var pasteDirectly: Bool {
        didSet { defaults.set(pasteDirectly, forKey: Key.pasteDirectly) }
    }

    public var alwaysPastePlainText: Bool {
        didSet { defaults.set(alwaysPastePlainText, forKey: Key.alwaysPastePlainText) }
    }

    public var panelPosition: PanelPosition {
        didSet { defaults.set(panelPosition.rawValue, forKey: Key.panelPosition) }
    }

    /// Apps whose copies are never recorded, in the order the user sees them.
    public var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }

    /// Skip content that arrives from other devices through Universal Clipboard.
    public var ignoreRemoteClipboard: Bool {
        didSet { defaults.set(ignoreRemoteClipboard, forKey: Key.ignoreRemoteClipboard) }
    }

    public var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Key.isPaused) }
    }

    public var captureImages: Bool {
        didSet { defaults.set(captureImages, forKey: Key.captureImages) }
    }

    public var captureFiles: Bool {
        didSet { defaults.set(captureFiles, forKey: Key.captureFiles) }
    }

    /// The largest clip recorded, in bytes, clamped to
    /// `PreferenceDefaults.maxItemBytesRange`.
    public var maxItemBytes: Int {
        didSet {
            let clamped = Self.clamp(maxItemBytes, to: PreferenceDefaults.maxItemBytesRange)
            if clamped != maxItemBytes { maxItemBytes = clamped }
            defaults.set(clamped, forKey: Key.maxItemBytes)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        historyLimit = Self.clamp(
            defaults.object(forKey: Key.historyLimit) as? Int ?? PreferenceDefaults.historyLimit,
            to: PreferenceDefaults.historyLimitRange
        )
        pasteDirectly = defaults.object(forKey: Key.pasteDirectly) as? Bool ?? PreferenceDefaults.pasteDirectly
        alwaysPastePlainText = defaults.object(forKey: Key.alwaysPastePlainText) as? Bool
            ?? PreferenceDefaults.alwaysPastePlainText
        panelPosition = (defaults.string(forKey: Key.panelPosition)).flatMap(PanelPosition.init(rawValue:))
            ?? PreferenceDefaults.panelPosition
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs)
            ?? PreferenceDefaults.excludedBundleIDs
        ignoreRemoteClipboard = defaults.object(forKey: Key.ignoreRemoteClipboard) as? Bool
            ?? PreferenceDefaults.ignoreRemoteClipboard
        isPaused = defaults.object(forKey: Key.isPaused) as? Bool ?? PreferenceDefaults.isPaused
        captureImages = defaults.object(forKey: Key.captureImages) as? Bool ?? PreferenceDefaults.captureImages
        captureFiles = defaults.object(forKey: Key.captureFiles) as? Bool ?? PreferenceDefaults.captureFiles
        maxItemBytes = Self.clamp(
            defaults.object(forKey: Key.maxItemBytes) as? Int ?? PreferenceDefaults.maxItemBytes,
            to: PreferenceDefaults.maxItemBytesRange
        )
    }

    /// What capture needs, as a value for `CapturePolicy` and `ClipBuilder`.
    public var captureSettings: CaptureSettings {
        CaptureSettings(
            isPaused: isPaused,
            excludedBundleIDs: Set(excludedBundleIDs),
            ignoreRemoteClipboard: ignoreRemoteClipboard,
            captureImages: captureImages,
            captureFiles: captureFiles,
            maxItemBytes: maxItemBytes
        )
    }

    /// The `UserDefaults` keys.
    enum Key {
        static let historyLimit = "historyLimit"
        static let pasteDirectly = "pasteDirectly"
        static let alwaysPastePlainText = "alwaysPastePlainText"
        static let panelPosition = "panelPosition"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let ignoreRemoteClipboard = "ignoreRemoteClipboard"
        static let isPaused = "isPaused"
        static let captureImages = "captureImages"
        static let captureFiles = "captureFiles"
        static let maxItemBytes = "maxItemBytes"
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
