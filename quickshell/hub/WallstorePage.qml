import QtQuick
import "../core"

// Wallstore: a store-style page for wallpapers. Opens over the hub like the app store.
// Type to search, arrows to browse, Enter to set the wallpaper (the whole UI re-themes from it), Esc to leave.
// Keys come from Hub.handleKey while the store is open.
// States: scanning (skeleton grid), scan error, empty folder, no search match, per-thumbnail
// loading/error, applying (overlay) and apply error (banner with retry).
Item {
    id: root

    property bool open: false
    signal closeRequested()

    property string query: ""
    property int current: 0
    readonly property int cols: 4
    property bool stagger: false      // staggered tile entrance, only right after opening
    property int dotN: 0
    property real pulse: 0.35

    readonly property bool scanning: Wall.files.length === 0 && !Wall.scanned
    readonly property bool scanFailed: Wall.scanFailed && Wall.files.length === 0
    readonly property bool folderEmpty: Wall.scanned && Wall.files.length === 0 && !Wall.scanFailed
    readonly property bool noMatch: Wall.files.length > 0 && items.length === 0

    readonly property var items: {
        const q = query.toLowerCase();
        return Wall.files.filter(f => q === "" || Wall.name(f).toLowerCase().indexOf(q) >= 0);
    }
    readonly property string sel: items.length > 0 ? items[Math.min(current, items.length - 1)] : ""

    // page enter/leave: fade + slide up
    property real t: open ? 1 : 0
    Behavior on t {
        NumberAnimation {
            duration: root.open ? 340 : 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Motion.out : Motion.inOut
        }
    }
    opacity: t
    visible: opacity > 0.01

    onOpenChanged: {
        if (open) {
            query = ""; current = 0;
            Wall.error = "";
            stagger = true; staggerOff.restart();
            scrollAnim.stop(); grid.contentY = 0;
            Wall.refresh();
            Theme.applyWallpaper();
        }
    }
    Timer { id: staggerOff; interval: 900; onTriggered: root.stagger = false }
    Timer { interval: 350; repeat: true; running: Wall.busy; onTriggered: root.dotN = (root.dotN + 1) % 4 }

    // shared pulse for skeleton tiles
    SequentialAnimation on pulse {
        running: root.open && root.scanning
        loops: Animation.Infinite
        NumberAnimation { to: 0.7; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
    }

    // ---- navigation ----
    NumberAnimation { id: scrollAnim; target: grid; property: "contentY"; duration: 260; easing.type: Easing.OutCubic }
    function ensureVisible() {
        const rowTop = Math.floor(current / cols) * grid.cellHeight;
        let y = grid.contentY;
        if (rowTop < y) y = rowTop;
        else if (rowTop + grid.cellHeight > y + grid.height) y = rowTop + grid.cellHeight - grid.height;
        y = Math.max(0, Math.min(Math.max(0, grid.contentHeight - grid.height), y));
        if (y === grid.contentY) return;
        scrollAnim.stop();
        scrollAnim.to = y;
        scrollAnim.start();
    }
    function resetView() { current = 0; scrollAnim.stop(); grid.contentY = 0; }
    function move(d) {
        const n = items.length;
        if (n === 0) return;
        current = Math.max(0, Math.min(n - 1, current + d));
        ensureVisible();
    }
    function apply() { if (sel !== "") Wall.apply(sel); }

    function handleKey(e) {
        let handled = true;
        switch (e.key) {
        case Qt.Key_Escape:
            if (Wall.error !== "") Wall.error = "";
            else if (query !== "") { query = ""; resetView(); }
            else closeRequested();
            break;
        case Qt.Key_Left: move(-1); break;
        case Qt.Key_Right: move(1); break;
        case Qt.Key_Up: if (current - cols >= 0) move(-cols); break;
        case Qt.Key_Down: move(cols); break;
        case Qt.Key_Return: case Qt.Key_Enter:
            if (scanFailed || folderEmpty) Wall.refresh(); else apply();
            break;
        case Qt.Key_Backspace: query = query.slice(0, -1); resetView(); break;
        default:
            if (e.text && e.text.length === 1 && e.text >= " " && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                query += e.text; resetView();
            } else handled = false;
        }
        e.accepted = handled;
    }

    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.deep, 0.97) }
    MouseArea { anchors.fill: parent; enabled: root.open }

    Item {
        id: content
        width: 1366
        height: 768
        x: (root.width - 1366) / 2
        y: (root.height - 768) / 2
        transform: Translate { y: (1 - root.t) * 30 }

        Txt { x: 72; y: 38; text: "Wallstore"; font.pixelSize: 30; font.weight: Font.Bold }

        Rectangle {
            x: 72; y: 96
            width: 520; height: 46; radius: 23
            color: Theme.glass
            border.width: 1
            border.color: Theme.glassBorder
            Txt {
                x: 22
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 140
                elide: Text.ElideRight
                text: root.query === "" ? "Type to search wallpapers" : root.query
                font.pixelSize: 17
                color: root.query === "" ? Theme.fgDim : Theme.fg
            }
            Txt {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: root.scanning ? "Scanning\u2026" : root.items.length + " found"
                font.pixelSize: 13
                color: Theme.fgDim
            }
        }

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 72
            y: 108
            text: Wall.busy ? "Applying\u2026" : "Enter  set wallpaper      Esc  back"
            font.pixelSize: 14
            color: Wall.busy ? Theme.accent : Theme.fgDim
        }

        // skeleton grid while the folder is being scanned
        Grid {
            x: 64; y: 170
            columns: root.cols
            visible: root.scanning
            Repeater {
                model: 8
                delegate: Item {
                    width: 302; height: 192
                    Rectangle {
                        x: 8; y: 8; width: 280; height: 158
                        radius: 10
                        color: Theme.glass
                        border.width: 1
                        border.color: Theme.glassBorder
                        Rectangle { anchors.fill: parent; anchors.margins: 5; radius: 6; color: Theme.glassHi; opacity: root.pulse }
                    }
                    Rectangle { x: 12; y: 174; width: 150; height: 10; radius: 5; color: Theme.glassHi; opacity: root.pulse * 0.8 }
                }
            }
        }

        GridView {
            id: grid
            x: 64; y: 170
            width: root.cols * 302
            height: 520
            clip: true
            // A hidden GridView still builds its first rows and starts decoding their
            // thumbnails. Wallstore is closed most of the time, so keep the model empty
            // until the page is on screen (the fade-out keeps visible true until it is gone).
            model: root.visible ? root.items : 0
            cellWidth: 302
            cellHeight: 192
            cacheBuffer: root.visible ? 360 : 0
            keyNavigationEnabled: false
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool cur: index === root.current
                readonly property bool isActive: modelData === Wall.current
                property real appear: 0
                property real selT: cur ? 1 : 0
                Behavior on selT { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                width: grid.cellWidth
                height: grid.cellHeight
                opacity: appear
                transform: Translate { y: (1 - cell.appear) * 18 }

                SequentialAnimation {
                    id: enter
                    PauseAnimation { duration: root.stagger ? Math.min(cell.index % root.cols + Math.floor(cell.index / root.cols), 6) * 55 : 0 }
                    NumberAnimation { target: cell; property: "appear"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                }
                Component.onCompleted: enter.start()
                Connections {
                    target: root
                    function onOpenChanged() { if (root.open) { cell.appear = 0; enter.restart(); } }
                }

                Item {
                    id: card
                    x: 8; y: 8; width: 280; height: 158
                    scale: 1 + 0.035 * cell.selT

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: Theme.glass
                        border.width: 1
                        border.color: Theme.glassBorder

                        // placeholder while the thumbnail loads (or fails)
                        Rectangle {
                            id: ph
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 6
                            color: Theme.glassHi
                            opacity: 0.5
                            visible: thumb.status !== Image.Ready
                            SequentialAnimation {
                                running: thumb.status === Image.Loading
                                loops: Animation.Infinite
                                NumberAnimation { target: ph; property: "opacity"; to: 1; duration: 650; easing.type: Easing.InOutSine }
                                NumberAnimation { target: ph; property: "opacity"; to: 0.4; duration: 650; easing.type: Easing.InOutSine }
                            }
                        }
                        Txt {
                            anchors.centerIn: parent
                            visible: thumb.status === Image.Error
                            text: "Can\u2019t load preview"
                            font.pixelSize: 13
                            color: Theme.fgDim
                        }
                        Image {
                            id: thumb
                            anchors.fill: parent
                            anchors.margins: 5
                            source: Wall.src(cell.modelData)
                            sourceSize.width: 360
                            fillMode: Image.PreserveAspectCrop
                            clip: true
                            asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 320 } }
                        }
                    }

                    Rectangle {
                        x: 14; y: 14
                        width: activeLbl.width + 20; height: 24; radius: 12
                        color: Theme.accent
                        opacity: cell.isActive ? 1 : 0
                        scale: cell.isActive ? 1 : 0.8
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                        Txt {
                            id: activeLbl
                            anchors.centerIn: parent
                            text: "ACTIVE"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                            color: Theme.accentText
                        }
                    }

                    Rectangle {
                        x: -5; y: -5; width: 290; height: 168
                        radius: 15
                        color: "transparent"
                        border.width: 3
                        border.color: Theme.fg
                        opacity: cell.selT
                    }
                }

                Txt {
                    x: 12; y: 174
                    width: 272
                    elide: Text.ElideRight
                    text: Wall.name(cell.modelData)
                    font.pixelSize: 13
                    color: cell.cur ? Theme.fg : Theme.fgDim
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { if (cell.cur) root.apply(); else root.current = cell.index; }
                }
            }
        }

        // empty / error / no-match states
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 320
            width: 700; height: 140
            opacity: (root.scanFailed || root.folderEmpty || root.noMatch) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 240 } }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                text: root.scanFailed ? "Can\u2019t read the wallpaper folder"
                    : root.folderEmpty ? "No wallpapers yet"
                    : "Nothing matches \u201c" + root.query + "\u201d"
                font.pixelSize: 24
                font.weight: Font.Bold
            }
            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 44
                text: root.scanFailed ? "Check that " + Wall.prettyDir(Wall.dir) + " exists, then retry"
                    : root.folderEmpty ? "Add jpg, png or webp images to " + Wall.prettyDir(Wall.dir)
                    : "Backspace to edit, Esc to clear the search"
                font.pixelSize: 15
                color: Theme.fgDim
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 90
                width: 130; height: 42; radius: 21
                color: Theme.fg
                visible: !root.noMatch
                Txt { anchors.centerIn: parent; text: "Retry"; font.pixelSize: 16; font.weight: Font.Bold; color: Theme.deep }
                MouseArea { anchors.fill: parent; onClicked: Wall.refresh() }
            }
        }

        // applying overlay
        Rectangle {
            x: 64; y: 170
            width: root.cols * 302; height: 520
            color: Qt.alpha(Theme.deep, 0.55)
            opacity: Wall.busy ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            MouseArea { anchors.fill: parent }
            Rectangle {
                anchors.centerIn: parent
                width: 280; height: 56; radius: 28
                color: Theme.glassHi
                border.width: 1
                border.color: Theme.glassBorder
                Row {
                    anchors.centerIn: parent
                    Txt { text: "Applying wallpaper"; font.pixelSize: 17; font.weight: Font.Bold }
                    Txt { width: 24; text: ".".repeat(root.dotN); font.pixelSize: 17; font.weight: Font.Bold }
                }
            }
        }

        // apply error banner
        Rectangle {
            id: banner
            readonly property bool showing: Wall.error !== ""
            property string msg: ""
            x: 72
            width: 720; height: 44; radius: 22
            y: showing ? 706 : 732
            opacity: showing ? 1 : 0
            visible: opacity > 0.01
            color: Qt.rgba(0.78, 0.22, 0.22, 0.96)
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
                text: banner.msg + "   \u00b7   Enter retry   \u00b7   Esc dismiss"
                font.pixelSize: 14
                color: "white"
            }
        }
    }
}
