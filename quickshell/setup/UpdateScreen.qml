import QtQuick
import "../core"
import "../hub"

// Step 4: the PS5 "system software update" page. Centred: a title, one status line, a progress bar with its
// percentage, and below it a quiet checklist of what is being installed. viii-deps runs in the background (no
// window). The password and the optional full update are asked in centred dialogs with pill buttons.
// (Layout from memory of the PS5 setup.)
Item {
    id: root
    required property var ctl
    property bool active: false
    width: 1366
    height: 768
    signal focusBack()

    readonly property string phase: ctl.updPhase
    property int sel: 0                 // dialog / button selection

    onPhaseChanged: {
        sel = 0;
        if (phase === "auth") { pwField.text = ""; pwField.forceActiveFocus(); }
        else if (pwField.activeFocus) root.focusBack();
    }

    function handleKey(e) {
        const k = e.key;
        const p = phase;
        if (p === "auth") {
            if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Escape) pwField.forceActiveFocus();
            e.accepted = true;
            return;
        }
        const two = (p === "ask" || p === "error");
        if (two && (k === Qt.Key_Left || k === Qt.Key_Right)) { sel = k === Qt.Key_Left ? 0 : 1; e.accepted = true; return; }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { choose(); e.accepted = true; return; }
        if (k === Qt.Key_Escape && p === "ask") { ctl.resultText = "Your system was not updated."; ctl.updPhase = "finish"; e.accepted = true; return; }
        e.accepted = false;
    }
    function choose() {
        const p = phase;
        if (p === "ask") {
            if (sel === 0) ctl.startFullUpdate();
            else { ctl.resultText = ctl.missingCount > 0 ? "Some packages are still missing." : "Everything Waystation needs is installed."; ctl.updPhase = "finish"; }
        }
        else if (p === "error") { if (sel === 0) ctl.retry(); else ctl.finish(); }
        else if (p === "finish" || p === "unsupported") ctl.finish();
    }

    readonly property string title: {
        switch (phase) {
        case "check": return "Checking your system";
        case "auth": return "Administrator access needed";
        case "install": return "Installing system software";
        case "ask": return ctl.missingCount > 0 ? "Some packages couldn\u2019t be installed" : "System software is ready";
        case "full": return "Updating your system";
        case "finish": return "You\u2019re all set";
        case "unsupported": return "Automatic install isn\u2019t available";
        case "error": return "Something went wrong";
        default: return "System Software";
        }
    }
    readonly property bool busy: phase === "check" || phase === "install" || phase === "full"
    readonly property bool showBar: phase === "install" || phase === "full" || phase === "ask" || phase === "finish"

    // spinner above the title while something runs
    Txt {
        x: (root.width - width) / 2
        y: 84
        text: "\u25cc"
        font.pixelSize: 40
        color: Theme.accent
        opacity: root.busy ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.busy && root.active }
    }
    Txt {
        x: 0
        y: 142
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root.title
        font.pixelSize: 36
    }
    Txt {
        x: (root.width - 760) / 2
        y: 200
        width: 760
        horizontalAlignment: Text.AlignHCenter
        text: root.phase === "finish" || root.phase === "unsupported" || root.phase === "error" ? root.ctl.resultText
              : (root.ctl.phaseText !== "" ? root.ctl.phaseText : (root.ctl.pretty !== "" ? "Detected: " + root.ctl.pretty : ""))
        font.pixelSize: 18
        color: Theme.fgDim
        wrapMode: Text.WordWrap
        maximumLineCount: 2
    }

    // progress bar
    Item {
        x: (root.width - 640) / 2
        y: 270
        width: 640
        height: 30
        opacity: root.showBar ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 240 } }
        Rectangle {
            id: track
            y: 4
            width: parent.width
            height: 6
            radius: 3
            color: Theme.glassHi
            clip: true
            Rectangle {
                height: parent.height
                radius: 3
                color: Theme.accent
                visible: !root.ctl.indeterminate
                width: track.width * root.ctl.progress
                Behavior on width { NumberAnimation { duration: Motion.scroll; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            }
            Rectangle {
                height: parent.height
                width: 140
                radius: 3
                color: Theme.accent
                visible: root.ctl.indeterminate
                SequentialAnimation on x {
                    loops: Animation.Infinite
                    running: root.ctl.indeterminate && root.active
                    NumberAnimation { from: -140; to: track.width; duration: 1500; easing.type: Easing.InOutSine }
                }
            }
        }
        Txt {
            y: 16
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: !root.ctl.indeterminate
            text: Math.round(root.ctl.progress * 100) + "%"
            font.pixelSize: 14
            color: Theme.fgDim
        }
    }

    // the checklist: two quiet columns, keyed on the count so a status change updates the text in place
    Grid {
        x: (root.width - 640) / 2
        y: 336
        columns: 2
        columnSpacing: 40
        rowSpacing: 2
        Repeater {
            model: root.ctl.pkgs.length
            delegate: Item {
                id: cell
                required property int index
                readonly property var e: root.ctl.pkgs[index] || ({ label: "", state: "", note: "" })
                width: 300
                height: 27
                Txt {
                    x: 2
                    width: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: cell.e.state === "installing" ? "\u25cc" : (cell.e.state === "ok" || cell.e.state === "have" ? "\u2713" : (cell.e.state === "failed" ? "!" : (cell.e.state === "missing" ? "\u2013" : "\u00b7")))
                    font.pixelSize: 15
                    color: cell.e.state === "failed" ? "#ff6b6b" : (cell.e.state === "installing" ? Theme.accent : (cell.e.state === "ok" ? Theme.fg : Theme.fgDim))
                    RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: cell.e.state === "installing" && root.active }
                }
                Txt {
                    x: 30
                    width: parent.width - 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: cell.e.label + (cell.e.state === "missing" ? "  \u00b7  " + cell.e.note : "")
                    font.pixelSize: 15
                    color: cell.e.state === "ok" || cell.e.state === "installing" ? Theme.fg : Theme.fgDim
                }
            }
        }
    }

    // the installer's last words, for when something goes wrong
    Text {
        x: (root.width - 900) / 2
        y: 604
        width: 900
        horizontalAlignment: Text.AlignHCenter
        color: Theme.fgDim
        opacity: 0.7
        font.family: "monospace"
        font.pixelSize: 12
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.NoWrap
        text: root.ctl.logLines.slice(-2).join("\n")
        visible: root.phase !== "check"
    }

    // ---- bottom buttons
    Pill {
        x: (root.width - width) / 2
        y: 656
        visible: root.phase === "finish" || root.phase === "unsupported"
        label: root.phase === "finish" ? "Finish" : "Continue"
        on: root.active
        onClicked: root.ctl.finish()
    }
    Row {
        x: (root.width - width) / 2
        y: 656
        spacing: 24
        visible: root.phase === "error"
        Pill { label: "Try again"; on: root.active && root.sel === 0; onClicked: { root.sel = 0; root.choose(); } }
        Pill { label: "Continue"; on: root.active && root.sel === 1; onClicked: { root.sel = 1; root.choose(); } }
    }

    // ---- dialog: administrator password
    Item {
        id: dlgPass
        anchors.fill: parent
        z: 20
        property real pT: root.phase === "auth" ? 1 : 0
        Behavior on pT { NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        opacity: pT
        visible: pT > 0.01
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.62); MouseArea { anchors.fill: parent } }
        Item {
            width: 500
            height: 280
            x: (parent.width - width) / 2
            y: 236 + (1 - dlgPass.pT) * 16
            scale: 0.96 + 0.04 * dlgPass.pT
            Rectangle { anchors.fill: parent; radius: 24; color: Qt.rgba(0.06, 0.065, 0.08, 0.97) }
            GlassSlot { anchors.fill: parent; radius: 24; alpha: 1 }
            Txt { x: 0; y: 28; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Administrator access"; font.pixelSize: 24 }
            Txt {
                x: 30
                y: 72
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                text: root.ctl.authError !== "" ? root.ctl.authError : "Enter your password to install system software."
                font.pixelSize: 15
                color: root.ctl.authError !== "" ? "#ff6b6b" : Theme.fgDim
            }
            Rectangle {
                x: 40
                y: 124
                width: parent.width - 80
                height: 50
                radius: 25
                color: Theme.glass
                border.width: 1
                border.color: pwField.activeFocus ? Theme.accent : Theme.glassBorder
                Behavior on border.color { ColorAnimation { duration: 160 } }
                TextInput {
                    id: pwField
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentText
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    echoMode: TextInput.Password
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.ctl.skipInstall();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const v = pwField.text;
                            pwField.text = "";
                            root.focusBack();
                            root.ctl.submitPassword(v);
                            event.accepted = true;
                        }
                    }
                }
            }
            Txt { x: 0; y: 206; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Enter  \u00b7  Continue          Esc  \u00b7  Skip"; font.pixelSize: 13; color: Theme.fgDim }
        }
    }

    // ---- dialog: optional full update
    Item {
        id: dlgAsk
        anchors.fill: parent
        z: 20
        property real pT: root.phase === "ask" ? 1 : 0
        Behavior on pT { NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        opacity: pT
        visible: pT > 0.01
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.62); MouseArea { anchors.fill: parent } }
        Item {
            width: 500
            height: 270
            x: (parent.width - width) / 2
            y: 240 + (1 - dlgAsk.pT) * 16
            scale: 0.96 + 0.04 * dlgAsk.pT
            Rectangle { anchors.fill: parent; radius: 24; color: Qt.rgba(0.06, 0.065, 0.08, 0.97) }
            GlassSlot { anchors.fill: parent; radius: 24; alpha: 1 }
            Txt { x: 0; y: 28; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Update your system?"; font.pixelSize: 24 }
            Txt {
                x: 36
                y: 76
                width: parent.width - 72
                horizontalAlignment: Text.AlignHCenter
                text: root.ctl.missingCount > 0
                      ? "A full update also refreshes your package lists, then Waystation retries the packages that were missing. It can take a while."
                      : "Optional. This upgrades every package on your system and can take a while."
                font.pixelSize: 16
                color: Theme.fgDim
                wrapMode: Text.WordWrap
                maximumLineCount: 4
            }
            Pill { x: 38; y: 192; label: "Update now"; on: root.sel === 0; onClicked: { root.sel = 0; root.choose(); } }
            Pill { x: 262; y: 192; label: "Not now"; on: root.sel === 1; onClicked: { root.sel = 1; root.choose(); } }
        }
    }
}
