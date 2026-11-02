import QtQuick
import QtQuick.Shapes

// The PS5 selection ring: a thin band, bright white at the top fading toward the bottom.
// A band is a big rounded rectangle with a smaller one cut out of it (odd-even fill), because a path stroke
// cannot carry a gradient.
Shape {
    id: root
    property real radius: 16            // outer radius
    property real thickness: 2.5
    preferredRendererType: Shape.CurveRenderer

    readonly property real outerR: Math.max(0, Math.min(radius, Math.min(width, height) / 2))
    readonly property real th: thickness
    readonly property real innerR: Math.max(0, outerR - th)

    ShapePath {
        strokeWidth: -1
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
            x1: 0; y1: 0
            x2: 0; y2: root.height
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.98) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.50) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.16) }
        }
        // outer edge
        startX: root.outerR; startY: 0
        PathLine { x: root.width - root.outerR; y: 0 }
        PathArc { x: root.width; y: root.outerR; radiusX: root.outerR; radiusY: root.outerR; direction: PathArc.Clockwise }
        PathLine { x: root.width; y: root.height - root.outerR }
        PathArc { x: root.width - root.outerR; y: root.height; radiusX: root.outerR; radiusY: root.outerR; direction: PathArc.Clockwise }
        PathLine { x: root.outerR; y: root.height }
        PathArc { x: 0; y: root.height - root.outerR; radiusX: root.outerR; radiusY: root.outerR; direction: PathArc.Clockwise }
        PathLine { x: 0; y: root.outerR }
        PathArc { x: root.outerR; y: 0; radiusX: root.outerR; radiusY: root.outerR; direction: PathArc.Clockwise }
        // inner edge (the hole)
        PathMove { x: root.th + root.innerR; y: root.th }
        PathLine { x: root.width - root.th - root.innerR; y: root.th }
        PathArc { x: root.width - root.th; y: root.th + root.innerR; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
        PathLine { x: root.width - root.th; y: root.height - root.th - root.innerR }
        PathArc { x: root.width - root.th - root.innerR; y: root.height - root.th; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
        PathLine { x: root.th + root.innerR; y: root.height - root.th }
        PathArc { x: root.th; y: root.height - root.th - root.innerR; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
        PathLine { x: root.th; y: root.th + root.innerR }
        PathArc { x: root.th + root.innerR; y: root.th; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
    }
}
