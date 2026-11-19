import AppKit
import SwiftUI

/// Kept's design tokens, from docs/DESIGN.md. Views take color, type, spacing
/// and sizes from here instead of hard-coding them.
@MainActor
enum Theme {
    /// Native semantic colors plus the one brand color, the highlighter.
    @MainActor
    enum Colors {
        /// Primary text.
        static let ink = Color(nsColor: .labelColor)
        /// Metadata and hints.
        static let inkMuted = Color(nsColor: .secondaryLabelColor)
        /// Quick-paste numbers and placeholders.
        static let inkFaint = Color(nsColor: .tertiaryLabelColor)
        /// Pane divider and footer rule.
        static let hairline = Color(nsColor: .separatorColor)
        /// The panel's opaque background where vibrancy can't draw
        /// (offscreen snapshots).
        static let panelBackground = Color(nsColor: .windowBackgroundColor)
        /// A barely-there fill behind key caps and image placeholders.
        static let wash = Color.primary.opacity(0.06)

        /// The highlighter drawn behind the selected row's text and the
        /// active filter. Never a solid control fill. Light mode glazes the
        /// line yellow under the usual ink; dark mode draws it the way a
        /// real highlighter and the app icon do, a near-opaque yellow under
        /// dark ink (`markedInk`).
        static let marker = AdaptiveColor(
            light: sRGB(0xFFD84D, opacity: 0.6),
            dark: sRGB(0xF2CC47, opacity: 0.94),
            lightIncreasedContrast: sRGB(0xFFD84D, opacity: 0.95),
            darkIncreasedContrast: sRGB(0xFFD84D)
        )
        /// The pin notch: the marker at full strength, so a 3 pt mark reads.
        static let markerNotch = AdaptiveColor(
            light: sRGB(0xF5C400),
            dark: sRGB(0xE8B73A)
        )
        /// The active filter's text, on the marker.
        static let markerInk = AdaptiveColor(
            light: sRGB(0x6E5400),
            dark: sRGB(0x1C1C1E),
            lightIncreasedContrast: sRGB(0x5C4600),
            darkIncreasedContrast: sRGB(0x1C1C1E)
        )

        /// Text on the marker (the selected row's title): the usual ink in
        /// light mode, the icon's dark line on yellow in dark mode.
        static func markedInk(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? sRGB(0x1C1C1E) : ink
        }

        /// Muted text on the marker (a link's path, file names). Stronger
        /// than `inkMuted`, which falls under 4.5:1 on yellow.
        static func markedInkMuted(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? sRGB(0x1C1C1E, opacity: 0.75) : Color.black.opacity(0.62)
        }

        static func sRGB(_ hex: UInt32, opacity: Double = 1) -> Color {
            Color(
                .sRGB,
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                opacity: opacity
            )
        }
    }

    /// One family, the system font; personality comes from what is set in
    /// which style.
    @MainActor
    enum Typography {
        /// Search input — big, like Spotlight.
        static let searchField = Font.system(size: 20)
        /// The magnifying glass before the query, optically matched to it.
        static let searchGlyph = Font.system(size: 17, weight: .regular)
        /// Filter tokens at the end of the search bar.
        static let filterToken = Font.system(size: 12)
        /// Clip summary in the list.
        static let rowTitle = Font.system(size: 13)
        /// The words of a row's title that match the search: the same size
        /// and ink, a weight heavier. No color, no underline.
        static let rowTitleMatch = Font.system(size: 13, weight: .semibold)
        /// Code-like clips in the list (SF Mono, a point smaller to match
        /// the proportional text's color).
        static let rowCode = Font.system(size: 12, design: .monospaced)
        /// Matching words in a code-like row.
        static let rowCodeMatch = Font.system(size: 12, weight: .semibold, design: .monospaced)
        /// Source app, age.
        static let rowMeta = Font.system(size: 11)
        /// Quick-paste numbers 1–9.
        static let index = Font.system(size: 11, weight: .medium).monospacedDigit()
        /// Prose in the preview pane.
        static let preview = Font.system(size: 13)
        /// Code, paths and JSON in the preview pane (SF Mono).
        static let previewCode = Font.system(size: 12, design: .monospaced)
        /// File paths under their names in the preview (SF Mono).
        static let previewPath = Font.system(size: 11, design: .monospaced)
        /// A link's host above the full address in the preview.
        static let previewHost = Font.system(size: 15, weight: .medium)
        /// A color's value under its swatch.
        static let previewValue = Font.system(size: 15, weight: .medium, design: .monospaced)
        /// Labels in the preview's fact list.
        static let factLabel = Font.system(size: 11)
        /// Values in the preview's fact list.
        static let factValue = Font.system(size: 12)
        /// Shortcut hints in the footer.
        static let footerKey = Font.system(size: 11, weight: .medium)
        /// Key caps inside footer hints.
        static let keyCap = Font.system(size: 10, weight: .medium)
        /// The first line of an empty state.
        static let emptyTitle = Font.system(size: 13, weight: .medium)
        /// The second line of an empty state.
        static let emptyHint = Font.system(size: 12)
        /// "Copied. Press ⌘V to paste." in the copy-only hint.
        static let hintTitle = Font.system(size: 13, weight: .medium)
        /// Why Kept didn't paste, under the hint's title.
        static let hintDetail = Font.system(size: 12)
    }

