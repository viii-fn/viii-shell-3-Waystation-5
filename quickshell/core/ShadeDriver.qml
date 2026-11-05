import QtQuick
import "."

// Advances Shade.phase forever with a single animation for the whole shell.
// Created once in shell.qml, next to ThemeDriver. Nothing here renders.
Item {
    visible: false
    width: 0
    height: 0

    NumberAnimation {
        target: Shade
        property: "phase"
        from: 0
        to: 1
        duration: Shade.cycleMs
        loops: Animation.Infinite
        easing.type: Easing.Linear
        running: true
        paused: Shade.users === 0
    }
}
