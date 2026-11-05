import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../settings"

// One hub per monitor. A layer-shell window that is shown when the monitor's workspace is empty
// (base layer) or when summoned. Design space is 1366x768, scaled uniformly to the actual screen.
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "viii-hub"
    WlrLayershell.keyboardFocus: (win.shown && win.isFocusedMon) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Computed explicitly, not as an inline binding: `screen` is assigned while the layer
    // surface maps, which made the direct binding re-enter itself (binding-loop warning).
    property bool shown: false
    property bool emptyDesk: false
    function syncShown() {
        const n = win.screen ? win.screen.name : "";
        const empty = Desk.isEmpty(n);
        win.emptyDesk = empty;
        win.shown = empty || Desk.summoned;
    }
    onScreenChanged: syncShown()
    readonly property var fm: Hyprland.focusedMonitor
    readonly property bool isFocusedMon: fm ? fm.name === screen.name : true

    property real vis: shown ? 1 : 0
    Behavior on vis {
        enabled: win.booted
        NumberAnimation {
            duration: win.shown ? Motion.reveal : Motion.hide
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.shown ? Motion.out : Motion.inOut
        }
    }
    // false only during Component.onCompleted, so the first shown state snaps in
    // instead of fading the whole hub in on every shell start
    property bool booted: false
    // false until the window is fully built; guards the shown handler against Desk
    // signals that can arrive while the component is still being created
    property bool ready: false
    visible: shown || vis > 0.002

    // ---- state ----
    property int page: 0                 // 0 = Apps (home row), 1 = Library
    property bool tabsFocus: false
    property bool gearFocus: false       // top-bar Settings gear has keyboard focus
    property bool launching: false
    // viii-launch: 0..1, the hub UI fades away while an app is launching
    property real launchT: launching ? 1 : 0
    Behavior on launchT { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    property real intro: 0
    property real pageT: page
    Behavior on pageT {
        NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    // ---- design-space scaling ----
    readonly property real s: Math.max(0.1, Math.min(width / 1366, height / 768))
    readonly property real dW: width / s
    readonly property real dH: height / s
    readonly property real vOff: Math.max(0, (dH - 768) / 2)
    readonly property bool appsMissing: home.entries.length <= 3 || libAll.length === 0

    readonly property var sel: page === 1 ? lib.cur : home.cur

    function iconUrl(entry) {
        if (!entry || entry.isLibrary === true || entry.isWall === true || entry.isWelcome === true || entry.isExplore === true) return "";
        const p = Apps.iconPath(entry);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }

    function rebuild() {
        home.entries = [{ isWall: true, name: "Wallstore", id: "viii.wallstore" }, { isExplore: true, name: "Explore", id: "viii.explore" }, { isWelcome: true, name: "Welcome", id: "viii.welcome" }].concat(Apps.ranked(9)).concat([{ isLibrary: true, name: "Library", id: "viii.library" }]);
        home.reset();
        libAll = Apps.alphabetical();
        filterLib();
    }

    // ---- search: type any letter to jump to the Library and filter it ----
    function matchRank(e, q) {
        const n = String(e.name || "").toLowerCase();
        if (n.indexOf(q) === 0) return 0;
        if (n.indexOf(" " + q) >= 0) return 1;
        if (n.indexOf(q) >= 0) return 2;
        const extra = (String(e.genericName || "") + " " + String(e.comment || "") + " " + Array.prototype.join.call(e.keywords || [], " ")).toLowerCase();
        return extra.indexOf(q) >= 0 ? 3 : -1;
    }
    function filterLib() {
        const q = query.trim().toLowerCase();
        if (q === "") { lib.entries = libAll; lib.reset(); return; }
        const hits = [];
        for (let i = 0; i < libAll.length; i++) {
            const r = matchRank(libAll[i], q);
            if (r >= 0) hits.push({ e: libAll[i], r: r });
        }
        hits.sort((a, b) => (a.r - b.r) || a.e.name.localeCompare(b.e.name));
        lib.entries = hits.map(h => h.e);
        lib.reset();
    }
    function typeChar(ch) {
        page = 1;
        tabsFocus = false; gearFocus = false; bellFocus = false; searchFocus = false;
        searchOpen = true;
        query = query + ch;
    }
    function openSearch() {
        page = 1;
        tabsFocus = false; gearFocus = false; bellFocus = false; searchFocus = false;
        searchOpen = true;
        root.forceActiveFocus();
    }

    function tint() {
        if (!shown || !isFocusedMon || !sel || settingsOpen) return;
        Apps.request(sel);
        Theme.applyPalette(Apps.paletteFor(sel));
    }
    onSelChanged: tint()
    onIsFocusedMonChanged: tint()

    Connections {
        target: Apps
        function onPalettesChanged() { win.tint(); }
    }
    Connections {
        target: Desk
        function onLibraryRequested() { win.page = 1; win.tabsFocus = false; }
        function onEmptyChanged() { win.syncShown(); }
        function onSummonedChanged() { win.syncShown(); }
        function onHubRequested() {      // viii-hub-root: back to the root page, whatever was open
            win.historyOpen = false;
            win.storeOpen = false;
            if (win.settingsOpen) win.closeSettings();
            win.searchOpen = false;
            win.query = "";
            win.bellFocus = false;
            win.gearFocus = false;
            win.searchFocus = false;
            win.page = 0;
            win.tabsFocus = false;
        }
        function onSettingsRequested() { if (win.isFocusedMon) win.openSettings(); }
        function onWardRequested() {
            if (!win.isFocusedMon) return;
            if (win.historyOpen) win.historyOpen = false; else win.openHistory();
        }
    }

    onShownChanged: {
        if (!ready) return;
        if (shown) initShown();
        else {
            Theme.applyWallpaper();
            resetTimer.restart();
        }
    }

    function initShown() {
        resetTimer.stop();
        bellFocus = false;
        historyOpen = false;
        gearFocus = false;
        rebuild();
        page = 0;
        tabsFocus = false;
        settingsOpen = false;
        launching = false;
        fx.reset();
        intro = 0;
        introAnim.restart();
        warm.restart();
        root.forceActiveFocus();
        tint();
    }

    Component.onCompleted: {
        ready = true;
        const was = shown;
        syncShown();
        if (shown && shown === was) initShown();   // syncShown changed nothing, so no signal ran
        booted = true;
        Apps.visible();
        retry.start();
    }

    NumberAnimation { id: introAnim; target: win; property: "intro"; from: 0; to: 1; duration: 1000 }

    // app list can be empty right at startup; try again a few times
    Timer {
        id: retry
        interval: 700; repeat: true
        property int tries: 0
        onTriggered: {
            if (!win.appsMissing || ++tries > 40) { stop(); return; }
            win.rebuild();
        }
    }
    // pre-compute palettes for the home row once it has settled
    Timer {
        id: warm
        interval: 2600
        onTriggered: { if (win.shown) for (let i = 0; i < home.entries.length; i++) Apps.request(home.entries[i]); }
    }
    Timer {
        id: resetTimer
        interval: Motion.hide + 80
        onTriggered: { win.storeOpen = false; win.historyOpen = false; fx.reset(); win.launching = false; launchTimer.stop(); abortTimer.stop(); }
    }
    Timer { id: launchTimer; interval: 700; onTriggered: Desk.summoned = false }
    Timer { id: abortTimer; interval: 2800; onTriggered: { if (win.shown) fx.abort(); win.launching = false; } }

    property bool storeOpen: false
    property bool historyOpen: false
    property bool bellFocus: false
    property bool settingsOpen: false
    // viii-ring-v3: true while keyboard focus is on the page content (tiles), not on the top bar or a full-screen page
    readonly property bool ringFocus: !tabsFocus && !gearFocus && !bellFocus && !searchFocus && !storeOpen && !historyOpen && !settingsOpen
    property bool searchFocus: false     // top-bar search button has keyboard focus
    property bool searchOpen: false      // the search field is open (Library page)
    property string query: ""
    property var libAll: []              // every app, A-Z; lib.entries is this list filtered by query
    onQueryChanged: filterLib()
    onPageChanged: { if (page === 0) { query = ""; searchOpen = false; searchFocus = false; } else { home.inCards = false; home.inContent = false; home.prompt = false; } }

    function openStore() { storeOpen = true; Theme.applyWallpaper(); }
    function openHistory() {
        historyOpen = true;
        bellFocus = false;
        gearFocus = false;
        storeOpen = false;
        settingsOpen = false;
        launching = false;
        Theme.applyWallpaper();
        root.forceActiveFocus();
    }
    function openSettings() {
        settingsOpen = true;
        Theme.applyWallpaper();
        storeOpen = false;
        launching = false;
        settings.categoryIndex = 0;
        settings.rowIndex = 0;
        settings.pane = 0;
        root.forceActiveFocus();
        settings.forceActiveFocus();
    }
    function closeSettings() {
        settingsOpen = false;
        root.forceActiveFocus();
    }

    // ---- actions ----
    function launch(entry, x, y, w, h) {
        if (launching || !entry) return;
        if (entry.isWelcome === true || entry.isExplore === true) return;
        if (entry.isWall === true) { openStore(); return; }
        if (entry.isLibrary === true) { page = 1; tabsFocus = false; return; }
        launching = true;
        fx.start(entry, x, y + (page === 0 ? home.y : lib.y), w, h);
        entry.execute();
        launchTimer.restart();
        abortTimer.restart();
    }

    function horiz(d) {
        if (tabsFocus) {
            if (gearFocus) { if (d < 0) { gearFocus = false; bellFocus = true; } }
            else if (bellFocus) { if (d < 0) { bellFocus = false; searchFocus = true; } else { bellFocus = false; gearFocus = true; } }
            else if (searchFocus) { if (d < 0) searchFocus = false; else { searchFocus = false; bellFocus = true; } }
            else if (page === 1 && d > 0) searchFocus = true;
            else page = Math.max(0, Math.min(1, page + d));
        }
        else if (page === 0) home.move(d);
        else lib.move(d, 0);
    }
    function vert(d) {
        if (tabsFocus) { if (d > 0) { tabsFocus = false; gearFocus = false; bellFocus = false; searchFocus = false; } }
        else if (page === 0) { if (d > 0) home.down(); else if (!home.up()) tabsFocus = true; }
        else { if (!lib.move(0, d) && d < 0) tabsFocus = true; }
    }
    function choose() {
        if (tabsFocus && searchFocus) { openSearch(); return; }
        if (tabsFocus && bellFocus) { openHistory(); return; }
        if (tabsFocus && gearFocus) { openSettings(); return; }
        if (tabsFocus) tabsFocus = false;
        else if (page === 0) home.activate();
        else lib.activate();
    }
    function back() {
        bellFocus = false;
        gearFocus = false;
        searchFocus = false;
        if (query !== "") query = "";
        else if (searchOpen) searchOpen = false;
        else if (page === 0 && home.inContent) home.up(true);
        else if (page === 0 && home.inCards) home.up();
        else if (tabsFocus) tabsFocus = false;
        else if (page === 1) page = 0;
        else Desk.summoned = false;
    }

    function handleKey(e) {
        if (settingsOpen) { settings.handleKey(e); return; }
        if (historyOpen) { hist.handleKey(e); return; }
        if (storeOpen) { store.handleKey(e); return; }
        if (launching) { e.accepted = true; return; }
        if (page === 0 && home.prompt) { home.promptKey(e); return; }
        let handled = true;
        switch (e.key) {
        case Qt.Key_Left: horiz(-1); break;
        case Qt.Key_Right: horiz(1); break;
        case Qt.Key_Up: vert(-1); break;
        case Qt.Key_Down: vert(1); break;
        case Qt.Key_Return: case Qt.Key_Enter: choose(); break;
        case Qt.Key_Space: if (searchOpen && query !== "") typeChar(" "); else choose(); break;
        case Qt.Key_Backspace: if (searchOpen && query !== "") query = query.slice(0, -1); else handled = false; break;
        case Qt.Key_Tab: page = 1 - page; tabsFocus = false; gearFocus = false; bellFocus = false; searchFocus = false; break;
        case Qt.Key_Escape: back(); break;
        default: {
            const c = e.text.length === 1 ? e.text.charCodeAt(0) : 0;
            if ((e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0 && c >= 32 && c !== 127) typeChar(e.text);
            else handled = false;
        }
        }
        e.accepted = handled;
    }

    // ---- scene ----
    FocusScope {
        id: root
        anchors.fill: parent
        focus: true
        opacity: win.vis
        Keys.onPressed: event => win.handleKey(event)

        Backdrop {
            anchors.fill: parent
            icon: win.iconUrl(win.sel)
            shown: win.shown
            wallpaper: win.settingsOpen || settings.reveal > 0.01 || (win.page === 0 && !!win.sel && (win.sel.isWall === true || win.sel.isWelcome === true))
            baseBehind: win.emptyDesk
            // settings: the wallpaper is dimmed to about 45% brightness (0.55 black-ish overlay)
            dim: (win.settingsOpen || settings.reveal > 0.01) ? 0.55 : 0.28
            scrim: !(win.settingsOpen || settings.reveal > 0.01)
            news: !win.settingsOpen && settings.reveal < 0.01 && win.page === 0 && !!win.sel && win.sel.isExplore === true && home.newsSrc.toString() !== ""
            ghost: !win.settingsOpen && settings.reveal < 0.01
            newsImg: home.newsSrc
        }

        Item {
            id: stage
            width: win.dW
            height: win.dH
            x: (win.width - width) / 2
            y: (win.height - height) / 2
            transformOrigin: Item.Center
            scale: win.s * (1.035 - 0.035 * win.vis)

            TopBar {
                id: bar
                width: parent.width
                page: win.page
                tabsFocus: win.tabsFocus
                gearFocus: win.gearFocus
                bellFocus: win.bellFocus
                searchFocus: win.searchFocus
                searchOpen: win.searchOpen
                query: win.query
                opacity: Math.min(1, win.intro * 2.5) * (1 - settings.reveal) * (1 - win.launchT) * (1 - home.navT)   // viii-header
                y: -12 * home.navT
                visible: opacity > 0.01
                onTabClicked: index => { win.page = index; win.tabsFocus = false; }
                onSettingsClicked: win.openSettings()
                onHistoryClicked: win.openHistory()
                onSearchClicked: win.openSearch()
            }

            HomePage {
                id: home
                width: parent.width
                height: parent.height
                intro: win.intro
                shown: win.shown
                focused: win.ringFocus
                opacity: (1 - win.pageT) * (1 - settings.reveal) * (1 - win.launchT)
                y: win.vOff - 26 * win.pageT - 18 * settings.reveal
                scale: 1 - 0.025 * settings.reveal
                visible: opacity > 0.01
                onLaunched: (entry, x, y, w, h) => win.launch(entry, x, y, w, h)
                onLinkOpened: Desk.summoned = false
            }

            LibraryPage {
                id: lib
                query: win.query
                focused: win.ringFocus
                width: parent.width
                height: parent.height
                opacity: win.pageT * (1 - settings.reveal) * (1 - win.launchT)
                y: 26 * (1 - win.pageT) - 18 * settings.reveal
                scale: 1 - 0.025 * settings.reveal
                visible: opacity > 0.01
                onLaunched: (entry, x, y, w, h) => win.launch(entry, x, y, w, h)
            }

            WallstorePage {
                id: store
                anchors.fill: parent
                open: win.storeOpen
                onCloseRequested: win.storeOpen = false
            }

            NotifHistoryPage {
                id: hist
                anchors.fill: parent
                open: win.historyOpen
                onCloseRequested: win.historyOpen = false
            }

            LaunchFx {
                id: fx
                anchors.fill: parent
            }

            SettingsPage {
                id: settings
                width: 1366
                height: 768
                x: (parent.width - 1366) / 2
                y: (parent.height - 768) / 2
                active: win.settingsOpen
                visible: win.settingsOpen || settings.reveal > 0.01
                enabled: win.settingsOpen
                onCloseRequested: win.closeSettings()
                onWallstoreRequested: { win.closeSettings(); win.openStore(); }
                onLibraryRequested: { win.closeSettings(); win.page = 1; win.tabsFocus = false; }
            }
            Connections {
                target: settings
                function onRevealChanged() {
                    if (!win.settingsOpen && settings.reveal < 0.01) win.tint();
                }
            }
        }
    }
}
