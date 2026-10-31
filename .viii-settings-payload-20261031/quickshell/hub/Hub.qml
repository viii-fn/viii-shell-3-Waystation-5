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

    readonly property bool shown: Desk.isEmpty(screen.name) || Desk.summoned
    readonly property var fm: Hyprland.focusedMonitor
    readonly property bool isFocusedMon: fm ? fm.name === screen.name : true

    property real vis: shown ? 1 : 0
    Behavior on vis {
        NumberAnimation {
            duration: win.shown ? Motion.reveal : Motion.hide
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.shown ? Motion.out : Motion.inOut
        }
    }
    visible: shown || vis > 0.002

    // ---- state ----
    property int page: 0                 // 0 = Apps (home row), 1 = Library
    property bool tabsFocus: false
    property bool launching: false
    property real intro: 0
    property real pageT: page
    Behavior on pageT {
        NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    // ---- design-space scaling ----
    readonly property real s: Math.max(0.1, Math.min(width / 1366, height / 768))
    readonly property real dW: width / s
    readonly property real dH: height / s

    readonly property var sel: page === 1 ? lib.cur : home.cur

    function iconUrl(entry) {
        if (!entry || entry.isLibrary === true || entry.isWall === true) return "";
        const p = Apps.iconPath(entry);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }

    function rebuild() {
        home.entries = [{ isWall: true, name: "Wallstore", id: "viii.wallstore" }].concat(Apps.ranked(16)).concat([{ isLibrary: true, name: "Library", id: "viii.library" }]);
        home.reset();
        lib.entries = Apps.alphabetical();
        lib.reset();
    }

    function tint() {
        if (!shown || !isFocusedMon || !sel) return;
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
        function onSettingsRequested() { if (win.isFocusedMon) win.openSettings(); }
    }

    onShownChanged: {
        if (shown) {
            resetTimer.stop();
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
        } else {
            Theme.applyWallpaper();
            resetTimer.restart();
        }
    }

    Component.onCompleted: {
        if (shown) {
            rebuild();
            introAnim.restart();
            warm.restart();
            tint();
        }
        retry.start();
    }

    NumberAnimation { id: introAnim; target: win; property: "intro"; from: 0; to: 1; duration: 1000 }

    // app list can be empty right at startup; try again a few times
    Timer {
        id: retry
        interval: 1200; repeat: true
        property int tries: 0
        onTriggered: {
            if (home.entries.length > 1 || ++tries > 6) { stop(); return; }
            win.rebuild();
        }
    }
    // pre-compute palettes for the home row once it has settled
    Timer {
        id: warm
        interval: 900
        onTriggered: { for (let i = 0; i < home.entries.length; i++) Apps.request(home.entries[i]); }
    }
    Timer {
        id: resetTimer
        interval: Motion.hide + 80
        onTriggered: { win.storeOpen = false; fx.reset(); win.launching = false; launchTimer.stop(); abortTimer.stop(); }
    }
    Timer { id: launchTimer; interval: 700; onTriggered: Desk.summoned = false }
    Timer { id: abortTimer; interval: 2800; onTriggered: { if (win.shown) fx.abort(); win.launching = false; } }

    property bool storeOpen: false
    property bool settingsOpen: false

    function openStore() { storeOpen = true; Theme.applyWallpaper(); }
    function openSettings() {
        settingsOpen = true;
        Theme.applyWallpaper();
        storeOpen = false;
        launching = false;
        settings.categoryIndex = 0;
        settings.rowIndex = 0;
        settings.pane = 0;
        root.forceActiveFocus();
    }
    function closeSettings() {
        settingsOpen = false;
        win.tint();
        root.forceActiveFocus();
    }

    // ---- actions ----
    function launch(entry, x, y, w, h) {
        if (launching || !entry) return;
        if (entry.isWall === true) { openStore(); return; }
        if (entry.isLibrary === true) { page = 1; tabsFocus = false; return; }
        launching = true;
        fx.start(entry, x, y, w, h);
        entry.execute();
        launchTimer.restart();
        abortTimer.restart();
    }

    function horiz(d) {
        if (tabsFocus) page = Math.max(0, Math.min(1, page + d));
        else if (page === 0) home.move(d);
        else lib.move(d, 0);
    }
    function vert(d) {
        if (tabsFocus) { if (d > 0) tabsFocus = false; }
        else if (page === 0) { if (d < 0) tabsFocus = true; }
        else { if (!lib.move(0, d) && d < 0) tabsFocus = true; }
    }
    function choose() {
        if (tabsFocus) tabsFocus = false;
        else if (page === 0) home.activate();
        else lib.activate();
    }
    function back() {
        if (tabsFocus) tabsFocus = false;
        else if (page === 1) page = 0;
        else Desk.summoned = false;
    }

    function handleKey(e) {
        if (settingsOpen) { settings.handleKey(e); return; }
        if (storeOpen) { store.handleKey(e); return; }
        if (launching) { e.accepted = true; return; }
        let handled = true;
        switch (e.key) {
        case Qt.Key_Left: case Qt.Key_H: horiz(-1); break;
        case Qt.Key_Right: case Qt.Key_L: horiz(1); break;
        case Qt.Key_Up: case Qt.Key_K: vert(-1); break;
        case Qt.Key_Down: case Qt.Key_J: vert(1); break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: choose(); break;
        case Qt.Key_Tab: page = 1 - page; tabsFocus = false; break;
        case Qt.Key_Escape: back(); break;
        default: handled = false;
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
            wallpaper: win.page === 0 && !!win.sel && win.sel.isWall === true
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
                opacity: Math.min(1, win.intro * 2.5)
                visible: !win.settingsOpen
                onTabClicked: index => { win.page = index; win.tabsFocus = false; }
                onSettingsClicked: win.openSettings()
            }

            HomePage {
                id: home
                width: parent.width
                height: parent.height
                intro: win.intro
                opacity: 1 - win.pageT
                y: -26 * win.pageT
                visible: opacity > 0.01 && !win.settingsOpen
                onLaunched: (entry, x, y, w, h) => win.launch(entry, x, y, w, h)
            }

            LibraryPage {
                id: lib
                width: parent.width
                height: parent.height
                opacity: win.pageT
                y: 26 * (1 - win.pageT)
                visible: opacity > 0.01 && !win.settingsOpen
                onLaunched: (entry, x, y, w, h) => win.launch(entry, x, y, w, h)
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 72
                y: parent.height - 56
                spacing: 28
                opacity: Math.min(1, win.intro * 2)
                Hint { key: "\u2190 \u2192"; label: "Browse" }
                Hint { key: "Enter"; label: win.page === 0 && win.sel && win.sel.isLibrary === true ? "Browse" : "Open" }
                Hint { key: "Tab"; label: "Switch" }
                Hint { key: "Esc"; label: "Back" }
            }

            WallstorePage {
                id: store
                anchors.fill: parent
                open: win.storeOpen
                onCloseRequested: win.storeOpen = false
            }

            LaunchFx {
                id: fx
                anchors.fill: parent
            }

            SettingsPage {
                id: settings
                anchors.fill: parent
                active: win.settingsOpen
                visible: win.settingsOpen
                enabled: win.settingsOpen
                opacity: win.settingsOpen ? 1 : 0
                onCloseRequested: win.closeSettings()
                onWallstoreRequested: { win.closeSettings(); win.openStore(); }
                onLibraryRequested: { win.closeSettings(); win.page = 1; win.tabsFocus = false; }
            }
        }
    }
}
