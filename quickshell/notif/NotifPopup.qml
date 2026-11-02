// viii-notif-v2
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../hub"

// Notification pop-up, PS5 style: a glass card that slides in from the top-right corner (that is where the PS5
// puts its pop-ups), round icon on the left, bold title, dim text under it. Click-through, no keyboard focus.
PanelWindow {
    id: win

    readonly property real s: screen ? Math.max(0.7, Math.min(screen.width / 1366, screen.height / 768)) : 1

    anchors { top: true; right: true }
    margins { top: Math.round(26 * win.s); right: Math.round(30 * win.s) }
    implicitWidth: Math.ceil(450 * win.s)
    implicitHeight: Math.ceil(150 * win.s)
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
    readonly property bool urgent: !!e && e.urgency === 2

    property real vis: on ? 1 : 0
    Behavior on vis {
        NumberAnimation {
            duration: win.on ? 460 : 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.on ? Motion.out : Motion.inOut
        }
    }

    property real pulse: 1
    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: win; property: "pulse"; to: 1.025; duration: 120; easing.type: Easing.OutCubic }
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
        width: 450
        height: 150
        scale: win.s
        transformOrigin: Item.TopLeft

        Item {
            id: card
            width: 410
            height: Math.max(84, col.implicitHeight + 34)
            x: stage.width - width - 4 + (1 - win.vis) * 70
            y: 6
            opacity: win.vis
            scale: (0.97 + 0.03 * win.vis) * win.pulse
            transformOrigin: Item.TopRight

            GlassSlot {
                anchors.fill: parent
                radius: 22
                edge: win.urgent ? Qt.rgba(1, 0.42, 0.42, 0.75) : Qt.rgba(1, 1, 1, 0.08)
            }

            // round icon disc
            Rectangle {
                id: disc
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 54
                height: 54
                radius: 27
                color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                Image {
                    id: img
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    sourceSize: Qt.size(64, 64)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    source: win.iconSrc(win.e)
                    visible: source !== "" && status === Image.Ready
                }
                Txt {
                    anchors.centerIn: parent
                    visible: !!win.e && win.e.kind === "app" && !img.visible
                    text: ((win.e && (win.e.app || win.e.title)) || "?").charAt(0).toUpperCase()
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }
                Canvas {
                    id: bolt
                    anchors.centerIn: parent
                    width: 16
                    height: 26
                    scale: 1.0
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
                            ctx.strokeStyle = "#f5f7fb";
                            ctx.lineWidth = 2.0;
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
                x: 86
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 86 - 22
                spacing: 3
                Txt {
                    width: parent.width
                    visible: !!win.e && win.e.kind === "app" && !!win.e.app && win.e.app !== win.e.title
                    text: win.e ? (win.e.app || "") : ""
                    font.pixelSize: 12
                    color: Theme.fgDim
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Txt {
                    width: parent.width
                    text: win.e ? win.e.title : ""
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Txt {
                    width: parent.width
                    visible: text !== ""
                    text: win.e ? win.e.body : ""
                    font.pixelSize: 13
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
