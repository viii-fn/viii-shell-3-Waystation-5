import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../hub"

// PS5-style notification toast: a dark glass card at the top centre that glides down, holds, and glides back up.
// Shows regular notifications and charger plug/unplug events (all state lives in core/Notifs.qml).
// Click-through, no keyboard focus, above everything (also over the hub and fullscreen windows).
// The window stays mapped (fully transparent when idle), so Hyprland never plays its own layer animation on it.
PanelWindow {
    id: win

    anchors { top: true }
    margins { top: 24 }
    implicitWidth: 480
    implicitHeight: 150
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "viii-notif"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property var fm: Hyprland.focusedMonitor
    readonly property bool isFocusedMon: fm ? fm.name === screen.name : true
    readonly property var e: Notifs.current
    readonly property bool on: Notifs.shown && isFocusedMon

    // 0 = hidden, 1 = fully shown
    property real vis: on ? 1 : 0
    Behavior on vis {
        NumberAnimation {
            duration: win.on ? 460 : 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.on ? Motion.out : Motion.inOut
        }
    }

    // small scale pulse when a new toast replaces the one on screen (e.g. the charger event)
    property real pulse: 1
    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: win; property: "pulse"; to: 1.035; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "pulse"; to: 1; duration: 260; easing.type: Easing.OutCubic }
    }
    Connections {
        target: Notifs
        function onCurrentChanged() { if (win.on && win.vis > 0.5) pulseAnim.restart(); }
    }

    function iconSrc(en) {
        if (!en || en.kind !== "app" || !en.icon) return "";
        if (en.icon.charAt(0) === "/") return "file://" + en.icon;
        if (en.icon.indexOf("file://") === 0) return en.icon;
        const p = Quickshell.iconPath(en.icon, true);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }

    Rectangle {
        id: card
        width: 440
        height: Math.max(76, col.implicitHeight + 30)
        x: (win.width - width) / 2
        y: 4 - (1 - win.vis) * 46
        radius: 24
        opacity: win.vis
        scale: (0.94 + 0.06 * win.vis) * win.pulse
        transformOrigin: Item.Top
        color: Qt.alpha(Theme.deep, 0.94)
        border.width: 1
        border.color: (win.e && win.e.urgency === 2) ? "#ff6b6b" : Theme.glassHi

        // round icon badge: the app's icon, its first letter, or a bolt for charger events
        Item {
            id: badge
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48

            Rectangle { anchors.fill: parent; radius: 24; color: Theme.glassHi }

            Image {
                id: img
                anchors.centerIn: parent
                width: 30
                height: 30
                sourceSize: Qt.size(60, 60)
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                source: win.iconSrc(win.e)
                visible: source !== "" && status === Image.Ready
            }
            Txt {
                anchors.centerIn: parent
                visible: !!win.e && win.e.kind === "app" && !img.visible
                text: ((win.e && (win.e.app || win.e.title)) || "?").charAt(0).toUpperCase()
                font.pixelSize: 21
                font.weight: Font.Bold
            }
            Canvas {
                id: bolt
                anchors.centerIn: parent
                width: 16
                height: 26
                visible: !!win.e && win.e.kind === "power"
                property var ent: win.e
                property color ink: Theme.accent
                property color dim: Theme.fgDim
                onEntChanged: requestPaint()
                onInkChanged: requestPaint()
                onDimChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const plugged = !!bolt.ent && bolt.ent.plugged === true;
                    ctx.fillStyle = plugged ? bolt.ink : bolt.dim;
                    ctx.beginPath();
                    ctx.moveTo(10.4, 0);
                    ctx.lineTo(0, 15.2);
                    ctx.lineTo(7.4, 15.2);
                    ctx.lineTo(5.1, 25.6);
                    ctx.lineTo(16, 9.6);
                    ctx.lineTo(8.6, 9.6);
                    ctx.closePath();
                    ctx.fill();
                    if (!plugged) {
                        // slash through the bolt = unplugged
                        ctx.strokeStyle = "#f5f7fb";
                        ctx.lineWidth = 2.4;
                        ctx.lineCap = "round";
                        ctx.beginPath();
                        ctx.moveTo(1.5, 24.5);
                        ctx.lineTo(14.5, 1.5);
                        ctx.stroke();
                    }
                }
            }
        }

        Column {
            id: col
            x: 84
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 84 - 22
            spacing: 3
            Txt {
                width: parent.width
                text: win.e ? win.e.title : ""
                font.pixelSize: 18
                font.weight: Font.Bold
                textFormat: Text.PlainText
            }
            Txt {
                width: parent.width
                visible: text !== ""
                text: win.e ? win.e.body : ""
                font.pixelSize: 15
                color: Theme.fgDim
                wrapMode: Text.Wrap
                maximumLineCount: 2
                textFormat: Text.PlainText
            }
        }
    }
}
