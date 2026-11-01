import QtQuick
import "../core"

// Library: every app, A-Z, in a grid. The focused tile grows and gets the same white ring as the home row.
Item {
    id: root

    property var entries: []
    property int current: 0
    property string query: ""

    signal launched(var entry, real x, real y, real w, real h)

    readonly property int cols: Math.max(4, Math.round((width - 96) / 180))
    readonly property real cellW: (width - 96) / cols
    readonly property real cellH: 178
    readonly property real tileSize: 124
    readonly property var cur: (entries && entries.length > 0) ? entries[Math.min(current, entries.length - 1)] : null

    property real wantY: 0

    function ensureVisible() {
        const row = Math.floor(current / cols);
        const top = row * cellH;
        const bot = top + cellH;
        let y = wantY;
        if (top < y) y = top;
        else if (bot > y + grid.height) y = bot - grid.height;
        y = Math.max(0, y);
        if (y !== wantY) {
            wantY = y;
            scroll.to = y;
            scroll.restart();
        }
    }
    onCurrentChanged: ensureVisible()

    function reset() { scroll.stop(); wantY = 0; grid.contentY = 0; current = 0; }

    // returns false when the move was blocked (top edge, so the caller can jump to the tabs)
    function move(dx, dy) {
        const n = entries.length;
        if (n === 0) return false;
        const col = current % cols;
        const row = Math.floor(current / cols);
        const lastRow = Math.floor((n - 1) / cols);
        if (dx !== 0) {
            const nc = col + dx;
            const ni = current + dx;
            if (nc < 0 || nc >= cols || ni < 0 || ni >= n) return false;
            current = ni;
            return true;
        }
        if (dy < 0) {
            if (row === 0) return false;
            current = current - cols;
            return true;
        }
        if (dy > 0) {
            if (row >= lastRow) return false;
            current = Math.min(n - 1, current + cols);
            return true;
        }
        return false;
    }

    function activate() {
        if (!cur) return;
        const it = grid.currentItem;
        let px = width / 2 - tileSize / 2, py = height / 2 - tileSize / 2;
        if (it) {
            const p = it.mapToItem(root, 0, 0);
            px = p.x + (it.width - tileSize) / 2;
            py = p.y + 16;
        }
        launched(cur, px, py, tileSize, tileSize);
    }

    NumberAnimation {
        id: scroll
        target: grid; property: "contentY"
        duration: Motion.scroll
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out
    }

    // nothing matched the search
    Txt {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 200
        visible: root.query !== "" && root.entries.length === 0
        text: "No apps match \u201c" + root.query + "\u201d"
        font.pixelSize: 22
        color: Theme.fgDim
    }

    GridView {
        id: grid
        x: 48
        y: 118
        width: root.width - 96
        height: root.height - 118 - 64
        clip: true
        interactive: false
        keyNavigationEnabled: false
        highlightFollowsCurrentItem: false
        cacheBuffer: 360
        cellWidth: root.cellW
        cellHeight: root.cellH
        model: root.entries
        currentIndex: root.current

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool isCur: index === root.current
            width: grid.cellWidth
            height: grid.cellHeight

            AppTile {
                id: tile
                x: (cell.width - root.tileSize) / 2
                y: 16
                width: root.tileSize
                height: root.tileSize
                entry: cell.modelData
                dim: cell.isCur ? 0 : 0.7
                scale: cell.isCur ? 1.1 : 1.0
                Behavior on scale { NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            }
            Rectangle {
                x: tile.x - 7; y: tile.y - 7
                width: tile.width + 14; height: tile.height + 14
                radius: tile.corner + 7
                color: "transparent"
                border.width: 3
                border.color: Theme.fg
                opacity: cell.isCur ? 1 : 0
                scale: tile.scale
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            }
            Txt {
                x: 8; y: 154
                width: cell.width - 16
                horizontalAlignment: Text.AlignHCenter
                text: cell.modelData.name
                font.pixelSize: 14
                font.weight: cell.isCur ? Font.DemiBold : Font.Normal
                color: cell.isCur ? Theme.fg : Theme.fgDim
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { if (cell.isCur) root.activate(); else root.current = cell.index; }
            }
        }
    }
}
