import SwiftUI

/// A one-pixel separator in the system separator color.
struct Hairline: View {
    enum Axis {
        case horizontal
        case vertical
    }

    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let thickness = 1 / max(displayScale, 1)
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(
                width: axis == .vertical ? thickness : nil,
                height: axis == .horizontal ? thickness : nil
            )
            .accessibilityHidden(true)
    }
}
