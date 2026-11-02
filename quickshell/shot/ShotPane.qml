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
    visible: open || flashing

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
    property real selX: 0                  // the region (kept after release so it can be adjusted)
    property real selY: 0
    property real selW: 0
    property real selH: 0
    property string dragKind: ""           // new | move | n s e w ne nw se sw
    property real px0: 0
    property real py0: 0
    property rect startRect: Qt.rect(0, 0, 0, 0)
    property real guideX: -1               // snap guide lines (-1 = none)
    property real guideY: -1
    property real pv: 0                    // 0..1 enter animation
    property real pop: 0                   // springy pop of the pane
    property bool flashing: false          // capture flash / leave fade is running
    property real flashA: 0
    property rect flashRect: Qt.rect(0, 0, 0, 0)
    readonly property var spring: [0.34, 1.56, 0.64, 1, 1, 1]

    // ---- shell commands -------------------------------------------------------------------
    readonly property string saveScript:
        "mkdir -p \"$(dirname \"$2\")\" || exit 1; " +
        "if [ -n \"$3\" ]; then magick \"$1\" -crop \"${3}x${4}+${5}+${6}\" +repage \"$2\" || exit 1; else cp \"$1\" \"$2\" || exit 1; fi; " +
        "wl-copy -t image/png < \"$2\" >/dev/null 2>&1; " +
        "rm -f \"$1\"; " +
        "notify-send -a Screenshot -i \"$2\" \"Screenshot captured\" \"Saved to Pictures/Screenshots and copied to the clipboard: $(basename \"$2\")\""

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
        from: 0; to: 1; duration: 260
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out
    }
    NumberAnimation {
        id: popAnim
        target: win; property: "pop"
        from: 0; to: 1; duration: 420
        easing.type: Easing.BezierSpline; easing.bezierCurve: win.spring
    }
    // capture flash (white over the captured area) while the dimming fades away; also the quiet fade on Esc
    ParallelAnimation {
        id: flashAnim
        NumberAnimation { target: win; property: "flashA"; to: 0; duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "pv"; to: 0; duration: 280; easing.type: Easing.OutCubic }
        onFinished: win.endFlash()
    }

    Connections {
        target: Desk
        function onShotRequested() { if (win.isFocusedMon && !win.busy && !win.open && !win.flashing) win.begin(); }
    }

    // ---- flow -------------------------------------------------------------------------------
    function begin() {
        busy = true;
        mode = "pane";
        choice = 0;
        dragging = false;
        rects = [];
        clearSel();
        frozenPath = "/tmp/viii-shot-" + screen.name + "-" + Date.now() + ".png";
        grim.command = ["grim", "-o", screen.name, frozenPath];
        grim.running = true;
    }
    function reveal() {
        revealTimer.stop();
        flashAnim.stop();
        flashing = false;
        open = true;
        inAnim.restart();
        popAnim.restart();
        root.forceActiveFocus();
    }
    function cleanup() {
        const p = frozenPath;
        if (p === "") { busy = false; return; }
        rm.command = ["rm", "-f", p];
        rm.running = true;
    }
    // leave the pane: with a flash over r (the captured area), or quietly (r = null)
    function leave(r) {
        inAnim.stop();
        open = false;
        dragging = false;
        flashRect = r ? r : Qt.rect(0, 0, 0, 0);
        flashA = r ? 0.85 : 0;
        flashing = true;
        flashAnim.restart();
    }
    function endFlash() {
        flashing = false;
        frozenUrl = "";
        mode = "pane";
        clearSel();
    }
    function fail(msg) {
        revealTimer.stop();
        open = false;
        flashing = false;
        frozenUrl = "";
        notifier.command = ["notify-send", "-a", "Screenshot", "-u", "critical", "Screenshot failed", msg];
        notifier.running = true;
        cleanup();
    }
    function dismiss() {
        leave(null);
        cleanup();
    }
    function back() {
        dragging = false;
        dragKind = "";
        guideX = -1; guideY = -1;
        if (mode === "region" && selW > 0) { clearSel(); return; }     // Esc once = redo the selection
        if (mode === "pane") dismiss(); else mode = "pane";
    }
    function pick(i) {
        choice = i;
        if (i === 0) { clearSel(); mode = "region"; if (!winProc.running) winProc.running = true; }
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
        cap.running = true;
        leave(full ? Qt.rect(0, 0, win.width, win.height) : Qt.rect(x, y, w, h));
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

    function clearSel() { selX = 0; selY = 0; selW = 0; selH = 0; dragKind = ""; guideX = -1; guideY = -1; }
    function clampX(v) { return Math.max(0, Math.min(win.width, v)); }
    function clampY(v) { return Math.max(0, Math.min(win.height, v)); }

    // snap targets: the screen edges and the edges of every window on this workspace
    function xCands() { const a = [0, win.width]; for (let i = 0; i < rects.length; i++) a.push(rects[i].x, rects[i].x + rects[i].w); return a; }
    function yCands() { const a = [0, win.height]; for (let i = 0; i < rects.length; i++) a.push(rects[i].y, rects[i].y + rects[i].h); return a; }
    function snapEdge(v, cands) {
        let best = v, bd = 9, hit = -1;
        for (let i = 0; i < cands.length; i++) {
            const d = Math.abs(cands[i] - v);
            if (d < bd) { bd = d; best = cands[i]; hit = cands[i]; }
        }
        return { v: best, hit: hit, d: bd };
    }

    // which part of the committed region is under (mx, my): a handle, "move", or "" (outside)
    function zoneAt(mx, my) {
        if (selW < 4 || selH < 4) return "";
        const x0 = selX, y0 = selY, x1 = selX + selW, y1 = selY + selH, t = 10;
        if (mx < x0 - t || mx > x1 + t || my < y0 - t || my > y1 + t) return "";
        let z = "";
        if (Math.abs(my - y0) <= t) z += "n"; else if (Math.abs(my - y1) <= t) z += "s";
        if (Math.abs(mx - x0) <= t) z += "w"; else if (Math.abs(mx - x1) <= t) z += "e";
        if (z !== "") return z;
        return (mx >= x0 && mx <= x1 && my >= y0 && my <= y1) ? "move" : "";
    }
    function cursorForZone(z) {
        if (z === "") return Qt.BlankCursor;
        if (z === "move") return Qt.SizeAllCursor;
        if (z === "n" || z === "s") return Qt.SizeVerCursor;
        if (z === "e" || z === "w") return Qt.SizeHorCursor;
        if (z === "nw" || z === "se") return Qt.SizeFDiagCursor;
        return Qt.SizeBDiagCursor;
    }

    function dragTo(mx, my) {
        const sr = startRect;
        const xc = xCands(), yc = yCands();
        let gx = -1, gy = -1;
        if (dragKind === "new") {
            const sx = snapEdge(clampX(mx), xc), sy = snapEdge(clampY(my), yc);
            gx = sx.hit; gy = sy.hit;
            selX = Math.min(ax, sx.v); selY = Math.min(ay, sy.v);
            selW = Math.abs(sx.v - ax); selH = Math.abs(sy.v - ay);
        } else if (dragKind === "move") {
            let nx = Math.max(0, Math.min(win.width - sr.width, sr.x + mx - px0));
            let ny = Math.max(0, Math.min(win.height - sr.height, sr.y + my - py0));
            const lx = snapEdge(nx, xc), rx = snapEdge(nx + sr.width, xc);
            if (lx.hit >= 0 && (rx.hit < 0 || lx.d <= rx.d)) { nx = lx.v; gx = lx.hit; }
            else if (rx.hit >= 0) { nx = rx.v - sr.width; gx = rx.hit; }
            const ty = snapEdge(ny, yc), by = snapEdge(ny + sr.height, yc);
            if (ty.hit >= 0 && (by.hit < 0 || ty.d <= by.d)) { ny = ty.v; gy = ty.hit; }
            else if (by.hit >= 0) { ny = by.v - sr.height; gy = by.hit; }
            selX = Math.max(0, Math.min(win.width - sr.width, nx));
            selY = Math.max(0, Math.min(win.height - sr.height, ny));
        } else {
            let l = sr.x, r = sr.x + sr.width, t = sr.y, b = sr.y + sr.height;
            if (dragKind.indexOf("w") >= 0) { const s = snapEdge(clampX(mx), xc); l = s.v; gx = s.hit; }
            if (dragKind.indexOf("e") >= 0) { const s = snapEdge(clampX(mx), xc); r = s.v; gx = s.hit; }
            if (dragKind.indexOf("n") >= 0) { const s = snapEdge(clampY(my), yc); t = s.v; gy = s.hit; }
            if (dragKind.indexOf("s") >= 0) { const s = snapEdge(clampY(my), yc); b = s.v; gy = s.hit; }
            selX = Math.min(l, r); selW = Math.abs(r - l);
            selY = Math.min(t, b); selH = Math.abs(b - t);
        }
        guideX = gx;
        guideY = gy;
    }

    function snap() { if (selW >= 4 && selH >= 4) grab(selX, selY, selW, selH); }

    function nudge(dx, dy, big) {
        if (selW < 4) return;
        const st = big ? 10 : 1;
        selX = Math.max(0, Math.min(win.width - selW, selX + dx * st));
        selY = Math.max(0, Math.min(win.height - selH, selY + dy * st));
    }

    function handleKey(e) {
        let ok = true;
        if (e.key === Qt.Key_Escape) back();
        else if (mode === "pane") {
            switch (e.key) {
            case Qt.Key_Left: choice = Math.max(0, choice - 1); break;
            case Qt.Key_Right: choice = Math.min(2, choice + 1); break;
            case Qt.Key_Tab: choice = (choice + 1) % 3; break;
            case Qt.Key_1: case Qt.Key_R: pick(0); break;
            case Qt.Key_2: case Qt.Key_W: pick(1); break;
            case Qt.Key_3: case Qt.Key_F: case Qt.Key_S: pick(2); break;
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: pick(choice); break;
            default: ok = false;
            }
        } else if (e.key === Qt.Key_Backspace) back();
        else if (mode === "region" && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)) snap();
        else if (mode === "region" && e.key === Qt.Key_Left) nudge(-1, 0, e.modifiers & Qt.ShiftModifier);
        else if (mode === "region" && e.key === Qt.Key_Right) nudge(1, 0, e.modifiers & Qt.ShiftModifier);
        else if (mode === "region" && e.key === Qt.Key_Up) nudge(0, -1, e.modifiers & Qt.ShiftModifier);
        else if (mode === "region" && e.key === Qt.Key_Down) nudge(0, 1, e.modifiers & Qt.ShiftModifier);
        else ok = false;
        e.accepted = ok;
    }

    // ---- selection geometry -----------------------------------------------------------------
    readonly property var hoverWin: (mode === "window" && area.containsMouse) ? hit(area.mouseX, area.mouseY) : null

    readonly property string zoneNow: mode !== "region" ? ""
        : (dragging ? (dragKind === "new" ? "" : dragKind) : (area.containsMouse ? zoneAt(area.mouseX, area.mouseY) : ""))

    readonly property rect selRect: {
        if (mode === "region") return Qt.rect(selX, selY, selW, selH);
        if (mode === "window" && hoverWin) return Qt.rect(hoverWin.x, hoverWin.y, hoverWin.w, hoverWin.h);
        return Qt.rect(0, 0, 0, 0);
    }
    property rect lastRect: Qt.rect(0, 0, 0, 0)
    onSelRectChanged: if (selRect.width > 0 && selRect.height > 0) lastRect = selRect
    readonly property rect target: flashing ? flashRect
        : ((selRect.width > 0 && selRect.height > 0)
            ? selRect
            : Qt.rect(lastRect.x + lastRect.width / 2, lastRect.y + lastRect.height / 2, 0, 0))

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
            border.color: Qt.alpha(Theme.fg, win.flashing ? win.pv : 1)
            Behavior on x { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on y { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on width { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on height { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        }

        // the capture flash
        Rectangle {
            x: win.flashRect.x; y: win.flashRect.y
            width: win.flashRect.width; height: win.flashRect.height
            color: "white"
            opacity: win.flashA
            visible: win.flashing && win.flashA > 0.01
        }

        // size / title chip on the selection
        Rectangle {
            id: chip
            visible: opacity > 0.01
            opacity: (win.open && win.mode !== "pane" && selBox.width > 30) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
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
            enabled: win.open
            cursorShape: win.mode === "region" ? win.cursorForZone(win.zoneNow) : Qt.ArrowCursor
            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) { win.back(); return; }
                if (win.mode !== "region") return;
                const z = win.zoneAt(mouse.x, mouse.y);
                win.px0 = mouse.x;
                win.py0 = mouse.y;
                win.startRect = Qt.rect(win.selX, win.selY, win.selW, win.selH);
                if (z !== "") win.dragKind = z;
                else {
                    win.dragKind = "new";
                    win.ax = win.snapEdge(win.clampX(mouse.x), win.xCands()).v;
                    win.ay = win.snapEdge(win.clampY(mouse.y), win.yCands()).v;
                    win.selX = win.ax; win.selY = win.ay; win.selW = 0; win.selH = 0;
                }
                win.dragging = true;
            }
            onPositionChanged: mouse => { if (win.dragging && win.mode === "region") win.dragTo(mouse.x, mouse.y); }
            onReleased: mouse => {
                if (mouse.button !== Qt.LeftButton) return;
                if (win.mode === "region") {
                    if (win.dragging && win.dragKind === "new" && (win.selW < 4 || win.selH < 4)) { win.selW = 0; win.selH = 0; }
                    win.dragging = false;
                    win.dragKind = "";
                    win.guideX = -1;
                    win.guideY = -1;
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
            opacity: (win.mode === "region" && win.open) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            // crosshair
            Rectangle { x: Math.round(area.mouseX); y: 0; width: 1; height: win.height; color: Qt.rgba(1, 1, 1, 0.55); visible: area.containsMouse && win.zoneNow === "" }
            Rectangle { x: 0; y: Math.round(area.mouseY); width: win.width; height: 1; color: Qt.rgba(1, 1, 1, 0.55); visible: area.containsMouse && win.zoneNow === "" }
            Rectangle {
                x: Math.round(area.mouseX) - 5; y: Math.round(area.mouseY) - 5
                width: 11; height: 11
                color: "transparent"
                border.width: 1
                border.color: Theme.fg
                visible: area.containsMouse && win.zoneNow === ""
            }

            // snap guides (shown while an edge snaps to a window or screen edge)
            Rectangle { visible: win.dragging && win.guideX >= 0; x: win.guideX; y: 0; width: 1; height: win.height; color: Theme.accent }
            Rectangle { visible: win.dragging && win.guideY >= 0; x: 0; y: win.guideY; width: win.width; height: 1; color: Theme.accent }

            // eight resize handles on the kept region
            Repeater {
                model: 8
                delegate: Rectangle {
                    required property int index
                    readonly property real fx: [0, 0.5, 1, 1, 1, 0.5, 0, 0][index]
                    readonly property real fy: [0, 0, 0, 0.5, 1, 1, 1, 0.5][index]
                    visible: win.selW >= 12 && win.selH >= 12 && !(win.dragging && win.dragKind === "new")
                    x: selBox.x + fx * selBox.width - 4.5
                    y: selBox.y + fy * selBox.height - 4.5
                    width: 9; height: 9
                    radius: 3
                    color: Theme.fg
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.5)
                }
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

            // magnifier, beside the cursor (flips at the screen edges). Rounded square: the pixels are drawn
            // on a canvas with a rounded clip path.
            Item {
                id: mag
                readonly property real zoom: 7
                readonly property real box: 105          // 15 x 15 pixels, one of them in the middle
                readonly property real gapPx: 26
                readonly property real corner: 18
                opacity: area.containsMouse ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 110 } }
                readonly property bool flipX: area.mouseX + gapPx + box > win.width - 8
                readonly property bool flipY: area.mouseY + gapPx + box + 32 > win.height - 8
                x: flipX ? area.mouseX - gapPx - box : area.mouseX + gapPx
                y: flipY ? area.mouseY - gapPx - box - 32 : area.mouseY + gapPx
                width: box
                height: box + 32

                Canvas {
                    id: magCanvas
                    width: mag.box; height: mag.box
                    readonly property string src: String(win.frozenUrl)
                    readonly property int px: Math.floor(area.mouseX)
                    readonly property int py: Math.floor(area.mouseY)
                    property string loaded: ""
                    onPxChanged: requestPaint()
                    onPyChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()
                    onImageLoaded: requestPaint()
                    onSrcChanged: {
                        if (loaded !== "") unloadImage(loaded);
                        loaded = src;
                        if (src !== "") loadImage(src);
                    }
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const B = width;
                        ctx.beginPath();
                        ctx.roundedRect(0, 0, B, B, mag.corner, mag.corner);
                        ctx.clip();
                        ctx.fillStyle = "#05060a";
                        ctx.fillRect(0, 0, B, B);
                        if (src === "" || !isImageLoaded(src)) return;
                        const iw = Math.max(frozen.implicitWidth, frozen.sourceSize.width);
                        const ih = Math.max(frozen.implicitHeight, frozen.sourceSize.height);
                        if (iw <= 0 || ih <= 0 || win.width <= 0 || win.height <= 0) return;
                        const rx = iw / win.width;
                        const ry = ih / win.height;
                        let sw = B / mag.zoom * rx;
                        let sh = B / mag.zoom * ry;
                        let sx = (px + 0.5) * rx - sw / 2;
                        let sy = (py + 0.5) * ry - sh / 2;
                        const kx = B / sw;
                        const ky = B / sh;
                        let dx = 0;
                        let dy = 0;
                        if (sx < 0) { dx = -sx * kx; sw += sx; sx = 0; }
                        if (sy < 0) { dy = -sy * ky; sh += sy; sy = 0; }
                        if (sx + sw > iw) sw = iw - sx;
                        if (sy + sh > ih) sh = ih - sy;
                        if (sw <= 0 || sh <= 0) return;
                        ctx.imageSmoothingEnabled = false;
                        ctx.drawImage(src, sx, sy, sw, sh, dx, dy, sw * kx, sh * ky);
                    }
                }
                // centre lines and the middle pixel
                Rectangle { x: 0; y: mag.box / 2 - 0.5; width: mag.box; height: 1; color: Qt.rgba(1, 1, 1, 0.20) }
                Rectangle { x: mag.box / 2 - 0.5; y: 0; width: 1; height: mag.box; color: Qt.rgba(1, 1, 1, 0.20) }
                Rectangle {
                    x: (mag.box - mag.zoom) / 2; y: (mag.box - mag.zoom) / 2
                    width: mag.zoom; height: mag.zoom
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.fg
                }
                // rounded frame
                Rectangle {
                    width: mag.box; height: mag.box
                    radius: mag.corner
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

        // Capture / Redo pill under the kept region
        Item {
            id: pill
            readonly property bool show: win.open && win.mode === "region" && win.selW >= 4 && win.selH >= 4 && !win.dragging
            opacity: show ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140 } }
            width: pillRow.width + 20
            height: 40
            x: Math.max(8, Math.min(win.width - width - 8, selBox.x + selBox.width / 2 - width / 2))
            y: (selBox.y + selBox.height + 14 + height < win.height - 6) ? selBox.y + selBox.height + 14 : selBox.y + selBox.height - height - 12

            Rectangle {
                anchors.fill: parent
                radius: 20
                color: Qt.rgba(0.07, 0.078, 0.098, 0.94)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.16)
            }
            MouseArea { anchors.fill: parent }      // clicks on the pill never start a new selection
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 12
                Rectangle {
                    width: capText.width + 28
                    height: 28
                    radius: 14
                    color: Theme.fg
                    Txt {
                        id: capText
                        anchors.centerIn: parent
                        text: "Capture  (Enter)"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: "#0b0d12"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.snap()
                    }
                }
            }
        }

        // ---- the pane: Region / Window / Screen ----
        Item {
            id: bar
            width: 376
            height: 124
            scale: win.s * (0.9 + 0.1 * win.pop)
            transformOrigin: Item.Bottom
            x: (win.width - width) / 2
            y: win.height - height - 40 * win.s + (1 - win.pop) * 26
            opacity: (win.open && win.mode === "pane") ? Math.min(1, win.pv * 1.4) : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: 22
                color: Qt.rgba(0.07, 0.078, 0.098, 0.94)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)
            }

            // one focus highlight that glides between the three options (small overshoot)
            Rectangle {
                x: 12 + win.choice * 120
                y: 12
                width: 112; height: 72
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.12)
                border.width: 2
                border.color: Theme.fg
                Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: win.spring } }
            }

            Repeater {
                model: ["Region", "Window", "Screen"]
                delegate: Item {
                    id: opt
                    required property string modelData
                    required property int index
                    x: 12 + index * 120
                    y: 12
                    width: 112; height: 72

                    Item {
                        id: icon
                        x: (parent.width - width) / 2
                        y: 11
                        width: 34; height: 26
                        scale: win.choice === opt.index ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: win.spring } }

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
                        x: 0; y: 45
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: opt.modelData
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Txt {
                        x: parent.width - width - 9; y: 6
                        text: String(opt.index + 1)
                        font.pixelSize: 11
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
        }
    }
}
