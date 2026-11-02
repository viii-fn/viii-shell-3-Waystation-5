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
    WlrLayershell.keyboardFocus: (win.shown && !win.kbCycle) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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

    // After a workspace switch Hyprland may hand the keyboard to a window on the new workspace.
    // Dropping and re-requesting the exclusive grab for a moment gives it back to the panel.
    property bool kbCycle: false
    function regrab() { kbCycle = true; kbTimer.restart(); }
    Timer { id: kbTimer; interval: 90; onTriggered: { win.kbCycle = false; scope.forceActiveFocus(); } }
    Connections {
        target: Desk
        function onCcRegrab() { win.regrab(); }
        function onCcOpenChanged() { console.log("[viii-cc] ccOpen ->", Desk.ccOpen); }
    }

    FocusScope {
        id: scope
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (ld.item) ld.item.key(event);
            else if (event.key === Qt.Key_Escape) { Desk.ccOpen = false; event.accepted = true; }
        }

        // viii-cc-scrim: a light dim over the top, then a fade that starts 30% up from the bottom
        // and ends in solid black, with pure black below it (the strip sits on that)
        Rectangle {
            id: scrim
            anchors.fill: parent
            opacity: win.vis
            readonly property real topDim: 0.15     // how much the upper part is dimmed (0 = not at all)
            readonly property real fadeFrom: 0.70   // where the fade starts, as a fraction of the screen height
            readonly property real fadeTo: 0.88     // where it is solid black
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, scrim.topDim) }
                GradientStop { position: scrim.fadeFrom; color: Qt.rgba(0, 0, 0, scrim.topDim) }
                GradientStop { position: scrim.fadeTo; color: Qt.rgba(0, 0, 0, 1.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1.0) }
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
                width: 1366
                height: 768
                x: (parent.width - 1366) / 2
                y: (parent.height - 768) / 2
                active: win.visible
                source: "CcContent.qml"
                onLoaded: item.vis = Qt.binding(() => win.vis)
            }
        }
    }
}
