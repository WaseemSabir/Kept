/// Every preference's default value and allowed range, in one place.
public enum PreferenceDefaults {
    /// Unpinned clips kept; pins don't count.
    public static let historyLimit = 500
    public static let historyLimitRange = 50...10_000
    /// The history sizes Settings offers.
    public static let historyLimitChoices = [100, 250, 500, 1_000, 2_500, 5_000, 10_000]
    public static let pasteDirectly = true
    public static let alwaysPastePlainText = false
    public static let panelPosition = PanelPosition.activeScreenCenter
    /// Password managers and keychains, which don't always mark what they copy.
    public static let excludedBundleIDs = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
    ]
    public static let ignoreRemoteClipboard = false
    public static let isPaused = false
    public static let captureImages = true
    public static let captureFiles = true
    /// Clips bigger than this (all representations together) are skipped.
    public static let maxItemBytes = 20 * 1024 * 1024
    /// 1 MB to 100 MB: everything Kept stores is read into memory on the
    /// main actor when it's recorded or pasted.
    public static let maxItemBytesRange = (1024 * 1024)...(100 * 1024 * 1024)

    /// The history sizes to offer: `historyLimitChoices`, plus `current` in
    /// its place when it isn't one of them (set by an older version, say),
    /// so the menu always shows what's in effect.
    public static func historyLimitChoices(including current: Int) -> [Int] {
        guard !historyLimitChoices.contains(current) else { return historyLimitChoices }
        return (historyLimitChoices + [current]).sorted()
    }
}
