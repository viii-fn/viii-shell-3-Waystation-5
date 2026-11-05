import QtQuick
import Quickshell
import "../core"

// viii-store: the Explore and Wallstore content screens, built on the same engine as WelcomeGrid.
// HomePage drives `lift` (its animated `c`) and `focusIdx`: Down enters, the selected tile's icon lifts into
// the top bar, the panes rise to HomePage.focusY and one GlassRing glides between them. There is no entry
// step: no Open button, no separate page. Eight panes in different grid sizes, fitted to the visible screen:
//
//   explore   lead (wide, full row) | tall + small      wallpapers   tall + small | current (wide, full row)
//   row 2     tall+small | small+tall | full row        row 2        full row | small+tall | tall + Browse all
//
// Row 2 peeks at the bottom edge at rest and is reached with Down; the grid scrolls so row 2 ends at the
// bottom of the visible area (HomePage.focusY..768).
//
// Data rules (2 GB RAM): nothing is decoded while the grid is hidden (the Repeater is empty), pictures use
// sourceSize, the wallpaper folder is rescanned once, 2 s after the grid appears. News is fetched by ExplorePage.
Item {
    id: root
    property string mode: "explore"        // "explore" (news panes) or "wall" (wallpaper panes)
    property bool shown: true
    readonly property bool active: shown && visible
    property real lift: 0                  // 0 = resting, 1 = the panes have focus (HomePage.c)
    property int focusIdx: -1              // focused pane while the panes have focus
    property real viewH: 528               // visible height while the panes have focus (HomePage.focusY..768)
    property real scrollY: 0               // row 2 is reached by scrolling the grid up
    signal cardClicked(int i)

    readonly property bool isWall: mode === "wall"
    readonly property real colW: 358
    readonly property real gutter: 23
    readonly property real tall: 233
    readonly property real small: 108
    readonly property real rowGap: 17
    readonly property real rowH: tall + rowGap + small            // 358
    readonly property real row2Y: rowH + 23                       // 381
    readonly property real contentH: row2Y + rowH                 // 739
    readonly property real wide: 2 * colW + gutter                // 739
    readonly property real col1: colW + gutter                    // 381
    readonly property real col2: 2 * (colW + gutter)              // 762
    readonly property int browseIdx: 7                            // wallpapers: the "Browse all" pane
    readonly property int count: 8
    width: 3 * colW + 2 * gutter
    height: contentH

    // pane rectangles (design px, relative to the grid)
    readonly property var gx: isWall ? [col1, 0, 0, 0, col1, col1, col2, col2] : [0, col2, col2, 0, 0, col1, col1, col2]
    readonly property var gy: isWall ? [0, 0, tall + rowGap, row2Y, row2Y, row2Y + small + rowGap, row2Y, row2Y + tall + rowGap]
                                     : [0, 0, tall + rowGap, row2Y, row2Y + tall + rowGap, row2Y, row2Y + small + rowGap, row2Y]
    readonly property var gw: [wide, colW, colW, colW, colW, colW, colW, colW]
    readonly property var gh: isWall ? [rowH, tall, small, rowH, small, tall, tall, small]
                                     : [rowH, tall, small, tall, small, small, tall, rowH]

    function topOf(i) { return gy[i] - scrollY; }
    function rowOf(i) { return gy[i] >= row2Y ? 1 : 0; }
    readonly property real row2Scroll: Math.max(0, contentH - viewH)

    // a pane exists when there is something to show in it
    function valid(i) {
        if (i < 0 || i >= count) return false;
        if (isWall) return i === browseIdx || i < Wall.recent.length;
        return i < News.items.length;
    }

    // Move the cursor by geometry: the nearest valid pane in that direction that shares some of the row
    // (or column) with the current one; ties go to the one whose centre is closest. -1 = nothing there.
    function nextIdx(from, dx, dy) {
        const f = Math.max(0, Math.min(count - 1, from));
        const x0 = gx[f], x1 = gx[f] + gw[f], y0 = gy[f], y1 = gy[f] + gh[f];
        let best = -1, bs = 1000000;
        for (let j = 0; j < count; j++) {
            if (j === f || !valid(j)) continue;
            const jx0 = gx[j], jx1 = gx[j] + gw[j], jy0 = gy[j], jy1 = gy[j] + gh[j];
            let gap, over, off;
            if (dx !== 0) {
                gap = dx > 0 ? jx0 - x1 : x0 - jx1;
                over = Math.min(y1, jy1) - Math.max(y0, jy0);
                off = Math.abs((jy0 + jy1) / 2 - (y0 + y1) / 2);
            } else {
                gap = dy > 0 ? jy0 - y1 : y0 - jy1;
                over = Math.min(x1, jx1) - Math.max(x0, jx0);
                off = Math.abs((jx0 + jx1) / 2 - (x0 + x1) / 2);
            }
            if (gap < -1 || over <= 0) continue;
            const s = gap * 4 + off;
            if (s < bs) { bs = s; best = j; }
        }
        return best;
    }

    readonly property string emptyTitle: isWall
        ? (Wall.scanFailed ? "Can\u2019t read the wallpaper folder" : (Wall.scanned ? "No wallpapers yet" : "Looking for wallpapers"))
        : (News.busy ? "Getting today\u2019s news" : "No news yet")
    readonly property string emptyText: isWall
        ? (Wall.scanned ? "Add jpg, png or webp images to ~/Pictures/Wallpapers" : "")
        : (News.busy ? "Linux and PlayStation stories are on their way."
                     : (News.failed ? "Could not reach the news feeds. It will try again in a few minutes." : "Stories appear here once you are online."))

    // ---- wallpaper folder: rescanned once, 2 s after the grid appears (never during the intro) ----
    onActiveChanged: { if (active && isWall) kick.restart(); }
    Timer { id: kick; interval: 2000; onTriggered: { if (root.active) Wall.refresh(); } }

    Behavior on scrollY { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    onFocusIdxChanged: { if (focusIdx >= 0) scrollY = rowOf(focusIdx) === 0 ? 0 : row2Scroll; }
    onLiftChanged: { if (lift < 0.05) scrollY = 0; }

    // ============================= pill row (same as Welcome) =============================
    component Pill: Rectangle {
        id: pill
        property string label: ""
        height: 26
        width: Math.min(pt.implicitWidth, 340) + 40
        radius: 13
        color: Qt.rgba(0.10, 0.11, 0.14, 0.78)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        Rectangle { x: 10; y: 8; width: 10; height: 10; radius: 5; color: Theme.accent }
        Txt { id: pt; x: 28; width: Math.min(implicitWidth, 340); anchors.verticalCenter: parent.verticalCenter; text: pill.label; font.pixelSize: 12 }
    }
    readonly property var focusItem: (!isWall && News.items.length > 0) ? News.items[Math.max(0, Math.min(News.items.length - 1, focusIdx >= 0 ? focusIdx : 0))] : null
    readonly property string pillA: isWall ? (Wall.scanned ? Wall.files.length + " wallpapers" : "Scanning\u2026") : "Linux \u00b7 PlayStation"
    readonly property string pillB: isWall ? (Wall.busy ? "Applying\u2026" : (Wall.error !== "" ? Wall.error : "Now \u00b7 " + Wall.name(Wall.current)))
                                           : (focusItem ? String(focusItem.source) + " \u00b7 " + News.ago(focusItem.ts) : "")
    Row {
        x: 0; y: -36
        spacing: 10
        Pill { label: root.pillA }
        Pill { label: root.pillB; visible: label !== "" }
    }

    // One clipped viewport keeps the scrolled-up row from sliding over the tile row above.
    Item {
        id: viewport
        width: root.width
        height: root.viewH
        clip: true

        Repeater {
            model: root.active ? root.count : 0
            delegate: Item {
                id: card
                required property int index
                readonly property var it: (!root.isWall && index < News.items.length) ? News.items[index] : null
                readonly property string wp: (root.isWall && index < Wall.recent.length && index !== root.browseIdx) ? Wall.recent[index] : ""
                readonly property bool browse: root.isWall && index === root.browseIdx
                readonly property bool has: it !== null || wp !== "" || browse
                readonly property bool placeholder: index === 0 && !has
                readonly property bool nowTag: wp !== "" && wp === Wall.current
                readonly property bool sel: index === root.focusIdx
                readonly property real cw: root.gw[index]
                readonly property real ch: root.gh[index]
                readonly property bool big: ch > 300
                readonly property string actText: browse ? "Enter \u00b7 Open"
                    : (root.isWall ? (nowTag ? "In use" : (Wall.busy ? "Applying\u2026" : "Enter \u00b7 Apply")) : "Enter \u00b7 Read")
                property real kk: sel ? 1 : 0
                Behavior on kk {
                    NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                }

                x: root.gx[index]
                y: root.topOf(index)
                width: cw
                height: ch
                visible: (has || placeholder) && y + height > -2 && y < root.viewH + 2

                // picture panes
                Rectangle { anchors.fill: parent; visible: card.has && !card.browse; color: Qt.rgba(0.07, 0.078, 0.098, 1) }
                Image {
                    anchors.fill: parent
                    source: card.it ? News.src(card.it.img) : (card.wp !== "" ? Wall.src(card.wp) : "")
                    sourceSize.width: Math.round(Math.max(card.cw, card.ch * 1.8) * 1.15)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }
                Rectangle {
                    visible: card.has && !card.browse
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: Math.min(parent.height, card.big ? 170 : (card.ch > 200 ? 120 : 84))
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.84) }
                    }
                }
                // panes that do not have focus dim a little while the panes are in use
                Rectangle {
                    visible: card.has && !card.browse
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.30 * root.lift * (1 - card.kk))
                }
                Rectangle {
                    visible: card.has && !card.browse
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                }

                // glass panes: "Browse all" and the empty state
                GlassSlot { anchors.fill: parent; radius: 8; visible: card.browse || card.placeholder }
                Item {
                    visible: card.browse
                    anchors.fill: parent
                    Txt { x: 18; y: 28; text: "Browse all"; font.pixelSize: 20; font.weight: Font.DemiBold }
                    Txt {
                        x: 18; y: 62
                        width: parent.width - 36
                        text: Wall.scanned ? Wall.files.length + " wallpapers \u00b7 search by name" : "Scanning the folder\u2026"
                        font.pixelSize: 13
                        color: Theme.fgDim
                    }
                }
                Column {
                    visible: card.placeholder
                    anchors.centerIn: parent
                    width: parent.width - 60
                    spacing: 8
                    Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.emptyTitle; font.pixelSize: 24; font.weight: Font.Bold }
                    Txt {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: text !== ""
                        text: root.emptyText
                        font.pixelSize: 15
                        color: Theme.fgDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                    }
                }

                // tag, top left: the story's group, or "Now" on the wallpaper in use
                Rectangle {
                    x: 8; y: 8
                    visible: card.has && !card.browse && tagTxt.text !== ""
                    width: tagTxt.width + 14
                    height: 20
                    radius: 10
                    color: card.nowTag ? Theme.accent : Qt.rgba(0.07, 0.078, 0.098, 0.88)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.16)
                    Txt {
                        id: tagTxt
                        anchors.centerIn: parent
                        text: card.nowTag ? "Now" : (card.it ? String(card.it.group) : "")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: card.nowTag ? Theme.accentText : Theme.fg
                    }
                }
                // action label on the focused pane
                Rectangle {
                    anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 8 }
                    width: act.width + 14
                    height: 20
                    radius: 10
                    opacity: card.kk * root.lift
                    visible: opacity > 0.01
                    color: Qt.rgba(1, 1, 1, 0.92)
                    Txt {
                        id: act
                        anchors.centerIn: parent
                        text: card.actText
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#14161a"
                    }
                }

                // text, bottom left
                Column {
                    visible: card.has && !card.browse
                    x: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    width: parent.width - 24
                    spacing: 3
                    Txt {
                        width: parent.width
                        text: card.it ? String(card.it.source) + "  \u00b7  " + News.ago(card.it.ts) : (card.wp !== "" ? "Wallpaper" : "")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.fgDim
                    }
                    Txt {
                        width: parent.width
                        text: card.it ? String(card.it.title) : (card.wp !== "" ? Wall.name(card.wp) : "")
                        font.pixelSize: card.big ? (card.cw > 500 ? 30 : 22) : (card.ch > 200 ? 18 : 14)
                        font.weight: card.big ? Font.Light : Font.Normal
                        wrapMode: Text.WordWrap
                        maximumLineCount: card.big ? 3 : 2
                    }
                    Txt {
                        visible: text !== ""
                        width: parent.width
                        text: (card.it && card.big) ? String(card.it.summary) : ""
                        font.pixelSize: 14
                        color: Theme.fgDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: card.visible
                    onClicked: root.cardClicked(card.index)
                }
            }
        }

        GlassRing {
            id: cardRing
            // Keep the ring on the last focused pane while it fades out.
            property int lastFi: 0
            readonly property int fi: Math.max(0, Math.min(root.count - 1, root.focusIdx >= 0 ? root.focusIdx : lastFi))
            onFiChanged: if (root.focusIdx >= 0) lastFi = fi
            readonly property real out: 3.5
            x: root.gx[fi] - out
            y: root.topOf(fi) - out
            width: root.gw[fi] + 2 * out
            height: root.gh[fi] + 2 * out
            radius: 8 + out
            thickness: 2.5
            shade: true
            trigger: root.focusIdx
            z: 10
            opacity: Math.max(0, Math.min(1, (root.lift - 0.35) / 0.65))
            visible: opacity > 0.01 && root.active
            // During a row switch the ring follows scrollY directly (already animated); a second y animation
            // on top of it would make the ring lag. Within a row scrollY is settled, so the ring glides.
            readonly property bool scrollSettled: (root.rowOf(fi) === 0 && Math.abs(root.scrollY) < 0.01)
                || (root.rowOf(fi) === 1 && Math.abs(root.scrollY - root.row2Scroll) < 0.01)
            Behavior on x { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on y { enabled: root.lift > 0.6 && cardRing.scrollSettled; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on width { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on height { enabled: root.lift > 0.6; NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        }
    }
}
