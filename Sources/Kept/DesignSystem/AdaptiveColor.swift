import SwiftUI

/// A color with one value in light mode and another in dark mode, resolved
/// from the color scheme of the view it's drawn in. Optional stronger values
/// apply when Increase Contrast is on (or `forcesIncreasedContrast` says so,
/// for snapshots: SwiftUI's own contrast setting can't be set).
struct AdaptiveColor: ShapeStyle {
    let light: Color
    let dark: Color
    var lightIncreasedContrast: Color?
    var darkIncreasedContrast: Color?

    func resolve(in environment: EnvironmentValues) -> Color {
        let isIncreased = environment.colorSchemeContrast == .increased || environment.forcesIncreasedContrast
        if environment.colorScheme == .dark {
            return isIncreased ? (darkIncreasedContrast ?? dark) : dark
        }
        return isIncreased ? (lightIncreasedContrast ?? light) : light
    }
}

/// Draws Kept's colors as under Increase Contrast whatever the system says.
private struct ForcesIncreasedContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var forcesIncreasedContrast: Bool {
        get { self[ForcesIncreasedContrastKey.self] }
        set { self[ForcesIncreasedContrastKey.self] = newValue }
    }
}
