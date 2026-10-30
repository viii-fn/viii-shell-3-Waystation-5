pragma Singleton
import QtQuick
import Quickshell

// Every curve and duration in the shell lives here, so the whole UI moves with one "feel".
// The same bezier shapes are declared on the Hyprland side (hypr/viii.lua), so windows and shell move alike.
Singleton {
    // QML wants cubic beziers as [c1x, c1y, c2x, c2y, 1, 1].
    readonly property var out:   [0.22, 1.00, 0.36, 1.00, 1, 1]  // strong ease-out: quick start, long soft landing (PS5 selection feel)
    readonly property var inOut: [0.65, 0.00, 0.35, 1.00, 1, 1]  // symmetric, for things leaving
    readonly property var soft:  [0.16, 1.00, 0.30, 1.00, 1, 1]  // extra gentle, for colour / background changes

    readonly property int focus: 300    // tile grows / shrinks
    readonly property int scroll: 460   // row slides to the next tile
    readonly property int tint: 700     // whole screen re-tints to the selected app
    readonly property int reveal: 720   // hub appears
    readonly property int hide: 380     // hub leaves
    readonly property int launch: 540   // tile zooms to fill the screen
}
