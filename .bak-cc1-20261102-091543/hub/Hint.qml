import QtQuick
import "../core"

// A key hint: a small keycap with the key name, then what it does. Used by the screenshot pane and the control center.
Row {
    id: root
    property string key: ""
    property string label: ""
    spacing: 8

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(22, keyText.implicitWidth + 14)
        height: 22
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
        Txt {
            id: keyText
            anchors.centerIn: parent
            text: root.key
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.pixelSize: 13
        color: Theme.fgDim
    }
}
