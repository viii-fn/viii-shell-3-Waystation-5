import QtQuick
import QtQuick.Shapes
import "../core"

// PS5 home row. The focused tile sits at the left margin; the row slides underneath it. The name
// sits under the small tiles (right of the focused one), exactly like the PS5; the big name, the
// Open button and the screen-time cards sit lower left. One animated number (f = focus position)
// drives every tile's size and position.
Item {
    id: root

    property real intro: 1
    property real zoom: 1                // 0 = all tiles equal and small, 1 = the focused tile is zoomed (driven by the intro below)
    property real introPrev: 0
    property var entries: []
    property int current: 0
    property real f: 0
    property bool animateF: true
    property real infoIn: 1
    signal launched(var entry, real x, real y, real w, real h)

    // geometry in design pixels, measured from the real PS5 home screen scaled to 1366 wide
    readonly property real small: 80
    readonly property real sel: 135
    readonly property real gap: 4
    readonly property real padL: 128
    readonly property real rowTop: 108
    readonly property real d: sel - small
    // extra space on each side of the selected tile (set by viii-sel-margin.sh)
    readonly property real selMargin: 4
    readonly property real d2: d + 2 * selMargin

    readonly property var cur: (entries && entries.length > 0) ? entries[Math.min(current, entries.length - 1)] : null
    readonly property bool special: cur !== null && (cur.isLibrary === true || cur.isWall === true)

    readonly property real topSum: {
        void ScreenTime.revision;
        let m = 0;
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            if (e && e.isLibrary !== true) m = Math.max(m, ScreenTime.sum(e, 7));
        }
        return m;
    }

    // ---- geometry: tile i's size/position as a function of the animated focus f ----
    function tent(j) { return Math.max(0, 1 - Math.abs(j - f)); }
    function tsum(i) {                     // sum of tent(j) for j < i
        const k = Math.floor(f);
        const fr = f - k;
        if (i <= k) return 0;
        if (i === k + 1) return 1 - fr;
        return 1;
    }
    readonly property real scrollOff: {
        const fr = f - Math.floor(f);
        return f * (small + gap) + d2 * zoom * fr * (1 - fr);
    }
    function wOf(i) { return small + d * zoom * tent(i); }
    function xOf(i) { return padL - selMargin * zoom + i * (small + gap) + d2 * zoom * tsum(i) + selMargin * zoom * tent(i) - scrollOff; }
    function stage(i) {                    // staggered entrance, 0..1
        // the whole row slides in together; only a very slight stagger (staggerMs per tile) ripples through it
        const p = Math.max(0, Math.min(1, (intro - Math.min(i, 9) * staggerMs / 1000) / 0.55));
        return 1 - Math.pow(1 - p, 3);
    }

    Behavior on f {
        enabled: root.animateF
        NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    // ---- intro timeline: slide in (equal small tiles) -> rest (holdMs) -> the focused tile zooms (zoomMs) ----
    readonly property int holdMs: 400
    readonly property int zoomMs: 600
    readonly property int staggerMs: 6
    readonly property var zoomCurve: [0.30, 0.0, 0.12, 1.0, 1, 1]          // soft start, long landing
    readonly property real infoZ: Math.max(0, Math.min(1, (zoom - 0.20) / 0.80))   // title and cards arrive during the 2nd part of the zoom
    onIntroChanged: {
        if (introPrev <= 0.001 && intro > 0.001) introSeq.restart();
        introPrev = intro;
    }
    SequentialAnimation {
        id: introSeq
        PropertyAction { target: root; property: "zoom"; value: 0 }
        PauseAnimation { duration: 550 + 9 * root.staggerMs + root.holdMs }
        NumberAnimation {
            target: root; property: "zoom"
            from: 0; to: 1; duration: root.zoomMs
            easing.type: Easing.BezierSpline; easing.bezierCurve: root.zoomCurve
        }
    }

    onCurrentChanged: { f = current; infoAnim.restart(); }

    function move(dir) {
        const n = Math.max(0, Math.min(entries.length - 1, current + dir));
        if (n === current) return false;
        current = n;
        return true;
    }
    function reset() { animateF = false; current = 0; f = current; animateF = true; }
    function activate() { if (cur) launched(cur, padL, rowTop, sel, sel); }
    function subtitle(e) {
        if (!e) return "";
        if (e.isWall === true) return "Wallpapers \u00b7 the whole interface follows the one you pick";
        if (e.isLibrary === true) return "Browse every installed app";
        return e.comment || e.genericName || "Application";
    }

    NumberAnimation {
        id: infoAnim
        target: root; property: "infoIn"
        from: 0; to: 1; duration: 380
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out
    }

    Repeater {
        model: root.entries
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property real w: root.wOf(index)
            readonly property real t: root.stage(index)
            readonly property real k: root.tent(index) * root.zoom      // 0 until the zoom: no ring, no raised tile, no dimming

            x: root.xOf(index) + (1 - t) * 454
            y: root.rowTop + (1 - k) * 4 + (1 - t) * 26
            width: w
            height: w
            z: k
            // tiles you have scrolled past stay where they are (dimmed); they only melt away as they leave the left edge
            opacity: t * Math.min(1, Math.max(0, (x + width) / 40))
            visible: x < root.width + 10 && x + width > 0 && opacity > 0.01

            AppTile {
                anchors.fill: parent
                entry: cell.modelData
                dim: 1 - cell.k
                ring: cell.k
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { if (cell.index === root.current) root.activate(); else root.current = cell.index; }
            }
        }
    }

    // ---- the PS5 label: name under the small tiles, right of the focused tile ----
    Txt {
        x: root.padL + root.sel + root.selMargin + 10
        y: root.rowTop + 4 + root.small + 12
        width: 700
        text: root.cur ? root.cur.name : ""
        font.pixelSize: 30
        font.weight: Font.Light
        opacity: root.infoZ * root.infoIn
        transform: Translate { x: (1 - root.infoIn) * 18 }
    }

    // ---- lower left: big name, subtitle, Open pill ----
    Item {
        id: hero
        x: root.padL
        y: 410
        width: 760
        height: 170
        opacity: root.infoZ * root.infoIn
        transform: Translate { x: (1 - root.infoIn) * 18 }

        Txt {
            width: parent.width
            text: root.cur ? root.cur.name : ""
            font.pixelSize: 54
            font.weight: Font.Bold
        }
        Txt {
            y: 74
            width: parent.width
            text: root.subtitle(root.cur)
            font.pixelSize: 17
            color: Theme.fgDim
        }

        // dark translucent pill, like the PS5 Play button
        Rectangle {
            y: 116
            width: 150; height: 46; radius: 23
            color: Qt.rgba(0.17, 0.18, 0.21, 0.88)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
            Row {
                anchors.centerIn: parent
                spacing: 10
                Item {
                    width: 14; height: 22
                    Shape {
                        y: 3
                        ShapePath {
                            strokeWidth: -1
                            fillColor: Theme.fg
                            startX: 0; startY: 0
                            PathLine { x: 14; y: 8 }
                            PathLine { x: 0; y: 16 }
                            PathLine { x: 0; y: 0 }
                        }
                    }
                }
                Txt {
                    text: root.special ? "Browse" : "Open"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.activate() }
        }
    }

    // name of the current wallpaper, shown while the Wallstore tile is selected
    Txt {
        x: root.padL
        y: 596
        opacity: (root.cur && root.cur.isWall === true) ? root.infoZ * root.infoIn : 0
        visible: opacity > 0.01
        text: "CURRENT WALLPAPER  \u00b7  " + Wall.name(Wall.current)
        font.pixelSize: 12
        font.letterSpacing: 1.6
        color: Theme.fgDim
    }

    // screen-time cards (the PS5's "Must see" row, per-app screen time instead of trophies)
    InfoCards {
        x: root.padL
        y: 584
        entry: root.cur
        topSum: root.topSum
        opacity: root.special ? 0 : root.infoZ * root.infoIn
        visible: opacity > 0.01
        transform: Translate { x: (1 - root.infoIn) * 18 }
    }
}
