import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../core"

// Full-screen background. Colours come from Theme (which glides to the selected app's palette),
// and the selected app's icon sits huge and blurred on the right, crossfading when selection changes.
Item {
    id: root

    property string iconSource: ""
    property bool active: true      // false = stop all animation
    property real dim: 1.0          // 1 = opaque (empty desktop); lower lets windows show through

    property bool showA: true
    property string srcA: ""
    property string srcB: ""
    property real drift: 0

    onIconSourceChanged: {
        if (showA) srcB = iconSource; else srcA = iconSource;
        showA = !showA;
    }
    Component.onCompleted: {
        if (srcA === "" && srcB === "") { srcA = iconSource; showA = true; }
    }

    // base gradient
    Rectangle {
        anchors.fill: parent
        opacity: root.dim
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.mid }
            GradientStop { position: 1.0; color: Theme.deep }
        }
    }

    // big radial glow in the accent colour, drifting slowly
    Shape {
        anchors.fill: parent
        opacity: root.dim
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width * 0.80 + root.drift
                centerY: root.height * 0.12
                centerRadius: root.width * 0.75
                focalX: centerX
                focalY: centerY
                GradientStop { position: 0.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.34) }
                GradientStop { position: 1.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    SequentialAnimation on drift {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { to: 70; duration: 9000; easing.type: Easing.InOutSine }
        NumberAnimation { to: -70; duration: 9000; easing.type: Easing.InOutSine }
    }

    // blurred app art, two layers for the crossfade
    component Art: Image {
        x: root.width * 0.42
        y: -root.height * 0.18
        width: root.height * 1.5
        height: width
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        rotation: -8
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 64
            blur: 1.0
            saturation: 0.25
        }
        Behavior on opacity {
            NumberAnimation { duration: Motion.tint; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.soft }
        }
        SequentialAnimation on scale {
            running: root.active
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.07; duration: 14000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.07; to: 1.0; duration: 14000; easing.type: Easing.InOutSine }
        }
    }

    Art { source: root.srcA; opacity: root.showA ? 0.5 * root.dim : 0 }
    Art { source: root.srcB; opacity: root.showA ? 0 : 0.5 * root.dim }

    // vignette
    Rectangle {
        anchors.fill: parent
        opacity: root.dim
        gradient: Gradient {
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }
}
