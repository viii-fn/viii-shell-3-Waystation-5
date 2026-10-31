import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../core"
import "../hub"

// Small pop-up at the bottom centre for brightness AND volume. Tiny window, no keyboard focus.
// Brightness comes from Desk.osdRequested; volume/mute are watched straight from PipeWire,
// so it shows no matter who changed them (keys, Control Center, another app).
PanelWindow {
    id: win

    anchors { bottom: true }
    margins { bottom: 64 }
    implicitWidth: 320
    implicitHeight: 64
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "viii-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property var fm: Hyprland.focusedMonitor
    readonly property bool isFocusedMon: fm ? fm.name === screen.name : true

    property string kind: "brightness"
    property int value: 0
    property bool muted: false
    property bool on: false

    property real vis: on ? 1 : 0
    Behavior on vis {
        NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }
    visible: on || vis > 0.002

    function pop() { on = true; hideTimer.restart(); }

    // ---- brightness ----
    Connections {
        target: Desk
        function onOsdRequested(k, v) {
            if (!win.isFocusedMon || Desk.ccOpen) return;
            win.kind = k;
            win.muted = false;
            win.value = v;
            win.pop();
        }
    }

    // ---- volume: no Quickshell-PipeWire API; listen with `pactl subscribe`, read with `wpctl` ----
    property bool armed: false          // ignore the first read after startup
    property int lastVol: -1
    property bool lastMuted: false
    Timer { running: true; interval: 2500; onTriggered: win.armed = true }

    Process {
        id: sub
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => { if (/on sink #/.test(line)) readTimer.restart(); }
        }
    }
    Timer { id: readTimer; interval: 60; onTriggered: { if (!getVol.running) getVol.running = true; } }
    Timer { running: true; interval: 800; onTriggered: { if (!getVol.running) getVol.running = true; } }

    Process {
        id: getVol
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /([0-9.]+)/.exec(this.text);
                if (!m) return;
                const v = Math.round(parseFloat(m[1]) * 100);
                const mu = this.text.indexOf("MUTED") >= 0;
                const changed = (v !== win.lastVol || mu !== win.lastMuted);
                win.lastVol = v;
                win.lastMuted = mu;
                if (!changed || !win.armed || !win.isFocusedMon || Desk.ccOpen) return;
                win.kind = "volume";
                win.muted = mu;
                win.value = v;
                win.pop();
            }
        }
    }

    Timer { id: hideTimer; interval: 1300; onTriggered: win.on = false }

    Rectangle {
        width: 300
        height: 56
        x: 10
        y: 4 + (1 - win.vis) * 14
        radius: 28
        opacity: win.vis
        color: Qt.alpha(Theme.deep, 0.92)
        border.width: 1
        border.color: Theme.glassHi

        Txt {
            x: 22
            anchors.verticalCenter: parent.verticalCenter
            text: win.kind === "volume" ? (win.muted ? "Muted" : "Volume") : "Brightness"
            font.pixelSize: 15
            color: Theme.fgDim
        }
        Rectangle {
            x: 118
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            height: 8
            radius: 4
            color: Theme.glassHi
            Rectangle {
                width: win.muted ? 0 : parent.width * Math.max(0, Math.min(1, win.value / 100))
                height: parent.height
                radius: 4
                color: Theme.accent
            }
        }
        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            text: win.muted ? "off" : win.value + "%"
            font.pixelSize: 17
            font.weight: Font.Bold
        }
    }
}
