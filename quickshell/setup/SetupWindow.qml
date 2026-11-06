import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../hub"

// One setup window per monitor: a full-screen overlay (above the hub). Only the main monitor draws the
// setup and takes the keyboard; the others just show the dimmed backdrop. Design space 1366x768, scaled
// uniformly, like the hub and Settings.
PanelWindow {
    id: win

    required property var ctl
    readonly property bool primary: ctl.mainScreen === "" || (!!screen && screen.name === ctl.mainScreen)

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "viii-setup"
    WlrLayershell.keyboardFocus: win.primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // fades in at start, out at the end (same curves as the hub)
    property bool shown: false
    Component.onCompleted: shown = true
    property real vis: (shown && !ctl.closing) ? 1 : 0
    Behavior on vis {
        NumberAnimation {
            duration: (win.shown && !win.ctl.closing) ? Motion.reveal : Motion.hide
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (win.shown && !win.ctl.closing) ? Motion.out : Motion.inOut
        }
    }

    readonly property real s: Math.max(0.1, Math.min(width / 1366, height / 768))

    // screens cross-fade and slide with one animated number
    property real pT: ctl.step
    Behavior on pT {
        NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }
    function fade(i) { return Math.max(0, 1 - Math.abs(pT - i) * 1.5); }
    function slide(i) { return (i - pT) * 70; }

    function refocus() { fs.forceActiveFocus(); }

    function route(e) {
        // Ctrl+Shift+Esc: leave the setup (marks it done). A way out if something below ever misbehaves.
        if (e.key === Qt.Key_Escape && (e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.ShiftModifier)) {
            ctl.finish();
            e.accepted = true;
            return;
        }
        if (!ctl.closing) {
            const t = [pair, lang, disp, agree, upd][ctl.step];
            if (t) t.handleKey(e);
        }
        e.accepted = true;
    }

    FocusScope {
        id: fs
        anchors.fill: parent
        focus: true
        opacity: win.vis
        Keys.onPressed: event => win.route(event)

        // the PS5 setup pages sit on a plain dark gradient (no wallpaper): the shell's own gradient + glows
        Backdrop {
            anchors.fill: parent
            wallpaper: false
            baseBehind: false
            ghost: false
        }

        Item {
            id: stage
            visible: win.primary
            width: 1366
            height: 768
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            transformOrigin: Item.Center
            scale: win.s * (1.035 - 0.035 * win.vis)

            PairScreen {
                id: pair
                ctl: win.ctl
                active: win.ctl.step === 0
                opacity: win.fade(0)
                x: win.slide(0)
                visible: opacity > 0.01
            }
            LanguageScreen {
                id: lang
                ctl: win.ctl
                active: win.ctl.step === 1
                opacity: win.fade(1)
                x: win.slide(1)
                visible: opacity > 0.01
            }
            DisplayScreen {
                id: disp
                ctl: win.ctl
                active: win.ctl.step === 2
                opacity: win.fade(2)
                x: win.slide(2)
                visible: opacity > 0.01
            }
            AgreementScreen {
                id: agree
                ctl: win.ctl
                active: win.ctl.step === 3
                opacity: win.fade(3)
                x: win.slide(3)
                visible: opacity > 0.01
            }
            UpdateScreen {
                id: upd
                ctl: win.ctl
                active: win.ctl.step === 4
                opacity: win.fade(4)
                x: win.slide(4)
                visible: opacity > 0.01
                onFocusBack: win.refocus()
            }
        }
    }
}
