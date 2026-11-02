import QtQuick
import QtQuick.Shapes

// PS5 glass: a rounded slot lit from the bottom-left corner (soft grey) down to near-black at the top-right,
// with a hairline edge. Used by the app tiles and the info cards.
Shape {
    id: root
    property real radius: 12
    property real alpha: 0.94
    property color bottomLeft: Qt.rgba(0.205, 0.213, 0.240, alpha)
    property color topRight: Qt.rgba(0.030, 0.034, 0.044, alpha)
    property color edge: Qt.rgba(1, 1, 1, 0.08)
    preferredRendererType: Shape.CurveRenderer

    readonly property real o: 0.5                                   // keeps the 1px edge inside the bounds
    readonly property real r: Math.max(0, Math.min(radius, Math.min(width, height) / 2) - o)

    ShapePath {
        strokeColor: root.edge
        strokeWidth: 1
        fillGradient: LinearGradient {
            x1: 0; y1: root.height
            x2: root.width; y2: 0
            GradientStop { position: 0.0; color: root.bottomLeft }
            GradientStop { position: 1.0; color: root.topRight }
        }
        startX: root.o + root.r; startY: root.o
        PathLine { x: root.width - root.o - root.r; y: root.o }
        PathArc { x: root.width - root.o; y: root.o + root.r; radiusX: root.r; radiusY: root.r; direction: PathArc.Clockwise }
        PathLine { x: root.width - root.o; y: root.height - root.o - root.r }
        PathArc { x: root.width - root.o - root.r; y: root.height - root.o; radiusX: root.r; radiusY: root.r; direction: PathArc.Clockwise }
        PathLine { x: root.o + root.r; y: root.height - root.o }
        PathArc { x: root.o; y: root.height - root.o - root.r; radiusX: root.r; radiusY: root.r; direction: PathArc.Clockwise }
        PathLine { x: root.o; y: root.o + root.r }
        PathArc { x: root.o + root.r; y: root.o; radiusX: root.r; radiusY: root.r; direction: PathArc.Clockwise }
    }
}
