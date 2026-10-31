import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../core"

// Home row. The focused tile always sits at the left margin with a fixed focus ring; the row slides
// underneath it. One animated number (f = focus position) drives every tile's size and position.
Item {
    id: root

    property real intro: 1
    property var entries: []
    property int current: 0
    property real f: 0
    property bool animateF: true
    property real infoIn: 1
    signal launched(var entry, real x, real y, real w, real h)

    readonly property real small: 92
    readonly property real sel: 170
    readonly property real gap: 5
    readonly property real padL: 72
    readonly property real cy: 214
    readonly property real d: sel - small
    readonly property real ringCorner: sel * 0.13

    readonly property var cur: (entries && entries.length > 0) ? entries[Math.min(current, entries.length - 1)] : null

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
        return f * (small + gap) + d * fr * (1 - fr);
    }
    function wOf(i) { return small + d * tent(i); }
    function xOf(i) { return padL + i * (small + gap) + d * tsum(i) - scrollOff; }
    function stage(i) {                    // staggered entrance, 0..1
        const p = Math.max(0, Math.min(1, (intro - Math.min(i, 9) * 0.05) / 0.55));
        return 1 - Math.pow(1 - p, 3);
    }

    Behavior on f {
        enabled: root.animateF
        NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    onCurrentChanged: { f = current; infoAnim.restart(); }

    function move(dir) {
        const n = Math.max(0, Math.min(entries.length - 1, current + dir));
        if (n === current) return false;
        current = n;
        return true;
    }
    function reset() { animateF = false; current = 0; f = current; animateF = true; }
    function activate() { if (cur) launched(cur, padL, cy - sel / 2, sel, sel); }
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

            x: root.xOf(index) + (1 - t) * 454
            y: root.cy - w / 4 + (1 - t) * 26
            width: w
            height: w
            opacity: t * Math.min(1, Math.max(0, 1 - (root.f - index)))
            visible: x < root.width + 10 && x + width > -10 && opacity > 0.01

            AppTile {
                anchors.fill: parent
                entry: cell.modelData
                dim: 1 - root.tent(cell.index)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { if (cell.index === root.current) root.activate(); else root.current = cell.index; }
            }
        }
    }

    // ---- info under the tile ----
    Item {
        id: info
        x: root.padL
        y: 346
        width: 900
        opacity: root.intro * root.infoIn
        transform: Translate { x: (1 - root.infoIn) * 18 }

        Txt {
            id: title
            width: parent.width
            text: root.cur ? root.cur.name : ""
            font.pixelSize: 40
            font.weight: Font.Bold
        }
        Txt {
            y: 50
            width: parent.width
            text: root.subtitle(root.cur)
            font.pixelSize: 16
            color: Theme.fgDim
        }

        Rectangle {
            y: 90
            width: 156; height: 48; radius: 24
            color: Theme.fg
            Row {
                anchors.centerIn: parent
                spacing: 10
                Item {
                    width: 14; height: 22
                    Shape {
                        y: 3
                        ShapePath {
                            strokeWidth: -1
                            fillColor: Theme.deep
                            startX: 0; startY: 0
                            PathLine { x: 14; y: 8 }
                            PathLine { x: 0; y: 16 }
                            PathLine { x: 0; y: 0 }
                        }
                    }
                }
                Txt {
                    text: root.cur && (root.cur.isLibrary === true || root.cur.isWall === true) ? "Browse" : "Open"
                    font.pixelSize: 19
                    font.weight: Font.Bold
                    color: Theme.deep
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.activate() }
        }

        // name of the current wallpaper, shown while the Wallstore tile is selected
        Txt {
            y: 176
            opacity: root.cur && root.cur.isWall === true ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            text: "CURRENT WALLPAPER  \u00b7  " + Wall.name(Wall.current)
            font.pixelSize: 12
            font.letterSpacing: 1.6
            color: Theme.fgDim
        }

        InfoCards {
            y: 176
            entry: root.cur
            topSum: root.topSum
            opacity: root.cur && (root.cur.isLibrary === true || root.cur.isWall === true) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }
    }
}
