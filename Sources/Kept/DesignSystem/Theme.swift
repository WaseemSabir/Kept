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
        /// active filter. Never a solid control fill.
        static let marker = AdaptiveColor(
            light: sRGB(0xFFD84D, opacity: 0.6),
            dark: sRGB(0xE8B73A, opacity: 0.3),
            lightIncreasedContrast: sRGB(0xFFD84D, opacity: 0.95),
            darkIncreasedContrast: sRGB(0xE8B73A, opacity: 0.5)
        )
        /// The pin notch: the marker at full strength, so a 3 pt mark reads.
        static let markerNotch = AdaptiveColor(
            light: sRGB(0xF5C400),
            dark: sRGB(0xE8B73A)
        )
        /// Pin glyph and active filter text.
        static let markerInk = AdaptiveColor(
            light: sRGB(0x8A6A00),
            dark: sRGB(0xF2C94C),
            lightIncreasedContrast: sRGB(0x5C4600),
            darkIncreasedContrast: sRGB(0xFFE08A)
        )

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
        /// Code-like clips in the list (SF Mono, a point smaller to match
        /// the proportional text's color).
        static let rowCode = Font.system(size: 12, design: .monospaced)
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
    }

    @MainActor
    enum Spacing {
        /// Everything aligns to this leading gutter.
        static let gutter: CGFloat = 12
        /// Inset of the preview pane's content.
        static let previewInset: CGFloat = 16
        /// Between a row's kind glyph (swatch, thumbnail, icon) and its text.
        static let glyphGap: CGFloat = 8
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
        /// Wide enough for "Yesterday", so source icons line up.
        static let ageColumnWidth: CGFloat = 52
        static let rowThumbnailSize = CGSize(width: 30, height: 20)
        static let rowGlyphSize: CGFloat = 16
        static let colorSwatchSize: CGFloat = 14
        static let factLabelWidth: CGFloat = 84
    }

    /// Only the panel's appearance animates, and not under Reduce Motion.
    @MainActor
    enum Motion {
        static let panelAppearDuration: TimeInterval = 0.12
        static let panelAppearScale: CGFloat = 0.98
    }
}
