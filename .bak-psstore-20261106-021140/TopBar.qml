import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../core"

// Tabs on the left; battery, clock and avatar on the right. Works in the 1366x768 design space.
Item {
    id: root
    property int page: 0
    property bool tabsFocus: false
    property bool gearFocus: false
    property bool bellFocus: false
    property bool searchFocus: false
    property bool searchOpen: false
    property string query: ""
    signal tabClicked(int index)
    signal settingsClicked()
    signal historyClicked()
    signal searchClicked()

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
                    opacity: (tab.cur && root.tabsFocus && !root.gearFocus && !root.bellFocus) ? 1 : 0
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
        anchors.rightMargin: 35
        y: 38
        spacing: 24
        layoutDirection: Qt.LeftToRight

        // Search: click it, or just type a letter anywhere. Grows into a field while searching.
        Item {
            id: searchBox
            readonly property bool active: root.searchOpen
            readonly property bool hot: searchArea.containsMouse || root.searchFocus
            property bool caretOn: true
            width: active ? 270 : 42
            height: 42
            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            scale: searchArea.pressed ? 0.97 : ((hot && !active) ? 1.08 : 1)
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Timer {
                interval: 530
                repeat: true
                running: searchBox.active
                onTriggered: searchBox.caretOn = !searchBox.caretOn
                onRunningChanged: searchBox.caretOn = true
            }
            Rectangle {
                anchors.fill: parent
                radius: 21
                color: Theme.glassHi
                border.width: 1
                border.color: searchBox.active ? Theme.fg : Theme.glassBorder
                opacity: (searchBox.hot || searchBox.active) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            Txt {
                x: searchBox.active ? 13 : (searchBox.width - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                font.family: Theme.iconFont
                font.pixelSize: 19
                color: Theme.fg
            }
            Txt {
                id: sText
                x: 42
                width: searchBox.width - 56
                anchors.verticalCenter: parent.verticalCenter
                visible: searchBox.width > 120
                opacity: searchBox.active ? 1 : 0
                text: root.query !== "" ? root.query : "Search apps"
                color: root.query !== "" ? Theme.fg : Theme.fgDim
                elide: Text.ElideLeft
                font.pixelSize: 17
            }
            Rectangle {
                x: 42 + (root.query !== "" ? Math.min(sText.contentWidth, sText.width) + 2 : 0)
                anchors.verticalCenter: parent.verticalCenter
                width: 2; height: 20; radius: 1
                color: Theme.fg
                visible: searchBox.active && searchBox.caretOn && searchBox.width > 120
            }
            MouseArea {
                id: searchArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.searchClicked()
            }
        }

        // Notification history bell (opens the history page; SUPER+N does the same).
        Item {
            width: 42; height: 42
            readonly property bool hot: bellArea.containsMouse || root.bellFocus
            scale: bellArea.pressed ? 0.94 : (hot ? 1.08 : 1)
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Rectangle {
                anchors.fill: parent
                radius: 21
                color: Theme.glassHi
                border.width: 1
                border.color: Theme.glassBorder
                opacity: parent.hot ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            Txt {
                anchors.centerIn: parent
                text: "\uf0f3"
                font.family: Theme.iconFont
                font.pixelSize: 20
                color: Theme.fg
            }
            MouseArea {
                id: bellArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.historyClicked()
            }
        }

        // battery
        Item {
            readonly property real pct: UPower.displayDevice ? UPower.displayDevice.percentage : -1
            readonly property bool charging: !!UPower.displayDevice && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged || UPower.displayDevice.state === UPowerDeviceState.PendingCharge)
            visible: pct >= 0
            width: visible ? 86 : 0
            height: 42
            Rectangle {
                id: body
                x: 12; y: 14
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
                    color: parent.parent.charging ? "#6bdc8b" : (parent.parent.pct < 0.15 ? "#ff6b6b" : Theme.fg)
                }
            }
            Rectangle { x: 41.5; y: 17.5; width: 3; height: 7; radius: 1.5; color: Theme.fg }
            // charging bolt: drawn once, repainted only when the colour changes
            Canvas {
                id: bolt
                x: 0; y: 13
                width: 10; height: 16
                property color ink: Theme.fg
                opacity: parent.charging ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }
                onInkChanged: requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = bolt.ink;
                    ctx.beginPath();
                    ctx.moveTo(6.5, 0);
                    ctx.lineTo(0, 9.5);
                    ctx.lineTo(4.6, 9.5);
                    ctx.lineTo(3.2, 16);
                    ctx.lineTo(10, 6);
                    ctx.lineTo(5.4, 6);
                    ctx.closePath();
                    ctx.fill();
                }
            }
            Txt { x: 52; y: (42 - height) / 2; text: Math.round(Math.max(0, parent.pct) * 100) + "%"; font.pixelSize: 16 }
        }

        // Settings gear, matching the PS5 home screen's top-right utility icons.
        Item {
            width: 42; height: 42
            readonly property bool hot: gearArea.containsMouse || root.gearFocus
            scale: gearArea.pressed ? 0.94 : (hot ? 1.08 : 1)
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            // hover surface fades by opacity (a colour fade from "transparent" dips through black)
            Rectangle {
                anchors.fill: parent
                radius: 21
                color: Theme.glassHi
                border.width: 1
                border.color: Theme.glassBorder
                opacity: parent.hot ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            Txt {
                anchors.centerIn: parent
                text: ""
                font.family: Theme.iconFont
                font.pixelSize: 21
                color: Theme.fg
                rotation: parent.hot ? 60 : 0
                Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: gearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsClicked()
            }
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
            Image {
                anchors.fill: parent
                source: Profile.picUrl
                sourceSize.width: 84
                sourceSize.height: 84
                fillMode: Image.PreserveAspectCrop
                visible: Profile.picUrl !== ""
            }
            Txt {
                anchors.centerIn: parent
                visible: Profile.picUrl === ""
                text: Profile.display.charAt(0).toUpperCase()
                font.pixelSize: 18
                font.weight: Font.Bold
                color: Theme.accentText
            }
        }
        
        // clock
        Txt {
            y: (42 - height) / 2
            text: Qt.formatDateTime(clk.date, "HH:mm")
            font.pixelSize: 24
            font.weight: Font.Medium
        }
    }
}
