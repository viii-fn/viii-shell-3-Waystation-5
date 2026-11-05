import QtQuick
import Quickshell.Networking
import "../core"

// viii-store: Explore support. The news panes are drawn by StoreGrid (same engine as the Welcome grid);
// this file keeps what is not a pane: the daily fetch while the Explore tile is on screen, and the
// "Open in browser?" dialog. HomePage owns the focus state and the keys.
Item {
    id: root

    property bool shown: true
    property int idx: 0
    property bool prompt: false          // "Open in browser?" dialog
    property int promptSel: 0            // 0 = Open, 1 = Cancel
    signal promptPicked(int sel)

    readonly property bool live: shown && visible
    readonly property var items: News.items
    readonly property var cur: items.length > 0 ? items[Math.max(0, Math.min(idx, items.length - 1))] : null

    // ---- network (same source as the Welcome grid) ----
    readonly property var wifiDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wifi) return devices[i];
        return null;
    }
    readonly property var wiredDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wired && devices[i].connected) return devices[i];
        return null;
    }
    readonly property var wifiNetworks: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    readonly property bool online: {
        for (let i = 0; i < wifiNetworks.length; i++)
            if (wifiNetworks[i].connected) return true;
        return wiredDevice !== null;
    }

    // ---- the daily fetch: only while this page is on screen and online, 2 s after it appears ----
    function maybeFetch() {
        if (live && online && (News.items.length === 0 || News.stale())) News.refresh();
    }
    onLiveChanged: { if (live) kick.restart(); }
    onOnlineChanged: { if (online && live) kick.restart(); }
    Timer { id: kick; interval: 2000; onTriggered: root.maybeFetch() }

    // ================= "Open in browser?" =================
    Item {
        id: dlg
        anchors.fill: parent
        z: 20
        property real pT: root.prompt ? 1 : 0
        Behavior on pT {
            NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        }
        opacity: pT
        visible: pT > 0.01

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.58)
            MouseArea { anchors.fill: parent; onClicked: root.promptPicked(1) }
        }

        Item {
            id: box
            width: 480
            height: 236
            x: (parent.width - width) / 2
            y: 244 + (1 - dlg.pT) * 16
            scale: 0.96 + 0.04 * dlg.pT

            Rectangle { anchors.fill: parent; radius: 22; color: Qt.rgba(0.06, 0.065, 0.08, 0.97) }
            GlassSlot { anchors.fill: parent; radius: 22; alpha: 1 }

            Txt {
                x: 28; y: 24
                text: "Open in browser?"
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }
            Txt {
                x: 28; y: 66
                width: parent.width - 56
                text: root.cur ? root.cur.title : ""
                font.pixelSize: 15
                color: Theme.fgDim
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
            Txt {
                x: 28; y: 116
                width: parent.width - 56
                text: root.cur ? News.host(root.cur.link) : ""
                font.pixelSize: 13
                color: Theme.fgDim
                opacity: 0.8
            }

            Repeater {
                model: 2
                delegate: Item {
                    id: btn
                    required property int index
                    readonly property bool on: root.promptSel === index
                    property real bk: on ? 1 : 0
                    Behavior on bk {
                        NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                    }
                    x: 28 + index * 224
                    y: 164
                    width: 200
                    height: 46

                    Rectangle {
                        anchors.fill: parent
                        radius: 23
                        color: Qt.rgba(0.12 + 0.07 * btn.bk, 0.13 + 0.07 * btn.bk, 0.15 + 0.07 * btn.bk, 0.92)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                    }
                    GlassRing {
                        readonly property real out: 3.5
                        x: -out; y: -out
                        width: btn.width + 2 * out
                        height: btn.height + 2 * out
                        radius: 23 + out
                        thickness: 2.5
                        opacity: btn.bk
                        visible: root.visible && opacity > 0.01
                    }
                    Txt {
                        anchors.centerIn: parent
                        text: btn.index === 0 ? "Open" : "Cancel"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.promptPicked(btn.index)
                    }
                }
            }
        }
    }
}
