import QtQuick
import "../core"

// One app tile: palette gradient, gloss, icon (or monogram if the icon can't load), optional dimming.
// Used by the home row, the library grid and the launch zoom.
Item {
    id: root
    property var entry: null
    property real dim: 0                 // 0 = normal, 1 = fully dimmed (unfocused)
    property real corner: Math.min(width, height) * 0.13
    property real iconScale: 0.58
    property real iconOpacity: 1

    readonly property bool isLib: entry !== null && entry !== undefined && entry.isLibrary === true

    readonly property var pal: {
        void Apps.palettes;
        return entry ? Apps.paletteFor(entry) : Apps.fallback("none");
    }

    readonly property string src: {
        if (!entry || isLib) return "";
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
            GradientStop { position: 1.0; color: Qt.darker(root.pal.surface, 1.15) }
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
        sourceSize: Qt.size(128, 128)
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
        visible: !root.isLib && img.status !== Image.Ready
        opacity: root.iconOpacity
        text: root.entry && root.entry.name ? String(root.entry.name).charAt(0).toUpperCase() : "?"
        font.pixelSize: Math.min(root.width, root.height) * 0.46
        font.weight: Font.Bold
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

    // dim overlay for unfocused tiles
    Rectangle {
        anchors.fill: parent
        radius: root.corner
        color: Qt.rgba(0, 0, 0, 0.30 * root.dim)
    }
}
