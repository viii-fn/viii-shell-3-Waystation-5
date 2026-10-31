import QtQuick
import "../core"

// One app tile: palette gradient, gloss, icon (or monogram if the icon can't load), optional dimming.
// Used by the home row, the library grid and the launch zoom.
Item {
    id: root
    property var entry: null
    property real dim: 0                 // 0 = normal, 1 = fully dimmed (unfocused)
    property real corner: Math.min(width, height) * 0.13
    property real iconScale: 0.7
    property real iconOpacity: 1

    readonly property bool isLib: entry !== null && entry !== undefined && entry.isLibrary === true
    readonly property bool isWall: entry !== null && entry !== undefined && entry.isWall === true

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

    Rectangle {
        anchors.fill: parent
        radius: root.corner
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.tint(root.pal.primaryContainer, Qt.alpha(root.pal.primary, 0.40)) }
            GradientStop { position: 1.0; color: Qt.darker(root.pal.surface, 5.15) }
        }
    }

    // soft top gloss
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: parent.height * 0.55
        radius: root.corner
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.17) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }

    Image {
        id: img
        anchors.centerIn: parent
        width: Math.min(root.width, root.height) * root.iconScale
        height: width
        source: root.src
        sourceSize: Qt.size(168, 168)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        opacity: root.iconOpacity
        visible: status === Image.Ready
        onStatusChanged: if (status === Image.Error) console.warn("[viii] icon failed:", root.entry ? root.entry.name : "?", root.src)
    }

    // monogram while the icon is missing / loading
    Txt {
        anchors.centerIn: parent
        visible: !root.isLib && !root.isWall && img.status !== Image.Ready
        opacity: root.iconOpacity
        text: root.entry && root.entry.name ? String(root.entry.name).charAt(0).toUpperCase() : "?"
        font.pixelSize: Math.min(root.width, root.height) * 0.46
        font.weight: Font.DemiBold
        color: Qt.lighter(root.pal.primary, 1.15)
    }

    // library glyph: 2x2 rounded squares
    Grid {
        anchors.centerIn: parent
        visible: root.isLib
        opacity: root.iconOpacity
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
        opacity: root.iconOpacity
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

    // dim overlay for unfocused tiles
    Rectangle {
        anchors.fill: parent
        radius: root.corner
        color: Qt.rgba(0, 0, 0, 0.40 * root.dim)
    }
}
