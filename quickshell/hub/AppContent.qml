import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../core"

// viii-appcontent: the PS Plus style content screen for a regular app tile.
//
//   row 1 (small): Screen time   Last 7 days   Share
//   row 2 (tall):  About         System        News
//
// It uses the same focus mechanism as WelcomeGrid: HomePage drives `lift` (its animated
// `c`), `focusIdx` and the shared card cursor, so Down enters the cards, the tile row
// recedes, the hero fades, the mosaic rises to HomePage.focusY and a single GlassRing
// glides between cards. Row 2 peeks at the bottom edge while the page rests.
//
// Data rules (2 GB RAM): nothing runs while the page is hidden; web data is cache-first and
// only fetched while the page is visible; /proc is only read while the page is visible.
Item {
    id: root
    property var entry: null
    property bool shown: true
    readonly property bool active: shown && visible
    property real lift: 0                  // 0 = resting, 1 = the cards have focus
    property int focusIdx: -1              // focused card while the cards have focus
    property real topSum: 0                // most-used seconds over 7 days (HomePage.topSum)

    readonly property real colW: 358
    readonly property real gutter: 23
    readonly property real small: 108
    readonly property real tall: 233
    readonly property real gapY: 23
    readonly property real contentH: small + gapY + tall
    width: 3 * colW + 2 * gutter
    height: contentH

    readonly property string home: Quickshell.env("HOME")
    readonly property string key: entry ? Apps.safeKey(entry) : ""
    property real nowSec: Date.now() / 1000

    // ======================= screen time =======================
    readonly property real today: { if (!root.active) return 0; void ScreenTime.revision; return entry ? ScreenTime.sum(entry, 1) : 0; }
    readonly property real week: { if (!root.active) return 0; void ScreenTime.revision; return entry ? ScreenTime.sum(entry, 7) : 0; }
    readonly property var series: {
        if (!root.active) return [];
        void ScreenTime.revision;
        const out = [];
        if (!entry) return out;
        for (let i = 6; i >= 0; i--) out.push(ScreenTime.sum(entry, i + 1) - ScreenTime.sum(entry, i));
        return out;
    }
    readonly property real maxDay: Math.max(60, ...series)
    readonly property int pct: topSum > 0 ? Math.round(100 * week / topSum) : 0

    // ======================= network (cache-first gate) =======================
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
    readonly property var activeNet: {
        for (let i = 0; i < wifiNetworks.length; i++)
            if (wifiNetworks[i].connected) return wifiNetworks[i];
        return null;
    }
    readonly property bool online: activeNet !== null || wiredDevice !== null

    // ======================= about this app (cache first, then viii-about) =======================
    property var about: null
    property var aboutTried: ({})
    onKeyChanged: { about = null; if (active) kick.restart(); }
    FileView {
        id: aboutFile
        path: root.key !== "" ? root.home + "/.cache/viii/about/" + root.key + ".json" : ""
        printErrors: false
        onLoaded: { try { root.about = JSON.parse(aboutFile.text()); } catch (e) { root.about = null; } }
        onLoadFailed: { root.about = null; root.fetchAbout(); }
    }
    Process {
        id: aboutProc
        onExited: (code, status) => {
            if (code === 0) aboutFile.reload();
            else root.aboutTried = ({});
        }
    }
    function fetchAbout() {
        if (!active || !online || !entry || aboutProc.running || aboutTried[key]) return;
        const e = entry;
        aboutTried[key] = true;
        aboutProc.command = ["nice", "-n", "19", home + "/.local/bin/viii-about", key, String(e.id || e.name), String(e.name), String(e.comment || "")];
        aboutProc.running = true;
    }

    // ======================= system monitor (tall widget) =======================
    readonly property bool sysOn: root.active
    property real cpuPct: 0
    property real memUsed: 0
    property real memTotal: 1
    property real diskFree: 0
    property real diskTotal: 0
    property real uptimeSec: 0
    property double cpuLastTotal: 0
    property double cpuLastIdle: 0

    function parseCpu(txt) {
        const line = String(txt).split("\n")[0].trim();
        const p = line.split(/\s+/);
        if (p.length < 5) return;
        let total = 0;
        for (let i = 1; i < p.length; i++) total += Number(p[i]) || 0;
        const idle = (Number(p[4]) || 0) + (Number(p[5]) || 0);
        if (root.cpuLastTotal > 0 && total > root.cpuLastTotal) {
            const dt = total - root.cpuLastTotal;
            const di = idle - root.cpuLastIdle;
            root.cpuPct = Math.max(0, Math.min(100, 100 * (1 - di / dt)));
        }
        root.cpuLastTotal = total;
        root.cpuLastIdle = idle;
    }
    function parseMem(txt) {
        const lines = String(txt).split("\n");
        let total = 0, avail = 0;
        for (let i = 0; i < lines.length; i++) {
            const parts = lines[i].split(":");
            if (parts.length < 2) continue;
            const v = Number(parts[1].trim().split(" ")[0]) || 0;
            if (parts[0] === "MemTotal") total = v;
            else if (parts[0] === "MemAvailable") avail = v;
        }
        if (total > 0) {
            root.memTotal = total * 1024;
            root.memUsed = Math.max(0, (total - avail) * 1024);
        }
    }
    function parseUptime(txt) {
        const v = Number(String(txt).trim().split(" ")[0]);
        if (v > 0) root.uptimeSec = v;
    }
    function parseDisk(txt) {
        const lines = String(txt).trim().split("\n");
        if (lines.length < 2) return;
        const f = lines[1].trim().split(/\s+/);
        if (f.length < 4) return;
        root.diskTotal = Number(f[1]) || 0;
        root.diskFree = Number(f[3]) || 0;
    }
    function fmtBytes(b) {
        const g = b / 1073741824;
        return (g >= 10 ? Math.round(g) : g.toFixed(1)) + " GB";
    }
    function fmtUptime(s) {
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        const m = Math.floor((s % 3600) / 60);
        return d > 0 ? d + "d " + h + "h" : (h > 0 ? h + "h " + m + "m" : m + "m");
    }

    FileView {
        id: cpuFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: root.parseCpu(cpuFile.text())
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: root.parseMem(memFile.text())
    }
    FileView {
        id: upFile
        path: "/proc/uptime"
        printErrors: false
        onLoaded: root.parseUptime(upFile.text())
    }
    Process {
        id: diskProc
        command: ["df", "-B1", "-P", "/"]
        stdout: StdioCollector { onStreamFinished: root.parseDisk(this.text) }
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.sysOn
        onTriggered: { cpuFile.reload(); memFile.reload(); upFile.reload(); }
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.sysOn
        onTriggered: { if (!diskProc.running) diskProc.running = true; }
    }
    onSysOnChanged: {
        if (!sysOn) return;
        cpuFile.reload(); memFile.reload(); upFile.reload();
        if (!diskProc.running) diskProc.running = true;
    }

    // ======================= scheduling =======================
    function refresh() {
        if (!active) return;
        nowSec = Date.now() / 1000;
        if (online && !about) fetchAbout();
        if (News.items.length === 0 || News.day !== News.today()) News.refresh();
    }
    Timer { id: kick; interval: 2000; onTriggered: root.refresh() }
    Timer { interval: 30000; repeat: true; running: root.active; onTriggered: root.refresh() }
    onActiveChanged: { if (active) { nowSec = Date.now() / 1000; kick.restart(); } }
    onOnlineChanged: { if (online) { aboutTried = ({}); kick.restart(); } }

    // ======================= building blocks =======================
    component Card: Item {
        id: card
        property string title: ""
        property string icon: ""               // SVG path, 24x24, drawn as a line icon
        default property alias content: body.data
        width: root.colW

        GlassSlot { anchors.fill: parent; radius: 16 }

        Item {
            x: 18; y: 16
            width: 20; height: 20
            Shape {
                width: 24; height: 24
                scale: 20 / 24
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 2
                    strokeColor: Theme.fg
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: card.icon }
                }
            }
        }
        Txt {
            x: 46; y: 15
            text: card.title
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }
        Item { id: body; anchors.fill: parent }
    }

    component MiniBar: Item {
        id: bar
        property real value: 0
        property color tone: Theme.glassBorder
        width: 14
        height: 60
        Rectangle {
            width: parent.width
            height: 3 + (parent.value / Math.max(1, root.maxDay)) * 46
            y: parent.height - height
            radius: 4
            color: bar.tone
        }
    }

    // ======================= layout (kept in sync with HomePage.wCol / wMid) =======================
    readonly property var cardX: [0, 1, 2, 0, 1, 2]
    readonly property var cardY: [0, 0, 0, small + gapY, small + gapY, small + gapY]
    readonly property var cardH: [small, small, small, tall, tall, tall]

    GlassRing {
        id: cardRing
        // Keep the ring on the last focused card while it fades out, instead of snapping
        // back to the first card as soon as focusIdx becomes -1.
        property int lastFi: 0
        readonly property int fi: Math.max(0, Math.min(root.cardX.length - 1, root.focusIdx >= 0 ? root.focusIdx : lastFi))
        onFiChanged: if (root.focusIdx >= 0) lastFi = fi
        readonly property real out: 3.5
        x: root.cardX[fi] * (root.colW + root.gutter) - out
        y: root.cardY[fi] - out
        width: root.colW + 2 * out
        height: root.cardH[fi] + 2 * out
        radius: 16 + out
        thickness: 2.5
        shade: true
        z: 4
        trigger: root.focusIdx
        opacity: root.focusIdx >= 0 ? 1 : 0
        visible: root.visible && opacity > 0.01
        Behavior on x { NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        Behavior on y { NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        Behavior on width { NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        Behavior on height { NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    }

    // ================================ row 1: screen time ================================
    Card {
        x: 0; y: root.cardY[0]
        height: root.small
        title: "Screen time"
        icon: "M12 3 a9 9 0 1 0 0.001 0 Z M12 7 V12 L15 14"

        Txt { x: 18; y: 45; text: root.today >= 60 ? ScreenTime.fmt(root.today) : "\u2014"; font.pixelSize: 34; font.weight: Font.Bold }
        Txt { x: 20; y: 86; text: root.today >= 60 ? "today" : "no usage yet"; font.pixelSize: 12; color: Theme.fgDim }
        Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 48; text: ScreenTime.fmt(root.week); font.pixelSize: 18; font.weight: Font.DemiBold }
        Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 72; text: "last 7 days"; font.pixelSize: 12; color: Theme.fgDim }
    }

    Card {
        x: 1 * (root.colW + root.gutter); y: root.cardY[1]
        height: root.small
        title: "Last 7 days"
        icon: "M4 20 V10 M9 20 V6 M14 20 V13 M19 20 V8"

        Txt { x: 18; y: 45; text: ScreenTime.fmt(root.week); font.pixelSize: 34; font.weight: Font.Bold }
        Txt { x: 20; y: 86; text: "this week"; font.pixelSize: 12; color: Theme.fgDim }
        Row {
            x: parent.width - 18 - 7 * 22
            y: 34
            spacing: 8
            Repeater {
                model: 7
                delegate: MiniBar {
                    required property int index
                    value: index < root.series.length ? root.series[index] : 0
                    tone: index === 6 ? Theme.accent : Theme.glassBorder
                }
            }
        }
    }

    Card {
        x: 2 * (root.colW + root.gutter); y: root.cardY[2]
        height: root.small
        title: "Share"
        icon: "M4 20 V10 H8 V20 Z M10 20 V4 H14 V20 Z M16 20 V13 H20 V20 Z"

        Txt { x: 18; y: 45; text: root.pct + "%"; font.pixelSize: 34; font.weight: Font.Bold }
        Txt { x: 20; y: 86; text: "of your most used"; font.pixelSize: 12; color: Theme.fgDim }
        Rectangle {
            x: parent.width - 18 - 96; y: 74
            width: 96; height: 6; radius: 3
            color: Qt.rgba(1, 1, 1, 0.12)
            Rectangle {
                height: parent.height; radius: 3
                color: Theme.accent
                width: parent.width * Math.min(100, root.pct) / 100
                Behavior on width { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            }
        }
    }

    // ================================ row 2: tall widgets ================================
    Card {
        x: 0; y: root.cardY[3]
        height: root.tall
        title: "About"
        icon: "M12 3 a9 9 0 1 0 0.001 0 Z M12 10 V17 M12 7 V7.01"

        Txt {
            x: 18; y: 48; width: parent.width - 36
            wrapMode: Text.WordWrap
            maximumLineCount: 7
            elide: Text.ElideRight
            lineHeight: 1.12
            text: root.about && root.about.text ? String(root.about.text)
                  : (root.entry ? (String(root.entry.comment || root.entry.genericName || "No description yet.")) : "")
            font.pixelSize: 14
            color: root.about && root.about.text ? Theme.fg : Theme.fgDim
        }
        Txt {
            anchors.left: parent.left; anchors.leftMargin: 18
            y: parent.height - 30
            text: root.about && root.about.source ? String(root.about.source) : (root.online ? "Loading description\u2026" : "Offline")
            font.pixelSize: 12; color: Theme.fgDim
        }
    }

    Card {
        x: 1 * (root.colW + root.gutter); y: root.cardY[4]
        height: root.tall
        title: "System"
        icon: "M4 5 H20 V15 H4 Z M8 19 H16 M12 15 V19"

        Txt { x: 18; y: 46; text: Math.round(root.cpuPct) + "%"; font.pixelSize: 40; font.weight: Font.Bold }
        Txt { x: 20; y: 98; text: "CPU"; font.pixelSize: 13; color: Theme.fgDim }
        Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 52; text: root.uptimeSec > 0 ? "Up " + root.fmtUptime(root.uptimeSec) : ""; font.pixelSize: 16; font.weight: Font.DemiBold }
        Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 76; text: "Uptime"; font.pixelSize: 13; color: Theme.fgDim }

        Txt { x: 18; y: 128; text: "Memory"; font.pixelSize: 13; color: Theme.fgDim }
        Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 126; text: root.fmtBytes(root.memUsed) + " of " + root.fmtBytes(root.memTotal); font.pixelSize: 13; font.weight: Font.DemiBold }
        Rectangle {
            x: 18; y: 148
            width: parent.width - 36; height: 5; radius: 2.5
            color: Qt.rgba(1, 1, 1, 0.12)
            Rectangle {
                height: parent.height; radius: 2.5
                width: parent.width * Math.min(1, root.memUsed / Math.max(1, root.memTotal))
                color: Theme.accent
            }
        }

        Txt { x: 18; y: 170; text: "Disk"; font.pixelSize: 13; color: Theme.fgDim }
        Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 168; text: root.diskTotal > 0 ? root.fmtBytes(root.diskFree) + " free" : ""; font.pixelSize: 13; font.weight: Font.DemiBold }
        Rectangle {
            x: 18; y: 192
            width: parent.width - 36; height: 5; radius: 2.5
            color: Qt.rgba(1, 1, 1, 0.12)
            Rectangle {
                height: parent.height; radius: 2.5
                width: parent.width * (root.diskTotal > 0 ? Math.min(1, (root.diskTotal - root.diskFree) / root.diskTotal) : 0)
                color: Theme.accent
            }
        }
    }

    Card {
        x: 2 * (root.colW + root.gutter); y: root.cardY[5]
        height: root.tall
        title: "Linux & PlayStation news"
        icon: "M4 5 H20 V19 H4 Z M7 9 H17 M7 12 H17 M7 15 H13"

        Txt {
            visible: News.items.length === 0
            x: 18; y: 54; width: parent.width - 36
            wrapMode: Text.WordWrap; maximumLineCount: 2
            text: root.online ? "No news this week" : "Waiting for network\u2026"
            font.pixelSize: 14; color: Theme.fgDim
        }
        Repeater {
            model: Math.min(3, News.items.length)
            delegate: Item {
                id: nrow
                required property int index
                readonly property var it: News.items[index]
                width: root.colW
                height: 56
                y: 46 + index * 58

                Txt {
                    x: 18; y: 0; width: parent.width - 36
                    text: nrow.it ? (String(nrow.it.source || "News") + "  \u00b7  " + News.ago(nrow.it.ts)) : ""
                    font.pixelSize: 11; color: Theme.fgDim
                }
                Txt {
                    x: 18; y: 17; width: parent.width - 36
                    text: nrow.it ? String(nrow.it.title) : ""
                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    font.pixelSize: 14; lineHeight: 1.05
                }
                Rectangle {
                    x: 18; y: 54; width: parent.width - 36; height: 1
                    color: Qt.rgba(1, 1, 1, 0.10)
                    visible: nrow.index < 2
                }
            }
        }
    }
}
