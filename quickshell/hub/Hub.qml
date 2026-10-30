import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"

// One of these per monitor. It is the "PS5 home screen":
//  - shows by itself when the monitor's active workspace has no windows (base level)
//  - fades away when a window arrives (the app slides in from the right, see hypr/viii.lua)
//  - can be summoned on top of windows (PS button / launcher key)
PanelWindow {
    id: win

    readonly property bool focusedHere: Hyprland.focusedMonitor !== null && screen !== null
                                        && Hyprland.focusedMonitor.name === screen.name
    readonly property bool wantShown: (screen !== null && Desk.isEmpty(screen.name)) || (Desk.summoned && focusedHere)
    readonly property bool overWindows: Desk.summoned && !(screen !== null && Desk.isEmpty(screen.name))

    property real reveal: 0
    property string page: "home"
    property bool tabFocus: false
    property bool launching: false
    property var homeEntries: []
    property var libEntries: []

    readonly property real u: height / 768

    // ---- window setup ----
    visible: reveal > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "viii-hub"
    WlrLayershell.layer: WlrLayer.Top
    // only grab the keyboard on the monitor you're actually on
    WlrLayershell.keyboardFocus: (wantShown && focusedHere) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // while fading out the hub must not eat clicks
    mask: wantShown ? fullMask : noMask
    Region { id: fullMask; item: stage }
    Region { id: noMask }

    Behavior on reveal {
        NumberAnimation {
            duration: win.wantShown ? Motion.reveal : Motion.hide
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.wantShown ? Motion.out : Motion.inOut
        }
    }

    onWantShownChanged: {
        if (wantShown) {
            homeEntries = Apps.ranked(12);
            libEntries = Apps.alphabetical();
            home.reset();
            lib.reset();
            page = "home";
            tabFocus = false;
            reveal = 1;
        } else {
            reveal = 0;
        }
    }

    // once fully hidden, forget the launch
    onRevealChanged: {
        if (reveal < 0.005) {
            launching = false;
            fx.reset();
            giveUp.stop();
        }
    }

    onPageChanged: Qt.callLater(() => (page === "home" ? home : lib).retint())

    Connections {
        target: Desk
        function onLibraryRequested() { if (win.wantShown) { win.page = "library"; win.tabFocus = false; } }
    }

    // ---- navigation ----
    function setPage(p) { page = p; }

    function nav(dx, dy) {
        if (tabFocus) {
            if (dy > 0) { tabFocus = false; return; }
            if (dx !== 0) setPage(dx > 0 ? "library" : "home");
            return;
        }
        if (page === "home") {
            if (dy < 0) { tabFocus = true; return; }
            if (dx !== 0) home.step(dx);
        } else {
            if (dy < 0 && lib.atTop()) { tabFocus = true; return; }
            lib.move(dx, dy);
        }
    }

    function activate() {
        if (tabFocus) { tabFocus = false; return; }
        (page === "home" ? home : lib).activate();
    }

    function back() {
        if (tabFocus) tabFocus = false;
        else if (page === "library") setPage("home");
        else if (Desk.summoned) Desk.summoned = false;
    }

    function launch(entry, item) {
        if (!item || launching) return;
        launching = true;
        const p = item.mapToItem(stage, 0, 0);
        fx.start(p.x, p.y, item.width * item.scale, item.height * item.scale, Apps.paletteFor(entry), Apps.iconPath(entry));
        entry.execute();
        Desk.summoned = false;
        giveUp.restart();
    }

    // app never opened a window: bring the hub back
    Timer {
        id: giveUp
        interval: 9000
        onTriggered: { fx.collapse(); win.launching = false; }
    }

    // ---- content ----
    Item {
        id: stage
        anchors.fill: parent
        opacity: win.reveal
        focus: true

        Keys.onPressed: event => {
            event.accepted = true;
            if (win.launching) return;
            switch (event.key) {
            case Qt.Key_Left:   case Qt.Key_H: win.nav(-1, 0); break;
            case Qt.Key_Right:  case Qt.Key_L: win.nav(1, 0); break;
            case Qt.Key_Up:     case Qt.Key_K: win.nav(0, -1); break;
            case Qt.Key_Down:   case Qt.Key_J: win.nav(0, 1); break;
            case Qt.Key_Return: case Qt.Key_Enter: win.activate(); break;
            case Qt.Key_Escape: case Qt.Key_Backspace: win.back(); break;
            default: event.accepted = false;
            }
        }

        Backdrop {
            anchors.fill: parent
            active: win.reveal > 0.001
            dim: win.overWindows ? 0.9 : 1.0
            iconSource: win.page === "home" ? home.iconSource : lib.iconSource
        }

        TopBar {
            id: top
            anchors.left: parent.left
            anchors.right: parent.right
            u: win.u
            page: win.page
            tabFocus: win.tabFocus
            reveal: win.reveal
            opacity: win.launching ? 0 : win.reveal
            Behavior on opacity { NumberAnimation { duration: 240 } }
        }

        HomePage {
            id: home
            anchors.fill: parent
            entries: win.homeEntries
            active: win.page === "home" && win.wantShown
            rowFocus: !win.tabFocus
            reveal: win.reveal
            opacity: (win.page === "home" && !win.launching) ? 1 : 0
            x: win.page === "home" ? 0 : -60 * win.u
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Behavior on x { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            onLaunchRequested: (entry, tile) => win.launch(entry, tile)
            onLibraryRequested: win.setPage("library")
        }

        LibraryPage {
            id: lib
            anchors.fill: parent
            entries: win.libEntries
            active: win.page === "library" && win.wantShown
            rowFocus: !win.tabFocus
            reveal: win.reveal
            opacity: (win.page === "library" && !win.launching) ? 1 : 0
            x: win.page === "library" ? 0 : 60 * win.u
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Behavior on x { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            onLaunchRequested: (entry, tile) => win.launch(entry, tile)
        }

        // key hints, bottom right
        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 72 * win.u
            anchors.bottomMargin: 34 * win.u
            spacing: 26 * win.u
            opacity: win.launching ? 0 : 0.75 * win.reveal
            Behavior on opacity { NumberAnimation { duration: 240 } }
            Text { text: "Enter  Open"; font.family: Theme.fontFamily; font.pixelSize: 14 * win.u; color: Theme.fg }
            Text { text: "Esc  Back"; font.family: Theme.fontFamily; font.pixelSize: 14 * win.u; color: Theme.fg }
        }

        LaunchFx {
            id: fx
            anchors.fill: parent
            u: win.u
        }
    }
}
