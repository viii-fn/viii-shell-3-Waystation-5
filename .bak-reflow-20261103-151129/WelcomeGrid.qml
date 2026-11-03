import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import "../core"

// The PS5 "Games" card grid, shown while the Welcome tile is selected.
//
//   col 1: Screen time (tall)    col 2: Most used (small)   col 3: Batteries (small)
//          Network (small)              About (tall)               Weather (tall)
//
// Data rules (2 GB RAM): nothing runs while the grid is hidden; web data (weather, about) is cached on disk,
// read from the cache first, and only fetched 2 s after the grid appears (never during the intro).
Item {
    id: root
    property bool shown: true
    readonly property bool active: shown && visible

    readonly property real colW: 358
    readonly property real gutter: 23
    readonly property real tall: 233
    readonly property real small: 108
    readonly property real rowGap: 17
    width: 3 * colW + 2 * gutter
    height: tall + rowGap + small

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
        if (!active || !online) return;
        nowSec = Date.now() / 1000;
        if (wxStale()) fetchWeather();
        if (!about) fetchAbout();
    }
    Timer { id: kick; interval: 2000; onTriggered: root.refreshAll() }
    Timer { interval: 30000; repeat: true; running: root.active && root.online; onTriggered: root.refreshAll() }
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

    // ============================= column 1 =============================
    Card {
        x: 0; y: 0
        height: root.tall
        title: "Screen time"
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
        x: 0; y: root.tall + root.rowGap
        height: root.small
        title: "Network"
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
        x: root.colW + root.gutter; y: 0
        height: root.small
        title: "Most used"
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
        x: root.colW + root.gutter; y: root.small + root.rowGap
        height: root.tall
        title: "About"
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
        x: 2 * (root.colW + root.gutter); y: 0
        height: root.small
        title: "Batteries"
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
        x: 2 * (root.colW + root.gutter); y: root.small + root.rowGap
        height: root.tall
        title: "Weather"
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
}
