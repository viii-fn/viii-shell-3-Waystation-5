// viii-ring-v8
import QtQuick
import QtQuick.Shapes

// The PS5 selection ring.
//  * ring: fully drawn at all times; a bright band in its conical gradient orbits slowly
//    and forever. There is no wipe-in / fade-out repeat cycle anymore.
//  * shade: a wide soft diagonal band sweeps over the content on selection and then
//    repeats on its own interval. The spin is independent of that interval.
Item {
    id: root
    property real radius: 16            // outer radius
    property real thickness: 2.5
    property bool shade: true           // gradient shade over the content
    property int trigger: 0             // change it to replay the shade sweep
    property bool animated: true

    // ---- tuning (design values, change here) ----
    readonly property int spinMs: 9000          // one full turn of the ring gradient (slow)
    readonly property int shadeUpMs: 10         // shade 0 -> peak
    readonly property int shadeHoldMs: 4        // shade stays at its peak
    readonly property int shadeDownMs: 1300     // shade peak -> 0 (the diagonal sweep)
    readonly property int shadeRepeatMs: 5000   // pause before the shade sweeps again (0 = only on selection)
    readonly property real shadePeak: 1.0       // overall strength of the shade (1 = as designed)
    readonly property real shadeSoft: 0.8       // half-width of the diagonal band (bigger = wider, softer)

    property real spin: 0               // angle of the conical ring gradient
    property real pulse: 0              // 0..1 shade strength
    property real wave: -0.45           // diagonal band position, -shadeSoft .. 1 + shadeSoft

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

    function play() {
        if (!animated) return;
        shadeCycle.restart();
    }
    function halt() {
        shadeCycle.stop();
        pulse = 0;
        wave = -shadeSoft;
    }
    onVisibleChanged: { if (visible) play(); else halt(); }
    onTriggerChanged: { if (visible) play(); }
    Component.onCompleted: if (visible) play()

    // The highlight orbits forever. 360 degrees looks the same as 0, so the loop is seamless.
    NumberAnimation on spin {
        from: 0; to: 360
        duration: root.spinMs
        loops: Animation.Infinite
        running: root.visible && root.animated
        easing.type: Easing.Linear
    }

    // One diagonal shade sweep per appearance / selection change, repeating on the shade interval.
    SequentialAnimation {
        id: shadeCycle
        loops: root.shadeRepeatMs > 0 ? Animation.Infinite : 1
        ParallelAnimation {
            NumberAnimation { target: root; property: "wave"; from: -root.shadeSoft; to: 1 + root.shadeSoft; duration: Math.max(1, root.shadeUpMs + root.shadeHoldMs + root.shadeDownMs); easing.type: Easing.Linear }
            SequentialAnimation {
                NumberAnimation { target: root; property: "pulse"; to: 1; duration: root.shadeUpMs; easing.type: Easing.OutCubic }
                PauseAnimation { duration: root.shadeHoldMs }
                NumberAnimation { target: root; property: "pulse"; to: 0; duration: root.shadeDownMs; easing.type: Easing.InOutSine }
            }
        }
        PauseAnimation { duration: Math.max(1, root.shadeRepeatMs) }
    }

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
