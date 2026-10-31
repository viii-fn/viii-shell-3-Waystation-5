import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../hub"

// PS5-style notification toast: a wide, dark glass banner at the top centre with a rounded-square icon tile,
// a bold title and a dim body. It glides down, holds, and glides back up.
// Shows regular notifications and charger plug/unplug events (all state lives in core/Notifs.qml).
// Drawn in a 1366x768 design space and scaled to the screen, so it keeps its proportions on any display.
// Click-through, no keyboard focus, above everything (also over the hub and fullscreen windows).
// The window stays mapped (fully transparent when idle), so Hyprland never plays its own layer animation on it.
PanelWindow {
    id: win

    readonly property real s: screen ? Math.max(0.7, Math.min(screen.width / 1366, screen.height / 768)) : 1

    anchors { top: true }
    margins { top: Math.round(28 * win.s) }
    implicitWidth: Math.ceil(640 * win.s)
    implicitHeight: Math.ceil(200 * win.s)
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
            duration: win.on ? 440 : 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.on ? Motion.out : Motion.inOut
        }
    }

    // small scale pulse when a new toast replaces the one on screen (e.g. the charger event)
    property real pulse: 1
    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: win; property: "pulse"; to: 1.03; duration: 120; easing.type: Easing.OutCubic }
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

    Item {
        id: stage
        width: 640
        height: 200
        scale: win.s
        transformOrigin: Item.TopLeft

        Rectangle {
            id: card
            width: 580
            height: Math.max(92, col.implicitHeight + 38)
            x: (stage.width - width) / 2
            y: 6 - (1 - win.vis) * 70
            radius: 18
            opacity: win.vis
            scale: (0.96 + 0.04 * win.vis) * win.pulse
            transformOrigin: Item.Top
            color: Qt.rgba(0.07, 0.078, 0.098, 0.95)
            border.width: 1
            border.color: (win.e && win.e.urgency === 2) ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.16)

            // rounded-square icon tile: the app's icon, its first letter, or a bolt for charger events
            Rectangle {
                id: tile
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                height: 64
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.10)

                Image {
                    id: img
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    sourceSize: Qt.size(80, 80)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    source: win.iconSrc(win.e)
                    visible: source !== "" && status === Image.Ready
                }
                Txt {
                    anchors.centerIn: parent
                    visible: !!win.e && win.e.kind === "app" && !img.visible
                    text: ((win.e && (win.e.app || win.e.title)) || "?").charAt(0).toUpperCase()
                    font.pixelSize: 28
                    font.weight: Font.Bold
                }
                Canvas {
                    id: bolt
                    anchors.centerIn: parent
                    width: 16
                    height: 26
                    scale: 1.45
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
                            ctx.lineWidth = 2.2;
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
                x: 100
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 100 - 26
                spacing: 3
                Txt {
                    width: parent.width
                    visible: !!win.e && win.e.kind === "app" && !!win.e.app && win.e.app !== win.e.title
                    text: win.e ? (win.e.app || "") : ""
                    font.pixelSize: 13
                    color: Theme.fgDim
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Txt {
                    width: parent.width
                    text: win.e ? win.e.title : ""
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Txt {
                    width: parent.width
                    visible: text !== ""
                    text: win.e ? win.e.body : ""
                    font.pixelSize: 17
                    color: Theme.fgDim
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
