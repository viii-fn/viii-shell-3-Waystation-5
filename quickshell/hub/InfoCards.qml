import QtQuick
import "../core"

// The row of glass cards under the Open button: today, last 7 days (bar chart), share of the most-used app.
Row {
    id: root
    property var entry: null
    property real topSum: 0
    spacing: 14

    readonly property real today: { void ScreenTime.revision; return entry ? ScreenTime.sum(entry, 1) : 0; }
    readonly property real week: { void ScreenTime.revision; return entry ? ScreenTime.sum(entry, 7) : 0; }
    readonly property var series: {
        void ScreenTime.revision;
        const out = [];
        if (!entry) return out;
        for (let i = 6; i >= 0; i--) out.push(ScreenTime.sum(entry, i + 1) - ScreenTime.sum(entry, i));
        return out;
    }
    readonly property real maxDay: Math.max(60, ...series)
    readonly property int pct: topSum > 0 ? Math.round(100 * week / topSum) : 0

    component Card: Item {
        property string label: ""
        height: 124
        GlassSlot { anchors.fill: parent; radius: 18 }
        Txt {
            x: 20; y: 16
            text: parent.label
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 1.6
            color: Theme.fgDim
        }
    }

    Card {
        width: 196
        label: "TODAY"
        Txt { x: 20; y: 42; text: ScreenTime.fmt(root.today); font.pixelSize: 38; font.weight: Font.Bold }
        Txt { x: 20; y: 94; text: root.today >= 60 ? "screen time" : "no usage yet"; font.pixelSize: 13; color: Theme.fgDim }
    }

    Card {
        width: 340
        label: "LAST 7 DAYS"
        Txt { x: 20; y: 42; text: ScreenTime.fmt(root.week); font.pixelSize: 38; font.weight: Font.Bold }
        Txt { x: 20; y: 94; text: "this week"; font.pixelSize: 13; color: Theme.fgDim }
        Item {
            x: parent.width - 20 - 150
            y: 18
            width: 150
            height: 90
            Repeater {
                model: 7
                delegate: Item {
                    required property int index
                    readonly property real v: index < root.series.length ? root.series[index] : 0
                    x: index * 22
                    width: 14
                    height: 90
                    Rectangle {
                        width: 14
                        height: 4 + (parent.v / root.maxDay) * 54
                        y: 66 - height
                        radius: 5
                        color: parent.index === 6 ? Theme.accent : Theme.glassBorder
                        Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
                    }
                    Txt {
                        x: (14 - width) / 2
                        y: 72
                        text: Qt.formatDate(new Date(Date.now() - (6 - parent.index) * 86400000), "ddd").charAt(0)
                        font.pixelSize: 11
                        color: parent.index === 6 ? Theme.fg : Theme.fgDim
                    }
                }
            }
        }
    }

    Card {
        width: 290
        label: "VS MOST USED"
        Txt { x: 20; y: 42; text: root.pct + "%"; font.pixelSize: 38; font.weight: Font.Bold }
        Rectangle { x: 20; y: 98; width: parent.width - 40; height: 6; radius: 3; color: Theme.glass
            Rectangle {
                height: parent.height
                radius: 3
                color: Theme.accent
                width: parent.width * Math.min(100, root.pct) / 100
                Behavior on width { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            }
        }
    }
}
