import SwiftUI

/// A color with one value in light mode and another in dark mode, resolved
/// from the color scheme of the view it's drawn in.
struct AdaptiveColor: ShapeStyle {
    let light: Color
    let dark: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? dark : light
    }
}