    @MainActor
    enum Spacing {
        /// Everything aligns to this leading gutter.
        static let gutter: CGFloat = 12
        /// Inset of the preview pane's content.
        static let previewInset: CGFloat = 16
        /// Between a row's kind glyph (swatch, thumbnail, icon) and its text.
        static let glyphGap: CGFloat = 8
        /// Between a row's age and its source app icon.
        static let metaGap: CGFloat = 8
    }

    @MainActor
    enum Layout {
        static let panelSize = CGSize(width: 720, height: 460)
        static let panelMaterial = NSVisualEffectView.Material.popover
        static let searchBarHeight: CGFloat = 52
        static let rowHeight: CGFloat = 34
        static let footerHeight: CGFloat = 30
        /// Holds the search glyph and the quick-paste numbers, so the query
        /// and the list text start at the same x.
        static let leadingColumnWidth: CGFloat = 28
        /// The list pane; the preview takes the rest (about 55%).
        static let listWidth: CGFloat = 324
        /// The highlighter behind a row's text.
        static let markerHeight: CGFloat = 20
        /// The highlighter behind the active filter token.
        static let tokenMarkerHeight: CGFloat = 17
        static let sourceIconSize: CGFloat = 16
        static let rowThumbnailSize = CGSize(width: 30, height: 20)
        static let rowGlyphSize: CGFloat = 16
        static let colorSwatchSize: CGFloat = 14
        static let factLabelWidth: CGFloat = 84
        /// How far a rounded text field's text sits inside its bezel.
        static let renameFieldInset: CGFloat = 5
        /// The text editor's corners and the space between its edge and
        /// its text (so the text keeps the preview's left edge).
        static let editorCornerRadius: CGFloat = 6
        static let editorInset: CGFloat = 8

        /// The copy-only hint: the panel's material, a quiet rounded card.
        static let hintMaterial = panelMaterial
        static let hintCornerRadius: CGFloat = 12
        static let hintPadding: CGFloat = 12
        /// The hint that explains the permission wraps at this width; the
        /// short one is as wide as its line.
        static let hintWidth: CGFloat = 300
        /// The hint's distance above the bottom edge of where the panel was.
        static let hintPanelOffset: CGFloat = 24
        /// The hint's distance above the bottom of the screen, with no panel.
        static let hintScreenOffset: CGFloat = 72
    }

    /// The Settings window: system controls in the classic two-column
    /// layout (right-aligned labels, controls beside them), one fixed width.
    @MainActor
    enum SettingsLayout {
        /// Every pane is this wide; only the height changes.
        static let width: CGFloat = 560
        static let verticalPadding: CGFloat = 20
        static let rowSpacing: CGFloat = 18
        /// Between a row's label and its controls.
        static let labelGap: CGFloat = 8
        /// Between controls (and their notes) in one row.
        static let controlSpacing: CGFloat = 6
        /// The controls column; notes wrap at this width.
        static let contentWidth: CGFloat = 330
        /// Lines a note up with the title of the checkbox above it.
        static let checkboxIndent: CGFloat = 20
        /// Explanations under controls: small and secondary.
        static let note = Font.system(size: 11)
        static let excludedAppsHeight: CGFloat = 168
        static let excludedAppIconSize: CGFloat = 18
        static let aboutIconSize: CGFloat = 96
        static let aboutName = Font.system(size: 20, weight: .semibold)
    }

    /// The welcome window: centered, alert-like, one column.
    @MainActor
    enum WelcomeLayout {
        static let width: CGFloat = 380
        static let padding: CGFloat = 24
        static let iconSize: CGFloat = 72
        static let title = Font.system(size: 17, weight: .semibold)
        static let buttonWidth: CGFloat = 96
    }

    /// Only the panel and the copy-only hint fade, and not under Reduce
    /// Motion.
    @MainActor
    enum Motion {
        static let panelAppearDuration: TimeInterval = 0.12
        static let panelAppearScale: CGFloat = 0.98
        /// The copy-only hint fades in and out this fast.
        static let hintFadeDuration: TimeInterval = 0.12
        /// How long "Copied. Press ⌘V to paste." stays.
        static let copiedHintDuration: TimeInterval = 2.5
        /// How long the hint with the "Allow Kept to paste…" button stays
        /// (longer while the pointer is over it).
        static let permissionHintDuration: TimeInterval = 8
    }
}
