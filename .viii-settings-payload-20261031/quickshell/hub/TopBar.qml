import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../core"

// Tabs on the left; battery, clock and avatar on the right. Works in the 1366x768 design space.
Item {
    id: root
    property int page: 0
    property bool tabsFocus: false
    signal tabClicked(int index)
    signal settingsClicked()

    height: 110

    SystemClock { id: clk; precision: SystemClock.Minutes }

    Row {
        x: 54
        y: 38
        spacing: 10
        Repeater {
            model: ["Apps", "Library"]
            delegate: Item {
                id: tab
                required property string modelData
                required property int index
                readonly property bool cur: root.page === index
                width: lbl.width + 36
                height: 42

                Rectangle {
                    anchors.fill: parent
                    radius: 21
                    color: Theme.glassHi
                    opacity: (tab.cur && root.tabsFocus) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                Txt {
                    id: lbl
                    anchors.centerIn: parent
                    text: tab.modelData
                    font.pixelSize: 21
                    font.weight: tab.cur ? Font.Bold : Font.Medium
                    color: tab.cur ? Theme.fg : Theme.fgDim
                }
                Rectangle {
                    x: (parent.width - width) / 2
                    y: parent.height - 2
                    height: 3
                    radius: 1.5
                    width: tab.cur ? lbl.width : 0
                    color: Theme.fg
                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
                }
                MouseArea { anchors.fill: parent; onClicked: root.tabClicked(tab.index) }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 72
        y: 38
        spacing: 24
        layoutDirection: Qt.LeftToRight

        // Settings gear, matching the PS5 home screen's top-right utility icons.
        Item {
            width: 42; height: 42
            Rectangle {
                anchors.fill: parent
                radius: 21
                color: gearArea.containsMouse ? Theme.glassHi : "transparent"
                border.width: gearArea.containsMouse ? 1 : 0
                border.color: Theme.glassBorder
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            Txt {
                anchors.centerIn: parent
                text: ""
                font.family: Theme.iconFont
                font.pixelSize: 21
                color: Theme.fg
            }
            MouseArea {
                id: gearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsClicked()
            }
        }

        // battery
        Item {
            readonly property real pct: UPower.displayDevice ? UPower.displayDevice.percentage : -1
            visible: pct >= 0
            width: visible ? 74 : 0
            height: 42
            Rectangle {
                id: body
                x: 0; y: 14
                width: 28; height: 14
                radius: 4
                color: "transparent"
                border.width: 1.5
                border.color: Theme.fg
                Rectangle {
                    x: 3; y: 3
                    height: parent.height - 6
                    width: Math.max(2, (parent.width - 6) * Math.min(1, Math.max(0, parent.parent.pct)))
                    radius: 2
                    color: parent.parent.pct < 0.15 ? "#ff6b6b" : Theme.fg
                }
            }
            Rectangle { x: 29.5; y: 17.5; width: 3; height: 7; radius: 1.5; color: Theme.fg }
            Txt { x: 40; y: (42 - height) / 2; text: Math.round(Math.max(0, parent.pct) * 100) + "%"; font.pixelSize: 16 }
        }

        // clock
        Txt {
            y: (42 - height) / 2
            text: Qt.formatDateTime(clk.date, "HH:mm")
            font.pixelSize: 24
            font.weight: Font.Medium
        }

        // avatar
        Rectangle {
            width: 42; height: 42; radius: 21
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.accent }
                GradientStop { position: 1.0; color: Qt.darker(Theme.accent, 1.8) }
            }
            border.width: 1
            border.color: Theme.glassBorder
            Txt {
                anchors.centerIn: parent
                text: (Quickshell.env("USER") || "u").charAt(0).toUpperCase()
                font.pixelSize: 18
                font.weight: Font.Bold
                color: Theme.accentText
            }
        }
    }
}
