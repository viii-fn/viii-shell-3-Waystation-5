import QtQuick
import "../core"
import "../hub"

// Step 0: the PS5 "connect your controller" page. Centred illustration (keyboard.svg instead of the DualSense),
// a title and one instruction line, no buttons. The ring sits on the Super key, which stands in for the PS button.
// (Layout from memory of the PS5 setup, not from reference frames.)
Item {
    id: root
    required property var ctl
    property bool active: false
    width: 1366
    height: 768

    function handleKey(e) {
        const k = e.key;
        // Super / Meta is the "PS button" here. Enter works too, in case the compositor keeps Super to itself.
        if (k === Qt.Key_Meta || k === Qt.Key_Super_L || k === Qt.Key_Super_R || k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (!e.isAutoRepeat) ctl.next();
            e.accepted = true;
            return;
        }
        e.accepted = false;
    }

    // keyboard.svg is 640 x 224; its Super key is at (72, 180), 46 x 36
    readonly property real kbX: (width - 640) / 2
    readonly property real kbY: 150
    readonly property real superX: 72
    readonly property real superY: 180
    readonly property real superW: 46
    readonly property real superH: 36

    Image {
        x: root.kbX
        y: root.kbY
        width: 640
        height: 224
        source: Qt.resolvedUrl("keyboard.svg")
        sourceSize.width: 1280
        sourceSize.height: 448
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
    }
    GlassRing {
        readonly property real out: 3.5
        x: root.kbX + root.superX - out
        y: root.kbY + root.superY - out
        width: root.superW + 2 * out
        height: root.superH + 2 * out
        radius: 6 + out
        thickness: 2.5
        animated: root.active
    }

    Txt {
        x: 0
        y: 424
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: "Connect your keyboard"
        font.pixelSize: 36
    }
    Txt {
        x: (root.width - 720) / 2
        y: 484
        width: 720
        horizontalAlignment: Text.AlignHCenter
        text: "Plug in or pair a keyboard, then press the Super key (or Enter) to continue."
        font.pixelSize: 19
        color: Theme.fgDim
        wrapMode: Text.WordWrap
        maximumLineCount: 2
    }
    Txt {
        x: (root.width - 720) / 2
        y: 560
        width: 720
        horizontalAlignment: Text.AlignHCenter
        text: root.ctl.keyboards.length > 0 ? root.ctl.keyboards.join("   \u00b7   ") : "No keyboard reported yet"
        font.pixelSize: 14
        color: Theme.fgDim
        opacity: 0.7
    }

    MouseArea { anchors.fill: parent; onClicked: root.ctl.next() }
}
