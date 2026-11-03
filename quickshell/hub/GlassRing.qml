// viii-ring-v4
import QtQuick
import QtQuick.Shapes

// The PS5 selection ring.
//  * a thin band whose gradient runs left -> right (bright at the left, fading to the right)
//  * every time the ring is shown or `trigger` changes, a bright band sweeps left -> right across the border
//    while its strength fades up and then fully down, after which the ring stays static
//  * `shade` (on by default): a soft gradient lies ON TOP of whatever the ring surrounds. It fades up, holds,
//    fades down on every new selection, then repeats every shadeRepeatMs while the item stays selected.
// A band is a big rounded rectangle with a smaller one cut out (odd-even fill), because a path stroke cannot
// carry a gradient. Only opacity / position numbers animate (no offscreen buffers).
Item {
    id: root
    property real radius: 16            // outer radius
    property real thickness: 2.5
    property bool shade: true           // gradient shade over the content
    property int trigger: 0             // change it to replay the intro
    property bool animated: true

    // ---- tuning (design values, change here) ----
    readonly property int sweepMs: 1400         // band travels left -> right
    readonly property int fadeUpMs: 600         // band strength 0 -> 1
    readonly property int fadeDownMs: 800       // band strength 1 -> 0
    readonly property int shadeUpMs: 200        // shade 0 -> peak
    readonly property int shadeHoldMs: 1      // shade stays at its peak
    readonly property int shadeDownMs: 1300     // shade peak -> 0
    readonly property int shadeRepeatMs: 5500   // pause before the shade plays again (0 = only on selection)
    readonly property real shadePeak: 1.0       // overall strength of the shade (1 = as designed)

    property real amp: 0                // 0..1 strength of the sweeping band
    property real pos: -0.3             // -0.3..1.3 position of the band along the width
    property real pulse: 0              // 0..1 shade strength

    readonly property real outerR: Math.max(0, Math.min(radius, Math.min(width, height) / 2))
    readonly property real th: thickness
    readonly property real innerR: Math.max(0, outerR - th)

    function play() {
        if (!animated) return;
        cycle.restart();
    }
    function halt() {
        cycle.stop();
        amp = 0;
        pulse = 0;
    }
    onVisibleChanged: { if (visible) play(); else halt(); }
    onTriggerChanged: { if (visible) play(); }
    Component.onCompleted: if (visible) play()

    // one cycle drives the ring sweep AND the shade: they start together and repeat on the same interval
    SequentialAnimation {
        id: cycle
        loops: root.shadeRepeatMs > 0 ? Animation.Infinite : 1
        ParallelAnimation {
            NumberAnimation { target: root; property: "pos"; from: -0.3; to: 1.3; duration: root.sweepMs; easing.type: Easing.InOutSine }
            SequentialAnimation {
                NumberAnimation { target: root; property: "amp"; from: 0; to: 1; duration: root.fadeUpMs; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "amp"; to: 0; duration: root.fadeDownMs; easing.type: Easing.InOutCubic }
            }
            SequentialAnimation {
                NumberAnimation { target: root; property: "pulse"; to: 1; duration: root.shadeUpMs; easing.type: Easing.OutCubic }
                PauseAnimation { duration: root.shadeHoldMs }
                NumberAnimation { target: root; property: "pulse"; to: 0; duration: root.shadeDownMs; easing.type: Easing.InOutSine }
            }
        }
        PauseAnimation { duration: Math.max(1, root.shadeRepeatMs) }
    }

    // one rounded band; `sweep` false = the static gradient, true = the moving highlight on top of it
    component RingBand: Shape {
        id: band
        property bool sweep: false
        property real outerR: 16
        property real th: 2.5
        property real innerR: 13.5
        property real amp: 0
        property real pos: 0
        readonly property real lo: Math.max(0, Math.min(1, pos - 0.22))
        readonly property real mid: Math.max(0, Math.min(1, pos))
        readonly property real hi: Math.max(0, Math.min(1, pos + 0.22))

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: sweep ? amp : 1
        visible: opacity > 0.01

        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: band.width; y2: 0
                GradientStop { position: 0.0;  color: band.sweep ? Qt.rgba(1, 1, 1, 0) : Qt.rgba(1, 1, 1, 0.98) }
                GradientStop { position: band.sweep ? band.lo : 0.5;  color: band.sweep ? Qt.rgba(1, 1, 1, 0) : Qt.rgba(1, 1, 1, 0.52) }
                GradientStop { position: band.sweep ? band.mid : 0.75; color: band.sweep ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(1, 1, 1, 0.30) }
                GradientStop { position: band.sweep ? band.hi : 0.9;  color: band.sweep ? Qt.rgba(1, 1, 1, 0) : Qt.rgba(1, 1, 1, 0.20) }
                GradientStop { position: 1.0;  color: band.sweep ? Qt.rgba(1, 1, 1, 0) : Qt.rgba(1, 1, 1, 0.16) }
            }
            // outer edge
            startX: band.outerR; startY: 0
            PathLine { x: band.width - band.outerR; y: 0 }
            PathArc { x: band.width; y: band.outerR; radiusX: band.outerR; radiusY: band.outerR; direction: PathArc.Clockwise }
            PathLine { x: band.width; y: band.height - band.outerR }
            PathArc { x: band.width - band.outerR; y: band.height; radiusX: band.outerR; radiusY: band.outerR; direction: PathArc.Clockwise }
            PathLine { x: band.outerR; y: band.height }
            PathArc { x: 0; y: band.height - band.outerR; radiusX: band.outerR; radiusY: band.outerR; direction: PathArc.Clockwise }
            PathLine { x: 0; y: band.outerR }
            PathArc { x: band.outerR; y: 0; radiusX: band.outerR; radiusY: band.outerR; direction: PathArc.Clockwise }
            // inner edge (the hole)
            PathMove { x: band.th + band.innerR; y: band.th }
            PathLine { x: band.width - band.th - band.innerR; y: band.th }
            PathArc { x: band.width - band.th; y: band.th + band.innerR; radiusX: band.innerR; radiusY: band.innerR; direction: PathArc.Clockwise }
            PathLine { x: band.width - band.th; y: band.height - band.th - band.innerR }
            PathArc { x: band.width - band.th - band.innerR; y: band.height - band.th; radiusX: band.innerR; radiusY: band.innerR; direction: PathArc.Clockwise }
            PathLine { x: band.th + band.innerR; y: band.height - band.th }
            PathArc { x: band.th; y: band.height - band.th - band.innerR; radiusX: band.innerR; radiusY: band.innerR; direction: PathArc.Clockwise }
            PathLine { x: band.th; y: band.th + band.innerR }
            PathArc { x: band.th + band.innerR; y: band.th; radiusX: band.innerR; radiusY: band.innerR; direction: PathArc.Clockwise }
        }
    }

    RingBand { sweep: false; outerR: root.outerR; th: root.th; innerR: root.innerR }
    RingBand { sweep: true; outerR: root.outerR; th: root.th; innerR: root.innerR; amp: root.amp; pos: root.pos }
    // the gradient shade: a rounded fill inside the band, bright at the left fading to the right.
    // A plain child shape on purpose: no inline component and no custom properties on the Shape itself.
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
                x2: shadeShape.width; y2: 0
                GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.34) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.14) }
                GradientStop { position: 1.0;  color: Qt.rgba(1, 1, 1, 0.04) }
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
