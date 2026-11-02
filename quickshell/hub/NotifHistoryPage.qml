import QtQuick
import Quickshell
import "../core"

// Notification history: a full page over the hub, same family as the Wallstore page.
// Newest first, relative times, "Clear all" (press Enter twice). Opened from the bell in the top bar or with SUPER+N.
// Keys come from Hub.handleKey while the page is open: Up/Down browse, Up from the first row reaches Clear all,
// Home/End/PageUp/PageDown jump, Esc leaves.
// Content is laid out in the 1366x768 design space, centred; the background is full-bleed.
Item {
    id: root

    property bool open: false
    signal closeRequested()

    property int current: 0
    property bool btnFocus: false
    property bool armed: false          // "Clear all" waits for a second Enter
    property real now: Date.now()

    readonly property var items: Notifs.history
    readonly property int count: items ? items.length : 0
    readonly property int rowH: 84

    // page enter/leave: fade + slide up
    property real t: open ? 1 : 0
    Behavior on t {
        NumberAnimation {
            duration: root.open ? 340 : 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Motion.out : Motion.inOut
        }
    }
    opacity: t
    visible: opacity > 0.01

    onOpenChanged: {
        if (open) {
            current = 0; btnFocus = false; armed = false;
            now = Date.now();
            scrollAnim.stop(); list.contentY = 0;
            Theme.applyWallpaper();
        }
    }
    onCountChanged: { if (current > count - 1) current = Math.max(0, count - 1); }

    Timer { interval: 30000; repeat: true; running: root.open; onTriggered: root.now = Date.now() }
    Timer { id: armTimer; interval: 3000; onTriggered: root.armed = false }

    function rel(ts) {
        const m = Math.floor(Math.max(0, root.now - ts) / 60000);
        if (m < 1) return "Just now";
        if (m < 60) return m + " min ago";
        const h = Math.floor(m / 60);
        if (h < 24) return h + (h === 1 ? " hour ago" : " hours ago");
        const d = Math.floor(h / 24);
        return d === 1 ? "Yesterday" : d + " days ago";
    }

    function iconSrc(en) {
        if (!en || en.kind !== "app" || !en.icon) return "";
        if (en.icon.charAt(0) === "/") return "file://" + en.icon;
        if (en.icon.indexOf("file://") === 0) return en.icon;
        const p = Quickshell.iconPath(en.icon, true);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }

    // ---- navigation ----
    NumberAnimation { id: scrollAnim; target: list; property: "contentY"; duration: 240; easing.type: Easing.OutCubic }
    function ensureVisible() {
        const top = current * rowH;
        let y = list.contentY;
        if (top < y) y = top;
        else if (top + rowH > y + list.height) y = top + rowH - list.height;
        y = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), y));
        if (y === list.contentY) return;
        scrollAnim.stop();
        scrollAnim.to = y;
        scrollAnim.start();
    }
    function move(d) {
        if (count === 0) return;
        current = Math.max(0, Math.min(count - 1, current + d));
        ensureVisible();
    }
    function pressClear() {
        if (count === 0) return;
        if (!armed) { armed = true; armTimer.restart(); return; }
        armed = false; armTimer.stop();
        Notifs.clear();
        btnFocus = false;
        current = 0;
    }

    function handleKey(e) {
        let handled = true;
        switch (e.key) {
        case Qt.Key_Escape:
            if (armed) { armed = false; armTimer.stop(); }
            else if (btnFocus) btnFocus = false;
            else closeRequested();
            break;
        case Qt.Key_Up:
            if (btnFocus) break;
            if (current === 0 && count > 0) btnFocus = true; else move(-1);
            break;
        case Qt.Key_Down:
            if (btnFocus) { btnFocus = false; armed = false; armTimer.stop(); }
            else move(1);
            break;
        case Qt.Key_PageUp: if (!btnFocus) move(-6); break;
        case Qt.Key_PageDown: if (!btnFocus) move(6); break;
        case Qt.Key_Home: if (!btnFocus && count > 0) { current = 0; ensureVisible(); } break;
        case Qt.Key_End: if (!btnFocus && count > 0) { current = count - 1; ensureVisible(); } break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
            if (btnFocus) pressClear();
            break;
        case Qt.Key_Left: case Qt.Key_Right: break;
        default: handled = false;
        }
        e.accepted = handled;
    }

    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.deep, 0.97) }
    MouseArea { anchors.fill: parent; enabled: root.open }

    Item {
        id: content
        width: 1366
        height: 768
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        transform: Translate { y: (1 - root.t) * 30 }

        Txt { x: 72; y: 38; text: "Notifications"; font.pixelSize: 30; font.weight: Font.Bold }
        Txt {
            x: 72; y: 96
            text: root.count === 0 ? "Nothing yet" : root.count + (root.count === 1 ? " notification" : " notifications")
            font.pixelSize: 17
            color: Theme.fgDim
        }

        // Clear all (Up from the first row, or click)
        Item {
            id: clearBtn
            x: 1366 - 72 - width
            y: 36
            width: 250
            height: 46
            opacity: root.count > 0 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            Rectangle {
                anchors.fill: parent
                radius: 23
                color: Theme.glassHi
                border.width: 1
                border.color: Theme.glassBorder
            }
            Rectangle {
                anchors.fill: parent
                radius: 23
                color: Theme.fg
                opacity: root.btnFocus ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
            Txt {
                anchors.centerIn: parent
                text: root.armed ? "Press Enter to confirm" : "Clear all"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: root.btnFocus ? Theme.deep : Theme.fg
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.btnFocus = true; root.pressClear(); }
            }
        }

        ListView {
            id: list
            x: 60
            y: 150
            width: 1246
            height: 530
            clip: true
            model: root.items
            keyNavigationEnabled: false
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool cur: !root.btnFocus && index === root.current
                readonly property bool power: !!modelData && modelData.kind === "power"
                property real selT: cur ? 1 : 0
                Behavior on selT { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                width: list.width
                height: root.rowH

                Rectangle {
                    x: 12; y: 5
                    width: parent.width - 24
                    height: 74
                    radius: 16
                    color: Theme.glass
                    border.width: 1
                    border.color: (row.modelData && row.modelData.urgency === 2) ? "#ff6b6b" : Theme.glassBorder

                    Rectangle {
                        id: tile
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54
                        height: 54
                        radius: 12
                        color: Theme.glassHi

                        Image {
                            id: ico
                            anchors.centerIn: parent
                            width: 34
                            height: 34
                            sourceSize: Qt.size(68, 68)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            source: root.iconSrc(row.modelData)
                            visible: source !== "" && status === Image.Ready
                        }
                        Txt {
                            anchors.centerIn: parent
                            visible: !row.power && !ico.visible
                            text: ((row.modelData && (row.modelData.app || row.modelData.title)) || "?").charAt(0).toUpperCase()
                            font.pixelSize: 24
                            font.weight: Font.Bold
                        }
                        Canvas {
                            id: bolt
                            anchors.centerIn: parent
                            width: 16
                            height: 26
                            scale: 1.15
                            visible: row.power
                            property bool plug: !!row.modelData && row.modelData.plugged === true
                            property color ink: Theme.accent
                            property color dim: Theme.fgDim
                            onPlugChanged: requestPaint()
                            onInkChanged: requestPaint()
                            onDimChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.fillStyle = bolt.plug ? bolt.ink : bolt.dim;
                                ctx.beginPath();
                                ctx.moveTo(10.4, 0);
                                ctx.lineTo(0, 15.2);
                                ctx.lineTo(7.4, 15.2);
                                ctx.lineTo(5.1, 25.6);
                                ctx.lineTo(16, 9.6);
                                ctx.lineTo(8.6, 9.6);
                                ctx.closePath();
                                ctx.fill();
                                if (!bolt.plug) {
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
                        x: 84
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 84 - 170
                        spacing: 3
                        Txt {
                            width: parent.width
                            text: row.modelData ? row.modelData.title : ""
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                        Txt {
                            width: parent.width
                            visible: text !== ""
                            text: {
                                const en = row.modelData;
                                if (!en) return "";
                                const a = (en.kind === "app" && en.app && en.app !== en.title) ? en.app : "";
                                const b = en.body || "";
                                return a !== "" && b !== "" ? a + "  \u00b7  " + b : (a !== "" ? a : b);
                            }
                            font.pixelSize: 14
                            color: Theme.fgDim
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }

                    Txt {
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData ? root.rel(row.modelData.t) : ""
                        font.pixelSize: 14
                        color: Theme.fgDim
                    }
                }

                // the single focus highlight
                Rectangle {
                    x: 8; y: 2
                    width: parent.width - 16
                    height: 80
                    radius: 20
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.fg
                    opacity: row.selT
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: { root.btnFocus = false; root.current = row.index; }
                }
            }
        }

        // empty state
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 300
            width: 700
            height: 100
            opacity: root.count === 0 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 240 } }
            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                text: "No notifications yet"
                font.pixelSize: 24
                font.weight: Font.Bold
            }
            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 44
                text: "Anything that pops up will be kept here"
                font.pixelSize: 15
                color: Theme.fgDim
            }
        }
    }
}
