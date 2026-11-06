import QtQuick
import "../core"
import "../hub"

// Step 1: the PS5 language page. A centred title, one vertical list that scrolls under a fixed focus ring
// (GlassRing with its shade), the language in use ticked, and a Next pill below. Picking a language also
// applies the keyboard layout straight away (viii-kb). (Layout from memory of the PS5 setup.)
Item {
    id: root
    required property var ctl
    property bool active: false
    width: 1366
    height: 768

    property int idx: 0
    property bool onNext: false
    readonly property int n: ctl.kbLayouts.length
    readonly property real rowH: 64
    readonly property real listW: 560
    readonly property real centerY: 340

    property real pos: idx
    Behavior on pos {
        NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    function place() {
        onNext = false;
        for (let i = 0; i < n; i++) {
            if (ctl.kbLayouts[i].code === ctl.kbCode) { idx = i; return; }
        }
        idx = 0;
    }
    onActiveChanged: if (active) place()
    Connections {
        target: root.ctl
        function onKbCodeChanged() { if (!root.active && root.ctl.step < 1) root.place(); }
    }

    function pick(i) { if (i >= 0 && i < n) ctl.setKeyboard(ctl.kbLayouts[i].code); }

    function handleKey(e) {
        const k = e.key;
        if (k === Qt.Key_Up) { if (onNext) onNext = false; else idx = Math.max(0, idx - 1); }
        else if (k === Qt.Key_Down) { if (!onNext) { if (idx < n - 1) idx += 1; else onNext = true; } }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (onNext) ctl.next(); else pick(idx); }
        else if (k === Qt.Key_Escape) ctl.prev();
        else { e.accepted = false; return; }
        e.accepted = true;
    }

    Txt {
        x: 0
        y: 62
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: "Language"
        font.pixelSize: 36
    }
    Txt {
        x: 0
        y: 116
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: "This also sets your keyboard layout."
        font.pixelSize: 17
        color: Theme.fgDim
    }

    Item {
        x: (root.width - root.listW) / 2
        y: 0
        width: root.listW
        height: root.height

        Repeater {
            model: root.n
            delegate: Item {
                id: row
                required property int index
                readonly property var entry: root.ctl.kbLayouts[index]
                readonly property real dist: index - root.pos
                readonly property bool sel: !root.onNext && root.idx === index
                x: 0
                y: root.centerY + dist * root.rowH - root.rowH / 2
                width: root.listW
                height: root.rowH
                opacity: Math.max(0, 1 - Math.abs(dist) * 0.3) * (root.onNext ? 0.75 : 1)
                visible: opacity > 0.02

                Txt {
                    x: 30
                    width: parent.width - 100
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.entry.name
                    font.pixelSize: 22
                    color: row.sel ? Theme.fg : Theme.fgDim
                    Behavior on color { ColorAnimation { duration: 160 } }
                }
                Txt {
                    anchors.right: parent.right
                    anchors.rightMargin: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2713"
                    font.pixelSize: 22
                    visible: root.ctl.kbCode === row.entry.code
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.onNext = false; root.idx = row.index; root.pick(row.index); }
                }
            }
        }

        // the focus ring stays in the middle; the list scrolls under it
        GlassRing {
            readonly property real out: 3.5
            x: -out
            y: root.centerY - (root.rowH - 10) / 2 - out
            width: root.listW + 2 * out
            height: root.rowH - 10 + 2 * out
            radius: 14 + out
            thickness: 2.5
            shade: true
            trigger: root.idx
            animated: root.active
            opacity: root.onNext ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
    }

    Txt {
        x: 0
        y: 566
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        visible: text !== ""
        text: root.ctl.kbStatus
        font.pixelSize: 14
        color: root.ctl.kbStatusKind === "error" ? "#ff6b6b" : Theme.fgDim
    }

    Pill {
        x: (root.width - width) / 2
        y: 632
        label: "Next"
        on: root.onNext && root.active
        onClicked: root.ctl.next()
    }
}
