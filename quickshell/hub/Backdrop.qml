import QtQuick
import QtQuick.Shapes
import "../core"

// Layered background: matugen gradient, two soft radial glows (one slowly drifting),
// a faint enlarged icon of the selected app (upscaling blurs it for free), and a bottom scrim.
Item {
    id: root
    property url icon: ""
    property bool shown: true
    property bool wallpaper: false
    property bool news: false
    property bool ghost: true
    property url newsImg: ""
    property real drift: 0
    // true when the hub window sits over the shell's own WallpaperLayer (empty desktop)
    property bool baseBehind: false
    // darkness of the wallpaper dim layer; Settings raises this so its content stays legible
    property real dim: 0.28
    Behavior on dim { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
    // bottom scrim; Settings turns it off so the whole wallpaper is dimmed evenly
    property bool scrim: true

    // true while a full-bleed image fully covers the gradient + glows below
    readonly property bool covered: wpLayer.opacity > 0.99 || newsLayer.opacity > 0.99

    // Gradient + glows are the background only while no full-bleed image covers them.
    // When covered they would still be shaded, so take them out of the scene entirely.
    Item {
        id: baseLayer
        anchors.fill: parent
        visible: !root.covered

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.tint(Theme.mid, Qt.alpha(Theme.accent, 0.20)) }
                GradientStop { position: 0.6; color: Theme.mid }
                GradientStop { position: 1.0; color: Theme.deep }
            }
        }

        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.width * 0.80 + root.drift; centerY: root.height * 0.02
                    centerRadius: root.width * 0.64
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.accent, 0.52) }
                    GradientStop { position: 0.55; color: Qt.alpha(Theme.accent, 0.15) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.accent, 0.0) }
                }
                startX: 0; startY: 0
                PathLine { x: root.width; y: 0 }
                PathLine { x: root.width; y: root.height }
                PathLine { x: 0; y: root.height }
                PathLine { x: 0; y: 0 }
            }
        }

        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.width * 0.08 - root.drift; centerY: root.height * 0.98
                    centerRadius: root.width * 0.55
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.accent, 0.20) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.accent, 0.0) }
                }
                startX: 0; startY: 0
                PathLine { x: root.width; y: 0 }
                PathLine { x: root.width; y: root.height }
                PathLine { x: 0; y: root.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }


    // full-bleed current wallpaper, shown while the Wallstore tile is selected (unloaded otherwise: 2 GB RAM).
    // On an empty desktop WallpaperLayer already draws this exact image behind the transparent hub
    // window, so only the dim is drawn here — no second full-screen texture.
    Item {
        id: wpLayer
        anchors.fill: parent
        readonly property bool drawImage: root.wallpaper && !root.baseBehind
        opacity: root.wallpaper ? (drawImage ? (wpImg.status === Image.Ready ? 1 : 0) : 1) : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

        Image {
            id: wpImg
            anchors.fill: parent
            visible: wpLayer.drawImage
            source: wpLayer.drawImage ? Wall.src(Wall.current) : ""
            sourceSize.width: Math.min(1920, Math.max(1366, Math.round(root.width)))
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
        }
        // dim so tiles and text stay readable on bright wallpapers
        Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.deep, root.dim) }
    }

    // viii-explore: full-bleed picture of the selected news item (Explore tile). Unloaded when not shown (2 GB RAM).
    Item {
        id: newsLayer
        anchors.fill: parent
        opacity: (root.news && nImg.status === Image.Ready) ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.soft } }
        Image {
            id: nImg
            anchors.fill: parent
            source: (root.news || newsLayer.opacity > 0.01) ? root.newsImg : ""
            sourceSize.width: Math.min(1920, Math.max(1366, Math.round(root.width)))
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
        }
        // dim the whole picture a little, and darken the left side where the text sits
        Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.deep, 0.30) }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.70) }
                GradientStop { position: 0.65; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.0) }
            }
        }
    }

    // ghost of the selected app's icon
    Item {
        id: ghostLayer
        anchors.fill: parent
        opacity: root.ghost ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        Image {
            id: ghost
            anchors.right: parent.right
            anchors.rightMargin: -root.height * 0.10
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -root.height * 0.04
            width: root.height * 0.95
            height: width
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            opacity: 0
        }
    }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: 140 }
        ScriptAction { script: ghost.source = root.icon }
        NumberAnimation { target: ghost; property: "opacity"; to: ghost.status === Image.Error ? 0 : 0.30; duration: 420; easing.type: Easing.OutCubic }
    }
    onIconChanged: swap.restart()

    // bottom scrim keeps the info area readable
    Rectangle {
        opacity: root.scrim ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.5
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.0) }
            GradientStop { position: 1.0; color: Qt.alpha(Theme.deep, 0.7) }
        }
    }
}
