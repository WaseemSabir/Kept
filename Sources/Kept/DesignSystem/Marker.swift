import SwiftUI

/// The highlighter swipe: a band whose ends are both cut at the same slant,
/// like a chisel-tip marker and the marked line in the app icon. Drawn
/// behind text, never as a control fill.
struct MarkerShape: Shape {
    /// How far the top edge sits right of the bottom edge, as a fraction of
    /// the height.
    var slant: CGFloat = 0.25
    var cornerRadius: CGFloat = 2.5

    func path(in rect: CGRect) -> Path {
        let shift = min(rect.height * slant, rect.width / 3)
        let corners = [
            CGPoint(x: rect.minX + shift, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX - shift, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        let radius = min(cornerRadius, rect.height / 2)
        var path = Path()
        // Start midway along the left edge, then round each corner in turn.
        path.move(to: CGPoint(x: (corners[3].x + corners[0].x) / 2, y: rect.midY))
        for index in corners.indices {
            path.addArc(
                tangent1End: corners[index],
                tangent2End: corners[(index + 1) % corners.count],
                radius: radius
            )
        }
        path.closeSubpath()
        return path
    }
}

@MainActor
extension View {
    /// Swipes the highlighter behind this view when `isMarked`, running a
    /// little past both ends the way a real marker does.
    func marked(
        _ isMarked: Bool,
        height: CGFloat = Theme.Layout.markerHeight,
        leading: CGFloat = 5,
        trailing: CGFloat = 9
    ) -> some View {
        background {
            if isMarked {
                MarkerShape()
                    .fill(Theme.Colors.marker)
                    .frame(height: height)
                    .padding(.leading, -leading)
                    .padding(.trailing, -trailing)
            }
        }
    }
}
