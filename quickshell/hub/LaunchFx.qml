import QtQuick
import "../core"

// The "game launch" moment: the selected tile grows from its own spot to fill the whole screen,
// then breathes quietly until the real window shows up and the hub fades away.
Item {
    id: root

    property real u: 1
    property var pal: ({ primaryContainer: "#222", surface: "#111" })

    function start(x, y, w, h, palette, iconPath) {
        pal = palette;
        icon.source = iconPath ? "file://" + iconPath : "";
        panel.x = x; panel.y = y; panel.width = w; panel.height = h;
        panel.radius = 20 * u;
        panel.opacity = 1;
        panel.visible = true;
        icon.opacity = 1;
        breathe.stop();
        grow.restart();
    }

    function reset() {
        grow.stop();
        breathe.stop();
        fade.stop();
        panel.visible = false;
        panel.opacity = 0;
    }

    // used when the app never showed up
    function collapse() { fade.restart(); }

    Rectangle {
        id: panel
        visible: false
        opacity: 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.pal.primaryContainer }
            GradientStop { position: 1.0; color: root.pal.surface }
        }

        Image {
            id: icon
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.5
            height: width
            sourceSize: Qt.size(256, 256)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    ParallelAnimation {
        id: grow
        NumberAnimation { target: panel; property: "x"; to: 0; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: panel; property: "y"; to: 0; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: panel; property: "width"; to: root.width; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: panel; property: "height"; to: root.height; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: panel; property: "radius"; to: 0; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        onFinished: breathe.restart()
    }

    SequentialAnimation {
        id: breathe
        loops: Animation.Infinite
        NumberAnimation { target: icon; property: "opacity"; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { target: icon; property: "opacity"; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
    }

    NumberAnimation {
        id: fade
        target: panel
        property: "opacity"
        to: 0
        duration: 320
        onFinished: { panel.visible = false; breathe.stop(); }
    }
}
