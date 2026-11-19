import SwiftUI

/// A color with one value in light mode and another in dark mode, resolved
/// from the color scheme of the view it's drawn in. Optional stronger values
/// apply when Increase Contrast is on.
struct AdaptiveColor: ShapeStyle {
    let light: Color
    let dark: Color
    var lightIncreasedContrast: Color?
    var darkIncreasedContrast: Color?

    func resolve(in environment: EnvironmentValues) -> Color {
        let isIncreased = environment.colorSchemeContrast == .increased
        if environment.colorScheme == .dark {
            return isIncreased ? (darkIncreasedContrast ?? dark) : dark
        }
        return isIncreased ? (lightIncreasedContrast ?? light) : light
    }
}
