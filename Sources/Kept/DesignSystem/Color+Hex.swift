import SwiftUI

extension Color {
    /// A color from `#RRGGBB` or `#RRGGBBAA` (sRGB).
    init?(hex: String) {
        guard let rgba = ClipDisplay.rgba(fromHex: hex) else { return nil }
        self.init(
            .sRGB,
            red: Double(rgba.red) / 255,
            green: Double(rgba.green) / 255,
            blue: Double(rgba.blue) / 255,
            opacity: Double(rgba.alpha) / 255
        )
    }
}
