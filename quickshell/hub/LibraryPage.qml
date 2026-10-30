import QtQuick
import "../core"

// "Game Library", PS5 style: every app in one grid. The selected cover pops up and the screen re-tints to it.
Item {
    id: root

    property var entries: []
    property bool active: false
    property bool rowFocus: true
    property real reveal: 1

    signal launchRequested(var entry, Item tile)

    readonly property real u: height / 768
    readonly property real lead: 72 * u
    readonly property real cell: 128 * u
    readonly property real gap: 22 * u
    readonly property int cols: Math.max(1, Math.floor((width - 2 * lead + gap) / (cell + gap)))
    readonly property var currentEntry: entries.length > 0 ? entries[Math.min(grid.currentIndex, entries.length - 1)] : null
    readonly property string iconSource: currentEntry ? "file://" + Apps.iconPath(currentEntry) : ""

    function reset() {
        grid.currentIndex = 0;
        grid.contentY = 0;
    }

    function atTop() { return grid.currentIndex < cols; }

    function move(dx, dy) {
        if (entries.length === 0) return;
        let i = grid.currentIndex + dx + dy * cols;
        i = Math.max(0, Math.min(entries.length - 1, i));
        grid.currentIndex = i;
        reveal_(i);
    }

    // keep the selected row inside the view (smoothly, via the Behavior on contentY)
    function reveal_(i) {
        const rowTop = Math.floor(i / cols) * grid.cellHeight;
        const rowBottom = rowTop + grid.cellHeight;
        if (rowTop < grid.contentY) grid.contentY = rowTop;
        else if (rowBottom > grid.contentY + grid.height) grid.contentY = rowBottom - grid.height;
    }

    function activate() {
        if (currentEntry) launchRequested(currentEntry, grid.itemAtIndex(grid.currentIndex));
    }

    function retint() {
        if (currentEntry) Theme.applyPalette(Apps.paletteFor(currentEntry));
    }

    onCurrentEntryChanged: if (active) retint()
    Connections {
        target: Apps
        function onPalettesChanged() { if (root.active) root.retint(); }
    }

    Column {
        x: root.lead
        y: 104 * root.u
        spacing: 2 * root.u
        opacity: root.reveal
        Text {
            text: "Library"
            font.family: Theme.fontFamily
            font.pixelSize: 34 * root.u
            font.weight: Font.DemiBold
            color: Theme.fg
        }
        Text {
            text: root.currentEntry ? root.currentEntry.name + "  \u00b7  " + root.entries.length + " apps" : ""
            font.family: Theme.fontFamily
            font.pixelSize: 15 * root.u
            color: Theme.fgDim
        }
    }

    GridView {
        id: grid
        anchors.fill: parent
        anchors.topMargin: 190 * root.u
        anchors.leftMargin: root.lead
        anchors.rightMargin: root.lead
        anchors.bottomMargin: 70 * root.u
        cellWidth: root.cell + root.gap
        cellHeight: root.cell + root.gap
        interactive: false
        clip: false
        cacheBuffer: 0
        model: root.entries
        currentIndex: 0

        Behavior on contentY {
            NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        }

        delegate: Item {
            id: cellItem
            required property var modelData
            required property int index
            readonly property bool isCurrent: index === grid.currentIndex
            width: grid.cellWidth
            height: grid.cellHeight
            z: isCurrent ? 5 : 0

            Tile {
                anchors.centerIn: parent
                entry: cellItem.modelData
                u: root.u
                size: root.cell
                focused: cellItem.isCurrent && root.rowFocus && root.active
                scale: cellItem.isCurrent && root.rowFocus ? 1.16 : 1.0
                appear: Math.max(0, Math.min(1, root.reveal * 1.9 - ((index % root.cols) + Math.floor(index / root.cols)) * 0.07))
                onActivated: {
                    if (cellItem.isCurrent) root.activate();
                    else { grid.currentIndex = cellItem.index; root.reveal_(cellItem.index); }
                }
            }
        }
    }
}
