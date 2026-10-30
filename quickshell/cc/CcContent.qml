import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import "../core"
import "../hub"

// Everything inside the Control Center. Loaded by ControlCenter.qml only while it is open,
// so none of this (PipeWire tracking, nmcli, bluetooth, mpris) costs anything when it is closed.
// Works in the 1366x768 design space.
Item {
    id: root

    property real vis: 1
    property int idx: 0              // 0 volume, 1 brightness, 2 wifi, 3 bluetooth, 4 media, 5 power
    property int powerIdx: 0
    property string armed: ""        // name of the destructive power item waiting for a second Enter

    property bool wifiOn: false
    property string wifiName: ""

    // ---- backends ----
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: (sink && sink.audio) ? sink.audio.volume : 0
    readonly property bool muted: (sink && sink.audio) ? sink.audio.muted : false

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter ? adapter.enabled : false
    readonly property int btCount: {
        if (!Bluetooth.devices) return 0;
        return Bluetooth.devices.values.filter(d => d.connected).length;
    }

    readonly property var player: {
        const l = Mpris.players.values;
        for (let i = 0; i < l.length; i++) if (l[i].isPlaying) return l[i];
        return l.length > 0 ? l[0] : null;
    }

    readonly property var powerItems: [
        { n: "Lock", c: ["hyprlock"], danger: false },
        { n: "Sleep", c: ["systemctl", "suspend"], danger: false },
        { n: "Restart", c: ["systemctl", "reboot"], danger: true },
        { n: "Shut down", c: ["systemctl", "poweroff"], danger: true }
    ]

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli -t -f WIFI g; nmcli -t -f TYPE,NAME connection show --active | grep '^802-11-wireless' | head -n1"]
        stdout: StdioCollector { onStreamFinished: root.wifiParsed(this.text) }
    }
    Timer { id: wifiTimer; interval: 1200; onTriggered: wifiProc.running = true }
    Timer { id: armTimer; interval: 3500; onTriggered: root.armed = "" }

    function wifiParsed(t) {
        const l = t.split("\n");
        wifiOn = (l[0] || "").trim() === "enabled";
        const n = l[1] || "";
        const c = n.indexOf(":");
        wifiName = c >= 0 ? n.slice(c + 1).replace(/\\:/g, ":") : "";
    }

    Component.onCompleted: { Desk.briRefresh(); wifiProc.running = true; }

    // ---- actions ----
    function select(i) { idx = Math.max(0, Math.min(5, i)); armed = ""; }

    function adjust(d) {   // d = +1 for Up, -1 for Down
        if (idx === 0) {
            if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, vol + 0.05 * d));
        } else if (idx === 1) {
            Desk.briStep(5 * d);
        } else if (idx === 4) {
            if (player) { if (d > 0) player.next(); else player.previous(); }
        } else if (idx === 5) {
            powerIdx = Math.max(0, Math.min(3, powerIdx - d));
            armed = "";
        }
    }

    function runPower() {
        const it = powerItems[powerIdx];
        if (it.danger && armed !== it.n) { armed = it.n; armTimer.restart(); return; }
        Desk.ccOpen = false;
        Quickshell.execDetached(it.c);
    }

    function enter() {
        if (idx === 0) {
            if (sink && sink.audio) sink.audio.muted = !muted;
        } else if (idx === 2) {
            Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "off" : "on"]);
            wifiOn = !wifiOn;
            wifiTimer.restart();
        } else if (idx === 3) {
            if (adapter) adapter.enabled = !adapter.enabled;
        } else if (idx === 4) {
            if (player && player.canTogglePlaying) player.togglePlaying();
        } else if (idx === 5) {
            runPower();
        }
    }

    function key(e) {
        let ok = true;
        switch (e.key) {
        case Qt.Key_Left: case Qt.Key_H: select(idx - 1); break;
        case Qt.Key_Right: case Qt.Key_L: select(idx + 1); break;
        case Qt.Key_Up: case Qt.Key_K: adjust(1); break;
        case Qt.Key_Down: case Qt.Key_J: adjust(-1); break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: enter(); break;
        case Qt.Key_Escape: Desk.ccOpen = false; break;
        default: ok = false;
        }
        e.accepted = ok;
    }

    // ---- inline building blocks ----
    component SliderCard: Item {
        id: sc
        property string title: ""
        property string big: ""
        property real frac: 0
        property string hintText: ""
        anchors.fill: parent
        Txt { text: sc.title; font.pixelSize: 20; font.weight: Font.DemiBold; color: Theme.fgDim }
        Txt { y: 30; text: sc.big; font.pixelSize: 64; font.weight: Font.Bold }
        Rectangle {
            y: 128
            width: parent.width
            height: 10
            radius: 5
            color: Qt.rgba(1, 1, 1, 0.18)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, sc.frac))
                height: parent.height
                radius: 5
                color: Theme.accent
            }
        }
        Txt { y: 156; text: sc.hintText; font.pixelSize: 15; color: Theme.fgDim }
    }

    component InfoCard: Item {
        id: ic
        property string title: ""
        property string big: ""
        property string sub: ""
        property string hintText: ""
        anchors.fill: parent
        Txt { text: ic.title; font.pixelSize: 20; font.weight: Font.DemiBold; color: Theme.fgDim }
        Txt { y: 40; width: parent.width; text: ic.big; font.pixelSize: 44; font.weight: Font.Bold }
        Txt { y: 106; width: parent.width; text: ic.sub; font.pixelSize: 22; color: Theme.fgDim }
        Txt { y: 156; text: ic.hintText; font.pixelSize: 15; color: Theme.fgDim }
    }

    // ---- scene ----
    Txt {
        x: 54
        y: 38
        text: "Control Center"
        font.pixelSize: 24
        font.weight: Font.Bold
        opacity: Math.min(1, root.vis * 2)
    }

    // detail card for the selected button
    Rectangle {
        id: card
        width: 560
        height: 214
        x: (root.width - width) / 2
        y: 270 + (1 - root.vis) * 30
        radius: 28
        color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        opacity: root.vis
        MouseArea { anchors.fill: parent }

        Item {
            anchors.fill: parent
            anchors.margins: 28

            Item {
                anchors.fill: parent
                opacity: root.idx === 0 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }
                SliderCard {
                    title: "Volume"
                    big: root.muted ? "Muted" : Math.round(root.vol * 100) + "%"
                    frac: root.muted ? 0 : root.vol
                    hintText: "↑ ↓ adjust     Enter mute"
                }
            }
            Item {
                anchors.fill: parent
                opacity: root.idx === 1 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }
                SliderCard {
                    title: "Brightness"
                    big: Desk.brightness >= 0 ? Desk.brightness + "%" : "—"
                    frac: Desk.brightness >= 0 ? Desk.brightness / 100 : 0
                    hintText: "↑ ↓ adjust"
                }
            }
            Item {
                anchors.fill: parent
                opacity: root.idx === 2 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }
                InfoCard {
                    title: "Wi-Fi"
                    big: root.wifiOn ? "On" : "Off"
                    sub: root.wifiOn ? (root.wifiName !== "" ? root.wifiName : "Not connected") : ""
                    hintText: "Enter turn " + (root.wifiOn ? "off" : "on")
                }
            }
            Item {
                anchors.fill: parent
                opacity: root.idx === 3 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }
                InfoCard {
                    title: "Bluetooth"
                    big: !root.adapter ? "No adapter" : (root.btOn ? "On" : "Off")
                    sub: root.btOn ? (root.btCount === 0 ? "No devices connected" : root.btCount + (root.btCount === 1 ? " device connected" : " devices connected")) : ""
                    hintText: root.adapter ? "Enter turn " + (root.btOn ? "off" : "on") : ""
                }
            }
            Item {
                anchors.fill: parent
                opacity: root.idx === 4 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }
                InfoCard {
                    title: root.player ? (root.player.isPlaying ? "Now playing" : "Paused") : "Media"
                    big: root.player ? (root.player.trackTitle || "Unknown track") : "Nothing playing"
                    sub: root.player ? (root.player.trackArtist || "") : ""
                    hintText: root.player ? "Enter play / pause     ↑ next     ↓ previous" : ""
                }
            }
            Item {
                anchors.fill: parent
                opacity: root.idx === 5 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }
                Txt { text: "Power"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Theme.fgDim }
                Column {
                    y: 30
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: root.powerItems
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool cur: root.powerIdx === index
                            width: parent.width
                            height: 30
                            radius: 15
                            color: cur ? Theme.fg : "transparent"
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Txt {
                                x: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData.n
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                                color: parent.cur ? "#101218" : Theme.fg
                            }
                            Txt {
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.armed === parent.modelData.n
                                text: "Press Enter again"
                                font.pixelSize: 14
                                color: "#101218"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root.powerIdx = parent.index; root.armed = ""; root.runPower(); }
                            }
                        }
                    }
                }
            }
        }
    }

    // the button strip
    Row {
        id: strip
        spacing: 30
        x: (root.width - width) / 2
        y: 520 + (1 - root.vis) * 50
        opacity: root.vis

        CcButton {
            glyph: ""; fallback: "VOL"; label: "Volume"
            lit: !root.muted
            selected: root.idx === 0
            onClicked: root.select(0)
        }
        CcButton {
            glyph: ""; fallback: "BRI"; label: "Brightness"
            selected: root.idx === 1
            onClicked: root.select(1)
        }
        CcButton {
            glyph: ""; fallback: "WiFi"; label: "Wi-Fi"
            lit: root.wifiOn
            selected: root.idx === 2
            onClicked: root.select(2)
        }
        CcButton {
            glyph: ""; fallback: "BT"; label: "Bluetooth"
            lit: root.btOn
            selected: root.idx === 3
            onClicked: root.select(3)
        }
        CcButton {
            glyph: ""; fallback: "MED"; label: "Media"
            lit: root.player !== null
            selected: root.idx === 4
            onClicked: root.select(4)
        }
        CcButton {
            glyph: ""; fallback: "PWR"; label: "Power"
            selected: root.idx === 5
            onClicked: root.select(5)
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 72
        y: parent.height - 56
        spacing: 28
        opacity: root.vis
        Hint { key: "← →"; label: "Select" }
        Hint { key: "↑ ↓"; label: "Adjust" }
        Hint { key: "Enter"; label: "Toggle" }
        Hint { key: "Esc"; label: "Close" }
    }
}
