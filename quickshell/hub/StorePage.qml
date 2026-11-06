import QtQuick
import "../core"

// viii-psstore: the Wallstore tab, in the layout the PS5 Store got in April 2026.
//  * It is a tab in the top bar (like PS Store on the console), not a tile in the home row and not a separate page you
//    "enter". L1 / R1 (Tab, Shift+Tab, PageDown, PageUp) switch to it; Hub slides it in.
//  * Large wide tiles in a carousel, the focused one sits at the left margin and the row slides under it (like the home row).
//  * The focused wallpaper is previewed full screen behind the page after a short dwell: the equivalent of the store's
//    trailer that starts playing on the highlighted tile. Hub feeds `previewSrc` into Backdrop's picture layer.
//  * Tags and a one-line description under the focused tile, and a "Browse by collection" ribbon (the console's
//    "browse by mood or genre"): All, New, Recently used, then one chip per sub-folder of the configured wallpaper folder.
//  * Typing searches. Enter sets the wallpaper (the whole UI re-themes from it).
//
// Performance (2 GB RAM): nothing is computed or decoded while the tab is not on screen (`live`); the carousel keeps only
// the tiles near the screen alive (a Loader per tile); one preview picture at a time; the folder is rescanned once, 2 s
// after the tab appears. Only x, y, opacity and colour animate. No clip, no mask, no offscreen buffer.
Item {
    id: root

    property bool shown: true            // the hub is on screen
    property bool active: false          // this tab is the current page
    property bool focused: true          // keyboard focus is on the page (not on the top bar)
    readonly property bool live: shown && active

    // ---- state ----
    property string query: ""
    property int coll: 0                 // selected collection (ribbon chip)
    property int cur: 0                  // focused tile
    property int row: 0                  // 0 = carousel, 1 = ribbon
    property real f: cur                 // animated focus position (tile units)
    Behavior on f { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }

    // ---- geometry (design px; the parent places this page at the top of the 1366x768 space) ----
    readonly property real x0: 96
    readonly property real tileW: 480
    readonly property real tileH: 270
    readonly property real stride: 500
    readonly property real tileY: 150
    readonly property real chipY: 622

    // ---- data ----
    function folderOf(p) {
        const pre = Wall.dir + "/";
        const rel = p.indexOf(pre) === 0 ? p.slice(pre.length) : p;
        const i = rel.indexOf("/");
        return i > 0 ? rel.slice(0, i) : "";
    }
    function extOf(p) { const i = p.lastIndexOf("."); return i > 0 ? p.slice(i + 1).toUpperCase() : ""; }
    function pretty(p) { return Wall.name(p).replace(/_/g, " ").replace(/ +/g, " ").trim(); }
    readonly property real newDays: 30

    // featured order: the one in use, the ones you used before, then the newest files first
    readonly property var ordered: {
        if (!live) return [];
        const have = {};
        for (let i = 0; i < Wall.files.length; i++) have[Wall.files[i]] = true;
        const seen = {};
        const out = [];
        if (Wall.current && have[Wall.current]) { seen[Wall.current] = true; out.push(Wall.current); }
        const h = Wall.history;
        for (let i = 0; i < h.length; i++) {
            const p = h[i];
            if (!seen[p] && have[p]) { seen[p] = true; out.push(p); }
        }
        const rest = Wall.files.filter(p => !seen[p]);
        const a = Wall.added;
        rest.sort((x, y) => (a[y] || 0) - (a[x] || 0));
        return out.concat(rest);
    }

    // ribbon chips
    readonly property var colls: {
        const out = [{ key: "all", label: "All", n: ordered.length }];
        if (!live) return out;
        const now = Date.now() / 1000;
        const a = Wall.added;
        let nNew = 0;
        const folders = {};
        for (let i = 0; i < ordered.length; i++) {
            const p = ordered[i];
            if (now - (a[p] || 0) < newDays * 86400) nNew++;
            const fo = folderOf(p);
            if (fo !== "") folders[fo] = (folders[fo] || 0) + 1;
        }
        if (nNew > 0 && nNew < ordered.length) out.push({ key: "new", label: "New", n: nNew });
        let nUsed = 0;
        const have = {};
        for (let i = 0; i < ordered.length; i++) have[ordered[i]] = true;
        for (let i = 0; i < Wall.history.length; i++) if (have[Wall.history[i]]) nUsed++;
        if (nUsed > 1) out.push({ key: "used", label: "Recently used", n: nUsed });
        const names = Object.keys(folders).sort((x, y) => x.localeCompare(y));
        for (let i = 0; i < names.length && out.length < 12; i++) out.push({ key: "f:" + names[i], label: names[i], n: folders[names[i]] });
        return out;
    }

    readonly property var items: {
        if (!live) return [];
        const c = colls[Math.max(0, Math.min(coll, colls.length - 1))];
        const q = query.toLowerCase();
        const now = Date.now() / 1000;
        const a = Wall.added;
        const used = {};
        for (let i = 0; i < Wall.history.length; i++) used[Wall.history[i]] = true;
        return ordered.filter(p => {
            if (q !== "" && (pretty(p) + " " + folderOf(p)).toLowerCase().indexOf(q) < 0) return false;
            if (c.key === "all") return true;
            if (c.key === "new") return now - (a[p] || 0) < newDays * 86400;
            if (c.key === "used") return !!used[p];
            return folderOf(p) === c.key.slice(2);
        });
    }
    readonly property string sel: items.length > 0 ? items[Math.min(cur, items.length - 1)] : ""
    readonly property bool selIsNew: sel !== "" && (Date.now() / 1000 - (Wall.added[sel] || 0)) < newDays * 86400
    readonly property var tags: {
        if (sel === "") return [];
        const t = [];
        if (sel === Wall.current) t.push("In use");
        if (selIsNew) t.push("New");
        const fo = folderOf(sel);
        if (fo !== "") t.push(fo);
        const e = extOf(sel);
        if (e !== "") t.push(e);
        return t;
    }

    readonly property bool scanning: Wall.files.length === 0 && !Wall.scanned
    readonly property bool scanFailed: Wall.scanFailed && Wall.files.length === 0
    readonly property bool folderEmpty: Wall.scanned && Wall.files.length === 0 && !Wall.scanFailed
    readonly property bool noMatch: Wall.files.length > 0 && items.length === 0
    readonly property bool showStates: live && (scanFailed || folderEmpty || noMatch)

    // ---- preview: the focused wallpaper fills the screen behind the page after a short dwell ----
    property string previewPath: ""
    readonly property url previewSrc: (live && previewPath !== "" && previewPath !== Wall.current) ? Wall.src(previewPath) : ""
    onSelChanged: { infoAnim.restart(); if (live) dwell.restart(); }
    Timer { id: dwell; interval: 320; onTriggered: root.previewPath = root.live ? root.sel : "" }

    onLiveChanged: {
        if (live) { dwell.restart(); kick.restart(); }
        else { previewPath = ""; query = ""; kick.stop(); }
    }
    onActiveChanged: { if (!active) { query = ""; row = 0; } }
    // the folder is rescanned once, 2 s after the tab appears (never during the page slide)
    Timer { id: kick; interval: 2000; onTriggered: { if (root.live) Wall.refresh(); } }

    onCollChanged: { cur = 0; chipScrollTo(coll); }
    onQueryChanged: cur = 0
    onItemsChanged: { if (cur >= items.length) cur = Math.max(0, items.length - 1); }

    // ---- keys (called by Hub) ----
    function move(dx, dy) {                // false = nothing to move to (Hub then goes to the top bar on Up)
        if (dy > 0) { if (row === 0 && colls.length > 1) { row = 1; return true; } return false; }
        if (dy < 0) { if (row === 1) { row = 0; return true; } return false; }
        if (row === 0) {
            const n = Math.max(0, Math.min(items.length - 1, cur + dx));
            if (n === cur) return false;
            cur = n;
            return true;
        }
        const m = Math.max(0, Math.min(colls.length - 1, coll + dx));
        if (m === coll) return false;
        coll = m;
        return true;
    }
    function activate() {
        if (scanFailed || folderEmpty) { Wall.refresh(); return; }
        if (row === 1) { row = 0; return; }
        if (sel !== "" && sel !== Wall.current && !Wall.busy) Wall.apply(sel);
    }
    function back() {                      // true = consumed (Esc closes things in this order, then Hub leaves the tab)
        if (Wall.error !== "") { Wall.error = ""; return true; }
        if (query !== "") { query = ""; return true; }
        if (row === 1) { row = 0; return true; }
        if (coll !== 0) { coll = 0; return true; }
        return false;
    }
    function typeChar(ch) { row = 0; query += ch; }
    function backspace() { query = query.slice(0, -1); }
    function handleKey(e) { e.accepted = false; }

    // ---- ribbon scroll ----
    property real chipScroll: 0
    Behavior on chipScroll { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
    readonly property real ribbonW: 1366 - 2 * x0
    function chipScrollTo(i) {
        const it = chipRep.itemAt(i);
        if (!it) { chipScroll = 0; return; }
        chipScroll = Math.max(0, it.x + it.width + 24 - ribbonW);
    }

    property real infoT: 1
    NumberAnimation { id: infoAnim; target: root; property: "infoT"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
    property int dotN: 0
    Timer { interval: 350; repeat: true; running: Wall.busy && root.live; onTriggered: root.dotN = (root.dotN + 1) % 4 }
    property real pulse: 0.35
    SequentialAnimation on pulse {
        running: root.live && root.scanning
        loops: Animation.Infinite
        NumberAnimation { to: 0.7; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
    }

    // ============================= heading row =============================
    Txt {
        x: root.x0; y: 108
        text: {
            const c = root.colls[Math.max(0, Math.min(root.coll, root.colls.length - 1))];
            return (c ? c.label : "All") + "  \u00b7  " + (root.scanning ? "scanning\u2026" : root.items.length + (root.items.length === 1 ? " wallpaper" : " wallpapers"));
        }
        font.pixelSize: 16
        font.weight: Font.DemiBold
        color: Theme.fgDim
        opacity: root.live ? 1 : 0
    }
    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: root.x0
        y: 102
        height: 28
        width: qTxt.width + 32
        radius: 14
        color: Qt.rgba(0.10, 0.11, 0.14, 0.78)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        opacity: root.query !== "" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Txt { id: qTxt; x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Search  \u00b7  " + root.query; font.pixelSize: 14 }
    }

    // ============================= carousel =============================
    // skeleton tiles while the folder is being scanned
    Repeater {
        model: root.live && root.scanning ? 3 : 0
        delegate: Rectangle {
            required property int index
            x: root.x0 + index * root.stride
            y: root.tileY
            width: root.tileW; height: root.tileH
            radius: 8
            color: Theme.glass
            border.width: 1
            border.color: Theme.glassBorder
            Rectangle { anchors.fill: parent; anchors.margins: 6; radius: 5; color: Theme.glassHi; opacity: root.pulse }
        }
    }

    Repeater {
        model: root.live ? root.items.length : 0
        delegate: Item {
            id: tile
            required property int index
            readonly property string path: root.items[index] !== undefined ? root.items[index] : ""
            readonly property bool curTile: index === root.cur
            // only tiles near the screen get a body (picture, scrim, texts); the rest is an empty Item
            readonly property bool near: x < 1366 + 40 && x + width > -40
            x: root.x0 + (index - root.f) * root.stride
            y: root.tileY
            width: root.tileW
            height: root.tileH
            // tiles that slide off to the left fade out instead of being cut at the screen edge
            opacity: Math.max(0, Math.min(1, (x + width - 30) / 110))
            visible: near && opacity > 0.01
            property real selT: curTile ? 1 : 0
            Behavior on selT { NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }

            Loader {
                anchors.fill: parent
                active: tile.near
                sourceComponent: Item {
                    Rectangle { anchors.fill: parent; radius: 8; color: Theme.glass }
                    Image {
                        id: pic
                        anchors.fill: parent
                        source: Wall.src(tile.path)
                        sourceSize.width: 640
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                    }
                    Txt {
                        anchors.centerIn: parent
                        visible: pic.status === Image.Error
                        text: "Can\u2019t load preview"
                        font.pixelSize: 14
                        color: Theme.fgDim
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 90
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.78) }
                        }
                    }
                    // unfocused tiles dim a little, the focused one is full strength
                    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.30 * (1 - tile.selT)) }
                    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14) }
                    Txt {
                        x: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                        width: parent.width - 32
                        text: root.pretty(tile.path)
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        x: 12; y: 12
                        width: usedLbl.width + 20; height: 24; radius: 12
                        color: Theme.accent
                        visible: tile.path === Wall.current
                        Txt { id: usedLbl; anchors.centerIn: parent; text: "IN USE"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2; color: Theme.accentText }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: tile.visible
                onClicked: { root.row = 0; if (tile.curTile) root.activate(); else root.cur = tile.index; }
            }
        }
    }

    GlassRing {
        id: ring
        readonly property real out: 3.5
        x: root.x0 + (root.cur - root.f) * root.stride - out
        y: root.tileY - out
        width: root.tileW + 2 * out
        height: root.tileH + 2 * out
        radius: 8 + out
        thickness: 2.5
        shade: true
        trigger: root.cur
        z: 5
        opacity: (root.focused && root.row === 0 && root.items.length > 0) ? 1 : 0
        visible: opacity > 0.01 && root.live
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    // "Applying..." on the focused tile
    Rectangle {
        x: root.x0 + root.tileW / 2 - width / 2
        y: root.tileY + root.tileH / 2 - height / 2
        width: 250; height: 48; radius: 24
        color: Theme.glassHi
        border.width: 1
        border.color: Theme.glassBorder
        opacity: (Wall.busy && root.live) ? 1 : 0
        visible: opacity > 0.01
        z: 6
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Row {
            anchors.centerIn: parent
            Txt { text: "Applying wallpaper"; font.pixelSize: 16; font.weight: Font.Bold }
            Txt { width: 22; text: ".".repeat(root.dotN); font.pixelSize: 16; font.weight: Font.Bold }
        }
    }

    // ============================= focused wallpaper: title, one-liner, tags =============================
    Item {
        x: root.x0
        y: root.tileY + root.tileH + 28
        width: 900
        height: 120
        opacity: root.sel !== "" ? root.infoT : 0
        visible: opacity > 0.01 && root.live
        transform: Translate { y: (1 - root.infoT) * 10 }

        Txt {
            width: parent.width
            text: root.sel !== "" ? root.pretty(root.sel) : ""
            font.pixelSize: 36
            font.weight: Font.Bold
        }
        Txt {
            y: 50
            width: parent.width
            text: root.sel === Wall.current ? "The wallpaper in use. The whole interface follows its colours."
                : "Press Enter to set it as your wallpaper. The whole interface re-themes from it."
            font.pixelSize: 17
            color: Theme.fgDim
        }
        Row {
            y: 88
            spacing: 8
            Repeater {
                model: root.tags
                delegate: Rectangle {
                    required property string modelData
                    height: 26
                    width: tg.width + 26
                    radius: 13
                    color: Qt.rgba(0.10, 0.11, 0.14, 0.78)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    Txt { id: tg; x: 13; anchors.verticalCenter: parent.verticalCenter; text: modelData; font.pixelSize: 13; font.weight: Font.DemiBold }
                }
            }
        }
    }

    // ============================= "Browse by collection" ribbon =============================
    Txt {
        x: root.x0; y: root.chipY - 30
        text: "Browse by collection"
        font.pixelSize: 15
        font.weight: Font.DemiBold
        color: Theme.fgDim
        opacity: (root.live && root.colls.length > 1) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    Item {
        x: root.x0 - root.chipScroll
        y: root.chipY
        height: 44
        width: 10
        visible: root.live
        Row {
            spacing: 12
            Repeater {
                id: chipRep
                model: root.live ? root.colls : []
                delegate: Item {
                    id: chip
                    required property var modelData
                    required property int index
                    readonly property bool isSel: index === root.coll
                    readonly property bool hot: isSel && root.row === 1 && root.focused
                    height: 44
                    width: lab.width + (cnt.visible ? cnt.width + 10 : 0) + 40
                    // chips that scroll past the ends of the ribbon fade out instead of being cut
                    opacity: Math.max(0, Math.min(1, (root.ribbonW - (x - root.chipScroll)) / 80, (x + width - root.chipScroll + 10) / 60))
                    visible: opacity > 0.01
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        color: chip.hot ? Theme.fg : (chip.isSel ? Theme.glassHi : Theme.glass)
                        border.width: 1
                        border.color: chip.isSel ? Theme.fg : Theme.glassBorder
                    }
                    Txt {
                        id: lab
                        x: 20; anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.label
                        font.pixelSize: 17
                        font.weight: chip.isSel ? Font.Bold : Font.Medium
                        color: chip.hot ? Theme.deep : Theme.fg
                    }
                    Txt {
                        id: cnt
                        x: 20 + lab.width + 10; anchors.verticalCenter: parent.verticalCenter
                        visible: chip.modelData.key !== "all"
                        text: chip.modelData.n
                        font.pixelSize: 13
                        color: chip.hot ? Qt.alpha(Theme.deep, 0.7) : Theme.fgDim
                    }
                    MouseArea { anchors.fill: parent; onClicked: { root.row = 1; root.coll = chip.index; } }
                }
            }
        }
    }

    // ============================= empty / error / no match =============================
    Item {
        x: root.x0
        y: root.tileY + 40
        width: 700; height: 160
        opacity: root.showStates ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 240 } }
        Txt {
            text: root.scanFailed ? "Can\u2019t read the wallpaper folder"
                : root.folderEmpty ? "No wallpapers yet"
                : "Nothing matches \u201c" + root.query + "\u201d"
            font.pixelSize: 28
            font.weight: Font.Bold
        }
        Txt {
            y: 46
            text: root.scanFailed ? "Check that " + Wall.prettyDir(Wall.dir) + " exists, then press Enter to retry"
                : root.folderEmpty ? "Add jpg, png or webp images to " + Wall.prettyDir(Wall.dir) + ", then press Enter"
                : "Backspace to edit, Esc to clear the search"
            font.pixelSize: 16
            color: Theme.fgDim
        }
        Rectangle {
            y: 94
            width: 130; height: 42; radius: 21
            color: Theme.fg
            visible: !root.noMatch
            Txt { anchors.centerIn: parent; text: "Retry"; font.pixelSize: 16; font.weight: Font.Bold; color: Theme.deep }
            MouseArea { anchors.fill: parent; onClicked: Wall.refresh() }
        }
    }

    // ============================= apply error =============================
    Rectangle {
        id: banner
        readonly property bool showing: Wall.error !== "" && root.live
        property string msg: ""
        x: root.x0
        width: 720; height: 44; radius: 22
        y: showing ? 700 : 724
        opacity: showing ? 1 : 0
        visible: opacity > 0.01
        color: Qt.rgba(0.78, 0.22, 0.22, 0.96)
        z: 6
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 220 } }
        Connections {
            target: Wall
            function onErrorChanged() { if (Wall.error !== "") banner.msg = Wall.error; }
        }
        Txt {
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 40
            elide: Text.ElideRight
            text: banner.msg + "   \u00b7   Esc dismiss"
            font.pixelSize: 14
            color: "white"
        }
    }
}
