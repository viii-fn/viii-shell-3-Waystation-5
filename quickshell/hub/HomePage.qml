import QtQuick
import QtQuick.Shapes
import Quickshell
import "../core"

// viii-reflow applied (Welcome move-up engine).
// viii-store applied (Explore and Wallstore run on the same engine: StoreGrid).
// PS5 home row. The focused tile sits at the left margin; the row slides underneath it. The name
// sits under the small tiles (right of the focused one), exactly like the PS5; the big name, the
// Open button and the screen-time cards sit lower left. One animated number (f = focus position)
// drives every tile's size and position.
Item {
    id: root

    property real intro: 1
    property real zoom: 1                // 0 = all tiles equal and small, 1 = the focused tile is zoomed (driven by the intro below)
    property real introPrev: 0
    property var entries: []
    property int current: 0
    property real f: 0
    property bool animateF: true
    property real infoIn: 1
    property bool shown: true            // the hub is on screen (the strip only keeps thumbnails loaded then)
    property bool focused: true          // viii-ring-v3: keyboard focus is on the tiles (not the top bar)
    signal launched(var entry, real x, real y, real w, real h)

    // geometry in design pixels, measured from the real PS5 home screen scaled to 1366 wide
    readonly property real small: 80
    readonly property real sel: 130
    readonly property real gap: 4
    readonly property real padL: 128
    readonly property real rowTop: 108
    readonly property real d: sel - small
    // extra space on each side of the selected tile (set by viii-sel-margin.sh)
    readonly property real selMargin: 4
    readonly property real d2: d + 2 * selMargin

    readonly property var cur: (entries && entries.length > 0) ? entries[Math.min(current, entries.length - 1)] : null
    readonly property bool special: cur !== null && (cur.isLibrary === true || cur.isWall === true)
    readonly property bool welcome: cur !== null && cur.isWelcome === true

    // ---- viii-explore: the news card row under the Explore tile ----
    readonly property bool explore: cur !== null && cur.isExplore === true

    // ---- viii-store: Wallstore and Explore take the Welcome path: Down enters (no Open button, no separate
    // page), the tile's icon lifts into the bar, the panes fit the visible screen. Cursor = wCard (0..7). ----
    readonly property bool wall: cur !== null && cur.isWall === true
    readonly property bool paneOn: explore || wall
    readonly property bool paneReady: wall || (explore && News.items.length > 0)
    signal storeRequested()                       // the "Browse all" pane: open the full Wallstore page
    // A normal application tile: it gets the same focusable content mosaic as Welcome.
    readonly property bool appPage: cur !== null && cur !== undefined && !special && !welcome && !explore
    property bool inCards: false
    property int cardIdx: 0

    // ---- viii-reflow: Welcome content focus. Down on the Welcome tile enters the card mosaic. ----
    property bool inContent: false
    property int wCard: 0                          // focused Welcome card: 0 Screen time, 1 Network, 2 Most used, 3 About, 4 Batteries, 5 Weather
    property real c: inContent ? 1 : 0             // 0 = tile focus, 1 = content focus (one number drives the whole reflow)
    Behavior on c { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }

    // ---- viii-header: navigating inside a page (Welcome/app cards or Explore cards) lifts the
    // selected tile's icon into the top-bar home slot and hides the bar completely. ----
    readonly property bool inPage: inContent || inCards
    property real navT: inPage ? 1 : 0
    Behavior on navT { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    readonly property real headX: 54               // where the top bar's left "Home" content starts
    readonly property real headY: 38
    readonly property real headS: 42               // icon size in the bar
    readonly property real zEff: zoom * (1 - c)    // the selected tile takes the small size while the content has focus
    readonly property real rowLift: 44             // tune: how far the tile row recedes upward (design px)
    readonly property real rowDim: 0.30            // tune: how much the whole row dims (0..1)
    readonly property real focusY: 240             // tune: top of the card mosaic while it has focus (design px)
    readonly property real restY: 376              // top of the card mosaic at rest (unchanged)
    // Content card grids. Welcome has 10 cards (two rows); a regular app page has 6
    // (3 small screen-time cards on top, 3 tall widgets below). Kept in sync with the grids.
    readonly property var wCol: [0, 0, 1, 1, 2, 2, 0, 1, 2, 2]              // column of each Welcome card
    readonly property var wMid: [116.5, 304, 54, 241.5, 54, 241.5, 497.5, 497.5, 435, 560]   // vertical centre (design px)
    readonly property var aCol: [0, 1, 2, 0, 1, 2]                          // column of each app card
    readonly property var aMid: [54, 54, 54, 247.5, 247.5, 247.5]           // vertical centre (design px)
    readonly property var cCol: root.appPage ? aCol : wCol
    readonly property var cMid: root.appPage ? aMid : wMid
    readonly property int cCount: root.appPage ? aCol.length : 10
    function wNav(dx, dy) {                        // move the card cursor; false = nothing to move to
        const i = Math.max(0, Math.min(cCount - 1, wCard));
        const cx = cMid[i];
        if (dx !== 0) {
            const col = cCol[i] + dx;
            if (col < 0 || col > 2) return false;
            let best = -1, bd = 1000000;
            for (let j = 0; j < cCount; j++) {
                if (cCol[j] !== col) continue;
                const dd = Math.abs(cMid[j] - cx);
                if (dd < bd) { bd = dd; best = j; }
            }
            if (best < 0 || best === i) return false;
            wCard = best;
            return true;
        }
        // Same column: pick the nearest card above/below the current one.
        let best = -1, bd = 1000000;
        for (let j = 0; j < cCount; j++) {
            if (cCol[j] !== cCol[i]) continue;
            const gap = cMid[j] - cx;
            if (dy > 0 ? gap <= 1 : gap >= -1) continue;
            const dd = Math.abs(gap);
            if (dd < bd) { bd = dd; best = j; }
        }
        if (best < 0) return false;
        wCard = best;
        return true;
    }
    property bool prompt: false          // "Open in browser?" dialog is up
    property int promptSel: 0            // 0 = Open, 1 = Cancel
    signal linkOpened()
    readonly property int newsIdx: (inContent && explore) ? wCard : 0       // viii-store
    readonly property var newsCur: (explore && News.items.length > 0) ? News.items[Math.min(newsIdx, News.items.length - 1)] : null
    readonly property url newsSrc: newsCur ? News.src(newsCur.img) : ""

    // ---- viii-store: pane cursor, Enter action, enter/leave ----
    function pNav(dx, dy) {                        // move the pane cursor by geometry; false = nothing there
        const g = wall ? wallGrid : exploreGrid;
        const n = g.nextIdx(wCard, dx, dy);
        if (n < 0) return false;
        wCard = n;
        return true;
    }
    function cNav(dx, dy) { return paneOn ? pNav(dx, dy) : wNav(dx, dy); }
    function paneAct() {                           // Enter on a focused pane
        if (explore) {
            if (newsCur) { promptSel = 0; prompt = true; }
            return;
        }
        if (!wall) return;
        if (wCard === wallGrid.browseIdx) { storeRequested(); return; }
        const p = wCard < Wall.recent.length ? Wall.recent[wCard] : "";
        if (p !== "" && p !== Wall.current && !Wall.busy) Wall.apply(p);
    }
    function down() {                    // from a tile into its content cards
        if (inContent) { cNav(0, 1); return true; }
        if ((welcome || appPage || paneReady) && zoom > 0.99) {
            wCard = (wall && Wall.recent.length === 0) ? wallGrid.browseIdx : 0;
            inContent = true;
            return true;
        }
        return false;
    }
    function up(force) {                 // from the cards back to the tile
        if (inContent) { if (!force && cNav(0, -1)) return true; inContent = false; return true; }
        if (!inCards) return false;
        inCards = false;
        prompt = false;
        return true;
    }
    function clickCard(i) {
        if (!paneReady || zoom < 0.99) return;
        if (inContent && wCard === i) activate();
        else { wCard = i; inContent = true; }
    }
    function openCurrent() {
        const it = newsCur;
        if (!it) return;
        const l = String(it.link);
        if (l.indexOf("https://") !== 0 && l.indexOf("http://") !== 0) return;
        Quickshell.execDetached(["xdg-open", l]);
        linkOpened();
    }
    function pick(sel) {
        prompt = false;
        if (sel === 0) openCurrent();
    }
    function promptKey(e) {
        switch (e.key) {
        case Qt.Key_Left: promptSel = 0; break;
        case Qt.Key_Right: promptSel = 1; break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: pick(promptSel); break;
        case Qt.Key_Escape: prompt = false; break;
        default: break;
        }
        e.accepted = true;
    }

    readonly property real topSum: {
        // only the visible home page shows this; hidden pages must not walk the whole
        // app list every time ScreenTime bumps its revision, or while the hub is down
        if (!root.visible || !root.shown) return 0;
        void ScreenTime.revision;
        let m = 0;
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            if (e && e.isLibrary !== true && e.isWall !== true && e.isWelcome !== true && e.isExplore !== true) m = Math.max(m, ScreenTime.sum(e, 7));
        }
        return m;
    }

    // ---- geometry: tile i's size/position as a function of the animated focus f ----
    function tent(j) { return Math.max(0, 1 - Math.abs(j - f)); }
    function tsum(i) {                     // sum of tent(j) for j < i
        const k = Math.floor(f);
        const fr = f - k;
        if (i <= k) return 0;
        if (i === k + 1) return 1 - fr;
        return 1;
    }
    readonly property real scrollOff: {
        const fr = f - Math.floor(f);
        return f * (small + gap) + d2 * zEff * fr * (1 - fr);
    }
    function wOf(i) { return small + d * zEff * tent(i); }
    function xOf(i) { return padL - selMargin * zEff + i * (small + gap) + d2 * zEff * tsum(i) + selMargin * zEff * tent(i) - scrollOff; }
    function stage(i) {                    // staggered entrance, 0..1
        // the whole row slides in together; only a very slight stagger (staggerMs per tile) ripples through it
        const p = Math.max(0, Math.min(1, (intro - Math.min(i, 9) * staggerMs / 1000) / 0.55));
        return 1 - Math.pow(1 - p, 3);
    }

    Behavior on f {
        enabled: root.animateF
        NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    // ---- intro timeline: slide in (equal small tiles) -> rest (holdMs) -> the focused tile zooms (zoomMs) ----
    readonly property int holdMs: 700
    readonly property int zoomMs: 450
    readonly property int staggerMs: 6
    readonly property var zoomCurve: [0.30, 0.0, 0.12, 1.0, 1, 1]          // soft start, long landing
    readonly property real infoZ: Math.max(0, Math.min(1, (zoom - 0.20) / 0.80))   // title and cards arrive during the 2nd part of the zoom
    onIntroChanged: {
        if (introPrev <= 0.001 && intro > 0.001) introSeq.restart();
        introPrev = intro;
    }
    SequentialAnimation {
        id: introSeq
        PropertyAction { target: root; property: "zoom"; value: 0 }
        PauseAnimation { duration: 550 + 9 * root.staggerMs + root.holdMs }
        NumberAnimation {
            target: root; property: "zoom"
            from: 0; to: 1; duration: root.zoomMs
            easing.type: Easing.BezierSpline; easing.bezierCurve: root.zoomCurve
        }
    }

    onCurrentChanged: { f = current; infoAnim.restart(); inCards = false; prompt = false; cardIdx = 0; inContent = false; wCard = 0; }

    function move(dir) {
        if (inContent) return cNav(dir, 0);                                      // viii-reflow
        if (inCards) {
            const m = Math.max(0, Math.min(News.items.length - 1, cardIdx + dir));
            if (m === cardIdx) return false;
            cardIdx = m;
            return true;
        }
        const n = Math.max(0, Math.min(entries.length - 1, current + dir));
        if (n === current) return false;
        current = n;
        return true;
    }
    function startIndex() {                // the tile that is selected when the hub opens: Welcome
        for (let i = 0; i < entries.length; i++) if (entries[i] && entries[i].isWelcome === true) return i;
        return 0;
    }
    function reset() { animateF = false; current = startIndex(); f = current; animateF = true; inCards = false; prompt = false; cardIdx = 0; inContent = false; wCard = 0; }
    function activate() {
        if (root.inContent) {            // viii-store: Explore reads a story, Wallstore applies a wallpaper; Welcome and app cards are display-only
            if (paneOn) paneAct();
            return;
        }
        if (paneOn) { down(); return; }  // no entry step: Enter on the tile does what Down does
        if (cur) launched(cur, padL, rowTop, sel, sel);
    }
    function subtitle(e) {
        if (!e) return "";
        if (e.isWall === true) return "Wallpapers \u00b7 the whole interface follows the one you pick";
        if (e.isLibrary === true) return "Browse every installed app";
        return e.comment || e.genericName || "Application";
    }

    NumberAnimation {
        id: infoAnim
        target: root; property: "infoIn"
        from: 0; to: 1; duration: 380
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out
    }

    Repeater {
        model: root.entries
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property real w: root.wOf(index)
            readonly property real t: root.stage(index)
            readonly property real k: root.tent(index) * root.zEff      // 0 until the zoom (and while the content has focus): no ring, no raised tile, dimmed
            readonly property bool sel: index === root.current
            readonly property real nt: sel ? root.navT : 0              // the selected tile alone flies up to the bar

            x: (root.xOf(index) + (1 - t) * 454) * (1 - nt) + root.headX * nt
            y: (root.rowTop + (1 - k) * 4 + (1 - t) * 26 - root.rowLift * root.navT) * (1 - nt) + root.headY * nt
            width: w * (1 - nt) + root.headS * nt
            height: width
            z: k + (sel ? root.navT * 20 : 0)
            // tiles you have scrolled past stay where they are (dimmed); they only melt away as they leave the left edge
            opacity: t * Math.min(1, Math.max(0, (x + width) / 40)) * (sel ? 1 : (1 - root.rowDim * root.navT))
            visible: x < root.width + 10 && x + width > 0 && opacity > 0.01

            AppTile {
                anchors.fill: parent
                entry: cell.modelData
                dim: 1 - cell.k
                // While a tile's page is open, every tile except the selected one is fully faded out (slot + icon).
                tileFade: cell.sel ? 1 : 1 - root.navT
                slotOpacity: cell.sel ? 1 - root.navT : 1
                ring: 0          // viii-ring-v2: the single floating ring below draws the selection
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { if (cell.index === root.current) root.activate(); else root.current = cell.index; }
            }
        }
    }

    // viii-ring-v2: ONE ring that glides to the selected tile and takes its size and corner radius.
    // It is placed between tile i0 and tile i1 by the animated focus f, so it moves with the row.
    GlassRing {
        id: selRing
        readonly property real out: 3.5
        readonly property int last: Math.max(0, root.entries.length - 1)
        readonly property int i0: Math.max(0, Math.min(last, Math.floor(root.f)))
        readonly property int i1: Math.min(last, i0 + 1)
        readonly property real fr: Math.max(0, Math.min(1, root.f - i0))
        readonly property real tw: root.wOf(i0) * (1 - fr) + root.wOf(i1) * fr
        readonly property real tx: root.xOf(i0) * (1 - fr) + root.xOf(i1) * fr
        readonly property real st: root.stage(i0) * (1 - fr) + root.stage(i1) * fr
        // viii-ring-v3: the ring is only there while a tile has focus (not top bar, not the Explore cards)
        property real focT: (root.focused && !root.inCards && !root.inContent) ? 1 : 0
        Behavior on focT { NumberAnimation { duration: 180 } }

        x: tx + (1 - st) * 454 - out
        y: root.rowTop + (1 - root.zoom) * 4 + (1 - st) * 26 - out - root.rowLift * root.navT
        width: tw + 2 * out
        height: width
        radius: tw * 0.14 + out
        thickness: 2.5
        shade: true
        z: 3
        trigger: root.current
        opacity: st * root.zoom * focT * Math.min(1, Math.max(0, (tx + tw) / 40))
        visible: root.visible && root.entries.length > 0 && opacity > 0.01 && x < root.width + 10
    }

    // ---- the PS5 label: name under the small tiles, right of the focused tile; on in-page
    // navigation it follows the selected icon up into the bar ----
    Txt {
        readonly property real baseX: root.padL + (root.sel + root.selMargin + 10) * (1 - root.c) + (root.small + 12) * root.c
        readonly property real baseY: root.rowTop + 4 + root.small + 12 - root.rowLift * root.navT
        x: baseX * (1 - root.navT) + (root.headX + root.headS + 16) * root.navT
        y: baseY * (1 - root.navT) + (root.headY + 4) * root.navT
        width: 700
        text: root.cur ? root.cur.name : ""
        font.pixelSize: 24
        font.weight: Font.Light
        opacity: root.infoZ * root.infoIn
        transform: Translate { x: (1 - root.infoIn) * 18 }
    }

    // ---- lower left: big name, subtitle, Open pill ----
    Item {
        id: hero
        x: root.padL
        y: 410
        width: 760
        height: 170
        opacity: (root.welcome || root.explore || root.wall) ? 0 : root.infoZ * root.infoIn * (1 - root.c)
        visible: opacity > 0.01
        transform: Translate { x: (1 - root.infoIn) * 18 }

        Txt {
            width: parent.width
            text: root.cur ? root.cur.name : ""
            font.pixelSize: 54
            font.weight: Font.Bold
        }
        Txt {
            y: 74
            width: parent.width
            text: root.subtitle(root.cur)
            font.pixelSize: 17
            color: Theme.fgDim
        }

        // dark translucent pill, like the PS5 Play button
        Rectangle {
            y: 116
            width: 150; height: 46; radius: 23
            color: Qt.rgba(0.5, 0.5, 0.5, 0.2)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
            Row {
                anchors.centerIn: parent
                spacing: 10
                Txt {
                    text: root.special ? "Browse" : "Open App"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.activate() }
        }
    }

    // regular app pages: screen-time mosaic plus tall widgets (About, System, News)
    AppContent {
        entry: root.cur
        shown: root.shown
        topSum: root.topSum
        x: root.padL
        y: 584 + (root.focusY - 584) * root.c
        lift: root.c
        focusIdx: root.inContent ? root.wCard : -1
        opacity: root.appPage ? root.infoZ * root.infoIn : 0
        visible: opacity > 0.01
        transform: Translate { x: (1 - root.infoIn) * 18 }
    }

    // viii-store: Explore. Eight news panes on the Welcome engine; the picture of the focused story is drawn by Backdrop.
    StoreGrid {
        id: exploreGrid
        mode: "explore"
        shown: root.shown
        x: root.padL
        y: root.restY + (root.focusY - root.restY) * root.c
        lift: root.c
        focusIdx: (root.inContent && root.explore) ? root.wCard : -1
        viewH: 768 - root.focusY
        opacity: root.explore ? root.infoZ * root.infoIn : 0
        visible: opacity > 0.01
        transform: Translate { x: (1 - root.infoIn) * 18 }
        onCardClicked: i => root.clickCard(i)
    }

    // viii-store: Wallstore. The wallpaper in use, the recent ones and "Browse all", on the same engine.
    StoreGrid {
        id: wallGrid
        mode: "wall"
        shown: root.shown
        x: root.padL
        y: root.restY + (root.focusY - root.restY) * root.c
        lift: root.c
        focusIdx: (root.inContent && root.wall) ? root.wCard : -1
        viewH: 768 - root.focusY
        opacity: root.wall ? root.infoZ * root.infoIn : 0
        visible: opacity > 0.01
        transform: Translate { x: (1 - root.infoIn) * 18 }
        onCardClicked: i => root.clickCard(i)
    }

    // viii-store: the daily news fetch and the "Open in browser?" dialog (Explore)
    ExplorePage {
        anchors.fill: parent
        shown: root.shown
        idx: root.newsIdx
        prompt: root.prompt
        promptSel: root.promptSel
        opacity: root.explore ? root.infoZ * root.infoIn : 0
        visible: opacity > 0.01
        transform: Translate { x: (1 - root.infoIn) * 18 }
        onPromptPicked: sel => root.pick(sel)
    }

    // Welcome: the PS5 card grid (three columns, tall and small cards alternating)
    WelcomeGrid {
        shown: root.shown                     // welcome-data: only fetch/animate while the hub is on screen
        x: root.padL
        y: root.restY + (root.focusY - root.restY) * root.c
        lift: root.c
        focusIdx: root.inContent ? root.wCard : -1
        viewH: 768 - root.focusY
        opacity: root.welcome ? root.infoZ * root.infoIn : 0
        visible: opacity > 0.01
        transform: Translate { x: (1 - root.infoIn) * 18 }
    }
}
