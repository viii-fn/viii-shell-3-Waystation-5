// viii-ring-v8
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import "../core"

// The PS5 selection ring.
//  * ring: fully drawn at all times; a bright band in its conical gradient orbits slowly
//    and forever. There is no wipe-in / fade-out repeat cycle anymore.
//  * shade: a wide soft diagonal band sweeps over the content on the shell-wide interval
//    (core/Shade.qml). The interval is shared and never restarts when the selection moves,
//    so one animation drives every ring. The spin is independent of the interval.
Item {
    id: root
    property real radius: 16            // outer radius
    property real thickness: 2.5
    property bool shade: true           // gradient shade over the content
    property int trigger: 0             // kept for call sites; the shade no longer restarts on selection
    property bool animated: true

    // ---- tuning (design values, change here) ----
    readonly property int spinMs: 9000          // one full turn of the ring gradient (slow)
    readonly property real shadePeak: 1.0       // overall strength of the shade (1 = as designed)
    readonly property real shadeSoft: 0.8       // half-width of the diagonal band (bigger = wider, softer)
    // Shade timing (sweep + interval) lives in core/Shade.qml, shared by every ring.

    property real spin: 0               // angle of the conical ring gradient
    // Shade state comes from the shared clock, so every ring is in phase and no ring
    // owns a timer. Rings that are hidden or not animated add no work.
    // The window check matters: a page can still say visible = true while its layer
    // surface is unmapped (window on a workspace with windows), and then nothing it
    // draws can be seen. A layer window that has never been mapped has no Window at all,
    // which is exactly the startup case where the hub is hidden over normal windows.
    readonly property bool onScreen: !!Window.window && Window.window.visible
    readonly property bool shadeActive: onScreen && visible && animated && shade
    readonly property real pulse: shadeActive ? Shade.pulse : 0
    readonly property real wave: shadeActive ? (Shade.band * (1 + 2 * shadeSoft) - shadeSoft) : -shadeSoft

    // Tell ShadeDriver whether the shared sweep is needed. A plain count keeps the
    // driver alive while any ring is on screen and stops it as soon as the last one goes.
    property bool shadeClaimed: false
    function syncShadeClaim() {
        if (shadeClaimed === shadeActive) return;
        shadeClaimed = shadeActive;
        Shade.users += shadeActive ? 1 : -1;
    }
    onShadeActiveChanged: syncShadeClaim()
    Component.onCompleted: syncShadeClaim()
    Component.onDestruction: if (shadeClaimed) Shade.users -= 1

    readonly property real outerR: Math.max(0, Math.min(radius, Math.min(width, height) / 2))
    readonly property real th: thickness
    readonly property real innerR: Math.max(0, outerR - th)
    readonly property real wLo: Math.max(0, Math.min(1, wave - shadeSoft))
    readonly property real wMid: Math.max(0, Math.min(1, wave))
    readonly property real wHi: Math.max(0, Math.min(1, wave + shadeSoft))
    // Width of the ring's bright -> transparent transition, in gradient angle. It grows
    // gently with the ring size so a big card ring fades as softly as a small button.
    readonly property real ramp: Math.max(0.08, Math.min(0.15, 0.075 + 0.00020 * Math.max(width, height)))
    // brightness of the diagonal band at position t (0..1) when its centre is at w and its half-width is sw;
    // every gradient stop asks this, so a band that is half outside the tile ramps in/out instead of popping
    function bandAlpha(t, w, sw) { return 0.58 * Math.max(0, 1 - Math.abs(t - w) / sw); }
    // ring alpha at gradient position t: 0.95 (bright) outside the gap, 0.33 (about a third
    // of the bright half) across half of the ring, with a smoothstep fade in between.
    function ringAlpha(t) {
        const lo = 0.25, hi = 0.75, low = 0.33;
        if (t >= lo && t <= hi) return low;
        const d = t < lo ? lo - t : t - hi;
        if (d >= root.ramp) return 0.95;
        const x = d / root.ramp;
        return low + (0.95 - low) * x * x * (3 - 2 * x);
    }

    // Kept for existing call sites: the sweep is driven by the shared clock now, so
    // selecting something never restarts it.
    function play() {}
    function halt() {}

    // The highlight orbits forever. 360 degrees looks the same as 0, so the loop is seamless.
    // Paused (not stopped) while the window is unmapped, so it resumes exactly where it was
    // instead of snapping back to the same angle every time the hub reopens.
    NumberAnimation on spin {
        from: 0; to: 360
        duration: root.spinMs
        loops: Animation.Infinite
        running: true
        paused: !root.onScreen || !root.visible || !root.animated
        easing.type: Easing.Linear
    }

    // No per-ring animation here: the sweep is a binding to Shade (core/Shade.qml).

    // the ring: a big rounded rectangle with a smaller one cut out (odd-even fill). The fill is a
    // conical gradient whose angle slowly turns, so a soft bright band travels around the ring.
    Shape {
        id: ringShape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                centerX: ringShape.width / 2
                centerY: ringShape.height / 2
                angle: root.spin
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.00)) }
                GradientStop { position: 0.05; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.05)) }
                GradientStop { position: 0.10; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.10)) }
                GradientStop { position: 0.13; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.13)) }
                GradientStop { position: 0.16; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.16)) }
                GradientStop { position: 0.18; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.18)) }
                GradientStop { position: 0.20; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.20)) }
                GradientStop { position: 0.22; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.22)) }
                GradientStop { position: 0.24; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.24)) }
                GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.25)) }
                GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.75)) }
                GradientStop { position: 0.76; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.76)) }
                GradientStop { position: 0.78; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.78)) }
                GradientStop { position: 0.80; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.80)) }
                GradientStop { position: 0.82; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.82)) }
                GradientStop { position: 0.84; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.84)) }
                GradientStop { position: 0.87; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.87)) }
                GradientStop { position: 0.90; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.90)) }
                GradientStop { position: 0.95; color: Qt.rgba(1, 1, 1, root.ringAlpha(0.95)) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, root.ringAlpha(1.00)) }
            }
            // outer edge
            startX: root.outerR; startY: 0
            PathLine { x: ringShape.width - root.outerR; y: 0 }
            PathArc { x: ringShape.width; y: root.outerR; radiusX: root.outerR; radiusY: root.outerR; direction: PathArc.Clockwise }
            PathLine { x: ringShape.width; y: ringShape.height - root.outerR }
            PathArc { x: ringShape.width - root.outerR; y: ringShape.height; radiusX: root.outerR; radiusY: root.outerR; direction: PathArc.Clockwise }
            PathLine { x: root.outerR; y: ringShape.height }
            PathArc { x: 0; y: ringShape.height - root.outerR; radiusX: root.outerR; radiusY: root.outerR; direction: PathArc.Clockwise }
            PathLine { x: 0; y: root.outerR }
            PathArc { x: root.outerR; y: 0; radiusX: root.outerR; radiusY: root.outerR; direction: PathArc.Clockwise }
            // inner edge (the hole)
            PathMove { x: root.th + root.innerR; y: root.th }
            PathLine { x: ringShape.width - root.th - root.innerR; y: root.th }
            PathArc { x: ringShape.width - root.th; y: root.th + root.innerR; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
            PathLine { x: ringShape.width - root.th; y: ringShape.height - root.th - root.innerR }
            PathArc { x: ringShape.width - root.th - root.innerR; y: ringShape.height - root.th; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
            PathLine { x: root.th + root.innerR; y: ringShape.height - root.th }
            PathArc { x: root.th; y: ringShape.height - root.th - root.innerR; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
            PathLine { x: root.th; y: root.th + root.innerR }
            PathArc { x: root.th + root.innerR; y: root.th; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
        }
    }

    // the shade: a rounded fill inside the ring; a wide soft band of light travels from the top-left corner to the
    // bottom-right corner. A plain child shape: no inline component, no custom properties on the Shape itself.
    Shape {
        id: shadeShape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.pulse * root.shadePeak
        visible: root.shade && opacity > 0.005

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: shadeShape.width; y2: shadeShape.height
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.bandAlpha(0.0, root.wave, root.shadeSoft)) }
                GradientStop { position: root.wLo; color: Qt.rgba(1, 1, 1, root.bandAlpha(root.wLo, root.wave, root.shadeSoft)) }
                GradientStop { position: root.wMid; color: Qt.rgba(1, 1, 1, root.bandAlpha(root.wMid, root.wave, root.shadeSoft)) }
                GradientStop { position: root.wHi; color: Qt.rgba(1, 1, 1, root.bandAlpha(root.wHi, root.wave, root.shadeSoft)) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, root.bandAlpha(1.0, root.wave, root.shadeSoft)) }
            }
            startX: root.th + root.innerR; startY: root.th
            PathLine { x: shadeShape.width - root.th - root.innerR; y: root.th }
            PathArc { x: shadeShape.width - root.th; y: root.th + root.innerR; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
            PathLine { x: shadeShape.width - root.th; y: shadeShape.height - root.th - root.innerR }
            PathArc { x: shadeShape.width - root.th - root.innerR; y: shadeShape.height - root.th; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
            PathLine { x: root.th + root.innerR; y: shadeShape.height - root.th }
            PathArc { x: root.th; y: shadeShape.height - root.th - root.innerR; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
            PathLine { x: root.th; y: root.th + root.innerR }
            PathArc { x: root.th + root.innerR; y: root.th; radiusX: root.innerR; radiusY: root.innerR; direction: PathArc.Clockwise }
        }
    }
}
