import QtQuick
import "../core"

// The home row. Selected tile grows and sits on the left, the rest stream off to the right.
// Under it: name, an Open pill, and screen time (the "trophy" slot of a PS5 home screen).
Item {
    id: root

    property var entries: []
    property bool active: true
    property bool rowFocus: true
    property real reveal: 1

    signal launchRequested(var entry, Item tile)
    signal libraryRequested()

    readonly property real u: height / 768
    readonly property real smallSize: 148 * u
    readonly property real bigSize: 236 * u
    readonly property real gap: 18 * u
    readonly property real lead: 72 * u

    readonly property var model: entries.concat([{ isLibrary: true, name: "Library" }])
    readonly property var currentEntry: model.length > 0 ? model[Math.min(list.currentIndex, model.length - 1)] : null
    readonly property string iconSource: (currentEntry && !currentEntry.isLibrary) ? "file://" + Apps.iconPath(currentEntry) : ""

    // biggest 7-day total in the row, so every progress bar is relative
    readonly property real weekMax: {
        void ScreenTime.revision;
        let m = 0;
        for (let i = 0; i < entries.length; i++) m = Math.max(m, ScreenTime.sum(entries[i], 7));
        return m;
    }

    function reset() {
        list.animateScroll = false;
        list.currentIndex = 0;
        list.contentX = list.originX;
        Qt.callLater(() => { list.animateScroll = true; });
    }

    function goTo(i) {
        const n = Math.max(0, Math.min(model.length - 1, i));
        list.currentIndex = n;
        list.contentX = list.originX + n * (smallSize + gap);
    }

    function step(dir) { goTo(list.currentIndex + dir); }

    function activate() {
        const e = currentEntry;
        if (!e) return;
        if (e.isLibrary) libraryRequested();
        else launchRequested(e, list.itemAtIndex(list.currentIndex));
    }

    function retint() {
        if (currentEntry) Theme.applyPalette(Apps.paletteFor(currentEntry));
    }

    onCurrentEntryChanged: if (active) retint()
    Connections {
        target: Apps
        function onPalettesChanged() { if (root.active) root.retint(); }
    }

    ListView {
        id: list
        property bool animateScroll: false

        anchors.left: parent.left
        anchors.right: parent.right
        y: root.height * 0.24
        height: root.bigSize + 36 * root.u
        orientation: ListView.Horizontal
        interactive: false
        spacing: root.gap
        leftMargin: root.lead
        rightMargin: width - root.lead - root.bigSize
        model: root.model
        currentIndex: 0
        cacheBuffer: 1600

        Behavior on contentX {
            enabled: list.animateScroll
            NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
        }

        delegate: Tile {
            id: tile
            required property var modelData
            required property int index

            entry: modelData
            u: root.u
            readonly property bool isCurrent: index === list.currentIndex
            focused: isCurrent && root.rowFocus && root.active
            size: isCurrent ? root.bigSize : root.smallSize
            // staggered entrance: each tile starts a little later than the one before it
            appear: Math.max(0, Math.min(1, root.reveal * 1.7 - index * 0.09))
            y: ListView.view.height - height - 20 * root.u

            onActivated: {
                if (isCurrent) root.activate();
                else root.goTo(index);
            }
        }
    }

    // ---- info under the selected tile ----
    Item {
        id: info
        x: root.lead
        y: list.y + list.height + 14 * root.u
        width: root.width - 2 * root.lead
        height: 190 * root.u

        property var shown: null
        property real swap: 1
        opacity: swap * root.reveal
        transform: Translate { y: (1 - info.swap) * 14 * root.u }

        readonly property bool isLib: shown !== null && shown.isLibrary === true
        readonly property real todaySecs: (shown && !isLib) ? ScreenTime.sum(shown, 1) : 0
        readonly property real weekSecs: (shown && !isLib) ? ScreenTime.sum(shown, 7) : 0

        Component.onCompleted: shown = root.currentEntry

        Connections {
            target: root
            function onCurrentEntryChanged() { swapAnim.restart(); }
        }

        SequentialAnimation {
            id: swapAnim
            NumberAnimation { target: info; property: "swap"; to: 0; duration: 80 }
            ScriptAction { script: info.shown = root.currentEntry }
            NumberAnimation {
                target: info; property: "swap"; to: 1
                duration: Motion.focus + 140
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out
            }
        }

        Column {
            spacing: 6 * root.u

            Text {
                text: info.shown ? info.shown.name : ""
                font.family: Theme.fontFamily
                font.pixelSize: 34 * root.u
                font.weight: Font.DemiBold
                color: Theme.fg
                elide: Text.ElideRight
                width: info.width
            }

            Text {
                text: info.isLib ? "All installed apps"
                    : (info.shown ? (info.shown.genericName || info.shown.comment || "") : "")
                font.family: Theme.fontFamily
                font.pixelSize: 15 * root.u
                color: Theme.fgDim
                elide: Text.ElideRight
                width: info.width * 0.7
            }

            Item { width: 1; height: 12 * root.u }

            Row {
                spacing: 34 * root.u

                // Open pill
                Rectangle {
                    id: pill
                    width: pillText.width + 70 * root.u
                    height: 52 * root.u
                    radius: height / 2
                    color: "white"
                    scale: root.rowFocus ? 1 : 0.95
                    opacity: root.rowFocus ? 1 : 0.7
                    Behavior on scale { NumberAnimation { duration: Motion.focus; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
                    Behavior on opacity { NumberAnimation { duration: Motion.focus } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 12 * root.u
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: info.isLib ? "\uf00a" : "\uf04b"
                            font.family: Theme.iconFont
                            font.pixelSize: 16 * root.u
                            color: "#101114"
                        }
                        Text {
                            id: pillText
                            anchors.verticalCenter: parent.verticalCenter
                            text: info.isLib ? "Browse" : "Open"
                            font.family: Theme.fontFamily
                            font.pixelSize: 19 * root.u
                            font.weight: Font.DemiBold
                            color: "#101114"
                        }
                    }
                }

                // screen time
                Column {
                    visible: !info.isLib
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9 * root.u

                    Row {
                        spacing: 30 * root.u
                        Column {
                            Text {
                                text: "TODAY"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11 * root.u
                                font.letterSpacing: 1.6
                                color: Theme.fgDim
                            }
                            Text {
                                text: ScreenTime.fmt(info.todaySecs)
                                font.family: Theme.fontFamily
                                font.pixelSize: 24 * root.u
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }
                        }
                        Column {
                            Text {
                                text: "7 DAYS"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11 * root.u
                                font.letterSpacing: 1.6
                                color: Theme.fgDim
                            }
                            Text {
                                text: ScreenTime.fmt(info.weekSecs)
                                font.family: Theme.fontFamily
                                font.pixelSize: 24 * root.u
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }
                        }
                    }

                    // progress bar (this app vs the most used app of the week)
                    Rectangle {
                        width: 250 * root.u
                        height: 6 * root.u
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.18)
                        Rectangle {
                            height: parent.height
                            radius: height / 2
                            color: Theme.accent
                            width: root.weekMax > 0 ? parent.width * Math.min(1, info.weekSecs / root.weekMax) : 0
                            Behavior on width {
                                NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                            }
                        }
                    }
                }
            }
        }
    }
}
