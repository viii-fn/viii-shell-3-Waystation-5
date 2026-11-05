import QtQuick
import "../core"
import "../hub"

// viii-ps5-settings: PS5-style category page.
//   left  : the category's sub-menus (plain text, the brighter one is the selected one);
//   right : the real controls of the selected sub-menu (toggles, sliders, choices, lists, values).
// One GlassRing marks the focus: on the left list, or on a row of the right pane.
Item {
    id: root

    property var category: ({})
    property var items: []
    property var rows: []
    property int itemIndex: 0
    property int currentIndex: 0
    property bool inPane: false
    property string armed: ""
    property bool running: true

    property var valueOf: function(action) { return ""; }
    property var toggleOf: function(action) { return false; }
    property var fractionOf: function(action) { return 0; }
    property var checkedOf: function(action) { return false; }

    signal activated()
    signal itemClicked(int index)
    signal rowClicked(int index)
    signal sliderAt(string action, real fraction)
    signal sliderEnd()

    readonly property real listX: 72
    readonly property real listW: 330
    readonly property real itemH: 74
    readonly property real paneX: 395
    readonly property real paneW: Math.max(0, width - paneX - 51)
    readonly property real panelY: 92
    readonly property real panelH: Math.max(0, height - panelY - 24)
    readonly property real rowGap: 8
    readonly property real out: 3.5

    function hOf(r) { return !r ? 58 : (String(r.kind) === "slider" ? 92 : (r.desc ? 80 : 58)); }

    readonly property int safeIndex: rows.length > 0 ? Math.max(0, Math.min(rows.length - 1, currentIndex)) : 0
    readonly property var cur: rows.length > 0 ? rows[safeIndex] : null
    readonly property var ys: {
        const a = [];
        let y = 0;
        for (let i = 0; i < rows.length; i++) { a.push(y); y += hOf(rows[i]) + rowGap; }
        a.push(y);
        return a;
    }

    // the ring, the rows and the list scroll with the same curve and duration, so they never drift
    property real scrollGoal: 0
    property real scrollY: scrollGoal
    property real selTop: ys[safeIndex] || 0
    property real selH: hOf(cur)
    property real itemPos: itemIndex
    Behavior on scrollY { enabled: root.running; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    Behavior on selTop { enabled: root.running; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    Behavior on selH { enabled: root.running; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    Behavior on itemPos { enabled: root.running; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }

    // viii-fix1: computed from the rows directly. It runs when `rows` changes, before `ys` and
    // `safeIndex` have updated, and a NaN here froze the scroll position (all rows at y = 0).
    function ensureVisible() {
        if (rows.length === 0) { scrollGoal = 0; return; }
        const si = Math.max(0, Math.min(rows.length - 1, currentIndex));
        let top = 0, total = 0;
        for (let i = 0; i < rows.length; i++) {
            if (i === si) top = total;
            total += hOf(rows[i]) + rowGap;
        }
        const bot = top + hOf(rows[si]);
        let g = isFinite(scrollGoal) ? scrollGoal : 0;
        if (top < g) g = top;
        else if (bot > g + panelH - 8) g = bot - panelH + 8;
        scrollGoal = Math.max(0, Math.min(Math.max(0, total - rowGap - panelH + 8), g));
    }
    onSafeIndexChanged: ensureVisible()
    onRowsChanged: ensureVisible()
    onItemIndexChanged: { scrollGoal = 0; Qt.callLater(ensureVisible); }

    component MenuText: Text {
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 16
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    // ---- header: only the category name, like the PS5 ----
    MenuText {
        x: 0; y: 27
        width: root.width
        text: root.category && root.category.title ? root.category.title : ""
        font.pixelSize: 29
    }

    // ---- left: sub-menus ----
    Repeater {
        model: root.items.length
        delegate: Item {
            id: li
            required property int index
            readonly property var entry: root.items[index] || null
            readonly property bool selected: root.itemIndex === index
            x: root.listX
            y: root.panelY + index * root.itemH
            width: root.listW
            height: root.itemH
            MenuText {
                x: 16
                width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                text: li.entry ? String(li.entry.title || "") : ""
                font.pixelSize: 17
                color: li.selected ? Theme.fg : Qt.alpha(Theme.fg, 0.45)
                Behavior on color { ColorAnimation { duration: 160 } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.itemClicked(li.index)
            }
        }
    }
    GlassRing {
        x: root.listX - root.out
        y: root.panelY + root.itemPos * root.itemH + 7 - root.out
        width: root.listW + 2 * root.out
        height: root.itemH - 14 + 2 * root.out
        radius: 3 + root.out
        thickness: 2.5
        shade: true
        trigger: root.itemIndex
        animated: root.running && !root.inPane
        visible: !root.inPane && root.items.length > 0
        onAnimatedChanged: if (animated && visible) play()
        z: 3
    }

    // ---- right: the controls of the selected sub-menu ----
    Item {
        id: pane
        x: root.paneX - 8
        y: root.panelY - 8
        width: root.paneW + 16
        height: root.panelH + 8
        clip: true

        GlassRing {
            x: 8 - root.out
            y: 8 + root.selTop - root.scrollY - root.out
            width: root.paneW + 2 * root.out
            height: root.selH + 2 * root.out
            radius: 3 + root.out
            thickness: 2.5
            shade: true
            trigger: root.safeIndex * 100 + root.itemIndex
            animated: root.running && root.inPane
            visible: root.inPane && root.rows.length > 0
            onAnimatedChanged: if (animated && visible) play()
            z: 3
        }

        Repeater {
            model: root.rows.length
            delegate: Item {
                id: rw
                required property int index
                readonly property var entry: root.rows[index] || null
                readonly property string kind: entry ? String(entry.kind || "info") : "info"
                readonly property string act: entry ? String(entry.action || "") : ""
                readonly property bool sel: root.inPane && root.safeIndex === index
                readonly property bool checked: kind === "choice" ? !!root.checkedOf(act) : false
                readonly property bool hasThumb: !!(entry && entry.thumb)
                readonly property real tx: kind === "choice" ? (hasThumb ? 112 : 58) : 24
                readonly property string val: (kind === "toggle" || kind === "slider") ? "" : String(root.valueOf(act) || "")
                readonly property bool on: kind === "toggle" ? !!root.toggleOf(act) : false
                readonly property real frac: kind === "slider" ? Math.max(0, Math.min(1, Number(root.fractionOf(act)) || 0)) : 0
                readonly property bool armedNow: root.armed !== "" && root.armed === act

                x: 8
                width: root.paneW
                height: root.hOf(entry)
                y: 8 + (root.ys[index] !== undefined ? root.ys[index] : 0) - root.scrollY
                visible: y + height > 0 && y < pane.height
                opacity: root.inPane ? 1 : 0.7
                Behavior on opacity { NumberAnimation { duration: 180 } }

                Rectangle {   // hairline between rows (the ring replaces it on the focused row)
                    x: 24; y: parent.height + root.rowGap / 2
                    width: parent.width - 48; height: 1
                    color: Qt.alpha(Theme.fg, 0.07)
                    visible: !rw.sel
                }

                MenuText {   // check mark of the chosen option
                    x: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✓"
                    font.pixelSize: 18
                    visible: rw.kind === "choice" && rw.checked
                }
                Image {
                    visible: rw.hasThumb
                    x: 58
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40
                    source: rw.hasThumb ? "file://" + encodeURI(String(rw.entry.thumb)) : ""
                    sourceSize.width: 80
                    sourceSize.height: 80
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Column {
                    x: rw.tx
                    y: rw.kind === "slider" ? 14 : (parent.height - implicitHeight) / 2
                    width: rw.width - rw.tx - 24 - (rw.kind === "toggle" ? 70 : 0)
                             - (rw.val !== "" ? Math.min(320, valText.implicitWidth) + 16 : 0)
                    spacing: 4
                    MenuText {
                        width: parent.width
                        text: rw.entry ? String(rw.entry.title || "") : ""
                        font.pixelSize: 17
                    }
                    MenuText {
                        width: parent.width
                        visible: !!(rw.entry && rw.entry.desc)
                        text: rw.entry && rw.entry.desc ? String(rw.entry.desc) : ""
                        font.pixelSize: 13
                        color: Theme.fgDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }
                }

                MenuText {   // value on the right (info rows, actions, choices)
                    id: valText
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(320, implicitWidth)
                    text: rw.val
                    visible: rw.val !== ""
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 16
                    color: rw.armedNow ? Theme.accent : Theme.fgDim
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                Item {   // toggle
                    visible: rw.kind === "toggle"
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54; height: 30
                    Rectangle {
                        anchors.fill: parent
                        radius: 15
                        color: rw.on ? Theme.accent : Theme.glassHi
                        border.width: 1
                        border.color: Theme.glassBorder
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        y: 4
                        x: rw.on ? 28 : 4
                        color: rw.on ? Theme.accentText : Theme.fgDim
                        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                Item {   // slider
                    id: sl
                    visible: rw.kind === "slider"
                    x: 24; y: parent.height - 36
                    width: parent.width - 48
                    height: 30
                    readonly property real knobW: 18
                    readonly property real usable: Math.max(1, width - knobW)
                    Rectangle {
                        id: track
                        x: sl.knobW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: sl.usable; height: 6; radius: 3
                        color: Theme.glassHi
                        Rectangle {
                            height: parent.height; radius: 3
                            width: track.width * rw.frac
                            color: Theme.accent
                            Behavior on width { enabled: !slideArea.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                    }
                    Rectangle {
                        width: sl.knobW; height: sl.knobW; radius: sl.knobW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: sl.knobW / 2 + sl.usable * rw.frac - width / 2
                        color: Theme.fg
                        Behavior on x { enabled: !slideArea.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: slideArea
                        anchors.fill: parent
                        anchors.margins: -8
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        function apply(mx) {
                            root.sliderAt(rw.act, Math.max(0, Math.min(1, (mx - 8 - sl.knobW / 2) / sl.usable)));
                        }
                        onPressed: mouse => apply(mouse.x)
                        onPositionChanged: mouse => { if (pressed) apply(mouse.x); }
                        onReleased: root.sliderEnd()
                        onCanceled: root.sliderEnd()
                    }
                }
                MenuText {   // percent of a slider
                    visible: rw.kind === "slider"
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    y: 14
                    text: String(root.valueOf(rw.act) || "")
                    color: Theme.fgDim
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: rw.kind === "info" ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: root.rowClicked(rw.index)
                }
            }
        }
    }
}
