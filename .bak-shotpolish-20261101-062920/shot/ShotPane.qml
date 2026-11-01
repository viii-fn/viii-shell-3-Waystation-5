import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../hub"

// Screenshot pane (Print key). One window per monitor, shown only on the focused one.
// Flow: grim freezes the screen first (so the pane is never in the picture), then the pane offers
// Region / Window / Screen. Region has rulers, a crosshair and a pixel magnifier; Window highlights
// the window under the cursor. The result is cropped from the frozen image, saved to
// ~/Pictures/Screenshots, copied to the clipboard, and announced with a toast.
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "viii-shot"
    WlrLayershell.keyboardFocus: win.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: open

    readonly property var fm: Hyprland.focusedMonitor
    readonly property bool isFocusedMon: fm ? fm.name === screen.name : true
    readonly property real s: Math.max(0.7, Math.min(width / 1366, height / 768))

    property bool open: false
    property bool busy: false
    property string mode: "pane"          // pane | region | window
    property int choice: 0
    property string frozenPath: ""
    property url frozenUrl: ""
    property var rects: []                 // window rectangles for Window mode
    property bool dragging: false
    property real ax: 0
    property real ay: 0
    property real pv: 0                    // 0..1 enter animation

    // ---- shell commands -------------------------------------------------------------------
    readonly property string saveScript:
        "mkdir -p \"$(dirname \"$2\")\" || exit 1; " +
        "if [ -n \"$3\" ]; then magick \"$1\" -crop \"${3}x${4}+${5}+${6}\" +repage \"$2\" || exit 1; else cp \"$1\" \"$2\" || exit 1; fi; " +
        "wl-copy -t image/png < \"$2\" >/dev/null 2>&1; " +
        "rm -f \"$1\"; " +
        "notify-send -a Screenshot -i \"$2\" \"Screenshot saved\" \"$(basename \"$2\") - copied to clipboard\""

    Process {
        id: grim
        onExited: (code, status) => {
            if (code === 0) { win.frozenUrl = "file://" + win.frozenPath; revealTimer.restart(); }
            else win.fail("grim could not capture the screen");
        }
    }
    Process {
        id: cap
        onExited: (code, status) => {
            win.busy = false;
            if (code !== 0) win.fail("Saving failed (is imagemagick installed?)");
        }
    }
    Process {
        id: rm
        onExited: (code, status) => { win.busy = false; }
    }
    Process { id: notifier }
    Process {
        id: winProc
        command: ["bash", "-c", "printf '{\"c\":'; hyprctl -j clients; printf ',\"m\":'; hyprctl -j monitors; printf '}'"]
        stdout: StdioCollector { onStreamFinished: win.loadWindows(this.text) }
    }

    Timer {
        id: revealTimer
        interval: 1500
        onTriggered: {
            if (!win.busy || win.open) return;
            if (frozen.status === Image.Ready) win.reveal(); else win.fail("Could not load the screenshot");
        }
    }

    NumberAnimation {
        id: inAnim
        target: win; property: "pv"
        from: 0; to: 1; duration: 320
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out
    }

    Connections {
        target: Desk
        function onShotRequested() { if (win.isFocusedMon && !win.busy && !win.open) win.begin(); }
    }

    // ---- flow -------------------------------------------------------------------------------
    function begin() {
        busy = true;
        mode = "pane";
        choice = 0;
        dragging = false;
        rects = [];
        frozenPath = "/tmp/viii-shot-" + screen.name + "-" + Date.now() + ".png";
        grim.command = ["grim", "-o", screen.name, frozenPath];
        grim.running = true;
    }
    function reveal() {
        revealTimer.stop();
        open = true;
        inAnim.restart();
        root.forceActiveFocus();
    }
    function cleanup() {
        const p = frozenPath;
        frozenUrl = "";
        if (p === "") { busy = false; return; }
        rm.command = ["rm", "-f", p];
        rm.running = true;
    }
    function fail(msg) {
        revealTimer.stop();
        open = false;
        notifier.command = ["notify-send", "-a", "Screenshot", "-u", "critical", "Screenshot failed", msg];
        notifier.running = true;
        cleanup();
    }
    function dismiss() {
        open = false;
        dragging = false;
        mode = "pane";
        cleanup();
    }
    function back() {
        dragging = false;
        if (mode === "pane") dismiss(); else mode = "pane";
    }
    function pick(i) {
        choice = i;
        if (i === 0) mode = "region";
        else if (i === 1) { mode = "window"; if (!winProc.running) winProc.running = true; }
        else grab(0, 0, 0, 0);
    }

    // x, y, w, h in logical pixels of this monitor; w or h of 0 = the whole screen
    function grab(x, y, w, h) {
        const full = !(w > 0 && h > 0);
        const iw = Math.max(frozen.implicitWidth, frozen.sourceSize.width);
        const ih = Math.max(frozen.implicitHeight, frozen.sourceSize.height);
        const rx = (iw > 0 && win.width > 0) ? iw / win.width : 1;
        const ry = (ih > 0 && win.height > 0) ? ih / win.height : 1;
        const px = Math.max(0, Math.round(x * rx));
        const py = Math.max(0, Math.round(y * ry));
        const pw = Math.max(1, Math.min(Math.round(w * rx), iw - px));
        const ph = Math.max(1, Math.min(Math.round(h * ry), ih - py));
        const out = Quickshell.env("HOME") + "/Pictures/Screenshots/screenshot-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".png";
        cap.command = ["bash", "-c", saveScript, "viii-shot", frozenPath, out,
                       full ? "" : String(pw), full ? "" : String(ph), full ? "" : String(px), full ? "" : String(py)];
        open = false;
        dragging = false;
        mode = "pane";
        frozenUrl = "";
        cap.running = true;
    }

    function loadWindows(text) {
        let j = null;
        try { j = JSON.parse(text); } catch (e) { return; }
        if (!j) return;
        const mon = (j.m || []).find(m => m.name === screen.name);
        if (!mon) return;
        const aw = mon.activeWorkspace ? mon.activeWorkspace.id : -1;
        const list = (j.c || []).filter(c => c.mapped && !c.hidden && c.monitor === mon.id && c.workspace && c.workspace.id === aw);
        list.sort((a, b) => ((b.floating ? 1 : 0) - (a.floating ? 1 : 0)) || (a.focusHistoryID - b.focusHistoryID));
        rects = list.map(c => ({ x: c.at[0] - mon.x, y: c.at[1] - mon.y, w: c.size[0], h: c.size[1], t: c.title || c.class || "" }));
    }

    function hit(px, py) {
        for (let i = 0; i < rects.length; i++) {
            const r = rects[i];
            if (px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h) return r;
        }
        return null;
    }

    function handleKey(e) {
        let ok = true;
        if (e.key === Qt.Key_Escape) back();
        else if (mode === "pane") {
            switch (e.key) {
            case Qt.Key_Left: case Qt.Key_H: choice = Math.max(0, choice - 1); break;
            case Qt.Key_Right: case Qt.Key_L: choice = Math.min(2, choice + 1); break;
            case Qt.Key_Tab: choice = (choice + 1) % 3; break;
            case Qt.Key_1: case Qt.Key_R: pick(0); break;
            case Qt.Key_2: case Qt.Key_W: pick(1); break;
            case Qt.Key_3: case Qt.Key_F: case Qt.Key_S: pick(2); break;
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: pick(choice); break;
            default: ok = false;
            }
        } else if (e.key === Qt.Key_Backspace) back();
        else ok = false;
        e.accepted = ok;
    }

    // ---- selection geometry -----------------------------------------------------------------
    readonly property var hoverWin: (mode === "window" && area.containsMouse) ? hit(area.mouseX, area.mouseY) : null

    readonly property rect selRect: {
        if (mode === "region" && dragging) {
            const x0 = Math.max(0, Math.min(win.width, Math.round(Math.min(ax, area.mouseX))));
            const y0 = Math.max(0, Math.min(win.height, Math.round(Math.min(ay, area.mouseY))));
            const x1 = Math.max(0, Math.min(win.width, Math.round(Math.max(ax, area.mouseX))));
            const y1 = Math.max(0, Math.min(win.height, Math.round(Math.max(ay, area.mouseY))));
            return Qt.rect(x0, y0, x1 - x0, y1 - y0);
        }
        if (mode === "window" && hoverWin) return Qt.rect(hoverWin.x, hoverWin.y, hoverWin.w, hoverWin.h);
        return Qt.rect(0, 0, 0, 0);
    }
    property rect lastRect: Qt.rect(0, 0, 0, 0)
    onSelRectChanged: if (selRect.width > 0 && selRect.height > 0) lastRect = selRect
    readonly property rect target: (selRect.width > 0 && selRect.height > 0)
        ? selRect
        : Qt.rect(lastRect.x + lastRect.width / 2, lastRect.y + lastRect.height / 2, 0, 0)

    // ---- scene --------------------------------------------------------------------------------
    FocusScope {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => win.handleKey(event)

        // the frozen screen
        Image {
            id: frozen
            anchors.fill: parent
            source: win.frozenUrl
            fillMode: Image.Stretch
            asynchronous: true
            onStatusChanged: {
                if (status === Image.Ready && win.busy && !win.open && win.frozenUrl != "") win.reveal();
                else if (status === Image.Error && win.busy && !win.open) win.fail("Could not load the screenshot");
            }
        }

        // dim everywhere except the selection (four rectangles around it)
        Rectangle { x: 0; y: 0; width: win.width; height: selBox.y; color: Qt.rgba(0, 0, 0, 0.5 * win.pv) }
        Rectangle { x: 0; y: selBox.y + selBox.height; width: win.width; height: Math.max(0, win.height - selBox.y - selBox.height); color: Qt.rgba(0, 0, 0, 0.5 * win.pv) }
        Rectangle { x: 0; y: selBox.y; width: selBox.x; height: selBox.height; color: Qt.rgba(0, 0, 0, 0.5 * win.pv) }
        Rectangle { x: selBox.x + selBox.width; y: selBox.y; width: Math.max(0, win.width - selBox.x - selBox.width); height: selBox.height; color: Qt.rgba(0, 0, 0, 0.5 * win.pv) }

        // the selection box (glides between windows in Window mode, follows the mouse in Region mode)
        Rectangle {
            id: selBox
            x: win.target.x
            y: win.target.y
            width: win.target.width
            height: win.target.height
            color: "transparent"
            border.width: width > 1 ? 2 : 0
            border.color: Theme.fg
            Behavior on x { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on y { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on width { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on height { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        }

        // size / title chip on the selection
        Rectangle {
            visible: win.mode !== "pane" && selBox.width > 30
            x: Math.min(selBox.x, win.width - width - 8)
            y: selBox.y > 40 ? selBox.y - height - 8 : selBox.y + 8
            height: 26
            width: chipText.width + 22
            radius: 13
            color: Qt.rgba(0.07, 0.078, 0.098, 0.92)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)
            Txt {
                id: chipText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, 420)
                font.pixelSize: 13
                text: (win.mode === "window" && win.hoverWin ? win.hoverWin.t + "   " : "") + Math.round(selBox.width) + " x " + Math.round(selBox.height)
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: win.mode === "region" ? Qt.BlankCursor : Qt.ArrowCursor
            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) { win.back(); return; }
                if (win.mode === "region") { win.ax = mouse.x; win.ay = mouse.y; win.dragging = true; }
            }
            onReleased: mouse => {
                if (mouse.button !== Qt.LeftButton) return;
                if (win.mode === "region" && win.dragging) {
                    const r = win.selRect;
                    win.dragging = false;
                    if (r.width >= 4 && r.height >= 4) win.grab(r.x, r.y, r.width, r.height);
                } else if (win.mode === "window") {
                    const h = win.hoverWin;
                    if (h) win.grab(h.x, h.y, h.w, h.h);
                } else if (win.mode === "pane") win.dismiss();
            }
        }

        // ---- Region mode: crosshair, rulers, magnifier ----
        Item {
            id: regionUi
            anchors.fill: parent
            visible: win.mode === "region" && win.open
            enabled: false

            // crosshair
            Rectangle { x: Math.round(area.mouseX); y: 0; width: 1; height: win.height; color: Qt.rgba(1, 1, 1, 0.55); visible: area.containsMouse }
            Rectangle { x: 0; y: Math.round(area.mouseY); width: win.width; height: 1; color: Qt.rgba(1, 1, 1, 0.55); visible: area.containsMouse }
            Rectangle {
                x: Math.round(area.mouseX) - 5; y: Math.round(area.mouseY) - 5
                width: 11; height: 11
                color: "transparent"
                border.width: 1
                border.color: Theme.fg
                visible: area.containsMouse
            }

            // rulers
            Canvas {
                id: rulerTop
                x: 0; y: 0
                width: win.width; height: 22
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "rgba(18,20,25,0.90)";
                    ctx.fillRect(0, 0, width, height);
                    ctx.strokeStyle = "rgba(255,255,255,0.5)";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    for (let x = 0; x <= width; x += 10) {
                        const len = x % 100 === 0 ? 14 : (x % 50 === 0 ? 10 : 6);
                        ctx.moveTo(x + 0.5, height);
                        ctx.lineTo(x + 0.5, height - len);
                    }
                    ctx.stroke();
                    ctx.fillStyle = "rgba(255,255,255,0.7)";
                    ctx.font = "10px " + Theme.fontFamily;
                    for (let x = 100; x < width; x += 100) ctx.fillText(String(x), x + 3, 10);
                }
            }
            Canvas {
                id: rulerLeft
                x: 0; y: 0
                width: 22; height: win.height
                onVisibleChanged: if (visible) requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "rgba(18,20,25,0.90)";
                    ctx.fillRect(0, 0, width, height);
                    ctx.strokeStyle = "rgba(255,255,255,0.5)";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    for (let y = 0; y <= height; y += 10) {
                        const len = y % 100 === 0 ? 14 : (y % 50 === 0 ? 10 : 6);
                        ctx.moveTo(width, y + 0.5);
                        ctx.lineTo(width - len, y + 0.5);
                    }
                    ctx.stroke();
                    ctx.fillStyle = "rgba(255,255,255,0.7)";
                    ctx.font = "10px " + Theme.fontFamily;
                    for (let y = 100; y < height; y += 100) ctx.fillText(String(y), 1, y - 3);
                }
            }
            // selected range and cursor markers on the rulers
            Rectangle { x: win.selRect.x; y: 0; width: win.selRect.width; height: 22; color: Qt.alpha(Theme.accent, 0.45) }
            Rectangle { x: 0; y: win.selRect.y; width: 22; height: win.selRect.height; color: Qt.alpha(Theme.accent, 0.45) }
            Rectangle { x: Math.round(area.mouseX) - 1; y: 0; width: 3; height: 22; color: Theme.fg; visible: area.containsMouse }
            Rectangle { x: 0; y: Math.round(area.mouseY) - 1; width: 22; height: 3; color: Theme.fg; visible: area.containsMouse }

            // magnifier, beside the cursor (flips at the screen edges)
            Item {
                id: mag
                readonly property real zoom: 8
                readonly property real box: 132
                readonly property real gapPx: 30
                visible: area.containsMouse
                readonly property bool flipX: area.mouseX + gapPx + box > win.width - 8
                readonly property bool flipY: area.mouseY + gapPx + box + 32 > win.height - 8
                x: flipX ? area.mouseX - gapPx - box : area.mouseX + gapPx
                y: flipY ? area.mouseY - gapPx - box - 32 : area.mouseY + gapPx
                width: box
                height: box + 32

                Rectangle { width: mag.box; height: mag.box; color: "#05060a" }
                Item {
                    width: mag.box; height: mag.box
                    clip: true
                    Image {
                        source: frozen.source
                        width: win.width * mag.zoom
                        height: win.height * mag.zoom
                        x: mag.box / 2 - (Math.floor(area.mouseX) * mag.zoom + mag.zoom / 2)
                        y: mag.box / 2 - (Math.floor(area.mouseY) * mag.zoom + mag.zoom / 2)
                        fillMode: Image.Stretch
                        smooth: false
                    }
                    Rectangle { x: 0; y: mag.box / 2 - 0.5; width: mag.box; height: 1; color: Qt.rgba(1, 1, 1, 0.22) }
                    Rectangle { x: mag.box / 2 - 0.5; y: 0; width: 1; height: mag.box; color: Qt.rgba(1, 1, 1, 0.22) }
                    Rectangle {
                        x: (mag.box - mag.zoom) / 2; y: (mag.box - mag.zoom) / 2
                        width: mag.zoom; height: mag.zoom
                        color: "transparent"
                        border.width: 1.5
                        border.color: Theme.fg
                    }
                }
                Rectangle {
                    width: mag.box; height: mag.box
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(1, 1, 1, 0.9)
                }
                Rectangle {
                    y: mag.box + 6
                    width: mag.box; height: 24
                    radius: 12
                    color: Qt.rgba(0.07, 0.078, 0.098, 0.92)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.16)
                    Txt {
                        anchors.centerIn: parent
                        font.pixelSize: 13
                        text: Math.floor(area.mouseX) + ",  " + Math.floor(area.mouseY)
                    }
                }
            }
        }

        // ---- the pane: Region / Window / Screen ----
        Item {
            id: bar
            width: 524
            height: 156
            scale: win.s
            transformOrigin: Item.Bottom
            x: (win.width - width) / 2
            y: win.height - height - 56 * win.s + (1 - win.pv) * 30
            opacity: win.mode === "pane" ? win.pv : 0
            visible: opacity > 0.01

            Rectangle {
                anchors.fill: parent
                radius: 26
                color: Qt.rgba(0.07, 0.078, 0.098, 0.94)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)
            }

            // one focus highlight that glides between the three options
            Rectangle {
                x: 16 + win.choice * 168
                y: 16
                width: 156; height: 92
                radius: 18
                color: Qt.rgba(1, 1, 1, 0.12)
                border.width: 2
                border.color: Theme.fg
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            }

            Repeater {
                model: ["Region", "Window", "Screen"]
                delegate: Item {
                    id: opt
                    required property string modelData
                    required property int index
                    x: 16 + index * 168
                    y: 16
                    width: 156; height: 92

                    Item {
                        x: (parent.width - width) / 2
                        y: 17
                        width: 34; height: 26

                        // region: four corner brackets
                        Item {
                            anchors.fill: parent
                            visible: opt.index === 0
                            Rectangle { x: 0; y: 0; width: 10; height: 3; color: Theme.fg }
                            Rectangle { x: 0; y: 0; width: 3; height: 10; color: Theme.fg }
                            Rectangle { x: 24; y: 0; width: 10; height: 3; color: Theme.fg }
                            Rectangle { x: 31; y: 0; width: 3; height: 10; color: Theme.fg }
                            Rectangle { x: 0; y: 23; width: 10; height: 3; color: Theme.fg }
                            Rectangle { x: 0; y: 16; width: 3; height: 10; color: Theme.fg }
                            Rectangle { x: 24; y: 23; width: 10; height: 3; color: Theme.fg }
                            Rectangle { x: 31; y: 16; width: 3; height: 10; color: Theme.fg }
                        }
                        // window: a frame with a title bar
                        Item {
                            anchors.fill: parent
                            visible: opt.index === 1
                            Rectangle { anchors.fill: parent; radius: 5; color: "transparent"; border.width: 3; border.color: Theme.fg }
                            Rectangle { x: 0; y: 8; width: 34; height: 3; color: Theme.fg }
                        }
                        // screen: a monitor on a stand
                        Item {
                            anchors.fill: parent
                            visible: opt.index === 2
                            Rectangle { x: 0; y: 0; width: 34; height: 21; radius: 4; color: "transparent"; border.width: 3; border.color: Theme.fg }
                            Rectangle { x: 15; y: 21; width: 4; height: 3; color: Theme.fg }
                            Rectangle { x: 9; y: 24; width: 16; height: 2; radius: 1; color: Theme.fg }
                        }
                    }

                    Txt {
                        x: 0; y: 56
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: opt.modelData
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                    Txt {
                        x: parent.width - width - 12; y: 9
                        text: String(opt.index + 1)
                        font.pixelSize: 12
                        color: Theme.fgDim
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.choice = opt.index
                        onClicked: win.pick(opt.index)
                    }
                }
            }

            Row {
                x: (parent.width - width) / 2
                y: 122
                spacing: 26
                Hint { key: "\u2190 \u2192"; label: "Choose" }
                Hint { key: "Enter"; label: "Select" }
                Hint { key: "Esc"; label: "Close" }
            }
        }
    }
}
