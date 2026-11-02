// viii-cc-1
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
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

    readonly property string mode: idx === 1 ? "windows" : (idx === 2 ? "notifs" : (idx === 3 ? "workspaces" : (idx === 8 ? "conns" : (idx === 9 ? "power" : ""))))

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
    readonly property int count: mode === "windows" ? wins.length : (mode === "workspaces" ? wsIds.length : (mode === "power" ? powerItems.length : (mode === "notifs" ? nList.length + 1 : (mode === "conns" ? 3 : 0))))
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
        } else if (mode === "workspaces") {
            switchWorkspace(wsOrder[cardIdx]);
        } else if (mode === "power") {
            runPower();
        } else if (mode === "notifs") {
            openHistoryFromCc();
        } else if (mode === "conns") {
            connToggle(cardIdx);
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
        if (inCards && mode === "notifs") {      // viii-cc-notif-conn: the list is vertical, Up/Down walk it
            if (e.key === Qt.Key_Up) { cardIdx = Math.max(0, cardIdx - 1); e.accepted = true; return; }
            if (e.key === Qt.Key_Down) { if (cardIdx >= count - 1) inCards = false; else cardIdx = cardIdx + 1; e.accepted = true; return; }
            if (e.key === Qt.Key_Left || e.key === Qt.Key_Right) { e.accepted = true; return; }
        }
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

    // ---- viii-cc-ws: Workspaces panel -------------------------------------------------------------------------
    property var wsIds: []              // workspaces to show: non-empty ones plus the current one, ascending by id
    property var wsData: ({})           // id -> { id, name, windows, monW, monH, clients: [{cls, x, y, w, h, focus}] }
    property int activeId: -1           // the workspace showing on the focused monitor
    property int wsWant: -1             // the workspace we just asked Hyprland for
    property int wsStep: 0              // which dispatch syntax is being tried
    property string wsMsg: ""
    property string swOut: ""
    property bool wsAgain: false

    // display order: the current workspace first, then the rest by id
    readonly property var wsOrder: {
        const out = [];
        if (wsIds.indexOf(activeId) >= 0) out.push(activeId);
        for (let i = 0; i < wsIds.length; i++) if (wsIds[i] !== activeId) out.push(wsIds[i]);
        return out;
    }

    // the SELECTED card is the tall one. selF glides to the selection, so the tall card moves smoothly.
    readonly property int selRank: inCards ? cardIdx : 0
    property real selF: selRank
    Behavior on selF { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }

    function wsTent(r) { return Math.max(0, 1 - Math.abs(r - selF)); }
    function wsS(r) {                   // how much "tall bonus" sits to the left of integer position r
        const k = Math.floor(selF);
        const fr = selF - k;
        if (r <= k) return 0;
        if (r === k + 1) return 1 - fr;
        return 1;
    }
    function wsX(rf) {                  // x of a card at (possibly fractional) position rf
        const a = Math.floor(rf);
        const f = rf - a;
        const pa = a * (smW + gap) + (bigW - smW) * wsS(a);
        const pb = (a + 1) * (smW + gap) + (bigW - smW) * wsS(a + 1);
        return pa + (pb - pa) * f;
    }

    // badge on the strip icon: how many workspaces have windows (Desk keeps this list fresh, so it costs nothing here)
    readonly property int wsBadge: {
        const c = Desk.wsCache || [];
        let n = 0;
        for (let i = 0; i < c.length; i++) if (c[i].id > 0 && c[i].windows > 0) n++;
        return n;
    }

    function iconForClass(cls) {
        if (!cls) return "";
        let p = "";
        try {
            const en = DesktopEntries.heuristicLookup(cls);
            if (en) p = Apps.iconPath(en);
        } catch (e) {}
        if (!p) p = Quickshell.iconPath(String(cls).toLowerCase(), true);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }

    // one process: workspaces + windows + monitors (only while the Workspaces panel is showing)
    function wsRefresh() { if (wsProc.running) wsAgain = true; else wsProc.running = true; }
    Process {
        id: wsProc
        command: ["sh", "-c", "hyprctl -j workspaces; echo '@@SEP@@'; hyprctl -j clients; echo '@@SEP@@'; hyprctl -j monitors"]
        stdout: StdioCollector { onStreamFinished: root.wsParsed(this.text) }
        onExited: { if (root.wsAgain) { root.wsAgain = false; root.wsRefresh(); } }
    }
    onModeChanged: { if (mode === "workspaces") wsRefresh(); }
    Connections { target: Desk; function onWsCacheChanged() { if (root.mode === "workspaces") wsDebounce.restart(); } }
    Timer { id: wsDebounce; interval: 120; onTriggered: root.wsRefresh() }

    function wsParsed(text) {
        const parts = String(text).split("@@SEP@@");
        if (parts.length < 3) return;
        let wss, cls, mons;
        try { wss = JSON.parse(parts[0]); cls = JSON.parse(parts[1]); mons = JSON.parse(parts[2]); }
        catch (e) { console.log("[viii-cc] workspace data unreadable:", e); return; }

        const monById = {};
        let mon = null;
        for (let i = 0; i < mons.length; i++) { monById[mons[i].id] = mons[i]; if (mons[i].focused) mon = mons[i]; }
        if (!mon && mons.length > 0) mon = mons[0];
        const act = (mon && mon.activeWorkspace) ? mon.activeWorkspace.id : -1;

        const mk = (id, name, n, m) => ({
            id: id, name: name, windows: n,
            monW: m ? m.width / (m.scale || 1) : 1366,
            monH: m ? m.height / (m.scale || 1) : 768,
            clients: []
        });
        const data = {};
        for (let i = 0; i < wss.length; i++) {
            const w = wss[i];
            if (w.id <= 0) continue;                       // special workspaces (scratchpads) are not listed
            data[w.id] = mk(w.id, w.name, w.windows, monById[w.monitorID] || mon);
        }
        for (let i = 0; i < cls.length; i++) {
            const c = cls[i];
            if (!c.mapped || c.hidden || !c.workspace || c.workspace.id <= 0) continue;
            const m = monById[c.monitor] || mon;
            if (!data[c.workspace.id]) data[c.workspace.id] = mk(c.workspace.id, c.workspace.name, 0, m);
            data[c.workspace.id].clients.push({
                cls: c["class"] || c.initialClass || "",
                x: c.at[0] - (m ? m.x : 0), y: c.at[1] - (m ? m.y : 0),
                w: c.size[0], h: c.size[1],
                focus: c.focusHistoryID === 0
            });
        }
        const ids = [];
        for (const k in data) {
            const d = data[k];
            if (d.windows > 0 || d.clients.length > 0 || d.id === act) ids.push(d.id);
        }
        ids.sort((a, b) => a - b);

        activeId = act;
        wsData = data;
        if (ids.join(",") !== wsIds.join(",")) wsIds = ids;
        if (wsWant > 0 && wsWant === act) { wsWant = -1; cardIdx = 0; }    // the workspace we just switched to is now first
    }

    // ---- switching. Enter on a card calls this. It never closes the panel. ----
    function switchWorkspace(id) {
        if (!(id > 0)) return;
        if (id === activeId) { wsMsg = ""; return; }       // already there
        wsWant = id; wsStep = 0; wsMsg = "";
        wsDispatch();
    }
    function wsCommand(step, id) {
        const lua = 'hl.dsp.focus({ workspace = "' + id + '" })';
        if (step === 0) return ["hyprctl", "dispatch", lua];                                   // Hyprland Lua config (this setup)
        if (step === 1) return ["hyprctl", "dispatch", "workspace", String(id)];               // old hyprlang syntax
        return ["hyprctl", "eval", "hl.dispatch(" + lua + ")"];                                // eval form
    }
    function wsDispatch() {
        swOut = "";
        swProc.command = wsCommand(wsStep, wsWant);
        console.log("[viii-cc] workspace", wsWant, "try", wsStep, JSON.stringify(swProc.command));
        swProc.running = true;
    }
    Process {
        id: swProc
        stdout: StdioCollector { onStreamFinished: root.swOut = this.text }
        onExited: chkTimer.restart()
    }
    Timer { id: chkTimer; interval: 150; onTriggered: chkProc.running = true }
    Process {
        id: chkProc
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector { onStreamFinished: root.wsChecked(this.text) }
    }
    function wsChecked(text) {
        let id = -1;
        try { id = JSON.parse(text).id; } catch (e) {}
        if (id === wsWant) {
            console.log("[viii-cc] switched to workspace", id, "(syntax", wsStep + ")");
            Desk.ccRegrab();
            regrabLate.restart();           // again once the hub underneath (if the new workspace is empty) has settled
            wsRefresh();                    // wsParsed then moves the new current workspace to the front
            return;
        }
        console.log("[viii-cc] workspace", wsWant, "not reached, active is", id, "; hyprctl said:", String(swOut).trim());
        if (wsStep < 2) { wsStep++; wsDispatch(); }
        else { wsMsg = "Could not switch workspace (see: viii log)"; wsWant = -1; msgTimer.restart(); }
    }
    Timer { id: msgTimer; interval: 4000; onTriggered: root.wsMsg = "" }
    Timer { id: regrabLate; interval: 550; onTriggered: Desk.ccRegrab() }
    // -------------------------------------------------------------------------------------------------------------

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
    Loader { anchors.fill: parent; active: root.mode === "workspaces"; sourceComponent: wsRowComp }
    Loader { anchors.fill: parent; active: root.mode === "power"; sourceComponent: powerRowComp }

    // viii-cc-notif-conn: Notifications (strip 2) and Connections (strip 8)
    Loader { anchors.fill: parent; active: root.mode === "notifs"; sourceComponent: notifComp }
    Loader { anchors.fill: parent; active: root.mode === "conns"; sourceComponent: connComp }

    Component {
        id: notifComp
        Item {
            id: nRoot
            readonly property int nRows: Math.max(1, root.nList.length)
            NumberAnimation on opacity { from: 0; to: 1; duration: 240 }

            Item {
                id: np
                width: 440
                height: 82 + nRoot.nRows * 62
                x: Math.max(root.padX, root.width / 2 + (2 - 4.5) * root.stepX - width / 2)
                y: root.rowBottom - height + (1 - root.vis) * 40
                opacity: root.vis

                GlassSlot { anchors.fill: parent; radius: 22 }

                Txt {
                    visible: root.nList.length === 0
                    x: 30
                    y: 12 + 21
                    text: "No notifications yet"
                    font.pixelSize: 17
                    color: Theme.fgDim
                }

                Repeater {
                    model: root.nList
                    delegate: Item {
                        id: nr
                        required property var modelData
                        required property int index
                        readonly property bool cur: root.inCards && root.cardIdx === index
                        readonly property bool power: !!modelData && modelData.kind === "power"
                        property real selT: cur ? 1 : 0
                        Behavior on selT { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        x: 12
                        y: 12 + index * 62
                        width: np.width - 24
                        height: 62

                        Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 14; color: Qt.rgba(1, 1, 1, 0.07); opacity: nr.selT }
                        GlassRing { anchors.fill: parent; anchors.margins: -1; radius: 17; opacity: nr.selT; visible: opacity > 0.01 }

                        Rectangle {
                            id: nDisc
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: Qt.rgba(1, 1, 1, 0.09)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            Image {
                                id: nImg
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                sourceSize: Qt.size(52, 52)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                source: root.nIcon(nr.modelData)
                                visible: source !== "" && status === Image.Ready
                            }
                            Txt {
                                anchors.centerIn: parent
                                visible: !nr.power && !nImg.visible
                                text: ((nr.modelData && (nr.modelData.app || nr.modelData.title)) || "?").charAt(0).toUpperCase()
                                font.pixelSize: 18
                                font.weight: Font.Bold
                            }
                            Canvas {
                                id: nBolt
                                anchors.centerIn: parent
                                width: 16
                                height: 26
                                scale: 0.8
                                visible: nr.power
                                property bool plug: !!nr.modelData && nr.modelData.plugged === true
                                property color ink: Theme.accent
                                property color dim: Theme.fgDim
                                onPlugChanged: requestPaint()
                                onInkChanged: requestPaint()
                                onDimChanged: requestPaint()
                                Component.onCompleted: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.fillStyle = nBolt.plug ? nBolt.ink : nBolt.dim;
                                    ctx.beginPath();
                                    ctx.moveTo(10.4, 0);
                                    ctx.lineTo(0, 15.2);
                                    ctx.lineTo(7.4, 15.2);
                                    ctx.lineTo(5.1, 25.6);
                                    ctx.lineTo(16, 9.6);
                                    ctx.lineTo(8.6, 9.6);
                                    ctx.closePath();
                                    ctx.fill();
                                }
                            }
                        }

                        Column {
                            x: 68
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 68 - 66
                            spacing: 2
                            Txt {
                                width: parent.width
                                text: nr.modelData ? nr.modelData.title : ""
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                textFormat: Text.PlainText
                            }
                            Txt {
                                width: parent.width
                                visible: text !== ""
                                text: root.nSub(nr.modelData)
                                font.pixelSize: 12
                                color: Theme.fgDim
                                textFormat: Text.PlainText
                            }
                        }

                        Txt {
                            anchors.right: parent.right
                            anchors.rightMargin: 18
                            y: 14
                            text: nr.modelData ? root.relT(nr.modelData.t) : ""
                            font.pixelSize: 12
                            color: Theme.fgDim
                        }
                        Rectangle {
                            visible: !!nr.modelData && nr.modelData.t > root.seenAtOpen
                            anchors.right: parent.right
                            anchors.rightMargin: 18
                            y: 36
                            width: 9
                            height: 9
                            radius: 4.5
                            color: Theme.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: { root.cardIdx = nr.index; root.inCards = true; root.activateCard(); }
                        }
                    }
                }

                // "Open full history" row
                Item {
                    id: hr
                    readonly property int hIdx: root.nList.length
                    readonly property bool cur: root.inCards && root.cardIdx === hIdx
                    property real selT: cur ? 1 : 0
                    Behavior on selT { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    x: 12
                    y: 12 + nRoot.nRows * 62 + 6
                    width: np.width - 24
                    height: 52

                    Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 14; color: Qt.rgba(1, 1, 1, 0.07); opacity: hr.selT }
                    GlassRing { anchors.fill: parent; anchors.margins: -1; radius: 17; opacity: hr.selT; visible: opacity > 0.01 }
                    Txt {
                        x: 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Open full history"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Txt {
                        anchors.right: parent.right
                        anchors.rightMargin: 52
                        anchors.verticalCenter: parent.verticalCenter
                        text: (Notifs.history ? Notifs.history.length : 0) + " saved"
                        font.pixelSize: 13
                        color: Theme.fgDim
                    }
                    Txt {
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u203a"
                        font.pixelSize: 26
                        color: Theme.fgDim
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.cardIdx = hr.hIdx; root.inCards = true; root.activateCard(); }
                    }
                }
            }
        }
    }

    Component {
        id: connComp
        Item {
            NumberAnimation on opacity { from: 0; to: 1; duration: 240 }

            Repeater {
                model: 3
                delegate: Item {
                    id: cn
                    required property int index
                    readonly property bool cur: root.inCards && root.cardIdx === index
                    readonly property bool lit: index === 0 ? (root.wifiOnNow && !root.wifiBlocked) : (index === 1 ? root.btOnNow : root.usbList.length > 0)

                    width: root.smW
                    height: root.smH
                    x: root.connX + index * (root.smW + root.gap)
                    y: root.rowBottom - height + (1 - root.vis) * 40
                    opacity: root.vis
                    scale: cur ? 1.04 : 1
                    Behavior on scale {
                        NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                    }

                    GlassSlot { anchors.fill: parent; radius: 18 }

                    Rectangle {
                        x: 22
                        y: 22
                        width: 64
                        height: 64
                        radius: 32
                        color: cn.lit ? Theme.fg : Qt.rgba(1, 1, 1, 0.10)
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Txt {
                            anchors.centerIn: parent
                            text: root.nfFamily !== "" ? root.connGlyphs[cn.index] : root.connFallbacks[cn.index]
                            font.family: root.nfFamily !== "" ? root.nfFamily : Theme.fontFamily
                            font.pixelSize: root.nfFamily !== "" ? 28 : 12
                            font.weight: Font.Bold
                            color: cn.lit ? Theme.deep : Theme.fgDim
                            elide: Text.ElideNone
                        }
                    }

                    Txt {
                        x: 22
                        y: 104
                        width: parent.width - 44
                        text: root.connTitles[cn.index]
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        color: Theme.fgDim
                    }
                    Txt {
                        x: 22
                        y: 130
                        width: parent.width - 44
                        text: root.connBig(cn.index)
                        font.pixelSize: 30
                        font.weight: Font.Bold
                    }
                    Txt {
                        x: 22
                        y: 178
                        width: parent.width - 44
                        text: root.connSub(cn.index)
                        font.pixelSize: 14
                        color: Theme.fgDim
                        wrapMode: Text.NoWrap
                        maximumLineCount: 4
                        lineHeight: 1.15
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }

                    GlassRing {
                        anchors.fill: parent
                        anchors.margins: -4.5
                        radius: 22
                        opacity: cn.cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    Txt {
                        x: 2
                        y: cn.height + 14
                        text: root.connLabel(cn.index)
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        opacity: cn.cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.cardIdx = cn.index; root.inCards = true; root.activateCard(); }
                    }
                }
            }
        }
    }

    // viii-cc-home: Home selected -> the Welcome cards (same grid as the hub's Welcome tile). Enter / click = hub root.
    Loader { anchors.fill: parent; active: root.idx === 0; sourceComponent: homeComp }
    Component {
        id: homeComp
        Item {
            NumberAnimation on opacity { from: 0; to: 1; duration: 240 }

            WelcomeGrid {
                id: homeGrid
                shown: true
                x: root.padX
                y: root.rowBottom - height + (1 - root.vis) * 40
                opacity: root.vis
            }
            MouseArea {
                x: homeGrid.x
                y: homeGrid.y
                width: homeGrid.width
                height: homeGrid.height
                onClicked: root.goHome()
            }
        }
    }

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
        id: wsRowComp
        Item {
            id: wsRow
            // keep the selected (tall) card on screen: scroll the row when it would pass the right edge
            property real shift: root.inCards
                ? Math.max(0, root.cardIdx * (root.smW + root.gap) + root.bigW - (root.width - 2 * root.padX))
                : 0
            Behavior on shift {
                NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
            }
            NumberAnimation on opacity { from: 0; to: 1; duration: 240 }

            Txt {
                visible: root.wsIds.length === 0
                x: root.padX
                y: root.rowBottom - 40
                text: "Loading workspaces..."
                font.pixelSize: 22
                color: Theme.fgDim
                opacity: root.vis
            }
            Txt {
                visible: root.wsMsg !== ""
                anchors.right: parent.right
                anchors.rightMargin: root.padX
                y: root.rowBottom + 14
                text: root.wsMsg
                font.pixelSize: 16
                color: "#ff8a8a"
            }

            Repeater {
                model: root.wsIds
                delegate: Item {
                    id: wk
                    required property int modelData
                    required property int index
                    readonly property var info: root.wsData[modelData] || null
                    readonly property int rank: root.wsOrder.indexOf(modelData)
                    property real rankF: rank                       // glides when the order changes (after a switch)
                    Behavior on rankF {
                        NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                    }
                    readonly property real t: root.wsTent(rankF)    // 1 = the selected, tall card
                    readonly property bool cur: root.inCards && root.cardIdx === rank
                    readonly property bool isActive: modelData === root.activeId
                    readonly property real snapH: 190 + 100 * t
                    readonly property int nWin: info ? Math.max(info.windows, info.clients.length) : 0

                    width: root.smW + (root.bigW - root.smW) * t
                    height: root.smH + (root.bigH - root.smH) * t
                    x: root.padX + root.wsX(rankF) - wsRow.shift
                    y: root.rowBottom - height + (1 - root.vis) * 40
                    visible: rank >= 0
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
                        height: wk.snapH
                        clip: true
                        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }

                        // mini-map: the monitor's shape, one rectangle (with the app's icon) per window
                        Item {
                            id: map
                            readonly property real mw: wk.info ? wk.info.monW : 1366
                            readonly property real mh: wk.info ? wk.info.monH : 768
                            readonly property real k: Math.min((snap.width - 14) / mw, (snap.height - 14) / mh)
                            anchors.centerIn: parent
                            width: mw * k
                            height: mh * k
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.12)
                            }
                            Repeater {
                                model: wk.info ? wk.info.clients : []
                                delegate: Rectangle {
                                    id: wr
                                    required property var modelData
                                    readonly property bool hot: modelData.focus && wk.isActive
                                    x: modelData.x * map.k
                                    y: modelData.y * map.k
                                    width: Math.max(8, modelData.w * map.k)
                                    height: Math.max(8, modelData.h * map.k)
                                    radius: 4
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    border.width: hot ? 2 : 1
                                    border.color: hot ? Theme.accent : Qt.rgba(1, 1, 1, 0.28)
                                    Image {
                                        readonly property real sz: Math.max(12, Math.min(44, Math.min(wr.width, wr.height) * 0.5))
                                        anchors.centerIn: parent
                                        width: sz
                                        height: sz
                                        visible: Math.min(wr.width, wr.height) >= 22
                                        source: root.iconForClass(wr.modelData.cls)
                                        sourceSize: Qt.size(88, 88)
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                            }
                        }
                        Txt {
                            anchors.centerIn: parent
                            visible: wk.nWin === 0
                            text: "Empty"
                            font.pixelSize: 18
                            color: Theme.fgDim
                        }
                    }

                    Rectangle {                                     // the workspace number, where other cards show the app icon
                        x: 16
                        y: snap.y + snap.height + 12
                        width: 38
                        height: 38
                        radius: 19
                        color: wk.isActive ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                        Txt {
                            anchors.centerIn: parent
                            text: String(wk.modelData)
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: wk.isActive ? Theme.deep : Theme.fg
                        }
                    }
                    Txt {
                        x: 64
                        y: snap.y + snap.height + 12
                        width: wk.width - 80
                        text: (wk.info && wk.info.name && isNaN(Number(wk.info.name)))
                            ? "Workspace " + wk.modelData + " · " + wk.info.name : "Workspace " + wk.modelData
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                    }
                    Txt {
                        x: 64
                        y: snap.y + snap.height + 38
                        width: wk.width - 80
                        text: (wk.nWin === 0 ? "Empty" : (wk.nWin === 1 ? "1 window" : wk.nWin + " windows")) + (wk.isActive ? " · current" : "")
                        font.pixelSize: 14
                        color: Theme.fgDim
                    }

                    GlassRing {
                        anchors.fill: parent
                        anchors.margins: -4.5
                        radius: 22
                        opacity: wk.cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    // PS5 "Resume Game" label under the selected card
                    Txt {
                        x: 2
                        y: wk.height + 14
                        text: wk.isActive ? "Current workspace" : "Switch to workspace"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        opacity: wk.cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.cardIdx = wk.rank; root.inCards = true; root.activateCard(); }
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

    // ---- viii-cc-notif-conn: Notifications + Connections panels -----------------------------------------------
    // Notifications: the last 5 entries of Notifs.history in one glass panel above the bell, plus "Open full history".
    readonly property var nList: (Notifs.history || []).slice(0, 5)
    property real seenAtOpen: 0                     // Desk.notifSeen as it was when the Control Center opened
    Component.onCompleted: seenAtOpen = Desk.notifSeen
    readonly property int unread: {
        const h = Notifs.history || [];
        let n = 0;
        for (let i = 0; i < h.length; i++) if (h[i].t > Desk.notifSeen) n++;
        return n;
    }
    // looking at the panel for a moment marks everything as seen (the dots stay until you leave, via seenAtOpen)
    Timer { running: root.mode === "notifs"; interval: 1200; onTriggered: Desk.notifSeen = Date.now() }
    function relT(ts) {
        const m = Math.floor(Math.max(0, Date.now() - ts) / 60000);
        if (m < 1) return "Now";
        if (m < 60) return m + " min";
        const h = Math.floor(m / 60);
        if (h < 24) return h + " h";
        return Math.floor(h / 24) + " d";
    }
    function nSub(en) {
        if (!en) return "";
        if (en.kind === "app" && en.app && en.app !== en.title) return en.app;
        return en.body || "";
    }
    function nIcon(en) {
        if (!en || en.kind !== "app" || !en.icon) return "";
        if (en.icon.charAt(0) === "/") return "file://" + en.icon;
        if (en.icon.indexOf("file://") === 0) return en.icon;
        const p = Quickshell.iconPath(en.icon, true);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }
    function openHistoryFromCc() {
        Desk.notifSeen = Date.now();
        Desk.ccOpen = false;
        Desk.openHistory();
    }

    // Connections: Wi-Fi and Bluetooth come from Quickshell (same sources as Settings), USB is read once when the panel opens.
    readonly property real connX: Math.max(padX, Math.min(width / 2 + 3.5 * stepX - (3 * smW + 2 * gap) / 2, width - padX - (3 * smW + 2 * gap)))
    readonly property var wifiDev: {
        const d = Networking.devices ? Networking.devices.values : [];
        for (let i = 0; i < d.length; i++) if (d[i].type === DeviceType.Wifi) return d[i];
        return null;
    }
    readonly property bool wiredUp: {
        const d = Networking.devices ? Networking.devices.values : [];
        for (let i = 0; i < d.length; i++) if (d[i].type === DeviceType.Wired && d[i].connected) return true;
        return false;
    }
    readonly property var wifiNets: wifiDev && wifiDev.networks ? wifiDev.networks.values : []
    readonly property var wifiActive: {
        for (let i = 0; i < wifiNets.length; i++) if (wifiNets[i].connected) return wifiNets[i];
        return null;
    }
    readonly property bool wifiOnNow: Networking.wifiEnabled
    readonly property bool wifiBlocked: !Networking.wifiHardwareEnabled
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOnNow: btAdapter ? btAdapter.enabled : false
    readonly property var btDevs: btAdapter && btAdapter.devices ? btAdapter.devices.values : []
    readonly property var btLinked: btDevs.filter(d => d.connected)

    property var usbList: []
    function usbRefresh() { if (!usbProc.running) usbProc.running = true; }
    function usbParsed(t) {
        const out = [];
        const l = t.split("\n");
        for (let i = 0; i < l.length; i++) {
            const s = l[i].trim();
            if (s === "") continue;
            const p = s.split("|");
            out.push({ name: p[0] || "USB device", vendor: p[1] || "" });
        }
        usbList = out;
    }
    Process {
        id: usbProc
        command: ["sh", "-c", 'for d in /sys/bus/usb/devices/*; do [ -f "$d/product" ] || continue; c=$(cat "$d/bDeviceClass" 2>/dev/null); [ "$c" = 09 ] && continue; [ "$c" = e0 ] && continue; r=$(cat "$d/removable" 2>/dev/null); [ "$r" = fixed ] && continue; p=$(cat "$d/product" 2>/dev/null); m=$(cat "$d/manufacturer" 2>/dev/null); echo "$p|$m"; done; true']
        stdout: StdioCollector { onStreamFinished: root.usbParsed(this.text) }
    }
    Connections { target: root; function onModeChanged() { if (root.mode === "conns") root.usbRefresh(); } }

    function connToggle(i) {
        if (i === 0) {
            if (wifiBlocked) return;
            Networking.wifiEnabled = !Networking.wifiEnabled;
            if (!Networking.wifiEnabled && wifiDev) wifiDev.scannerEnabled = false;
        } else if (i === 1) {
            if (btAdapter) btAdapter.enabled = !btAdapter.enabled;
        } else {
            usbRefresh();
        }
    }
    function connBig(i) {
        if (i === 0) return wifiBlocked ? "Blocked" : (wifiOnNow ? "On" : "Off");
        if (i === 1) return !btAdapter ? "No adapter" : (btOnNow ? "On" : "Off");
        return usbList.length === 0 ? "None" : String(usbList.length);
    }
    function connSub(i) {
        if (i === 0) {
            if (!wifiOnNow || wifiBlocked) return "";
            if (wifiActive) return wifiActive.name + "\n" + Math.round(wifiActive.signalStrength * 100) + "% signal";
            return wiredUp ? "Ethernet connected" : "Not connected";
        }
        if (i === 1) {
            if (!btOnNow) return "";
            if (btLinked.length === 0) return "No devices connected";
            const n = [];
            for (let k = 0; k < btLinked.length && k < 3; k++) n.push(btLinked[k].name || btLinked[k].deviceName || "Device");
            return n.join("\n") + (btLinked.length > 3 ? "\n+" + (btLinked.length - 3) + " more" : "");
        }
        if (usbList.length === 0) return "Nothing plugged in";
        const u = [];
        for (let k = 0; k < usbList.length && k < 3; k++) u.push(usbList[k].name);
        return u.join("\n") + (usbList.length > 3 ? "\n+" + (usbList.length - 3) + " more" : "");
    }
    function connLabel(i) {
        if (i === 0) return wifiBlocked ? "" : (wifiOnNow ? "Turn Wi-Fi off" : "Turn Wi-Fi on");
        if (i === 1) return !btAdapter ? "" : (btOnNow ? "Turn Bluetooth off" : "Turn Bluetooth on");
        return "Refresh";
    }
    readonly property var connTitles: ["Wi-Fi", "Bluetooth", "USB"]
    readonly property var connGlyphs: ["\uf1eb", "\uf294", "\uf287"]
    readonly property var connFallbacks: ["WIFI", "BT", "USB"]

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
            Rectangle {                                 // viii-cc-ws: number of workspaces that have windows
                visible: it.index === 3 && root.wsBadge > 0
                x: parent.width - 14
                y: -6
                width: 20
                height: 20
                radius: 10
                color: Theme.accent
                Txt {
                    anchors.centerIn: parent
                    text: String(root.wsBadge)
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: Theme.deep
                }
            }
            Rectangle {                                 // viii-cc-notif-conn: unread notifications on the bell
                visible: it.index === 2 && root.unread > 0
                x: parent.width - 14
                y: -6
                width: root.unread > 9 ? 26 : 20
                height: 20
                radius: 10
                color: Theme.accent
                Txt {
                    anchors.centerIn: parent
                    text: root.unread > 9 ? "9+" : String(root.unread)
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: Theme.deep
                }
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
