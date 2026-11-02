import QtQuick
import Quickshell.Networking
import "../core"

// viii-explore: the PS5 "Explore" page. While the Explore tile is selected: the lead story (source, date,
// title, short summary) lower left, a row of news cards below, and the selected story's picture as the
// background (drawn by Backdrop). HomePage owns the focus state (cardsFocus, idx, prompt) and the keys;
// this file only draws it. Data: News (daily cache). Nothing is loaded or fetched while it is hidden.
Item {
    id: root

    property bool shown: true
    property real padL: 128
    property bool cardsFocus: false
    property int idx: 0
    property bool prompt: false          // "Open in browser?" dialog
    property int promptSel: 0            // 0 = Open, 1 = Cancel
    signal cardClicked(int i)
    signal promptPicked(int sel)

    readonly property bool live: shown && visible
    readonly property var items: News.items
    readonly property var cur: items.length > 0 ? items[Math.max(0, Math.min(idx, items.length - 1))] : null

    readonly property real cardW: 232
    readonly property real cardH: 130
    readonly property real cardGap: 14
    property real scrollX: Math.max(0, idx - 3) * (cardW + cardGap)
    Behavior on scrollX {
        NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

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

    readonly property string emptyTitle: News.busy ? "Getting today\u2019s news" : "No news yet"
    readonly property string emptyText: {
        if (News.busy) return "Linux and PlayStation stories are on their way.";
        if (!online) return "Waiting for a network connection.";
        if (News.failed) return "Could not reach the news feeds. It will try again in a few minutes.";
        return "Today\u2019s stories will appear here in a moment.";
    }

    // ================= lead story =================
    Item {
        id: lead
        x: root.padL
        y: 372
        width: 780
        height: 200
        property real k: 1
        opacity: k
        transform: Translate { y: (1 - lead.k) * 10 }

        NumberAnimation {
            id: leadAnim
            target: lead; property: "k"
            from: 0; to: 1; duration: 380
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out
        }
        Connections {
            target: root
            function onCurChanged() { leadAnim.restart(); }
        }

        Column {
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: 10
            Txt {
                visible: root.cur !== null
                width: parent.width
                text: root.cur ? root.cur.source + "  |  " + News.ago(root.cur.ts) : ""
                font.pixelSize: 16
                color: Theme.fgDim
            }
            Txt {
                width: parent.width
                text: root.cur ? root.cur.title : root.emptyTitle
                font.pixelSize: 38
                font.weight: Font.Light
                wrapMode: Text.WordWrap
                maxLineCount: 2
            }
            Txt {
                visible: text !== ""
                width: 700
                text: root.cur ? root.cur.summary : root.emptyText
                font.pixelSize: 17
                color: Theme.fgDim
                wrapMode: Text.WordWrap
                maxLineCount: 2
            }
        }
    }

    // ================= card row =================
    Item {
        id: strip
        x: root.padL - 8
        y: 582
        width: root.width - root.padL + 8
        height: root.cardH + 16
        clip: true

        Repeater {
            model: root.live ? root.items.length : 0
            delegate: Item {
                id: card
                required property int index
                readonly property var it: root.items[index]
                readonly property bool sel: index === root.idx && root.cardsFocus
                property real kk: sel ? 1 : 0
                Behavior on kk {
                    NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                }

                x: 8 + index * (root.cardW + root.cardGap) - root.scrollX
                y: 8 + (1 - kk) * 3
                width: root.cardW
                height: root.cardH
                visible: x + width > -20 && x < strip.width + 20

                Rectangle { anchors.fill: parent; color: Qt.rgba(0.07, 0.078, 0.098, 1) }
                Image {
                    anchors.fill: parent
                    source: card.it ? News.src(card.it.img) : ""
                    sourceSize: Qt.size(464, 260)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 84
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.84) }
                    }
                }
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.30 * (1 - card.kk)) }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                }

                // group tag, top left
                Rectangle {
                    x: 8; y: 8
                    width: tag.width + 14
                    height: 20
                    radius: 10
                    color: Qt.rgba(0.07, 0.078, 0.098, 0.88)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.16)
                    Txt {
                        id: tag
                        anchors.centerIn: parent
                        text: card.it ? card.it.group : ""
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
                // action label on the selected card
                Rectangle {
                    anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 8 }
                    width: act.width + 14
                    height: 20
                    radius: 10
                    opacity: card.kk
                    visible: opacity > 0.01
                    color: Qt.rgba(1, 1, 1, 0.92)
                    Txt {
                        id: act
                        anchors.centerIn: parent
                        text: "Enter \u00b7 Read"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#14161a"
                    }
                }

                Column {
                    x: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 9
                    width: parent.width - 24
                    spacing: 2
                    Txt {
                        width: parent.width
                        text: card.it ? card.it.source : ""
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.fgDim
                    }
                    Txt {
                        width: parent.width
                        text: card.it ? card.it.title : ""
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        maxLineCount: 2
                    }
                }

                GlassRing {
                    readonly property real out: 3.5
                    x: -out; y: -out
                    width: card.width + 2 * out
                    height: card.height + 2 * out
                    radius: 6 + out
                    thickness: 2.5
                    opacity: card.kk
                    visible: opacity > 0.01
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.cardClicked(card.index)
                }
            }
        }
    }

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
                maxLineCount: 2
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
                        visible: opacity > 0.01
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
