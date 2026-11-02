// viii-ring-v2
import QtQuick
import QtQuick.Shapes

// The PS5 selection ring.
//  * a thin band whose gradient runs left -> right (bright at the left, fading to the right)
//  * every time the ring is shown or `trigger` changes, a bright band sweeps left -> right across the border
//    while its strength fades up and then fully down, after which the ring stays static
//  * `shade: true` adds a faint inner shade that fades up and down every ~5.5 s
// A band is a big rounded rectangle with a smaller one cut out (odd-even fill), because a path stroke cannot
// carry a gradient. Only opacity / position numbers animate (no offscreen buffers).
Item {
    id: root
    property real radius: 16            // outer radius
    property real thickness: 2.5
    property bool shade: false          // inner shade that pulses on a slow timer
    property int trigger: 0             // change it to replay the intro sweep
    property bool animated: true

    // ---- tuning (design values, change here) ----
    readonly property int sweepMs: 1400         // band travels left -> right
    readonly property int fadeUpMs: 600         // band strength 0 -> 1
    readonly property int fadeDownMs: 800       // band strength 1 -> 0
    readonly property int shadePauseMs: 5500    // time between shade pulses
    readonly property real shadePeak: 0.10      // shade strength at the top of a pulse

    property real amp: 0                // 0..1 strength of the sweeping band
    property real pos: -0.3             // -0.3..1.3 position of the band along the width
    property real pulse: 0              // 0..1 shade strength

    readonly property real outerR: Math.max(0, Math.min(radius, Math.min(width, height) / 2))
    readonly property real th: thickness
    readonly property real innerR: Math.max(0, outerR - th)

    function play() {
        if (!animated) return;
        intro.restart();
    }
    onVisibleChanged: if (visible) play()
    onTriggerChanged: play()
    Component.onCompleted: if (visible) play()

    ParallelAnimation {
        id: intro
        NumberAnimation { target: root; property: "pos"; from: -0.3; to: 1.3; duration: root.sweepMs; easing.type: Easing.InOutSine }
        SequentialAnimation {
            NumberAnimation { target: root; property: "amp"; from: 0; to: 1; duration: root.fadeUpMs; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "amp"; to: 0; duration: root.fadeDownMs; easing.type: Easing.InOutCubic }
        }
    }

    SequentialAnimation {
        running: root.shade && root.visible && root.animated
        loops: Animation.Infinite
        PauseAnimation { duration: root.shadePauseMs }
        NumberAnimation { target: root; property: "pulse"; from: 0; to: 1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "pulse"; to: 0; duration: 900; easing.type: Easing.InOutSine }
    }

    // inner shade (inside the band)
    Rectangle {
        visible: root.shade && opacity > 0.005
        anchors.fill: parent
        anchors.margins: root.th
        radius: root.innerR
        color: "white"
        opacity: root.shadePeak * root.pulse
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
}
