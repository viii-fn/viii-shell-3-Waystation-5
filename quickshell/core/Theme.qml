pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live colours of the shell. Plain state only (no nested objects), because a Behavior inside a
// singleton segfaults Qt 6.12. The smooth gliding is done by core/ThemeDriver.qml, created once in shell.qml.
//
// Two sources of colour:
//   - the wallpaper palette (~/.cache/viii/theme.json, written by `viii-theme`): the default look
//   - a per-app palette (hub tiles): applyPalette(), while the hub is open on an app
Singleton {
    id: root

    // targets: pages set these (via applyPalette)
    property color tgtAccent: "#7aa2ff"
    property color tgtOn: "#0b1020"
    property color tgtMid: "#18203a"
    property color tgtDeep: "#090b12"

    // animated values: ThemeDriver writes these; everything in the UI binds to them
    property color accent: "#7aa2ff"
    property color accentText: "#0b1020"
    property color mid: "#18203a"
    property color deep: "#090b12"

    readonly property color fg: "#f5f7fb"
    readonly property color fgDim: Qt.rgba(1, 1, 1, 0.62)
    readonly property string fontFamily: {
        const have = Qt.fontFamilies();
        const want = ["Inter", "SF Pro Display", "Noto Sans", "Cantarell", "DejaVu Sans"];
        for (let i = 0; i < want.length; i++) if (have.indexOf(want[i]) >= 0) return want[i];
        return "sans-serif";
    }
    readonly property string iconFont: "Symbols Nerd Font"

    // glass surfaces, tinted by the (gliding) accent, so every card/pill follows the wallpaper palette
    readonly property color glass: Qt.alpha(Qt.lighter(accent, 1.5), 0.10)
    readonly property color glassHi: Qt.alpha(Qt.lighter(accent, 1.5), 0.20)
    readonly property color glassBorder: Qt.alpha(Qt.lighter(accent, 1.5), 0.28)

    // p = { primary, onPrimary, primaryContainer, surface } (see Apps.parse)
    function applyPalette(p) {
        tgtAccent = p.primary;
        tgtOn = p.onPrimary;
        tgtMid = Qt.darker(p.primaryContainer, 1.35);
        tgtDeep = Qt.darker(p.surface, 1.5);
    }

    // ---- wallpaper palette ----
    property var wp: null               // { primary, onPrimary, primaryContainer, surface } once loaded

    function applyWallpaper() {
        if (wp) applyPalette(wp);
    }

    FileView {
        id: wpFile
        path: Quickshell.env("HOME") + "/.cache/viii/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                if (j && j.primary) { root.wp = j; root.applyWallpaper(); }
            } catch (e) {}
        }
    }
}
