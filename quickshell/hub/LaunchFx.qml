// viii-launch-v1
import QtQuick
import "../core"

// Launch effect, PS5 style: no zoom. The hub UI fades away (Hub.launchT) while the app's icon fades in a little
// right of the centre and slides to the centre. It stays until the hub fades (the new window appeared), or fades
// itself out if nothing opened.
Item {
    id: fx

    property var entry: null
    property bool active: false
    property real inT: 0                 // 0..1 progress of the icon fade-in / slide
    property real fade: 1                // overall opacity (the abort path fades it out)

    // ---- tuning (design px in the 1366x768 space, milliseconds) ----
    readonly property real iconSize: 170         // size of the icon tile
    readonly property real slide: 70             // starts this far right of the centre
    readonly property int delayMs: 140           // lets the UI start fading first
    readonly property int inMs: 460              // icon fade-in + slide time

    visible: active
    z: 50

    // x, y, w, h (where the tile was) are accepted for compatibility and not needed any more
    function start(e, x, y, w, h) {
        enter.stop();
        out.stop();
        entry = e;
        fade = 1;
        inT = 0;
        active = true;
        enter.restart();
    }
    function abort() { if (active) { enter.stop(); out.restart(); } }
    function reset() { enter.stop(); out.stop(); active = false; fade = 1; inT = 0; }

    SequentialAnimation {
        id: enter
        PauseAnimation { duration: fx.delayMs }
        NumberAnimation { target: fx; property: "inT"; from: 0; to: 1; duration: fx.inMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    NumberAnimation {
        id: out
        target: fx; property: "fade"; to: 0; duration: 320
        onFinished: fx.reset()
    }

    AppTile {
        width: fx.iconSize
        height: fx.iconSize
        x: (fx.width - width) / 2 + (1 - fx.inT) * fx.slide
        y: (fx.height - height) / 2
        entry: fx.entry
        opacity: fx.inT * fx.fade
    }
}
