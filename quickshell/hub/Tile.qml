import QtQuick
import QtQuick.Effects
import "../core"

// One app "cover". Square art made from the app's matugen palette with its icon in the middle.
// The parent decides `size` (row: big when selected; grid: fixed) and `focused` (ring + glow).
Item {
    id: root

    property var entry
    property bool focused: false
    property real size: 150
    property real u: 1
    property real appear: 1        // 0..1, staggered entrance (slides in from the right while fading up)

    signal activated()

    readonly property bool isLibrary: entry !== undefined && entry !== null && entry.isLibrary === true
    readonly property string key: isLibrary ? "library" : Apps.safeKey(entry)
    readonly property var pal: isLibrary ? Apps.fallback("library") : (Apps.palettes[key] || Apps.fallback(key))
    readonly property string iconSrc: isLibrary ? "" : "file://" + Apps.iconPath(entry)

    width: size
    height: size
    opacity: appear
    transform: Translate { x: (1 - root.appear) * 90 * root.u }

    Behavior on size {
        NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }
    Behavior on scale {
        NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    Component.onCompleted: if (!isLibrary) Apps.request(entry)

    RectangularShadow {
        anchors.fill: art
        radius: art.radius
        blur: 52 * root.u
        spread: 2 * root.u
        offset.y: 16 * root.u
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: root.focused ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.focus } }
    }

    Rectangle {
        id: art
        anchors.fill: parent
        radius: 20 * root.u
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.pal.primaryContainer }
            GradientStop { position: 1.0; color: root.pal.surface }
        }

        // soft top-left sheen
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        Image {
            visible: !root.isLibrary
            anchors.centerIn: parent
            width: parent.width * 0.52
            height: width
            source: root.iconSrc
            sourceSize: Qt.size(256, 256)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        // The "Library" tile draws a 3x3 grid instead of an icon
        Grid {
            visible: root.isLibrary
            anchors.centerIn: parent
            columns: 3
            spacing: root.size * 0.05
            Repeater {
                model: 9
                Rectangle {
                    width: root.size * 0.14
                    height: width
                    radius: width * 0.3
                    color: Theme.fg
                    opacity: 0.85
                }
            }
        }
    }

    // focus ring
    Rectangle {
        anchors.fill: art
        anchors.margins: -4 * root.u
        radius: art.radius + 4 * root.u
        color: "transparent"
        border.width: 3 * root.u
        border.color: "white"
        opacity: root.focused ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.focus } }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
}
