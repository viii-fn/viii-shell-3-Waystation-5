pragma Singleton
import QtQuick
import Quickshell

// Live colours of the shell. Plain state only (no nested objects), because a Behavior inside a
// singleton segfaults Qt 6.12. The smooth gliding is done by core/ThemeDriver.qml, created once in shell.qml.
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
    readonly property string fontFamily: "Inter"
    readonly property string iconFont: "Symbols Nerd Font"

    // p = { primary, onPrimary, primaryContainer, surface } (see Apps.parse)
    function applyPalette(p) {
        tgtAccent = p.primary;
        tgtOn = p.onPrimary;
        tgtMid = Qt.darker(p.primaryContainer, 1.35);
        tgtDeep = Qt.darker(p.surface, 1.5);
    }
}
