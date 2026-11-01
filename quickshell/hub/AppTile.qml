import QtQuick
import "../core"

// One app tile, PS5 style: a dark glass slot with the app icon on it (no colour gradient, no gloss).
// Used by the home row, the library grid and the launch zoom.
Item {
    id: root
    property var entry: null
    property real dim: 0                 // 0 = normal, 1 = fully dimmed (unfocused)
    property real corner: Math.min(width, height) * 0.18
    property real iconScale: 0.8
    property real iconOpacity: 1

    readonly property bool isLib: entry !== null && entry !== undefined && entry.isLibrary === true
    readonly property bool isWall: entry !== null && entry !== undefined && entry.isWall === true
    readonly property real shade: iconOpacity * (1 - 0.10 * dim)

    readonly property var pal: {
        void Apps.palettes;
        return entry ? Apps.paletteFor(entry) : Apps.fallback("none");
    }

    readonly property string src: {
        if (!entry || isLib || isWall) return "";
        const p = Apps.iconPath(entry);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }

    // the slot: one flat rounded rectangle
    Rectangle {
        anchors.fill: parent
        radius: root.corner
        color: Qt.rgba(0.055, 0.06, 0.075, 0.92 - 0.08 * root.dim)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.09)
    }

    Image {
        id: img
        anchors.centerIn: parent
        width: Math.min(root.width, root.height) * root.iconScale
        height: width
        source: root.src
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        opacity: root.shade
        visible: status === Image.Ready
        onStatusChanged: if (status === Image.Error) console.warn("[viii] icon failed:", root.entry ? root.entry.name : "?", root.src)
    }

    // monogram while the icon is missing / loading
    Txt {
        anchors.centerIn: parent
        visible: !root.isLib && !root.isWall && img.status !== Image.Ready
        opacity: root.shade
        text: root.entry && root.entry.name ? String(root.entry.name).charAt(0).toUpperCase() : "?"
        font.pixelSize: Math.min(root.width, root.height) * 0.46
        font.weight: Font.DemiBold
        color: Qt.lighter(root.pal.primary, 1.15)
    }

    // library glyph: 2x2 rounded squares
    Grid {
        anchors.centerIn: parent
        visible: root.isLib
        opacity: root.shade
        columns: 2
        spacing: Math.min(root.width, root.height) * 0.06
        Repeater {
            model: 4
            Rectangle {
                required property int index
                width: Math.min(root.width, root.height) * 0.19
                height: width
                radius: width * 0.3
                color: Theme.fg
                opacity: index === 0 ? 1 : 0.72
            }
        }
    }

    // Wallstore glyph: a picture frame with a sun and two hills
    Item {
        anchors.centerIn: parent
        visible: root.isWall
        opacity: root.shade
        width: Math.min(root.width, root.height) * 0.50
        height: width * 0.74
        Rectangle {
            anchors.fill: parent
            radius: width * 0.14
            color: "transparent"
            border.width: Math.max(2, width * 0.07)
            border.color: Theme.fg
            clip: true
            Rectangle { x: parent.width * 0.66; y: parent.height * 0.18; width: parent.width * 0.16; height: width; radius: width / 2; color: Theme.fg }
            Rectangle { x: parent.width * 0.06; y: parent.height * 0.52; width: parent.width * 0.46; height: width; rotation: 45; radius: width * 0.08; color: Theme.fg; opacity: 0.85 }
            Rectangle { x: parent.width * 0.38; y: parent.height * 0.62; width: parent.width * 0.40; height: width; rotation: 45; radius: width * 0.08; color: Theme.fg; opacity: 0.65 }
        }
    }
}
