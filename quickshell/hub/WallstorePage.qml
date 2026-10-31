import QtQuick
import "../core"

// Wallstore: a store-style page for wallpapers. Opens over the hub like the app store.
// Type to search, arrows to browse, Enter to set the wallpaper (the whole UI re-themes from it), Esc to leave.
// Keys come from Hub.handleKey while the store is open.
Item {
    id: root

    property bool open: false
    signal closeRequested()

    property string query: ""
    property int current: 0
    readonly property int cols: 4

    readonly property var items: {
        const q = query.toLowerCase();
        return Wall.files.filter(f => q === "" || Wall.name(f).toLowerCase().indexOf(q) >= 0);
    }
    readonly property string sel: items.length > 0 ? items[Math.min(current, items.length - 1)] : ""

    opacity: open ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }

    onOpenChanged: {
        if (open) { query = ""; current = 0; Wall.refresh(); Theme.applyWallpaper(); }
    }

    function move(d) {
        const n = items.length;
        if (n === 0) return;
        current = Math.max(0, Math.min(n - 1, current + d));
        grid.positionViewAtIndex(current, GridView.Contain);
    }
    function apply() { if (sel !== "") Wall.apply(sel); }

    function handleKey(e) {
        let handled = true;
        switch (e.key) {
        case Qt.Key_Escape:
            if (query !== "") { query = ""; current = 0; } else closeRequested();
            break;
        case Qt.Key_Left: move(-1); break;
        case Qt.Key_Right: move(1); break;
        case Qt.Key_Up: if (current - cols >= 0) move(-cols); break;
        case Qt.Key_Down: move(cols); break;
        case Qt.Key_Return: case Qt.Key_Enter: apply(); break;
        case Qt.Key_Backspace: query = query.slice(0, -1); current = 0; break;
        default:
            if (e.text && e.text.length === 1 && e.text >= " " && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                query += e.text; current = 0;
            } else handled = false;
        }
        e.accepted = handled;
    }

    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.deep, 0.97) }

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
            width: parent.width - 120
            elide: Text.ElideRight
            text: root.query === "" ? "Type to search wallpapers" : root.query
            font.pixelSize: 17
            color: root.query === "" ? Theme.fgDim : Theme.fg
        }
        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: root.items.length + " found"
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

    GridView {
        id: grid
        x: 64; y: 170
        width: root.cols * 302
        height: 520
        clip: true
        model: root.items
        cellWidth: 302
        cellHeight: 192
        keyNavigationEnabled: false

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool cur: index === root.current
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                x: 8; y: 8; width: 280; height: 158
                radius: 10
                color: Theme.glass
                border.width: 1
                border.color: Theme.glassBorder
                Image {
                    anchors.fill: parent
                    anchors.margins: 5
                    source: Wall.src(cell.modelData)
                    sourceSize.width: 360
                    fillMode: Image.PreserveAspectCrop
                    clip: true
                    asynchronous: true
                }
                Rectangle {
                    visible: cell.modelData === Wall.current
                    x: 14; y: 14
                    width: activeLbl.width + 20; height: 24; radius: 12
                    color: Theme.accent
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
            }
            Rectangle {
                visible: cell.cur
                x: 3; y: 3; width: 290; height: 168
                radius: 15
                color: "transparent"
                border.width: 3
                border.color: Theme.fg
            }
            Txt {
                x: 12; y: 172
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

    Txt {
        anchors.centerIn: parent
        visible: root.items.length === 0
        text: Wall.files.length === 0 ? "No wallpapers found in ~/Pictures/Wallpapers" : "Nothing matches your search"
        font.pixelSize: 18
        color: Theme.fgDim
    }
}
