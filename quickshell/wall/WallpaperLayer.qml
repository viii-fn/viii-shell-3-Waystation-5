import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// The desktop wallpaper, drawn by the shell (no swaybg/hyprpaper needed). One per monitor, bottom layer.
// A new wallpaper fades in over the old one.
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.deep
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "viii-wall"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Image {
        id: back
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1920
        onStatusChanged: { if (status === Image.Ready && front.opacity > 0.99) front.opacity = 0; }
    }
    Image {
        id: front
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1920
        opacity: 0
        onStatusChanged: { if (status === Image.Ready && source !== back.source) fade.restart(); }
    }
    SequentialAnimation {
        id: fade
        NumberAnimation { target: front; property: "opacity"; from: 0; to: 1; duration: 700; easing.type: Easing.InOutQuad }
        ScriptAction {
            script: {
                if (back.source === front.source && back.status === Image.Ready) front.opacity = 0;
                else back.source = front.source;
            }
        }
    }

    Connections {
        target: Wall
        function onCurrentChanged() { front.source = Wall.src(Wall.current); }
    }
    Component.onCompleted: back.source = Wall.src(Wall.current)
}
