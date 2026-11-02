import QtQuick
import "../core"

// "Top wallpapers": the most recently set wallpapers as a plain row of thumbnails (PS5 "Must see" style).
// Display only: nothing here can be selected. The thumbnails exist only while the strip is active (2 GB RAM).
Item {
    id: root
    property bool active: false
    readonly property int count: Math.min(6, Wall.recent.length)
    width: 1122
    height: 124

    Txt {
        text: "Top wallpapers"
        font.pixelSize: 15
        font.weight: Font.DemiBold
        color: Theme.fgDim
    }

    Row {
        y: 26
        spacing: 14
        Repeater {
            model: root.active ? root.count : 0
            delegate: Item {
                id: cell
                required property int index
                readonly property string path: Wall.recent[index]
                width: 174
                height: 98

                // shows while the picture loads
                Rectangle { anchors.fill: parent; color: Qt.rgba(0.07, 0.078, 0.098, 1) }
                Image {
                    anchors.fill: parent
                    source: Wall.src(cell.path)
                    sourceSize: Qt.size(348, 196)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)
                }
                // the one in use
                Rectangle {
                    visible: cell.path === Wall.current
                    x: 8; y: 8
                    width: nowText.width + 16
                    height: 20
                    radius: 10
                    color: Qt.rgba(0.07, 0.078, 0.098, 0.92)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.16)
                    Txt {
                        id: nowText
                        anchors.centerIn: parent
                        text: "Now"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    Txt {
        visible: root.active && root.count === 0
        y: 40
        text: "No wallpapers yet. Open the Wallstore to add some."
        font.pixelSize: 15
        color: Theme.fgDim
    }
}
