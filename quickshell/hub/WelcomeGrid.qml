import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import "../core"

// viii-ps5hub (keeps the viii-padfix behaviour: no clip, cards fade by position, bottomPad under the last row).
// The PS5 "Welcome hub": ONE page, shown while the Welcome tile is selected. Explore is merged into it.
//
//   widget band   col 1: Screen time (tall) + Batteries (small)
//   (358 high)    col 2: Most used (tall)   + Notifications (small)
//                 col 3: Weather (tall)     + System (small)
//   feed 1        "PlayStation news": three 16:9 story cards
//   feed 2        "Linux news":       three 16:9 story cards
//
// Focus rows: 0..5 are the widgets (scroll 0), 6..11 are the stories (scroll = row2Scroll, both feeds visible).
//
// Performance rules (2 GB RAM): nothing here exists while the tile is not selected. The widgets live in an
// asynchronous Loader and the story cards in a Repeater, both gated on `active`; images are only loaded for cards
// that are on screen; /proc is only sampled while the System card is on screen; web data comes from backends that
// keep a cache on disk (viii-weather, viii-news) and is fetched 2 s after the page appears, never during the intro.
Item {
    id: root
    property bool shown: true
    readonly property bool active: shown && visible
    property real lift: 0                  // 0 = resting, 1 = the cards have focus (HomePage.c)
    property int focusIdx: -1              // focused card while the cards have focus
    property real viewH: 528               // visible height of the grid while it has focus (HomePage.focusY..768)
    property real scrollY: 0               // the stories are reached by scrolling the page up
    readonly property real bottomY: 770    // design-space bottom of the screen: cards below it are not rendered

    readonly property real colW: 358
    readonly property real gutter: 23
    readonly property real tall: 233
    readonly property real small: 108
    readonly property real rowGap: 17
    readonly property real bandH: tall + rowGap + small            // 358: the widget band
    readonly property real feedH: 201                              // 358 x 201 = 16:9 story cards
    readonly property real head1Y: bandH + 14                      // heading of feed 1
    readonly property real feed1Y: bandH + 48
    readonly property real head2Y: feed1Y + feedH + 14             // heading of feed 2
    readonly property real feed2Y: feed1Y + feedH + 48
    readonly property real contentH: feed2Y + feedH                // 856
    readonly property real bottomPad: 40                           // space under the last feed while the cards have focus
    readonly property int widgetCount: 6                           // cards 0..5 are widgets, 6..11 are stories
    width: 3 * colW + 2 * gutter
    height: contentH

    function topOf(i) { return cardY[i] - root.scrollY; }
    // The Settings fade. A card whose top edge is at or below fadeFull (HomePage px) is fully visible and it is
    // gone fadeLen higher up. Opacity only: no clip, no mask, no offscreen buffer.
    readonly property real fadeFull: 100
    readonly property real fadeLen: 80
    function fadeAt(top) { return Math.max(0, Math.min(1, (root.y + top - (fadeFull - fadeLen)) / fadeLen)); }
    // a card is only drawn while it is on screen: not faded out at the top, not below the bottom edge
    function onScreen(top) { return fadeAt(top) > 0.01 && root.y + top < bottomY; }
    readonly property real row2Scroll: Math.max(0, contentH + bottomPad - viewH)

    readonly property string home: Quickshell.env("HOME")
    property real nowSec: Date.now() / 1000

    // ======================= network (feeds the pill and the weather/news fetches) =======================
    // Nothing is read while the page is not on screen, so network changes cost nothing then.
    readonly property var wifiDevice: {
        if (!root.active) return null;
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wifi) return devices[i];
        return null;
    }
    readonly property var wiredDevice: {
        if (!root.active) return null;
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
    readonly property string netMain: wiredDevice && !activeNet ? "Ethernet" : (activeNet ? activeNet.name : (wifiOn ? "Offline" : "Wi-Fi is off"))

    // ======================= batteries (same source as the top bar) =======================
    function isCharging(d) {
        return d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged || d.state === UPowerDeviceState.PendingCharge;
    }
    // PS5-style gauges identify a device by its picture, so pick the icon from the
    // UPower model name. Laptop and DualSense are the two real devices here; anything
    // else gets the generic gadget glyph until it needs its own drawing.
    function batteryKind(name) {
        const n = String(name || "").toLowerCase();
        if (n.indexOf("laptop") >= 0 || n.indexOf("notebook") >= 0) return "laptop";
        if (n.indexOf("dualsense") >= 0 || n.indexOf("controller") >= 0
                || n.indexOf("gamepad") >= 0) return "dualsense";
        return "device";
    }
    readonly property var batts: {
        if (!root.active) return [];
        const out = [];
        const main = UPower.displayDevice;
        if (main && main.isPresent) out.push({ name: "Laptop", kind: "laptop", pct: main.percentage, charging: isCharging(main) });
        const list = UPower.devices ? UPower.devices.values : [];
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (!d || d === main || d.powerSupply || d.isLaptopBattery || !(d.percentage > 0)) continue;
            const name = d.model || "Device";
            out.push({ name: name, kind: batteryKind(name), pct: d.percentage, charging: isCharging(d) });
        }
        return out.slice(0, 3);
    }

    // ======================= system monitor (the System widget) =======================
    // /proc is read only while the widget band is on screen; the disk check runs once a minute.
    readonly property bool sysOn: root.active && root.scrollY < 120
    property real cpuPct: 0
    property real memUsed: 0
    property real memTotal: 1
    property real diskFree: 0
    property real diskTotal: 0
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
    Process {
        id: diskProc
        command: ["df", "-B1", "-P", "/"]
        stdout: StdioCollector { onStreamFinished: root.parseDisk(this.text) }
    }
    Timer {
        interval: 3000
        repeat: true
        running: root.sysOn
        onTriggered: { cpuFile.reload(); memFile.reload(); }
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.sysOn
        onTriggered: { if (!diskProc.running) diskProc.running = true; }
    }
    onSysOnChanged: {
        if (!sysOn) return;
        cpuFile.reload(); memFile.reload();
        if (!diskProc.running) diskProc.running = true;
    }

    // ======================= screen time + most used =======================
    property var weekSecs: [0, 0, 0, 0, 0, 0, 0]        // oldest ... today
    property var topApps: []                            // up to three { entry, secs }, most used first
    readonly property real weekTotal: weekSecs.reduce((a, b) => a + b, 0)
    readonly property real maxDay: Math.max.apply(null, weekSecs.concat([1800]))

    function iconOf(entry) {
        const p = Apps.iconPath(entry);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
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
        const list = Apps.visible();
        const scored = [];
        for (let i = 0; i < list.length; i++) {
            const s = ScreenTime.sum(list[i], 7);
            if (s >= 60) scored.push({ entry: list[i], secs: s });
        }
        scored.sort((a, b) => b.secs - a.secs);
        topApps = scored.slice(0, 3);
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

    // ======================= news feeds (the daily cache written by viii-news) =======================
    // The backend picks three stories per group; each group is one feed, like the PS5's separate news feeds.
    readonly property var feedA: root.active ? News.items.filter(it => it.group === "PlayStation").slice(0, 3) : []
    readonly property var feedB: root.active ? News.items.filter(it => it.group === "Linux").slice(0, 3) : []
    function story(i) {                        // the story shown by focus index i (6..11), or null
        if (i >= 6 && i <= 8) return i - 6 < feedA.length ? feedA[i - 6] : null;
        if (i >= 9 && i <= 11) return i - 9 < feedB.length ? feedB[i - 9] : null;
        return null;
    }
    function valid(i) { return i >= 0 && i < 12 && (i < widgetCount || story(i) !== null); }
    readonly property string emptyTitle: News.busy ? "Getting today\u2019s news" : "No news yet"
    readonly property string emptyText: News.busy ? "Linux and PlayStation stories are on their way."
        : (News.failed ? "Could not reach the news feeds. It will try again in a few minutes." : "Stories appear here once you are online.")

    // ======================= scheduling =======================
    function refreshAll() {
        if (!active) return;
        nowSec = Date.now() / 1000;
        if (!online) return;
        if (wxStale()) fetchWeather();
        if (News.items.length === 0 || News.day !== News.today()) News.refresh();
    }
    Timer { id: kick; interval: 2000; onTriggered: root.refreshAll() }
    Timer { interval: 60000; repeat: true; running: root.active; onTriggered: root.refreshAll() }
    onOnlineChanged: { if (online) kick.restart(); }

    // ======================= building blocks =======================
    component Card: Item {
        id: card
        property int idx: -1
        opacity: root.fadeAt(card.y)
        visible: root.onScreen(card.y)
        readonly property bool live: visible && root.active    // children load images / run animations only while true
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

    // PS5 battery gauge: a thin progress ring with the device glyph in the middle
    // and a small segmented battery below it. Charging rings are mint green, a low
    // charge is amber, everything else stays white.
    component BatGauge: Item {
        id: gauge
        property real value: 0
        property bool charging: false
        property string kind: "device"
        width: 54; height: 54
        readonly property color tone: gauge.charging ? "#4ee38a"
            : (gauge.value < 0.2 ? "#f0a63a" : Theme.fg)
        readonly property int bars: Math.max(0, Math.min(3, Math.ceil(gauge.value * 3)))

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 3.5
                strokeColor: Qt.rgba(1, 1, 1, 0.13)
                fillColor: "transparent"
                PathAngleArc { centerX: 27; centerY: 27; radiusX: 24.5; radiusY: 24.5; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeWidth: 3.5
                strokeColor: gauge.tone
                fillColor: "transparent"
                PathAngleArc {
                    centerX: 27; centerY: 27; radiusX: 24.5; radiusY: 24.5
                    startAngle: -90
                    sweepAngle: Math.max(2, 360 * Math.min(1, Math.max(0, gauge.value)))
                }
            }
        }

        Image {
            x: 15; y: 10
            width: 24; height: 24
            source: "icons/" + gauge.kind + ".svg"
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
        }

        // the little battery pictogram from the PS5 gauge
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 37
            width: 15; height: 8
            Rectangle {
                x: 0; y: 0
                width: 13; height: 8
                radius: 2
                color: "transparent"
                border.width: 1
                border.color: Theme.fg
            }
            Rectangle {
                x: 13.5; y: 2.1
                width: 1.5; height: 3.8
                radius: 0.75
                color: Theme.fg
            }
            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    x: 2.0 + index * 3.1; y: 2.0
                    width: 2.2; height: 4.0
                    radius: 0.6
                    color: index < gauge.bars ? Theme.fg : "transparent"
                }
            }
        }
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

    // ============================= pill row + focus ring =============================
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
        x: 0; y: -36 - root.scrollY
        spacing: 10
        opacity: Math.max(0, 1 - root.scrollY / 60)        // leaves with the widget band instead of hanging in mid air
        visible: opacity > 0.01 && root.active
        Pill { label: Qt.formatDateTime(new Date(root.nowSec * 1000), "dddd, d MMMM  \u00b7  HH:mm") }
        Pill { label: root.online ? "Online \u00b7 " + root.netMain : "Offline" }
    }

    // cards 0..5 = widgets, 6..8 = feed 1, 9..11 = feed 2
    readonly property var cardX: [0, 0, 1, 1, 2, 2, 0, 1, 2, 0, 1, 2]
    readonly property var cardY: [0, tall + rowGap, 0, tall + rowGap, 0, tall + rowGap, feed1Y, feed1Y, feed1Y, feed2Y, feed2Y, feed2Y]
    readonly property var cardH: [tall, small, tall, small, tall, small, feedH, feedH, feedH, feedH, feedH, feedH]
    Behavior on scrollY { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    onFocusIdxChanged: { if (focusIdx >= 0) scrollY = focusIdx < widgetCount ? 0 : row2Scroll; }
    onLiftChanged: { if (lift < 0.05) scrollY = 0; }

    // Not clipped: a clip would cut the scrolled-up rows along a hard line and cut the ring off at the sides and bottom.
    Item {
        id: viewport
        width: root.width
        height: root.viewH

        GlassRing {
            id: cardRing
            // Keep the ring on the last focused card while it fades out, instead of snapping back to the first card.
            property int lastFi: 0
            readonly property int fi: Math.max(0, Math.min(root.cardX.length - 1, root.focusIdx >= 0 ? root.focusIdx : lastFi))
            onFiChanged: if (root.focusIdx >= 0) lastFi = fi
            readonly property real out: 3.5
            x: root.cardX[fi] * (root.colW + root.gutter) - out
            y: root.topOf(fi) - out
            width: root.colW + 2 * out
            height: root.cardH[fi] + 2 * out
            radius: (fi < root.widgetCount ? 16 : 5) + out
            thickness: 2.5
            shade: true
            trigger: root.focusIdx
            z: 10
            opacity: Math.max(0, Math.min(1, (root.lift - 0.35) / 0.65)) * root.fadeAt(root.topOf(fi))
            visible: opacity > 0.01 && root.active
            // During a row switch the ring follows scrollY directly (already animated); a second y animation on top
            // of it would make the ring lag. Within a band scrollY is settled, so the ring glides between cards.
            readonly property bool scrollSettled: (root.focusIdx < root.widgetCount && Math.abs(root.scrollY) < 0.01)
                || (root.focusIdx >= root.widgetCount && Math.abs(root.scrollY - root.row2Scroll) < 0.01)
            Behavior on x { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on y { enabled: root.lift > 0.6 && cardRing.scrollSettled; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on width { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on height { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        }

        // ============================= feed headings =============================
        Txt {
            x: 2; y: root.head1Y - root.scrollY
            text: "PlayStation news"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            opacity: root.fadeAt(y)
            visible: root.feedA.length > 0 && root.onScreen(y)
        }
        Txt {
            x: 2; y: root.head2Y - root.scrollY
            text: "Linux news"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            opacity: root.fadeAt(y)
            visible: root.feedB.length > 0 && root.onScreen(y)
        }

        // nothing to show yet (offline, or the first fetch is still running)
        Item {
            x: 0; y: root.feed1Y - root.scrollY
            width: 2 * root.colW + root.gutter
            height: root.feedH
            opacity: root.fadeAt(y)
            visible: root.active && News.items.length === 0 && root.onScreen(y)
            GlassSlot { anchors.fill: parent; radius: 16 }
            Column {
                anchors.centerIn: parent
                width: parent.width - 60
                spacing: 8
                Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.emptyTitle; font.pixelSize: 22; font.weight: Font.DemiBold }
                Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.emptyText; font.pixelSize: 14; color: Theme.fgDim; wrapMode: Text.WordWrap; maximumLineCount: 3 }
            }
        }

        // ============================= the widget band =============================
        // One asynchronous Loader: every widget (and everything inside it) is destroyed while the page is not shown.
        Loader {
            active: root.active
            asynchronous: true
            sourceComponent: widgetBand
        }

        // ============================= the two news feeds =============================
        Repeater {
            model: root.active ? 6 : 0
            delegate: Item {
                id: sc
                required property int index
                readonly property int gi: 6 + index
                readonly property var it: root.story(gi)
                readonly property bool sel: gi === root.focusIdx
                property real kk: sel ? 1 : 0
                Behavior on kk {
                    NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                }
                x: root.cardX[gi] * (root.colW + root.gutter)
                y: root.topOf(gi)
                width: root.colW
                height: root.feedH
                opacity: root.fadeAt(y)
                visible: it !== null && root.onScreen(y)
                readonly property bool live: visible && root.active

                Rectangle { anchors.fill: parent; color: Qt.rgba(0.07, 0.078, 0.098, 1) }
                Image {
                    anchors.fill: parent
                    source: (sc.live && sc.it) ? News.src(sc.it.img) : ""
                    sourceSize.width: 412
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 120
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.84) }
                    }
                }
                // cards that do not have focus dim a little while the cards are in use
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.30 * root.lift * (1 - sc.kk)) }
                Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12) }

                // action label on the focused card
                Rectangle {
                    anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 8 }
                    width: act.width + 14
                    height: 20
                    radius: 10
                    opacity: sc.kk * root.lift
                    visible: opacity > 0.01
                    color: Qt.rgba(1, 1, 1, 0.92)
                    Txt { id: act; anchors.centerIn: parent; text: "Enter \u00b7 Read"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#14161a" }
                }

                Column {
                    x: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    width: parent.width - 24
                    spacing: 3
                    Txt {
                        width: parent.width
                        text: sc.it ? String(sc.it.source) + "  \u00b7  " + News.ago(sc.it.ts) : ""
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.fgDim
                    }
                    Txt {
                        width: parent.width
                        text: sc.it ? String(sc.it.title) : ""
                        font.pixelSize: 16
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }
                }
            }
        }
    }

    // ============================= the six widgets =============================
    Component {
        id: widgetBand
        Item {
            // ---- column 1 ----
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
                title: "Batteries"
                idx: 1
                icon: "M3 8 H18 A1 1 0 0 1 19 9 V15 A1 1 0 0 1 18 16 H3 A1 1 0 0 1 2 15 V9 A1 1 0 0 1 3 8 Z M21.5 11 V13"

                Txt { visible: root.batts.length === 0; x: 18; y: 56; text: "No battery detected"; font.pixelSize: 14; color: Theme.fgDim }
                Item {
                    x: 0; y: 44
                    width: parent.width; height: 54
                    Row {
                        anchors.centerIn: parent
                        spacing: 22
                        Repeater {
                            model: root.batts
                            delegate: BatGauge {
                                required property var modelData
                                value: modelData.pct
                                charging: modelData.charging
                                kind: modelData.kind
                            }
                        }
                    }
                }
            }

            // ---- column 2 ----
            Card {
                id: muCard
                x: root.colW + root.gutter; y: root.topOf(2)
                height: root.tall
                title: "Most used"
                idx: 2
                icon: "M12 2.5 L14.9 8.6 L21.5 9.4 L16.6 13.9 L17.9 20.5 L12 17.2 L6.1 20.5 L7.4 13.9 L2.5 9.4 L9.1 8.6 Z"

                Txt {
                    visible: root.topApps.length === 0
                    x: 18; y: 56; width: parent.width - 36
                    wrapMode: Text.WordWrap; maximumLineCount: 3
                    text: "Use an app for a while and your favourites show up here."
                    font.pixelSize: 14; color: Theme.fgDim
                }
                Repeater {
                    model: root.topApps
                    delegate: Item {
                        id: mu
                        required property var modelData
                        required property int index
                        x: 0; y: 52 + index * 59
                        width: root.colW; height: 50
                        readonly property var pal: { void Apps.palettes; return Apps.paletteFor(mu.modelData.entry); }
                        Image {
                            x: 18; y: 3
                            width: 40; height: 40
                            source: muCard.live ? root.iconOf(mu.modelData.entry) : ""
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                        }
                        Txt { x: 70; y: 0; width: parent.width - 90; text: mu.modelData.entry.name; elide: Text.ElideRight; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Txt { x: 70; y: 21; width: parent.width - 90; text: ScreenTime.fmt(mu.modelData.secs) + " this week"; font.pixelSize: 12; color: Theme.fgDim }
                        Rectangle {
                            x: 70; y: 42
                            width: parent.width - 90; height: 4; radius: 2
                            color: Qt.rgba(1, 1, 1, 0.12)
                            Rectangle {
                                height: parent.height; radius: 2
                                width: parent.width * Math.min(1, mu.modelData.secs / Math.max(1, root.weekTotal))
                                color: mu.pal.primary
                            }
                        }
                    }
                }
            }

            Card {
                x: root.colW + root.gutter; y: root.topOf(3)
                height: root.small
                title: "Notifications"
                idx: 3
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

            // ---- column 3 ----
            Card {
                id: wxCard
                x: 2 * (root.colW + root.gutter); y: root.topOf(4)
                height: root.tall
                title: "Weather"
                idx: 4
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
                    Bone { x: 18; y: 54; width: 56; height: 56; radius: 28; run: wxCard.live && !root.wx }
                    Bone { x: 90; y: 56; width: 110; height: 34; run: wxCard.live && !root.wx }
                    Bone { x: 92; y: 102; width: 90; height: 14; run: wxCard.live && !root.wx }
                    Bone { x: 18; y: 132; width: 200; height: 12; run: wxCard.live && !root.wx }
                    Repeater {
                        model: 5
                        delegate: Bone {
                            required property int index
                            x: 18 + index * ((root.colW - 36) / 5); y: 170
                            width: 44; height: 36
                            run: wxCard.live && !root.wx
                        }
                    }
                    Txt {
                        x: 18; y: 210
                        text: root.online ? "Loading weather\u2026" : "Waiting for network\u2026"
                        font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.40)
                    }
                }
            }

            Card {
                x: 2 * (root.colW + root.gutter); y: root.topOf(5)
                height: root.small
                title: "System"
                idx: 5
                icon: "M4 5 H20 V15 H4 Z M8 19 H16 M12 15 V19"

                Txt { x: 18; y: 42; text: Math.round(root.cpuPct) + "%"; font.pixelSize: 30; font.weight: Font.Bold }
                Txt { x: 20; y: 80; text: "CPU"; font.pixelSize: 12; color: Theme.fgDim }
                Item {
                    x: 130; y: 44
                    width: parent.width - 150; height: 56
                    Txt { y: 0; text: "Memory"; font.pixelSize: 12; color: Theme.fgDim }
                    Txt { anchors.right: parent.right; y: 0; text: root.fmtBytes(root.memUsed) + " / " + root.fmtBytes(root.memTotal); font.pixelSize: 12; font.weight: Font.DemiBold }
                    Rectangle {
                        y: 19; width: parent.width; height: 4; radius: 2
                        color: Qt.rgba(1, 1, 1, 0.12)
                        Rectangle {
                            height: parent.height; radius: 2
                            width: parent.width * Math.min(1, root.memUsed / Math.max(1, root.memTotal))
                            color: Theme.accent
                        }
                    }
                    Txt { y: 30; text: "Disk"; font.pixelSize: 12; color: Theme.fgDim }
                    Txt { anchors.right: parent.right; y: 30; text: root.diskTotal > 0 ? root.fmtBytes(root.diskFree) + " free" : ""; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Rectangle {
                        y: 49; width: parent.width; height: 4; radius: 2
                        color: Qt.rgba(1, 1, 1, 0.12)
                        Rectangle {
                            height: parent.height; radius: 2
                            width: parent.width * (root.diskTotal > 0 ? Math.min(1, (root.diskTotal - root.diskFree) / root.diskTotal) : 0)
                            color: Theme.accent
                        }
                    }
                }
            }
        }
    }
}
