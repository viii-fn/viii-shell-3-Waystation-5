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

    // Decode at the real screen width. A 1920px decode on a 1366px panel is 2.3x the
    // texture memory for no visible gain (this machine has 1.8 GB of RAM).
    readonly property int texW: win.screen && win.screen.width > 0 ? win.screen.width : 1366

    Image {
        id: back
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: win.texW
        onStatusChanged: {
            if (status === Image.Ready && front.opacity > 0.99) {
                front.opacity = 0;
                front.source = "";      // back holds this frame now: drop the duplicate texture
            }
        }
    }
    Image {
        id: front
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: win.texW
        opacity: 0
        onStatusChanged: {
            if (status !== Image.Ready) return;
            if (source === back.source) {
                // re-applied the same image: nothing to cross-fade, so release the duplicate
                if (opacity < 0.01) front.source = "";
                return;
            }
            fade.restart();
        }
    }
    SequentialAnimation {
        id: fade
        NumberAnimation { target: front; property: "opacity"; from: 0; to: 1; duration: 700; easing.type: Easing.InOutQuad }
        ScriptAction {
            script: {
                if (back.source === front.source && back.status === Image.Ready) {
                    front.opacity = 0;
                    front.source = "";
                } else {
                    back.source = front.source;
                }
            }
        }
    }

    Connections {
        target: Wall
        function onCurrentChanged() { front.source = Wall.src(Wall.current); }
    }
    Component.onCompleted: back.source = Wall.src(Wall.current)
}
