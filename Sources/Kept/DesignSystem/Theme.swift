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

        /// The highlighter drawn behind the selected row's text and the pin
        /// notch. Never a solid control fill.
        static let marker = AdaptiveColor(
            light: sRGB(0xFFD84D, opacity: 0.6),
            dark: sRGB(0xE8B73A, opacity: 0.3)
        )
        /// Pin glyph and active filter text.
        static let markerInk = AdaptiveColor(
            light: sRGB(0x8A6A00),
            dark: sRGB(0xF2C94C)
        )

        private static func sRGB(_ hex: UInt32, opacity: Double = 1) -> Color {
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
        /// Clip summary in the list.
        static let rowTitle = Font.system(size: 13)
        /// Source app, age.
        static let rowMeta = Font.system(size: 11)
        /// Quick-paste numbers 1–9.
        static let index = Font.system(size: 11, weight: .medium).monospacedDigit()
        /// Prose in the preview pane.
        static let preview = Font.system(size: 13)
        /// Code, paths and JSON in the preview pane (SF Mono).
        static let previewCode = Font.system(size: 12, design: .monospaced)
        /// Shortcut hints in the footer.
        static let footerKey = Font.system(size: 11, weight: .medium)
        /// Key caps inside footer hints.
        static let keyCap = Font.system(size: 10, weight: .medium)
    }

    @MainActor
    enum Spacing {
        /// Everything aligns to this leading gutter.
        static let gutter: CGFloat = 12
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
    }

    /// Only the panel's appearance animates, and not under Reduce Motion.
    @MainActor
    enum Motion {
        static let panelAppearDuration: TimeInterval = 0.12
        static let panelAppearScale: CGFloat = 0.98
    }
}
