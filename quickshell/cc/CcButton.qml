import QtQuick
import "../core"
import "../hub"

// One round button of the Control Center strip. PS5 behaviour: the selected one turns white,
// grows, gets a ring and shows its name underneath.
Item {
    id: root
    property string glyph: ""        // Font Awesome codepoint (needs a Nerd Font symbols font)
    property string fallback: ""     // short text used when no Nerd Font is installed
    property string label: ""
    property bool selected: false
    property bool lit: true          // false = feature is off (dimmed glyph)
    signal clicked()

    width: 96
    height: 140

    readonly property string nfFamily: {
        const f = Qt.fontFamilies();
        if (f.indexOf("Symbols Nerd Font") >= 0) return "Symbols Nerd Font";
        if (f.indexOf("Symbols Nerd Font Mono") >= 0) return "Symbols Nerd Font Mono";
        for (let i = 0; i < f.length; i++) if (f[i].indexOf("Nerd Font") >= 0) return f[i];
        return "";
    }

    Item {
        id: disc
        width: 84
        height: 84
        x: 6
        y: 8
        scale: root.selected ? 1.22 : 1
        Behavior on scale {
            NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -6
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: Theme.fg
            opacity: root.selected ? 0.9 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.selected ? Theme.fg : Qt.rgba(1, 1, 1, 0.16)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.22)
            Behavior on color { ColorAnimation { duration: 180 } }
        }
        Txt {
            anchors.centerIn: parent
            text: root.nfFamily !== "" ? root.glyph : root.fallback
            font.family: root.nfFamily !== "" ? root.nfFamily : Theme.fontFamily
            font.pixelSize: root.nfFamily !== "" ? 32 : 18
            font.weight: Font.Bold
            color: root.selected ? "#101218" : Theme.fg
            opacity: root.lit ? 1 : 0.45
        }
    }

    Txt {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 116
        text: root.label
        font.pixelSize: 17
        font.weight: Font.DemiBold
        opacity: root.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
