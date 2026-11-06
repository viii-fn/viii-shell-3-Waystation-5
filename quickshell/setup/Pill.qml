import QtQuick
import "../core"
import "../hub"

// The PS5 pill button used all over the shell (hub "Open App", the Explore dialog): a dark translucent
// pill; while `on` the GlassRing hugs it (3.5 px outside, same as every other ring in the shell).
Item {
    id: root
    property string label: ""
    property bool on: false
    signal clicked()
    width: 200
    height: 46

    property real bk: on ? 1 : 0
    Behavior on bk {
        NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(0.12 + 0.07 * root.bk, 0.13 + 0.07 * root.bk, 0.15 + 0.07 * root.bk, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
    }
    GlassRing {
        readonly property real out: 3.5
        x: -out
        y: -out
        width: root.width + 2 * out
        height: root.height + 2 * out
        radius: root.height / 2 + out
        thickness: 2.5
        opacity: root.bk
        visible: opacity > 0.01
    }
    Txt {
        anchors.centerIn: parent
        text: root.label
        font.pixelSize: 18
        font.weight: Font.DemiBold
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
