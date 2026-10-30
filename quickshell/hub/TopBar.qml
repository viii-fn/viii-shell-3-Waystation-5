import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower
import "../core"

Item {
    id: root

    property string page: "home"
    property bool tabFocus: false
    property real reveal: 1
    property real u: 1

    readonly property var bat: UPower.displayDevice
    readonly property real pct: bat && bat.isPresent ? (bat.percentage <= 1 ? bat.percentage * 100 : bat.percentage) : -1
    readonly property bool charging: bat && bat.isPresent && bat.state === UPowerDeviceState.Charging

    height: 96 * u
    opacity: reveal
    transform: Translate { y: -(1 - root.reveal) * 26 * root.u }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Row {
        id: tabs
        x: 72 * root.u
        anchors.verticalCenter: parent.verticalCenter
        spacing: 38 * root.u

        Repeater {
            model: [ { k: "home", t: "Apps" }, { k: "library", t: "Library" } ]
            delegate: Item {
                id: tab
                required property var modelData
                readonly property bool isActive: root.page === modelData.k
                width: label.width + 28 * root.u
                height: 48 * root.u

                // focus pill (only while the tab bar itself has focus)
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.16)
                    opacity: tab.isActive && root.tabFocus ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.focus } }
                }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: tab.modelData.t
                    font.family: Theme.fontFamily
                    font.pixelSize: 22 * root.u
                    font.weight: tab.isActive ? Font.DemiBold : Font.Normal
                    color: tab.isActive ? Theme.fg : Theme.fgDim
                    Behavior on color { ColorAnimation { duration: Motion.focus } }
                }

                // underline
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: label.width
                    height: 3 * root.u
                    radius: height / 2
                    color: Theme.fg
                    opacity: tab.isActive ? 1 : 0
                    transform: Scale {
                        origin.x: width / 2
                        xScale: tab.isActive ? 1 : 0.25
                        Behavior on xScale {
                            NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                        }
                    }
                    Behavior on opacity { NumberAnimation { duration: Motion.focus } }
                }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 72 * root.u
        anchors.verticalCenter: parent.verticalCenter
        spacing: 28 * root.u

        // battery
        Row {
            visible: root.pct >= 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.u
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.iconFont
                font.pixelSize: 20 * root.u
                color: Theme.fg
                text: root.charging ? "\uf0e7"
                    : root.pct > 85 ? "\uf240"
                    : root.pct > 60 ? "\uf241"
                    : root.pct > 35 ? "\uf242"
                    : root.pct > 10 ? "\uf243" : "\uf244"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: 18 * root.u
                color: Theme.fg
                text: Math.round(root.pct) + "%"
            }
        }

        // clock
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: 24 * root.u
            font.weight: Font.Medium
            color: Theme.fg
            text: Qt.formatDateTime(clock.date, "hh:mm")
        }

        // avatar (~/pfp.jpg; the accent colour shows if the file is missing)
        ClippingRectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 46 * root.u
            height: width
            radius: width / 2
            color: Theme.accent
            Image {
                anchors.fill: parent
                source: "file://" + Quickshell.env("HOME") + "/pfp.jpg"
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
    }
}
