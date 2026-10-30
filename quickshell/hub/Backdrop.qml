import QtQuick
import QtQuick.Shapes
import "../core"

// Layered background: matugen gradient, two soft radial glows (one slowly drifting),
// a faint enlarged icon of the selected app (upscaling blurs it for free), and a bottom scrim.
Item {
    id: root
    property url icon: ""
    property bool shown: true
    property real drift: 0

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.tint(Theme.mid, Qt.alpha(Theme.accent, 0.20)) }
            GradientStop { position: 0.6; color: Theme.mid }
            GradientStop { position: 1.0; color: Theme.deep }
        }
    }

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width * 0.80 + root.drift; centerY: root.height * 0.02
                centerRadius: root.width * 0.64
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: Qt.alpha(Theme.accent, 0.52) }
                GradientStop { position: 0.55; color: Qt.alpha(Theme.accent, 0.15) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.accent, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width * 0.08 - root.drift; centerY: root.height * 0.98
                centerRadius: root.width * 0.55
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: Qt.alpha(Theme.accent, 0.20) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.accent, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    SequentialAnimation on drift {
        running: root.shown
        loops: Animation.Infinite
        NumberAnimation { to: 70; duration: 16000; easing.type: Easing.InOutSine }
        NumberAnimation { to: -70; duration: 16000; easing.type: Easing.InOutSine }
    }

    // ghost of the selected app's icon
    Image {
        id: ghost
        anchors.right: parent.right
        anchors.rightMargin: -root.height * 0.10
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.height * 0.04
        width: root.height * 0.95
        height: width
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        opacity: 0
    }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: 140 }
        ScriptAction { script: ghost.source = root.icon }
        NumberAnimation { target: ghost; property: "opacity"; to: ghost.status === Image.Error ? 0 : 0.10; duration: 420; easing.type: Easing.OutCubic }
    }
    onIconChanged: swap.restart()

    // bottom scrim keeps the info area readable
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.5
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }
}
