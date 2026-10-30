import QtQuick
import "../core"

// Launch effect: the app's tile zooms from its spot to fill the screen. It stays until the hub fades
// (the new window appeared), or fades itself out if nothing opened.
Item {
    id: fx

    property var entry: null
    property bool active: false
    property real sx: 0
    property real sy: 0
    property real sw: 100
    property real sh: 100
    property real cornerR: 20
    property real iconFade: 1
    property real fade: 1

    visible: active
    z: 50

    function start(e, x, y, w, h) {
        zoom.stop();
        entry = e;
        sx = x; sy = y; sw = w; sh = h;
        cornerR = Math.min(w, h) * 0.13;
        iconFade = 1;
        fade = 1;
        active = true;
        zoom.restart();
    }
    function abort() { if (active) out.restart(); }
    function reset() { zoom.stop(); out.stop(); active = false; fade = 1; }

    ParallelAnimation {
        id: zoom
        NumberAnimation { target: fx; property: "sx"; to: 0; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: fx; property: "sy"; to: 0; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: fx; property: "sw"; to: fx.width; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: fx; property: "sh"; to: fx.height; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: fx; property: "cornerR"; to: 0; duration: Motion.launch; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        NumberAnimation { target: fx; property: "iconFade"; to: 0; duration: Motion.launch * 0.6 }
    }

    NumberAnimation {
        id: out
        target: fx; property: "fade"; to: 0; duration: 320
        onFinished: fx.reset()
    }

    AppTile {
        x: fx.sx; y: fx.sy; width: fx.sw; height: fx.sh
        entry: fx.entry
        corner: fx.cornerR
        iconOpacity: fx.iconFade
        opacity: fx.fade
    }
}
