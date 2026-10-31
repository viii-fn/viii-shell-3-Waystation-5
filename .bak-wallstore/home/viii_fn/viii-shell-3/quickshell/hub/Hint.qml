import QtQuick
import "../core"

// Bottom-right key hint: [key] label
Row {
    id: root
    property string key: ""
    property string label: ""
    spacing: 9

    Rectangle {
        height: 24
        width: Math.max(24, kt.width + 16)
        radius: 7
        color: Theme.glassHi
        border.width: 1
        border.color: Theme.glassBorder
        Txt { id: kt; anchors.centerIn: parent; text: root.key; font.pixelSize: 12; font.weight: Font.DemiBold }
    }
    Txt { y: (24 - height) / 2; text: root.label; font.pixelSize: 14; color: Theme.fgDim }
}
