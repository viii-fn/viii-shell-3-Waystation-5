// viii-osd-v2
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "../core"
import "../hub"

// Volume + brightness pop-up, bottom centre, PS5 glass style (same slot, same white ink as the hub).
// Brightness comes from Desk.osdRequested. Volume and mute are watched straight from PipeWire (`pactl subscribe`),
// so it shows no matter who changed them (keys, Control Center, another app). The watcher restarts itself if
// PipeWire restarts, so the pop-up keeps working after an audio restart.
// Drawn in a 380x96 design space and scaled to the screen. Tiny window, no keyboard focus, clicks pass through.
PanelWindow {
    id: win

    readonly property real s: screen ? Math.max(0.7, Math.min(screen.width / 1366, screen.height / 768)) : 1

    anchors { bottom: true }
    margins { bottom: Math.round(52 * win.s) }
    implicitWidth: Math.ceil(380 * win.s)
    implicitHeight: Math.ceil(96 * win.s)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
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

    readonly property string nfFamily: {
        const f = Qt.fontFamilies();
        if (f.indexOf("Symbols Nerd Font") >= 0) return "Symbols Nerd Font";
        if (f.indexOf("Symbols Nerd Font Mono") >= 0) return "Symbols Nerd Font Mono";
        for (let i = 0; i < f.length; i++) if (f[i].indexOf("Nerd Font") >= 0) return f[i];
        return "";
    }
    readonly property bool isVol: kind === "volume"
    readonly property string glyph: {
        if (isVol) return (muted || value <= 0) ? "\uf026" : (value < 50 ? "\uf027" : "\uf028");
        return "\uf185";
    }
    readonly property string glyphFallback: isVol ? (muted ? "OFF" : "VOL") : "BRT"
    readonly property real frac: muted ? 0 : Math.max(0, Math.min(1, value / 100))

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

    // ---- volume: straight from PipeWire (event-driven, no process and no polling) ----
    // Settings and the Control Center already write through this service, so every source
    // (keys, sliders, other apps) updates the same value and the pop-up reacts to it.
    property bool primed: false         // the first value is the current state, not a change
    property int lastVol: -1
    property bool lastMuted: false

    readonly property var sinkNode: Pipewire.defaultAudioSink
    readonly property var sinkAudio: win.sinkNode ? win.sinkNode.audio : null
    readonly property real sinkVol: win.sinkAudio ? win.sinkAudio.volume : -1
    readonly property bool sinkMuted: win.sinkAudio ? win.sinkAudio.muted : false

    function volChanged() {
        if (!win.sinkAudio) return;
        const v = Math.round(Math.max(0, Math.min(1, win.sinkVol)) * 100);
        const mu = win.sinkMuted;
        const changed = (v !== win.lastVol || mu !== win.lastMuted);
        win.lastVol = v;
        win.lastMuted = mu;
        if (!win.primed) { win.primed = true; return; }
        if (!changed || !win.isFocusedMon || Desk.ccOpen) return;
        win.kind = "volume";
        win.muted = mu;
        win.value = v;
        win.pop();
    }
    onSinkVolChanged: volChanged()
    onSinkMutedChanged: volChanged()
    onSinkAudioChanged: volChanged()

    Timer { id: hideTimer; interval: 1400; onTriggered: win.on = false }

    Item {
        id: stage
        width: 380
        height: 96
        scale: win.s
        transformOrigin: Item.TopLeft

        Item {
            id: card
            width: 350
            height: 72
            x: 15
            y: 12 + (1 - win.vis) * 18
            opacity: win.vis
            scale: 0.96 + 0.04 * win.vis
            transformOrigin: Item.Bottom

            GlassSlot { anchors.fill: parent; radius: 24 }

            // icon disc
            Rectangle {
                id: disc
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 46
                radius: 23
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Txt {
                    anchors.centerIn: parent
                    text: win.nfFamily !== "" ? win.glyph : win.glyphFallback
                    font.family: win.nfFamily !== "" ? win.nfFamily : Theme.fontFamily
                    font.pixelSize: win.nfFamily !== "" ? 22 : 11
                    font.weight: Font.Bold
                    color: win.muted ? Theme.fgDim : Theme.fg
                    elide: Text.ElideNone
                }
            }

            Txt {
                x: 76
                y: 11
                text: win.isVol ? (win.muted ? "Muted" : "Volume") : "Brightness"
                font.pixelSize: 13
                color: Theme.fgDim
            }

            // level bar: white ink on a soft track, like the hub
            Rectangle {
                id: track
                x: 76
                y: 40
                width: 188
                height: 8
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.16)
                Rectangle {
                    width: Math.max(win.frac > 0 ? parent.height : 0, parent.width * win.frac)
                    height: parent.height
                    radius: 4
                    color: Theme.fg
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }

            Txt {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: win.muted ? "off" : win.value + "%"
                font.pixelSize: 20
                font.weight: Font.Bold
                color: win.muted ? Theme.fgDim : Theme.fg
            }
        }
    }
}
