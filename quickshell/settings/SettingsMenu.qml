import QtQuick
import "../core"
import "../hub"

// viii-settings-menu: the one reusable category page.
//
// Layout (from the PS5 settings screen):
//   * item list on the left, 30% of the inner width;
//   * editable value / slider / toggle on the right, the remaining 70%;
//   * the caller owns the 10% screen padding, so this component only lays out its own width.
//
// Selection is drawn with the shared GlassRing and nothing else: the ring owns both the outline
// and the travelling overlay shade. There is deliberately no filled "selected row" background.
Item {
    id: root

    property var category: ({})
    property var rows: []
    property int currentIndex: 0
    property string armed: ""
    property bool running: true

    // The page owns the backend; the menu only asks for display values. These are plain
    // function properties so the component stays reusable for any settings backend.
    property var valueOf: function(action) { return ""; }
    property var toggleOf: function(action) { return false; }
    property var fractionOf: function(action) { return 0; }

    signal activated()
    signal adjusted(int delta)
    signal rowClicked(int index)
    signal sliderAt(string action, real fraction)
    signal sliderEnd()

    readonly property real gap: 24
    readonly property real listW: Math.round((width - gap) * 0.30)
    readonly property real detailX: listW + gap
    readonly property real detailW: Math.max(0, width - detailX)
    readonly property real rowH: 66
    readonly property real rowGap: 6
    readonly property real pitch: rowH + rowGap
    readonly property real panelY: 96
    readonly property real panelH: 520

    readonly property int safeIndex: rows.length > 0
        ? Math.max(0, Math.min(rows.length - 1, currentIndex)) : 0
    readonly property var cur: rows.length > 0 ? rows[safeIndex] : null
    readonly property string kind: cur ? String(cur.kind || "info") : "info"
    readonly property string action: cur ? String(cur.action || "") : ""
    readonly property bool isOn: kind === "toggle" ? !!toggleOf(action) : false
    readonly property real frac: kind === "slider"
        ? Math.max(0, Math.min(1, Number(fractionOf(action)) || 0)) : 0
    readonly property bool armedNow: armed !== "" && armed === action
    readonly property string hint: {
        switch (kind) {
        case "slider": return "← / →   Adjust";
        case "cycle": return "← / →   Change";
        case "toggle": return "Enter   Toggle";
        case "action": return armedNow ? "Enter   Confirm" : "Enter   Activate";
        default: return "";
        }
    }

    component MenuText: Text {
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 16
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    // ---- header ----
    MenuText {
        x: 0; y: 0
        width: Math.max(0, root.width - 180)
        text: root.category && root.category.title ? root.category.title : ""
        font.pixelSize: 32
        font.weight: Font.DemiBold
    }
    MenuText {
        x: 0; y: 47
        width: Math.max(0, root.width - 180)
        text: root.category && root.category.description ? root.category.description : ""
        font.pixelSize: 14
        color: Theme.fgDim
    }
    MenuText {
        anchors.right: parent.right
        y: 8
        width: 170
        text: "Esc   Back"
        font.pixelSize: 12
        color: Theme.fgDim
        horizontalAlignment: Text.AlignRight
    }

    // ---- left: item list (text only; the ring is the only decoration) ----
    Column {
        x: 0; y: root.panelY
        width: root.listW
        spacing: root.rowGap

        Repeater {
            model: root.rows.length

            delegate: Item {
                id: item
                required property int index

                readonly property var entry: root.rows[index] || null
                readonly property bool selected: root.currentIndex === index

                width: root.listW
                height: root.rowH

                Column {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, root.listW - 32)
                    spacing: 5

                    MenuText {
                        width: parent.width
                        text: item.entry ? String(item.entry.title || "") : ""
                        font.pixelSize: 16
                        font.weight: item.selected ? Font.DemiBold : Font.Medium
                        color: item.selected ? Theme.fg : Theme.fgDim
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                    MenuText {
                        width: parent.width
                        text: item.entry ? String(item.entry.desc || "") : ""
                        font.pixelSize: 12
                        color: Theme.fgDim
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.rowClicked(item.index)
                }
            }
        }
    }

    // ---- the one selection marker: shared ring + overlay shade ----
    GlassRing {
        readonly property real out: 3.5
        x: -out
        y: root.panelY + root.safeIndex * root.pitch - out
        width: root.listW + 2 * out
        height: root.rowH + 2 * out
        radius: 3 + out
        thickness: 2.5
        shade: true
        trigger: root.safeIndex
        animated: root.running
        visible: root.rows.length > 0
        // when the page becomes the visible layer again, replay the shade from its start
        onAnimatedChanged: if (animated && visible) play()
        z: 3
        opacity: visible ? 1 : 0
        Behavior on y {
            NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        }
    }

    // ---- right: the selected item's control (no panel; text and controls only) ----
    Item {
        id: detail
        x: root.detailX + 34
        y: root.panelY + 30
        width: Math.max(0, root.detailW - 68)
        height: root.panelH - 60

        MenuText {
            x: 0; y: 0
            text: "SELECTED"
            font.pixelSize: 11
            font.letterSpacing: 1.6
            color: Theme.fgDim
        }
        MenuText {
            x: 0; y: 18
            width: detail.width
            text: root.cur ? String(root.cur.title || "") : ""
            font.pixelSize: 24
            font.weight: Font.DemiBold
        }
        MenuText {
            x: 0; y: 56
            width: detail.width
            text: root.cur ? String(root.cur.desc || "") : ""
            font.pixelSize: 13
            color: Theme.fgDim
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        MenuText {
            x: 0; y: 120
            text: root.kind === "toggle" ? "STATE"
                : (root.kind === "action" ? "ACTION"
                : (root.kind === "info" ? "INFORMATION" : "VALUE"))
            font.pixelSize: 11
            font.letterSpacing: 1.6
            color: Theme.fgDim
        }
        MenuText {
            x: 0; y: 140
            width: detail.width
            text: root.action !== "" ? String(root.valueOf(root.action)) : ""
            font.pixelSize: root.kind === "cycle" ? 28 : 36
            font.weight: Font.DemiBold
            color: root.armedNow ? Theme.accent : Theme.fg
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        // slider
        Item {
            id: sliderItem
            visible: root.kind === "slider"
            x: 0; y: 214
            width: Math.min(440, detail.width)
            height: 30

            readonly property real knobW: 18
            readonly property real usable: Math.max(1, width - knobW)

            Rectangle {
                id: track
                x: sliderItem.knobW / 2
                anchors.verticalCenter: parent.verticalCenter
                width: sliderItem.usable
                height: 6
                radius: 3
                color: Theme.glassHi
                Rectangle {
                    height: parent.height
                    radius: 3
                    width: track.width * root.frac
                    color: Theme.accent
                    Behavior on width {
                        enabled: !slideArea.pressed
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                }
            }
            Rectangle {
                width: sliderItem.knobW; height: sliderItem.knobW
                radius: sliderItem.knobW / 2
                anchors.verticalCenter: parent.verticalCenter
                x: sliderItem.knobW / 2 + sliderItem.usable * root.frac - width / 2
                color: Theme.fg
                scale: slideArea.pressed ? 1.25 : (slideArea.containsMouse ? 1.12 : 1)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                Behavior on x {
                    enabled: !slideArea.pressed
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
            }
            MouseArea {
                id: slideArea
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function apply(mx) {
                    root.sliderAt(root.action, Math.max(0, Math.min(1,
                        (mx - 8 - sliderItem.knobW / 2) / sliderItem.usable)));
                }
                onPressed: mouse => apply(mouse.x)
                onPositionChanged: mouse => { if (pressed) apply(mouse.x); }
                onReleased: root.sliderEnd()
                onCanceled: root.sliderEnd()
            }
        }

        // toggle
        Item {
            visible: root.kind === "toggle"
            x: 0; y: 208
            width: 80; height: 42

            Rectangle {
                anchors.fill: parent
                radius: 21
                color: root.isOn ? Theme.accent : Theme.glassHi
                border.width: 1
                border.color: Theme.glassBorder
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            Rectangle {
                width: 34; height: 34
                radius: 17
                y: 4
                x: root.isOn ? 42 : 4
                color: root.isOn ? Theme.accentText : Theme.fgDim
                Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated()
            }
        }

        // cycle: the big value above is the current choice, these change it
        Row {
            visible: root.kind === "cycle"
            x: 0; y: 212
            spacing: 18

            Item {
                width: 48; height: 42
                MenuText {
                    anchors.centerIn: parent
                    text: "‹"
                    font.pixelSize: 26
                    color: prevArea.containsMouse ? Theme.accent : Theme.fg
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                MouseArea {
                    id: prevArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.adjusted(-1)
                }
            }
            Item {
                width: 48; height: 42
                MenuText {
                    anchors.centerIn: parent
                    text: "›"
                    font.pixelSize: 26
                    color: nextArea.containsMouse ? Theme.accent : Theme.fg
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                MouseArea {
                    id: nextArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.adjusted(1)
                }
            }
        }

        // action
        Item {
            visible: root.kind === "action"
            x: 0; y: 214
            width: Math.min(300, detail.width)
            height: 40

            MenuText {
                anchors.centerIn: parent
                text: root.armedNow ? "Press Enter again" : "Press Enter"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: root.armedNow ? Theme.accent
                    : (actionArea.containsMouse ? Theme.accent : Theme.fg)
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            MouseArea {
                id: actionArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated()
            }
        }

        // info
        MenuText {
            visible: root.kind === "info"
            x: 0; y: 216
            width: detail.width
            text: "Read only"
            font.pixelSize: 14
            color: Theme.fgDim
        }

        MenuText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.hint
            font.pixelSize: 12
            color: root.armedNow ? Theme.accent : Theme.fgDim
            horizontalAlignment: Text.AlignLeft
        }
    }
}
