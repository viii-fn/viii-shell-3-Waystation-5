// viii-cc-1
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../hub"

// The PS5-style Control Center, drawn in the 1366x768 design space. Loaded by ControlCenter.qml only while it is open,
// so the window snapshots and everything else here cost nothing when it is closed.
//
//   strip (bottom): Home, Active app, Notifications, Workspaces, Music, Volume, Mic, Battery, Connections, Power
//   cards (above the selected icon): Active app = one snapshot card per open window, Power = four cards.
//   (the other icons are in the strip but their panels are built one by one in the next steps)
//
// Keys (forwarded by ControlCenter.qml): Left/Right move, Up goes into the cards, Down/Esc comes back,
// Enter acts, Delete closes the selected window.
Item {
    id: root

    property real vis: 1
    property int idx: 1              // strip selection, 0..9
    property bool inCards: false
    property int cardIdx: 0
    property string armed: ""        // name of the destructive power card waiting for a second Enter

    // ---- geometry (taken from the PS5 screenshot, scaled to 1366x768) ----
    readonly property real bigW: 314
    readonly property real bigH: 375
    readonly property real smW: 257
    readonly property real smH: 285
    readonly property real gap: 12
    readonly property real padX: 57
    readonly property real rowBottom: 620
    readonly property real stripY: 690
    readonly property real stepX: 84
    readonly property real powerX: width / 2 + 4.5 * stepX + 40 - (4 * 200 + 3 * gap)

    readonly property var names: ["Home", "Active app", "Notifications", "Workspaces", "Music", "Volume", "Mic", "Battery", "Connections", "Power"]
    readonly property var glyphs: ["", "", "", "", "", "", "", "", "", ""]
    readonly property var fallbacks: ["HOME", "APP", "NOTIF", "WS", "MUSIC", "VOL", "MIC", "BAT", "NET", "PWR"]

    readonly property string mode: idx === 1 ? "windows" : (idx === 9 ? "power" : "")

    readonly property string nfFamily: {
        const f = Qt.fontFamilies();
        if (f.indexOf("Symbols Nerd Font") >= 0) return "Symbols Nerd Font";
        if (f.indexOf("Symbols Nerd Font Mono") >= 0) return "Symbols Nerd Font Mono";
        for (let i = 0; i < f.length; i++) if (f[i].indexOf("Nerd Font") >= 0) return f[i];
        return "";
    }

    readonly property var powerItems: [
        { n: "Lock", c: ["hyprlock"], danger: false, g: "" },
        { n: "Sleep", c: ["systemctl", "suspend"], danger: false, g: "" },
        { n: "Restart", c: ["systemctl", "reboot"], danger: true, g: "" },
        { n: "Shut down", c: ["systemctl", "poweroff"], danger: true, g: "" }
    ]

    // ---- windows: the last focused one first (Desk remembers it, because the Control Center takes keyboard focus) ----
    function winList() {
        const all = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : [];
        const last = Desk.lastActive;
        const out = [];
        if (last && all.indexOf(last) >= 0) out.push(last);
        for (let i = 0; i < all.length; i++) if (all[i] !== last) out.push(all[i]);
        return out.slice(0, 8);
    }
    readonly property var wins: winList()
    readonly property int count: mode === "windows" ? wins.length : (mode === "power" ? powerItems.length : 0)
    onCountChanged: {
        if (count === 0) inCards = false;
        else if (cardIdx >= count) cardIdx = count - 1;
    }

    function entryFor(tl) {
        if (!tl || !tl.appId) return null;
        try { return DesktopEntries.heuristicLookup(tl.appId); } catch (e) { return null; }
    }
    function appName(tl) {
        const en = entryFor(tl);
        if (en && en.name) return en.name;
        return tl && tl.appId ? tl.appId : "Window";
    }
    function iconFor(tl) {
        if (!tl) return "";
        const en = entryFor(tl);
        let p = "";
        if (en) p = Apps.iconPath(en);
        else if (tl.appId) p = Quickshell.iconPath(String(tl.appId).toLowerCase(), true);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }
    function wsLabel(tl) {
        try {
            const l = Hyprland.toplevels.values;
            for (let i = 0; i < l.length; i++)
                if (l[i].wayland === tl) return l[i].workspace ? "Workspace " + l[i].workspace.id : "";
        } catch (e) {}
        return "";
    }
    readonly property string appIcon: iconFor(wins.length > 0 ? wins[0] : null)

    function xOf(i) { return i <= 0 ? 0 : bigW + gap + (i - 1) * (smW + gap); }
    function cardW(i) { return i === 0 ? bigW : smW; }

    // ---- actions ----
    function select(i) { idx = Math.max(0, Math.min(9, i)); inCards = false; cardIdx = 0; armed = ""; }
    function enterCards() { if (count > 0) { inCards = true; cardIdx = Math.min(cardIdx, count - 1); } }
    function goHome() { Desk.ccOpen = false; Desk.summoned = true; }

    function runPower() {
        const it = powerItems[cardIdx];
        if (!it) return;
        if (it.danger && armed !== it.n) { armed = it.n; armTimer.restart(); return; }
        Desk.ccOpen = false;
        Quickshell.execDetached(it.c);
    }

    function activateCard() {
        if (mode === "windows") {
            const tl = wins[cardIdx];
            if (!tl) return;
            Desk.ccOpen = false;
            Desk.summoned = false;
            tl.activate();
        } else if (mode === "power") {
            runPower();
        }
    }

    function choose() {
        if (inCards) activateCard();
        else if (idx === 0) goHome();
        else enterCards();
    }

    function closeCard() {
        if (!inCards || mode !== "windows") return;
        const tl = wins[cardIdx];
        if (tl) tl.close();
    }

    function key(e) {
        let ok = true;
        switch (e.key) {
        case Qt.Key_Left:
            if (inCards) { cardIdx = Math.max(0, cardIdx - 1); armed = ""; }
            else select(idx - 1);
            break;
        case Qt.Key_Right:
            if (inCards) { cardIdx = Math.min(count - 1, cardIdx + 1); armed = ""; }
            else select(idx + 1);
            break;
        case Qt.Key_Up: enterCards(); break;
        case Qt.Key_Down: inCards = false; armed = ""; break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: choose(); break;
        case Qt.Key_Delete: closeCard(); break;
        case Qt.Key_Escape:
            if (inCards) { inCards = false; armed = ""; }
            else Desk.ccOpen = false;
            break;
        default: ok = false;
        }
        e.accepted = ok;
    }

    Timer { id: armTimer; interval: 3500; onTriggered: root.armed = "" }
    SystemClock { id: clk; precision: SystemClock.Minutes }

    // ---- clock ----
    Txt {
        anchors.right: parent.right
        anchors.rightMargin: root.padX
        y: 34
        text: Qt.formatDateTime(clk.date, "HH:mm")
        font.pixelSize: 34
        font.weight: Font.Medium
        opacity: root.vis
    }

    // ---- card rows ----
    Loader { anchors.fill: parent; active: root.mode === "windows"; sourceComponent: winRowComp }
    Loader { anchors.fill: parent; active: root.mode === "power"; sourceComponent: powerRowComp }

    Component {
        id: winRowComp
        Item {
            id: winRow
            property real shift: root.inCards
                ? Math.max(0, root.xOf(root.cardIdx) + root.cardW(root.cardIdx) - (root.width - 2 * root.padX))
                : 0
            Behavior on shift {
                NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
            }
            NumberAnimation on opacity { from: 0; to: 1; duration: 240 }

            Txt {
                visible: root.wins.length === 0
                x: root.padX
                y: root.rowBottom - 40
                text: "No open windows"
                font.pixelSize: 22
                color: Theme.fgDim
                opacity: root.vis
            }

            Repeater {
                model: root.wins
                delegate: Item {
                    id: wc
                    required property var modelData
                    required property int index
                    readonly property bool big: index === 0
                    readonly property bool cur: root.inCards && root.cardIdx === index
                    readonly property real snapH: big ? 290 : 190

                    width: big ? root.bigW : root.smW
                    height: big ? root.bigH : root.smH
                    x: root.padX + root.xOf(index) - winRow.shift
                    y: root.rowBottom - height + (1 - root.vis) * 40
                    opacity: root.vis
                    scale: cur ? 1.03 : 1
                    Behavior on scale {
                        NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                    }

                    GlassSlot { anchors.fill: parent; radius: 18 }

                    Item {
                        id: snap
                        x: 10
                        y: 10
                        width: parent.width - 20
                        height: wc.snapH
                        clip: true
                        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }
                        Image {
                            anchors.centerIn: parent
                            width: 64
                            height: 64
                            visible: !sv.hasContent
                            source: root.iconFor(wc.modelData)
                            sourceSize: Qt.size(128, 128)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                        }
                        ScreencopyView {
                            id: sv
                            captureSource: wc.modelData
                            live: false
                            visible: hasContent
                            anchors.centerIn: parent
                            readonly property real sc: (implicitWidth > 0 && implicitHeight > 0)
                                ? Math.max(snap.width / implicitWidth, snap.height / implicitHeight) : 1
                            width: implicitWidth > 0 ? implicitWidth * sc : snap.width
                            height: implicitHeight > 0 ? implicitHeight * sc : snap.height
                        }
                    }

                    Image {
                        x: 16
                        y: snap.y + snap.height + 14
                        width: 38
                        height: 38
                        source: root.iconFor(wc.modelData)
                        sourceSize: Qt.size(76, 76)
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    Txt {
                        x: 64
                        y: snap.y + snap.height + 12
                        width: wc.width - 80
                        text: root.appName(wc.modelData)
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                    }
                    Txt {
                        x: 64
                        y: snap.y + snap.height + 38
                        width: wc.width - 80
                        text: {
                            const w = root.wsLabel(wc.modelData);
                            const f = wc.modelData === Desk.lastActive ? "focused" : "";
                            return w !== "" && f !== "" ? w + " · " + f : (w !== "" ? w : f);
                        }
                        font.pixelSize: 14
                        color: Theme.fgDim
                    }

                    GlassRing {
                        anchors.fill: parent
                        anchors.margins: -4.5
                        radius: 22
                        opacity: wc.cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    // PS5 "Resume Game" label under the selected card
                    Txt {
                        x: 2
                        y: wc.height + 14
                        text: "Switch to window"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        opacity: wc.cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.cardIdx = wc.index; root.inCards = true; root.activateCard(); }
                    }
                }
            }
        }
    }

    Component {
        id: powerRowComp
        Item {
            NumberAnimation on opacity { from: 0; to: 1; duration: 240 }

            Repeater {
                model: root.powerItems
                delegate: Item {
                    id: pc
                    required property var modelData
                    required property int index
                    readonly property bool cur: root.inCards && root.cardIdx === index
                    readonly property bool arm: root.armed === modelData.n

                    width: 200
                    height: 150
                    x: root.powerX + index * (width + root.gap)
                    y: root.rowBottom - height + (1 - root.vis) * 40
                    opacity: root.vis
                    scale: cur ? 1.04 : 1
                    Behavior on scale {
                        NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                    }

                    GlassSlot { anchors.fill: parent; radius: 18 }
                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: "#e5484d"
                        opacity: pc.arm ? 0.30 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                    }
                    Txt {
                        width: parent.width
                        y: 26
                        horizontalAlignment: Text.AlignHCenter
                        text: root.nfFamily !== "" ? pc.modelData.g : pc.modelData.n.charAt(0)
                        font.family: root.nfFamily !== "" ? root.nfFamily : Theme.fontFamily
                        font.pixelSize: 38
                    }
                    Txt {
                        width: parent.width
                        y: 94
                        horizontalAlignment: Text.AlignHCenter
                        text: pc.modelData.n
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Txt {
                        width: parent.width
                        y: 122
                        horizontalAlignment: Text.AlignHCenter
                        visible: pc.arm
                        text: "Press Enter again"
                        font.pixelSize: 13
                        color: Theme.fgDim
                    }
                    GlassRing {
                        anchors.fill: parent
                        anchors.margins: -4.5
                        radius: 22
                        opacity: pc.cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.cardIdx = pc.index; root.inCards = true; root.runPower(); }
                    }
                }
            }
        }
    }

    // ---- the strip ----
    Repeater {
        model: 10
        delegate: Item {
            id: it
            required property int index
            readonly property bool cur: root.idx === index

            width: 56
            height: 56
            x: root.width / 2 + (index - 4.5) * root.stepX - width / 2
            y: root.stripY - height / 2 + (1 - root.vis) * 40
            opacity: root.vis
            scale: cur ? 1.22 : 1
            Behavior on scale {
                NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
            }

            GlassSlot {
                anchors.fill: parent
                radius: 28
                opacity: it.cur ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            GlassRing {
                anchors.fill: parent
                anchors.margins: -4.5
                radius: 32.5
                opacity: it.cur && !root.inCards ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Image {
                visible: it.index === 1 && root.appIcon !== ""
                anchors.centerIn: parent
                width: 34
                height: 34
                source: root.appIcon
                sourceSize: Qt.size(68, 68)
                asynchronous: true
                fillMode: Image.PreserveAspectFit
            }
            Txt {
                visible: !(it.index === 1 && root.appIcon !== "")
                anchors.centerIn: parent
                text: root.nfFamily !== "" ? root.glyphs[it.index] : root.fallbacks[it.index]
                font.family: root.nfFamily !== "" ? root.nfFamily : Theme.fontFamily
                font.pixelSize: root.nfFamily !== "" ? 26 : 12
                font.weight: Font.Bold
                opacity: it.cur ? 1 : 0.7
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { root.select(it.index); if (it.index === 0) root.goHome(); }
            }
        }
    }

    // name of the selected icon
    Txt {
        width: 240
        x: root.width / 2 + (root.idx - 4.5) * root.stepX - width / 2
        y: root.stripY + 46
        horizontalAlignment: Text.AlignHCenter
        text: root.names[root.idx]
        font.pixelSize: 15
        font.weight: Font.DemiBold
        opacity: root.vis
        Behavior on x {
            NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        }
    }
}
