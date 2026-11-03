import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import "../core"

// viii-reflow applied (pill row + card focus ring).
// The PS5 "Games" card grid, shown while the Welcome tile is selected.
//
//   col 1: Screen time (tall)    col 2: Most used (small)   col 3: Batteries (small)
//          Network (small)              About (tall)               Weather (tall)
//   row 2: System (tall)         News (tall)                Clock (small) + Notifications (small)
//
// Row 2 peeks at the bottom edge at rest and is reached with Down; the mosaic scrolls so row 2
// fills the focused viewport (HomePage.focusY..768).
//
// Data rules (2 GB RAM): nothing runs while the grid is hidden; web data (weather, about) is cached on disk,
// read from the cache first, and only fetched 2 s after the grid appears (never during the intro).
Item {
    id: root
    property bool shown: true
    readonly property bool active: shown && visible
    property real lift: 0                  // viii-reflow: 0 = resting, 1 = the cards have focus (HomePage.c)
    property int focusIdx: -1              // focused card while the cards have focus
    property real viewH: 528               // visible height of the grid while it has focus (HomePage.focusY..768)
    property real scrollY: 0               // row 2 is reached by scrolling the mosaic up

    readonly property real colW: 358
    readonly property real gutter: 23
    readonly property real tall: 233
    readonly property real small: 108
    readonly property real rowGap: 17
    readonly property real rowH: tall + rowGap + small
    readonly property real rowGapY: 23
    readonly property real row2Y: rowH + rowGapY
    readonly property real contentH: row2Y + rowH
    width: 3 * colW + 2 * gutter
    height: contentH

    function topOf(i) { return cardY[i] - root.scrollY; }
    readonly property real row2Scroll: Math.max(0, contentH - viewH)

    readonly property string home: Quickshell.env("HOME")
    property real nowSec: Date.now() / 1000

    // ======================= network (same source as Settings) =======================
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
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property bool online: activeNet !== null || wiredDevice !== null
    readonly property bool searching: wifiOn && !online
    readonly property real signal: activeNet ? activeNet.signalStrength : 0
    readonly property string netMain: wiredDevice && !activeNet ? "Ethernet" : (activeNet ? activeNet.name : (wifiOn ? "Offline" : "Wi-Fi is off"))
    readonly property string netSub: {
        if (activeNet) return "Wi-Fi \u00b7 " + Math.round(signal * 100) + "% signal";
        if (wiredDevice) return wiredDevice.name;
        return wifiOn ? "Looking for a network\u2026" : "Turn it on in Settings";
    }

    // ======================= batteries (same source as the top bar) =======================
    function isCharging(d) {
        return d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged || d.state === UPowerDeviceState.PendingCharge;
    }
    readonly property var batts: {
        const out = [];
        const main = UPower.displayDevice;
        if (main && main.isPresent) out.push({ name: "Laptop", pct: main.percentage, charging: isCharging(main) });
        const list = UPower.devices ? UPower.devices.values : [];
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (!d || d === main || d.powerSupply || d.isLaptopBattery || !(d.percentage > 0)) continue;
            out.push({ name: d.model || "Device", pct: d.percentage, charging: isCharging(d) });
        }
        return out.slice(0, 3);
    }

    // ======================= system monitor (row 2 widget) =======================
    // /proc is read only while the widget row is on screen; the disk check runs once a minute.
    readonly property bool sysOn: root.active && root.lift > 0.6 && root.scrollY > 20
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
    readonly property var latestNotif: Notifs.history.length > 0 ? Notifs.history[0] : null
    function notifAgo(t) {
        const m = Math.max(0, Math.round((root.nowSec * 1000 - t) / 60000));
        return m < 60 ? m + "m ago" : (m < 2880 ? Math.round(m / 60) + "h ago" : Math.round(m / 1440) + "d ago");
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

    // ======================= screen time + most used =======================
    property var weekSecs: [0, 0, 0, 0, 0, 0, 0]        // oldest ... today
    property var topApp: null                           // { entry, secs } or null
    readonly property real weekTotal: weekSecs.reduce((a, b) => a + b, 0)
    readonly property real maxDay: Math.max.apply(null, weekSecs.concat([1800]))
    readonly property int topShare: topApp && weekTotal > 0 ? Math.round(100 * topApp.secs / weekTotal) : 0
    readonly property string topIcon: {
        if (!topApp) return "";
        const p = Apps.iconPath(topApp.entry);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }
    readonly property var topPal: {
        void Apps.palettes;
        return topApp ? Apps.paletteFor(topApp.entry) : Apps.fallback("none");
    }

    function dayTotal(off) {
        const rec = ScreenTime.days[ScreenTime.dayKey(off)];
        if (!rec) return 0;
        let s = 0;
        for (const k in rec) s += rec[k];
        return s;
    }
    function recalc() {
        const w = [];
        for (let i = 6; i >= 0; i--) w.push(dayTotal(i));
        weekSecs = w;
        let best = null, bs = 0;
        const list = Apps.visible();
        for (let i = 0; i < list.length; i++) {
            const s = ScreenTime.sum(list[i], 7);
            if (s > bs) { bs = s; best = list[i]; }
        }
        topApp = best && bs >= 60 ? { entry: best, secs: bs } : null;
    }
    Connections {
        target: ScreenTime
        function onRevisionChanged() { if (root.active) root.recalc(); }
    }
    onActiveChanged: {
        if (active) { nowSec = Date.now() / 1000; recalc(); kick.restart(); }
    }

    // ======================= weather (cache first, then viii-weather) =======================
    property var wx: null
    FileView {
        id: wxFile
        path: root.home + "/.cache/viii/weather.json"
        printErrors: false
        onLoaded: { try { root.wx = JSON.parse(wxFile.text()); } catch (e) { root.wx = null; } }
        onLoadFailed: root.wx = null
    }
    Process {
        id: wxProc
        command: ["nice", "-n", "19", root.home + "/.local/bin/viii-weather"]
        onExited: (code, status) => { if (code === 0) wxFile.reload(); }
    }
    function wxStale() { return !wx || (Date.now() / 1000 - wx.ts) > 900; }
    function fetchWeather() { if (online && !wxProc.running) wxProc.running = true; }

    function wmoText(c) {
        if (c === 0) return "Clear sky";
        if (c === 1) return "Mostly clear";
        if (c === 2) return "Partly cloudy";
        if (c === 3) return "Overcast";
        if (c === 45 || c === 48) return "Fog";
        if (c >= 51 && c <= 57) return "Drizzle";
        if (c >= 61 && c <= 67) return "Rain";
        if (c >= 71 && c <= 77) return "Snow";
        if (c >= 80 && c <= 82) return "Rain showers";
        if (c === 85 || c === 86) return "Snow showers";
        if (c >= 95) return "Thunderstorm";
        return "\u2014";
    }
    function wmoKind(c, day) {
        if (c <= 1) return day ? "sun" : "moon";
        if (c <= 3) return "cloud";
        if (c === 45 || c === 48) return "fog";
        if (c >= 95) return "storm";
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "snow";
        return "rain";
    }
    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    function ago(ts) {
        const m = Math.max(0, Math.round((nowSec - ts) / 60));
        return m < 60 ? m + "m" : (m < 2880 ? Math.round(m / 60) + "h" : Math.round(m / 1440) + "d");
    }

    // ======================= about (cache first, then viii-about) =======================
    readonly property string aboutKey: topApp ? Apps.safeKey(topApp.entry) : ""
    property var about: null
    property var aboutTried: ({})
    onAboutKeyChanged: about = null
    FileView {
        id: aboutFile
        path: root.aboutKey !== "" ? root.home + "/.cache/viii/about/" + root.aboutKey + ".json" : ""
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
        if (!active || !online || !topApp || aboutProc.running || aboutTried[aboutKey]) return;
        const e = topApp.entry;
        aboutTried[aboutKey] = true;
        aboutProc.command = ["nice", "-n", "19", home + "/.local/bin/viii-about", aboutKey, String(e.id || e.name), String(e.name), String(e.comment || "")];
        aboutProc.running = true;
    }

    // ======================= scheduling =======================
    function refreshAll() {
        if (!active) return;
        nowSec = Date.now() / 1000;
        if (!online) return;
        if (wxStale()) fetchWeather();
        if (!about) fetchAbout();
        // the News widget shows the same cache Explore uses; refresh only while Welcome is on screen
        if (News.items.length === 0 || News.day !== News.today()) News.refresh();
    }
    Timer { id: kick; interval: 2000; onTriggered: root.refreshAll() }
    Timer { interval: 30000; repeat: true; running: root.active; onTriggered: root.refreshAll() }
    onOnlineChanged: { if (online) { aboutTried = ({}); kick.restart(); } }

    // ======================= building blocks =======================
    component Card: Item {
        id: card
        property int idx: -1
        opacity: 1                                          // every card stays fully opaque; the ring marks focus
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

    // a progress ring with a number inside (PS5 controller battery)
    component Ring: Item {
        id: ring
        property real value: 0
        property color tone: Theme.fg
        property string label: ""
        width: 40; height: 40
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 4
                strokeColor: Qt.rgba(1, 1, 1, 0.14)
                fillColor: "transparent"
                PathAngleArc { centerX: 20; centerY: 20; radiusX: 17; radiusY: 17; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeWidth: 4
                strokeColor: ring.tone
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 20; centerY: 20; radiusX: 17; radiusY: 17; startAngle: -90; sweepAngle: Math.max(6, 360 * Math.min(1, ring.value)) }
            }
        }
        Txt { anchors.centerIn: parent; text: ring.label; font.pixelSize: 11; font.weight: Font.DemiBold }
    }

    // weather glyph
    component WxIcon: Item {
        id: wi
        property string kind: "cloud"
        property real size: 56
        width: size; height: size
        readonly property string cloud: "M7 18 A4 4 0 0 1 7 10 A5.5 5.5 0 0 1 17.6 9 A4.5 4.5 0 0 1 17 18 Z"
        readonly property string d: {
            switch (kind) {
            case "sun": return "M12 8 a4 4 0 1 0 0.001 0 Z M12 2 V4 M12 20 V22 M2 12 H4 M20 12 H22 M4.9 4.9 L6.3 6.3 M17.7 17.7 L19.1 19.1 M4.9 19.1 L6.3 17.7 M17.7 6.3 L19.1 4.9";
            case "moon": return "M20 14.5 A8 8 0 1 1 9.5 4 A6.5 6.5 0 0 0 20 14.5 Z";
            case "fog": return "M4 8 H20 M3 12 H21 M5 16 H19 M8 20 H16";
            case "rain": return cloud + " M8 21 L7 23 M12 21 L11 23 M16 21 L15 23";
            case "snow": return cloud + " M8 21 H8.01 M12 22 H12.01 M16 21 H16.01";
            case "storm": return cloud + " M12.5 13 L10 17.5 H14 L11.5 22";
            default: return cloud;
            }
        }
        Shape {
            width: 24; height: 24
            scale: wi.size / 24
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1.4
                strokeColor: Theme.fg
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: wi.d }
            }
        }
    }

    // skeleton placeholder: pulses only while `run`
    component Bone: Rectangle {
        id: bone
        property bool run: false
        radius: 7
        color: Qt.rgba(1, 1, 1, 0.10)
        SequentialAnimation on opacity {
            running: bone.run
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
        }
    }

    // ============================= viii-reflow: pill row + card focus ring =============================
    component Pill: Rectangle {
        id: pill
        property string label: ""
        height: 26
        width: pt.implicitWidth + 40
        radius: 13
        color: Qt.rgba(0.10, 0.11, 0.14, 0.78)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        Rectangle { x: 10; y: 8; width: 10; height: 10; radius: 5; color: Theme.accent }
        Txt { id: pt; x: 28; anchors.verticalCenter: parent.verticalCenter; text: pill.label; font.pixelSize: 12 }
    }
    Row {
        x: 0; y: -36
        spacing: 10
        Pill { label: Qt.formatDate(new Date(root.nowSec * 1000), "dddd, d MMMM") }
        Pill { label: root.online ? "Online \u00b7 " + root.netMain : "Offline" }
    }

    // row 1: the six original cards; row 2: four widgets (System, News, Clock, Notifications)
    readonly property var cardX: [0, 0, 1, 1, 2, 2, 0, 1, 2, 2]
    readonly property var cardY: [0, tall + rowGap, 0, small + rowGap, 0, small + rowGap, row2Y, row2Y, row2Y, row2Y + small + rowGap]
    readonly property var cardH: [tall, small, small, tall, small, tall, tall, tall, small, small]
    Behavior on scrollY { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    onFocusIdxChanged: { if (focusIdx >= 0) scrollY = focusIdx < 6 ? 0 : row2Scroll; }
    onLiftChanged: { if (lift < 0.05) scrollY = 0; }

    // One clipped viewport keeps the scrolled-up rows from sliding over the tile row above.
    Item {
        id: viewport
        width: root.width
        height: root.viewH
        clip: true

    GlassRing {
        id: cardRing
        // Keep the ring on the last focused card while it fades out, instead of snapping
        // back to the first card as soon as focusIdx becomes -1.
        property int lastFi: 0
        readonly property int fi: Math.max(0, Math.min(root.cardX.length - 1, root.focusIdx >= 0 ? root.focusIdx : lastFi))
        onFiChanged: if (root.focusIdx >= 0) lastFi = fi
        readonly property real out: 3.5
        x: root.cardX[fi] * (root.colW + root.gutter) - out
        y: root.topOf(fi) - out
        width: root.colW + 2 * out
        height: root.cardH[fi] + 2 * out
        radius: 16 + out
        thickness: 2.5
        shade: true
        trigger: root.focusIdx
        z: 10
        opacity: Math.max(0, Math.min(1, (root.lift - 0.35) / 0.65))
        visible: opacity > 0.01 && root.active
        // During a row switch the ring follows scrollY directly (which is already animated).
        // A second y animation on top of it made the ring lag behind and drift out of place.
        // Within a row, scrollY is settled, so the ring glides between stacked cards.
        readonly property bool scrollSettled: (root.focusIdx < 6 && Math.abs(root.scrollY) < 0.01)
            || (root.focusIdx >= 6 && Math.abs(root.scrollY - root.row2Scroll) < 0.01)
        Behavior on x { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        Behavior on y { enabled: root.lift > 0.6 && scrollSettled; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        Behavior on width { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        Behavior on height { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    }

    // ============================= column 1 =============================
    Card {
        x: 0; y: root.topOf(0)
        height: root.tall
        title: "Screen time"
        idx: 0
        icon: "M12 3 a9 9 0 1 0 0.001 0 Z M12 7 V12 L15 14"

        Txt { x: 18; y: 46; text: ScreenTime.fmt(root.weekSecs[6]); font.pixelSize: 40; font.weight: Font.Bold }
        Txt { x: 20; y: 98; text: root.weekSecs[6] >= 60 ? "today" : "no usage yet"; font.pixelSize: 13; color: Theme.fgDim }
        Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 54; text: ScreenTime.fmt(root.weekTotal); font.pixelSize: 20; font.weight: Font.DemiBold }
        Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 82; text: "last 7 days"; font.pixelSize: 13; color: Theme.fgDim }

        Item {
            id: bars
            x: 18; y: 124
            width: parent.width - 36
            height: 100
            Repeater {
                model: 7
                delegate: Item {
                    id: bar
                    required property int index
                    readonly property real v: root.weekSecs[index]
                    x: index * ((bars.width - 30) / 6)
                    width: 30
                    height: 100
                    Rectangle {
                        width: 30
                        height: 5 + (bar.v / root.maxDay) * 64
                        y: 74 - height
                        radius: 7
                        color: bar.index === 6 ? Theme.accent : Theme.glassBorder
                    }
                    Txt {
                        x: (30 - width) / 2
                        y: 82
                        text: Qt.formatDate(new Date(Date.now() - (6 - bar.index) * 86400000), "ddd").charAt(0)
                        font.pixelSize: 12
                        color: bar.index === 6 ? Theme.fg : Theme.fgDim
                    }
                }
            }
        }
    }

    Card {
        x: 0; y: root.topOf(1)
        height: root.small
        title: "Network"
        idx: 1
        icon: "M2 9 A15 15 0 0 1 22 9 M5.5 12.5 A10 10 0 0 1 18.5 12.5 M9 16 A5 5 0 0 1 15 16 M12 19.5 H12.01"

        // loading ring while there is no connection
        Item {
            x: 18; y: 54
            width: 30; height: 30
            visible: root.searching
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 3
                    strokeColor: Qt.rgba(1, 1, 1, 0.14)
                    fillColor: "transparent"
                    PathAngleArc { centerX: 15; centerY: 15; radiusX: 12; radiusY: 12; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: 3
                    strokeColor: Theme.fg
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 15; centerY: 15; radiusX: 12; radiusY: 12; startAngle: -90; sweepAngle: 100 }
                }
            }
            RotationAnimator on rotation {
                from: 0; to: 360
                duration: 1100
                loops: Animation.Infinite
                running: root.active && root.searching
            }
        }
        Txt { x: root.searching ? 62 : 18; y: 50; width: parent.width - (root.searching ? 80 : 110); text: root.netMain; font.pixelSize: 18; font.weight: Font.DemiBold }
        Txt { x: root.searching ? 62 : 18; y: 76; width: parent.width - (root.searching ? 80 : 110); text: root.netSub; font.pixelSize: 13; color: Theme.fgDim }

        // signal bars
        Row {
            visible: root.activeNet !== null
            anchors.right: parent.right; anchors.rightMargin: 20
            y: 52
            height: 30
            spacing: 4
            Repeater {
                model: 4
                delegate: Rectangle {
                    required property int index
                    width: 6
                    height: 8 + index * 7
                    y: 30 - height
                    radius: 2
                    color: root.signal >= (index + 0.5) / 4.4 ? Theme.fg : Qt.rgba(1, 1, 1, 0.18)
                }
            }
        }
    }

    // ============================= column 2 =============================
    Card {
        x: root.colW + root.gutter; y: root.topOf(2)
        height: root.small
        title: "Most used"
        idx: 2
        icon: "M12 2.5 L14.9 8.6 L21.5 9.4 L16.6 13.9 L17.9 20.5 L12 17.2 L6.1 20.5 L7.4 13.9 L2.5 9.4 L9.1 8.6 Z"

        Txt { visible: !root.topApp; x: 18; y: 56; text: "Nothing recorded yet"; font.pixelSize: 14; color: Theme.fgDim }
        Item {
            visible: !!root.topApp
            anchors.fill: parent
            Image {
                x: 18; y: 48
                width: 44; height: 44
                source: root.topIcon
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }
            Txt { x: 74; y: 46; width: parent.width - 92; text: root.topApp ? root.topApp.entry.name : ""; font.pixelSize: 17; font.weight: Font.DemiBold }
            Txt { x: 74; y: 70; width: parent.width - 92; text: root.topApp ? ScreenTime.fmt(root.topApp.secs) + " this week \u00b7 " + root.topShare + "%" : ""; font.pixelSize: 13; color: Theme.fgDim }
            Rectangle {
                x: 74; y: 94
                width: parent.width - 92; height: 5; radius: 2.5
                color: Qt.rgba(1, 1, 1, 0.12)
                Rectangle {
                    height: parent.height; radius: 2.5
                    width: parent.width * Math.min(100, root.topShare) / 100
                    color: root.topPal.primary
                }
            }
        }
    }

    Card {
        x: root.colW + root.gutter; y: root.topOf(3)
        height: root.tall
        title: "About"
        idx: 3
        icon: "M12 3 a9 9 0 1 0 0.001 0 Z M12 11 V16.5 M12 7.8 H12.01"

        Txt { visible: !root.topApp; x: 18; y: 54; width: parent.width - 36; wrapMode: Text.WordWrap; maximumLineCount: 3; text: "Use an app for a while and a little about your favourite shows up here."; font.pixelSize: 14; color: Theme.fgDim }

        Item {
            visible: !!root.topApp
            anchors.fill: parent
            Txt { x: 18; y: 46; width: parent.width - 36; text: root.topApp ? root.topApp.entry.name : ""; font.pixelSize: 20; font.weight: Font.DemiBold }
            Txt {
                visible: !!root.about && root.about.text !== ""
                x: 18; y: 82; width: parent.width - 36
                wrapMode: Text.WordWrap; maximumLineCount: 6
                text: root.about ? root.about.text : ""
                font.pixelSize: 14; color: Theme.fgDim
                lineHeight: 1.12
            }
            Txt {
                visible: !!root.about && root.about.text !== ""
                x: 18; y: 205
                width: parent.width - 36
                text: root.about ? root.about.source + (root.about.pkg ? " \u00b7 " + root.about.pkg + " " + root.about.version : "") : ""
                font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.40)
            }
            // not loaded yet / offline: the desktop-entry comment if there is one, otherwise a skeleton
            Txt {
                visible: !root.about && !!root.topApp && !!root.topApp.entry.comment
                x: 18; y: 82; width: parent.width - 36
                wrapMode: Text.WordWrap; maximumLineCount: 3
                text: root.topApp && root.topApp.entry.comment ? root.topApp.entry.comment : ""
                font.pixelSize: 14; color: Theme.fgDim
            }
            Item {
                visible: !root.about
                x: 18; y: 150
                width: parent.width - 36; height: 70
                Bone { y: 0; width: parent.width; height: 12; run: root.active && !root.about }
                Bone { y: 22; width: parent.width * 0.85; height: 12; run: root.active && !root.about }
                Bone { y: 44; width: parent.width * 0.6; height: 12; run: root.active && !root.about }
            }
            Txt {
                visible: !root.about
                x: 18; y: 205
                text: root.online ? "Fetching details\u2026" : "Waiting for network\u2026"
                font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.40)
            }
        }
    }

    // ============================= column 3 =============================
    Card {
        x: 2 * (root.colW + root.gutter); y: root.topOf(4)
        height: root.small
        title: "Batteries"
        idx: 4
        icon: "M3 8 H18 A1 1 0 0 1 19 9 V15 A1 1 0 0 1 18 16 H3 A1 1 0 0 1 2 15 V9 A1 1 0 0 1 3 8 Z M21.5 11 V13"

        Txt { visible: root.batts.length === 0; x: 18; y: 56; text: "No battery detected"; font.pixelSize: 14; color: Theme.fgDim }
        Item {
            x: 18; y: 50
            width: parent.width - 36; height: 44
            Repeater {
                model: root.batts
                delegate: Item {
                    id: bat
                    required property var modelData
                    required property int index
                    x: index * 112
                    width: 108; height: 44
                    Ring {
                        value: bat.modelData.pct
                        label: String(Math.round(bat.modelData.pct * 100))
                        tone: bat.modelData.charging ? "#6bdc8b" : (bat.modelData.pct < 0.15 ? "#ff6b6b" : Theme.fg)
                    }
                    Txt { x: 50; y: 4; width: 56; text: bat.modelData.name; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Txt { x: 50; y: 23; width: 56; text: bat.modelData.charging ? "Charging" : "Battery"; font.pixelSize: 11; color: bat.modelData.charging ? "#6bdc8b" : Theme.fgDim }
                }
            }
        }
    }

    Card {
        x: 2 * (root.colW + root.gutter); y: root.topOf(5)
        height: root.tall
        title: "Weather"
        idx: 5
        icon: "M12 8 a4 4 0 1 0 0.001 0 Z M12 2 V4 M12 20 V22 M2 12 H4 M20 12 H22 M4.9 4.9 L6.3 6.3 M17.7 17.7 L19.1 19.1 M4.9 19.1 L6.3 17.7 M17.7 6.3 L19.1 4.9"

        Txt {
            anchors.right: parent.right; anchors.rightMargin: 18
            y: 17
            width: 170
            horizontalAlignment: Text.AlignRight
            text: root.wx ? (root.online ? root.wx.place : "Offline \u00b7 " + root.ago(root.wx.ts) + " ago") : ""
            font.pixelSize: 13; color: Theme.fgDim
        }

        Item {
            visible: !!root.wx
            anchors.fill: parent
            WxIcon { x: 18; y: 52; size: 56; kind: root.wx ? root.wmoKind(root.wx.code, root.wx.day) : "cloud" }
            Txt { x: 90; y: 42; text: root.wx ? root.wx.temp + "\u00b0" : ""; font.pixelSize: 50; font.weight: Font.Bold }
            Txt { x: 92; y: 102; text: root.wx ? root.wmoText(root.wx.code) : ""; font.pixelSize: 15 }
            Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 58; text: root.wx ? "H " + root.wx.hi + "\u00b0" : ""; font.pixelSize: 14; font.weight: Font.DemiBold }
            Txt { anchors.right: parent.right; anchors.rightMargin: 18; y: 80; text: root.wx ? "L " + root.wx.lo + "\u00b0" : ""; font.pixelSize: 14; color: Theme.fgDim }
            Txt { x: 18; y: 128; text: root.wx ? "Feels " + root.wx.feels + "\u00b0  \u00b7  Wind " + root.wx.wind + " km/h" : ""; font.pixelSize: 13; color: Theme.fgDim }
            Rectangle { x: 18; y: 156; width: parent.width - 36; height: 1; color: Qt.rgba(1, 1, 1, 0.10) }
            Row {
                x: 18; y: 168
                Repeater {
                    model: root.wx ? root.wx.hours : []
                    delegate: Item {
                        id: hr
                        required property var modelData
                        width: (root.colW - 36) / 5
                        height: 50
                        Txt { y: 0; text: root.pad2(hr.modelData.h) + ":00"; font.pixelSize: 12; color: Theme.fgDim }
                        Txt { y: 19; text: hr.modelData.t + "\u00b0"; font.pixelSize: 17; font.weight: Font.DemiBold }
                    }
                }
            }
        }

        // nothing cached yet: skeleton until the first fetch lands
        Item {
            visible: !root.wx
            anchors.fill: parent
            Bone { x: 18; y: 54; width: 56; height: 56; radius: 28; run: root.active && !root.wx }
            Bone { x: 90; y: 56; width: 110; height: 34; run: root.active && !root.wx }
            Bone { x: 92; y: 102; width: 90; height: 14; run: root.active && !root.wx }
            Bone { x: 18; y: 132; width: 200; height: 12; run: root.active && !root.wx }
            Repeater {
                model: 5
                delegate: Bone {
                    required property int index
                    x: 18 + index * ((root.colW - 36) / 5); y: 170
                    width: 44; height: 36
                    run: root.active && !root.wx
                }
            }
            Txt {
                x: 18; y: 210
                text: root.online ? "Loading weather\u2026" : "Waiting for network\u2026"
                font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.40)
            }
        }
    }

    // ============================= row 2: extra widgets =============================
    Card {
        x: 0; y: root.topOf(6)
        height: root.tall
        title: "System"
        idx: 6
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
        x: root.colW + root.gutter; y: root.topOf(7)
        height: root.tall
        title: "News"
        idx: 7
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

    Card {
        x: 2 * (root.colW + root.gutter); y: root.topOf(8)
        height: root.small
        title: "Clock"
        idx: 8
        icon: "M12 3 a9 9 0 1 0 0.001 0 Z M12 7 V12 L15 14"

        Txt { x: 18; y: 44; text: Qt.formatTime(new Date(root.nowSec * 1000), "HH:mm"); font.pixelSize: 36; font.weight: Font.Bold }
        Txt { x: 20; y: 88; width: parent.width - 36; text: Qt.formatDate(new Date(root.nowSec * 1000), "dddd, d MMMM"); font.pixelSize: 13; color: Theme.fgDim }
    }

    Card {
        x: 2 * (root.colW + root.gutter); y: root.topOf(9)
        height: root.small
        title: "Notifications"
        idx: 9
        icon: "M6 9 A6 6 0 0 1 18 9 V14 L20 17 H4 L6 14 Z M10 20 A2 2 0 0 0 14 20"

        Txt {
            anchors.right: parent.right; anchors.rightMargin: 18; y: 18
            text: Notifs.history.length > 0 ? String(Notifs.history.length) : ""
            font.pixelSize: 14; font.weight: Font.DemiBold; color: Theme.accent
        }
        Txt {
            visible: !root.latestNotif
            x: 18; y: 50
            text: "All caught up"
            font.pixelSize: 14; color: Theme.fgDim
        }
        Txt {
            visible: !!root.latestNotif
            x: 18; y: 44; width: parent.width - 80
            text: root.latestNotif ? String(root.latestNotif.title || root.latestNotif.body || "Notification") : ""
            elide: Text.ElideRight
            font.pixelSize: 14; font.weight: Font.DemiBold
        }
        Txt {
            visible: !!root.latestNotif
            x: 18; y: 68; width: parent.width - 36
            text: root.latestNotif ? (String(root.latestNotif.app || "System") + "  \u00b7  " + root.notifAgo(root.latestNotif.t)) : ""
            elide: Text.ElideRight
            font.pixelSize: 12; color: Theme.fgDim
        }
    }
    }
}
