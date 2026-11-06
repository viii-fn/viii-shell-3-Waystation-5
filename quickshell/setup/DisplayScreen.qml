import QtQuick
import "../core"
import "../hub"

// Step 2: the PS5's display page, read-only. The PS5 asks you to adjust HDR against a sun symbol; here the sun
// just reports whether the display supports HDR, with the resolution beside it. Nothing is changed.
// (Layout from memory of the PS5 setup.)
Item {
    id: root
    required property var ctl
    property bool active: false
    width: 1366
    height: 768

    readonly property var shownDisplays: ctl.displays.slice(0, 3)
    readonly property bool anyHdr: {
        for (let i = 0; i < ctl.displays.length; i++) if (ctl.displays[i].hdr === "supported") return true;
        return false;
    }

    function handleKey(e) {
        const k = e.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) ctl.next();
        else if (k === Qt.Key_Escape) ctl.prev();
        else { e.accepted = false; return; }
        e.accepted = true;
    }

    Txt {
        x: 0
        y: 62
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: "Screen and Video"
        font.pixelSize: 36
    }
    Txt {
        x: 0
        y: 116
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: "Your display, as Hyprland reports it. Nothing is changed here."
        font.pixelSize: 17
        color: Theme.fgDim
    }

    // the sun: lit when the display supports HDR, dim when it does not (or when that is unknown)
    Item {
        id: sun
        x: (root.width - 96) / 2
        y: 168
        width: 96
        height: 96
        opacity: root.anyHdr ? 1 : 0.45
        Behavior on opacity { NumberAnimation { duration: 300 } }
        Rectangle {
            anchors.centerIn: parent
            width: 38
            height: 38
            radius: 19
            color: root.anyHdr ? Theme.accent : Theme.fg
        }
        Repeater {
            model: 8
            delegate: Item {
                required property int index
                width: 96
                height: 96
                rotation: index * 45
                Rectangle {
                    x: 46
                    y: 4
                    width: 4
                    height: 16
                    radius: 2
                    color: root.anyHdr ? Theme.accent : Theme.fg
                }
            }
        }
    }

    Column {
        x: (root.width - 640) / 2
        y: 300
        width: 640
        spacing: 14

        Item {
            width: parent.width
            height: 92
            visible: !root.ctl.displaysLoaded || root.shownDisplays.length === 0
            GlassSlot { anchors.fill: parent; radius: 18; alpha: 0.92 }
            Txt {
                anchors.centerIn: parent
                text: root.ctl.displaysLoaded ? "No display information" : "Checking your display\u2026"
                font.pixelSize: 20
                color: Theme.fgDim
            }
        }

        Repeater {
            model: root.shownDisplays.length
            delegate: Item {
                id: card
                required property int index
                readonly property var m: root.shownDisplays[index]
                width: 640
                height: 92
                GlassSlot { anchors.fill: parent; radius: 18; alpha: 0.92 }
                Txt {
                    x: 28
                    y: 16
                    width: 300
                    text: card.m.description || card.m.name
                    font.pixelSize: 14
                    color: Theme.fgDim
                }
                Txt {
                    x: 28
                    y: 40
                    width: 340
                    text: card.m.width + "\u00d7" + card.m.height + " @ " + card.m.refresh + " Hz"
                    font.pixelSize: 26
                }
                Rectangle {
                    x: 392
                    y: 50
                    width: 10
                    height: 10
                    radius: 5
                    color: card.m.hdr === "supported" ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                }
                Txt {
                    x: 412
                    y: 16
                    width: 210
                    text: "HDR"
                    font.pixelSize: 14
                    color: Theme.fgDim
                }
                Txt {
                    x: 412
                    y: 40
                    width: 210
                    text: card.m.hdr === "supported" ? "Supported" : (card.m.hdr === "unsupported" ? "Not supported" : "Unknown")
                    font.pixelSize: 20
                }
            }
        }
    }

    Pill {
        x: (root.width - width) / 2
        y: 632
        label: "Next"
        on: root.active
        onClicked: root.ctl.next()
    }
}
