import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"

// PS-button Control Center. One layer-shell window per monitor, shown only on the focused monitor
// while Desk.ccOpen is true. The content (CcContent.qml) is only loaded while the window is visible.
// Design space is 1366x768, scaled uniformly to the actual screen (same as the hub).
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "viii-cc"
    WlrLayershell.keyboardFocus: win.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var fm: Hyprland.focusedMonitor
    readonly property bool isFocusedMon: fm ? fm.name === screen.name : true
    readonly property bool shown: Desk.ccOpen && isFocusedMon

    property real vis: shown ? 1 : 0
    Behavior on vis {
        NumberAnimation {
            duration: win.shown ? Motion.reveal : Motion.hide
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.shown ? Motion.out : Motion.inOut
        }
    }
    visible: shown || vis > 0.002

    readonly property real s: Math.max(0.1, Math.min(width / 1366, height / 768))
    readonly property real dW: width / s
    readonly property real dH: height / s

    onShownChanged: if (shown) scope.forceActiveFocus()

    FocusScope {
        id: scope
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (ld.item) ld.item.key(event);
            else if (event.key === Qt.Key_Escape) { Desk.ccOpen = false; event.accepted = true; }
        }

        // dim scrim, tinted by the current theme, darker toward the bottom where the strip sits
        Rectangle {
            anchors.fill: parent
            opacity: win.vis
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.30) }
                GradientStop { position: 0.55; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.72) }
                GradientStop { position: 1.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.95) }
            }
        }

        // click anywhere outside the card / buttons closes it
        MouseArea { anchors.fill: parent; onClicked: Desk.ccOpen = false }

        Item {
            id: stage
            width: win.dW
            height: win.dH
            x: (win.width - width) / 2
            y: (win.height - height) / 2
            transformOrigin: Item.Center
            scale: win.s

            Loader {
                id: ld
                anchors.fill: parent
                active: win.visible
                source: "CcContent.qml"
                onLoaded: item.vis = Qt.binding(() => win.vis)
            }
        }
    }
}
