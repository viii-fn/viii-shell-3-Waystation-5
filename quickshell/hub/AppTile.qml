import QtQuick
import QtQuick.Shapes
import "../core"

// One app tile, PS5 style: a dark glass slot with the app icon on it (no colour gradient, no gloss).
// Used by the home row, the library grid and the launch zoom.
Item {
    id: root
    property var entry: null
    property real dim: 0                 // 0 = normal, 1 = fully dimmed (unfocused)
    property real corner: Math.min(width, height) * 0.14
    property real iconScale: 0.8
    property real iconOpacity: 1
    property real ring: 0                // 0..1: the PS5 selection ring around the tile (the home row drives it)

    readonly property bool isLib: entry !== null && entry !== undefined && entry.isLibrary === true
    readonly property bool isWall: entry !== null && entry !== undefined && entry.isWall === true
    readonly property bool isWelcome: entry !== null && entry !== undefined && entry.isWelcome === true
    readonly property bool isExplore: entry !== null && entry !== undefined && entry.isExplore === true
    readonly property real shade: iconOpacity * (1 - 0.10 * dim)

    readonly property var pal: {
        void Apps.palettes;
        return entry ? Apps.paletteFor(entry) : Apps.fallback("none");
    }

    readonly property string src: {
        if (!entry || isLib || isWall || isWelcome || isExplore) return "";
        const p = Apps.iconPath(entry);
        if (!p) return "";
        return p.charAt(0) === "/" ? "file://" + p : p;
    }

    // the slot: PS5 glass (soft grey bottom-left -> near black top-right)
    GlassSlot {
        anchors.fill: parent
        radius: root.corner
        alpha: 1
    }

    // selection ring: always there, only visible while the tile is focused
    GlassRing {
        readonly property real out: 3.5
        x: -out; y: -out
        width: root.width + 2 * out
        height: root.height + 2 * out
        radius: root.corner + out
        thickness: 2.5
        opacity: root.ring
        visible: opacity > 0.01
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
        visible: !root.isLib && !root.isWall && !root.isWelcome && !root.isExplore && img.status !== Image.Ready
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

    // Welcome glyph: the Arch logo (vector path, only created on the Welcome tile)
    Loader {
        anchors.centerIn: parent
        active: root.isWelcome
        opacity: root.shade
        scale: Math.min(root.width, root.height) * 0.52 / 24
        sourceComponent: Shape {
            width: 24; height: 24
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillColor: Theme.fg
                PathSvg {
                    path: "M11.39 0.605 C10.376 3.092 9.764 4.72 8.635 7.132 C9.328 7.866 10.178 8.721 11.558 9.686 C10.074 9.076 9.062 8.462 8.306 7.826 C6.86 10.842 4.596 15.138 0 23.395 C3.612 21.31 6.412 20.025 9.021 19.533 A6.61 6.61 0 0 1 8.85 17.986 L8.853 17.871 C8.911 15.556 10.114 13.776 11.54 13.898 C12.966 14.018 14.074 15.994 14.018 18.307 A6.52 6.52 0 0 1 13.872 19.55 C16.452 20.055 19.247 21.335 22.834 23.407 C22.129 22.112 21.502 20.944 20.899 19.827 C19.952 19.093 18.965 18.139 16.952 17.134 C18.336 17.494 19.328 17.909 20.102 18.374 C13.03 7.857 12.39 5.964 11.39 0.605 Z"
                }
            }
        }
    }

    // Explore glyph: a compass (ring and needle), vector shapes, only created on the Explore tile
    Loader {
        anchors.centerIn: parent
        active: root.isExplore
        opacity: root.shade
        scale: Math.min(root.width, root.height) * 0.52 / 24
        sourceComponent: Shape {
            width: 24; height: 24
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1.8
                strokeColor: Theme.fg
                fillColor: "transparent"
                PathAngleArc { centerX: 12; centerY: 12; radiusX: 10.4; radiusY: 10.4; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: Theme.fg
                startX: 17.2; startY: 6.8
                PathLine { x: 13.5; y: 13.5 }
                PathLine { x: 10.5; y: 10.5 }
                PathLine { x: 17.2; y: 6.8 }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: Qt.alpha(Theme.fg, 0.45)
                startX: 6.8; startY: 17.2
                PathLine { x: 10.5; y: 10.5 }
                PathLine { x: 13.5; y: 13.5 }
                PathLine { x: 6.8; y: 17.2 }
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
