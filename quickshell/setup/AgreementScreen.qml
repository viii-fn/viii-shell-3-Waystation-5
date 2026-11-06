import QtQuick
import "../core"
import "../hub"

// Step 3: the PS5 user agreement page (centred title, a long scrolling text on a translucent panel, then Accept /
// Do Not Accept), rewritten for Waystation. (Layout from memory of the PS5 setup.)
Item {
    id: root
    required property var ctl
    property bool active: false
    width: 1366
    height: 768

    property int sel: 0                 // 0 = Accept, 1 = Do Not Accept
    property string note: ""

    readonly property var blocks: [
        { h: "1. About Waystation", t: "Waystation is a free, open-source desktop shell built on Quickshell and Hyprland. It brings the PlayStation 5\u2019s interactive interface to everyone, on any computer that can run them. This agreement is between you and viii-shell-3 (\u201cwe\u201d, \u201cus\u201d), the project that publishes Waystation." },
        { h: "2. Your licence", t: "Waystation is provided free of charge under the open-source licence published with its source code. You may use, study, change and share it under that licence. Nothing in this agreement takes those rights away." },
        { h: "3. What setup does", t: "With your permission, setup can change your keyboard layout, read your display\u2019s resolution and HDR support, and install the programs Waystation needs through your distribution\u2019s package manager. Installing packages needs administrator access, which you grant by entering your password; it is used only for that and is never stored. A full system update is optional and only runs if you choose it." },
        { h: "4. Changes to your files", t: "The installer links Waystation\u2019s configuration into ~/.config and its helper programs into ~/.local/bin. Anything it replaces is backed up first, in ~/.local/state/viii/backups, so you can put it back." },
        { h: "5. Network access", t: "Some features use the internet: the weather card (Open-Meteo, with your approximate location from an IP lookup unless you set one in ~/.config/viii/location), the news cards (public feeds from Linux and gaming sites) and app descriptions (Wikipedia). Those services can see your IP address and follow their own terms. Waystation includes no account system and no analytics." },
        { h: "6. No warranty", t: "Waystation is provided \u201cas is\u201d, without warranty of any kind, and you use it at your own risk. To the fullest extent the law allows, viii-shell-3 and its contributors are not liable for loss or damage arising from its use, including problems caused by installing or updating packages. Keep backups of anything you care about." },
        { h: "7. Trademarks", t: "PlayStation and related marks belong to Sony Interactive Entertainment. Waystation is an independent project and is not affiliated with, sponsored by or endorsed by them." },
        { h: "8. Accepting", t: "By choosing Accept you agree to this agreement. If you choose Do Not Accept, setup will not install anything and stays on this screen." }
    ]

    onActiveChanged: if (active) { sel = 0; note = ""; fl.contentY = 0; }

    function scrollBy(dy) {
        const max = Math.max(0, fl.contentHeight - fl.height);
        fl.contentY = Math.max(0, Math.min(max, fl.contentY + dy));
    }
    function choose() {
        if (sel === 0) ctl.next();
        else note = "Setup can\u2019t continue until you accept.";
    }
    function handleKey(e) {
        const k = e.key;
        if (k === Qt.Key_Up) scrollBy(-72);
        else if (k === Qt.Key_Down) scrollBy(72);
        else if (k === Qt.Key_PageUp) scrollBy(-fl.height + 40);
        else if (k === Qt.Key_PageDown) scrollBy(fl.height - 40);
        else if (k === Qt.Key_Left) { sel = 0; note = ""; }
        else if (k === Qt.Key_Right) { sel = 1; note = ""; }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) choose();
        else if (k === Qt.Key_Escape) ctl.prev();
        else { e.accepted = false; return; }
        e.accepted = true;
    }

    Txt {
        x: 0
        y: 62
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: "User Agreement"
        font.pixelSize: 36
    }
    Txt {
        x: 0
        y: 116
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: "Waystation  \u00b7  viii-shell-3"
        font.pixelSize: 15
        color: Theme.fgDim
    }

    // the text sits on a light, translucent panel, centred
    Item {
        x: (root.width - 900) / 2
        y: 158
        width: 900
        height: 440

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }

        Flickable {
            id: fl
            x: 40
            y: 28
            width: parent.width - 80
            height: parent.height - 56
            contentWidth: width
            contentHeight: col.implicitHeight + 24
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            Behavior on contentY {
                NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
            }

            Column {
                id: col
                width: fl.width - 24
                spacing: 20

                Repeater {
                    model: root.blocks
                    delegate: Column {
                        id: blk
                        required property var modelData
                        width: col.width
                        spacing: 6
                        Txt {
                            width: parent.width
                            text: blk.modelData.h
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }
                        Txt {
                            width: parent.width
                            text: blk.modelData.t
                            font.pixelSize: 16
                            color: Theme.fgDim
                            wrapMode: Text.WordWrap
                            lineHeight: 1.2
                        }
                    }
                }
            }
        }

        // scroll position: a thin line on the right edge
        Rectangle {
            x: parent.width - 18
            y: 28
            width: 3
            height: parent.height - 56
            radius: 1.5
            color: Qt.alpha(Theme.fg, 0.08)
            visible: fl.contentHeight > fl.height
            Rectangle {
                width: parent.width
                radius: 1.5
                color: Qt.alpha(Theme.fg, 0.45)
                height: Math.max(24, parent.height * fl.height / Math.max(1, fl.contentHeight))
                y: (parent.height - height) * (fl.contentY / Math.max(1, fl.contentHeight - fl.height))
            }
        }
    }

    Row {
        x: (root.width - width) / 2
        y: 632
        spacing: 24
        Pill {
            label: "Accept"
            on: root.active && root.sel === 0
            onClicked: { root.sel = 0; root.choose(); }
        }
        Pill {
            label: "Do Not Accept"
            on: root.active && root.sel === 1
            onClicked: { root.sel = 1; root.choose(); }
        }
    }
    Txt {
        x: 0
        y: 696
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root.note
        font.pixelSize: 14
        color: Theme.fgDim
        visible: text !== ""
    }
}
