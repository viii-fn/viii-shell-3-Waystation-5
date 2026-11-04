import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../hub"

// Screenshot pane (Print key). One window per monitor, shown only on the focused one.
// Flow: grim freezes the screen first (so the pane is never in the picture), then the pane offers
// Region / Window / Screen. Region has a crosshair and a pixel magnifier; Window highlights
// the window under the cursor. The result is cropped from the frozen image, saved to
// ~/Pictures/Screenshots, copied to the clipboard, and announced with a toast.
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "viii-shot"
    WlrLayershell.keyboardFocus: (win.open || win.counting) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: open || flashing || counting

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
    // ---- recorder (viii-shot3)
    property string kind: "shot"           // shot | rec  (the two tabs of the panel)
    property int sound: 1                  // 0 off, 1 system audio, 2 system audio + microphone
    property bool counting: false          // the 3-2-1 countdown before a recording
    property int countN: 3
    property real cdX: 0
    property real cdY: 0
    property bool pendingRec: false
    property var recArgs: null
    property real monOffX: 0
    property real monOffY: 0
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
        function onShotRequested() {
            if (Rec.active) { if (win.isFocusedMon) Rec.stop(); return; }     // Print again = stop recording
            if (win.isFocusedMon && !win.busy && !win.open && !win.flashing && !win.counting) win.begin();
        }
    }

    // ---- flow -------------------------------------------------------------------------------
    function begin() {
        busy = true;
        mode = "pane";
        kind = "shot";
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
        if (pendingRec) { pendingRec = false; startCountdown(); }
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
        if (counting) { cancelCountdown(); return; }
        dragging = false;
        dragKind = "";
        guideX = -1; guideY = -1;
        if (mode === "region" && selW > 0) { clearSel(); return; }     // Esc once = redo the selection
        if (mode === "pane") dismiss(); else mode = "pane";
    }
    function pick(i) {
        choice = i;
        if (kind === "rec") {
            if (i === 0) { clearSel(); mode = "region"; if (!winProc.running) winProc.running = true; }
            else if (i === 1) recordScreen();
            else sound = (sound + 1) % 3;                  // the Sound tile just cycles off / system / system + mic
            return;
        }
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
        monOffX = mon.x;
        monOffY = mon.y;
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

    function snap() {
        if (selW < 4 || selH < 4) return;
        if (kind === "rec") recordRegion(selX, selY, selW, selH);
        else grab(selX, selY, selW, selH);
    }

    // ---- recorder: the Record tab, the 3-2-1 countdown and the hand-over to viii-record ----
    function setKind(k) { kind = k; choice = Math.min(choice, 2); }
    function toggleKind() { setKind(kind === "shot" ? "rec" : "shot"); }
    function recordScreen() {
        recArgs = { target: screen.name, geom: "-", cx: width / 2, cy: height / 2 };
        pendingRec = true;
        leave(null);                       // the pane fades out; endFlash() then starts the countdown
    }
    function recordRegion(x, y, w, h) {
        const iw = Math.max(frozen.implicitWidth, frozen.sourceSize.width);
        const ih = Math.max(frozen.implicitHeight, frozen.sourceSize.height);
        const rx = (iw > 0 && width > 0) ? iw / width : 1;
        const ry = (ih > 0 && height > 0) ? ih / height : 1;
        let pw = Math.max(2, Math.round(w * rx));
        let ph = Math.max(2, Math.round(h * ry));
        pw -= pw % 2;
        ph -= ph % 2;
        const px = Math.round(x * rx + monOffX);
        const py = Math.round(y * ry + monOffY);
        recArgs = { target: "region", geom: pw + "x" + ph + "+" + px + "+" + py, cx: x + w / 2, cy: y + h / 2 };
        pendingRec = true;
        leave(null);
    }
    function startCountdown() {
        cleanup();                         // the frozen screenshot is not needed any more
        countN = 3;
        cdX = Math.max(100, Math.min(width - 100, recArgs ? recArgs.cx : width / 2));
        cdY = Math.max(100, Math.min(height - 120, recArgs ? recArgs.cy : height / 2));
        counting = true;
        root.forceActiveFocus();
    }
    function tickCountdown() {
        countN = countN - 1;
        if (countN <= 0) { counting = false; startDelay.start(); }
    }
    function cancelCountdown() {
        counting = false;
        pendingRec = false;
        recArgs = null;
        startDelay.stop();
    }
    function beginRecording() {
        if (!recArgs) return;
        const snd = sound === 0 ? "off" : (sound === 1 ? "sys" : "both");
        Rec.start(recArgs.target, recArgs.geom, snd);
        recArgs = null;
    }
    function nudge(dx, dy, big) {
        if (selW < 4) return;
        const st = big ? 10 : 1;
        selX = Math.max(0, Math.min(win.width - selW, selX + dx * st));
        selY = Math.max(0, Math.min(win.height - selH, selY + dy * st));
    }

    function handleKey(e) {
        let ok = true;
        if (counting) { if (e.key === Qt.Key_Escape) back(); e.accepted = true; return; }
        if (e.key === Qt.Key_Escape) back();
        else if (mode === "pane") {
            switch (e.key) {
            case Qt.Key_Left: choice = Math.max(0, choice - 1); break;
            case Qt.Key_Right: choice = Math.min(2, choice + 1); break;
            case Qt.Key_Tab: case Qt.Key_Backtab: case Qt.Key_Up: case Qt.Key_Down: toggleKind(); break;
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

    // ---- scene (viii-shot3) ----------------------------------------------------------------
    // Sony-style capture UI: the frozen screen dims, one glass panel offers Region / Window / Screen with
    // the same selection ring as the rest of the shell, and the ring also outlines the captured area.
    // No rulers. Only opacity / x / y / scale and colours are animated.
    // The panel has two tabs: Screenshot and Record (Tab key / click to switch).
    FocusScope {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => win.handleKey(event)

        readonly property color dimColor: Qt.alpha(Theme.deep, 0.60 * win.pv)
        // bumped when the Window-mode highlight lands on another window, so the ring shade plays again
        property int winTick: 0
        Connections {
            target: win
            function onHoverWinChanged() { root.winTick++; }
        }

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
        Rectangle { x: 0; y: 0; width: win.width; height: selBox.y; color: root.dimColor }
        Rectangle { x: 0; y: selBox.y + selBox.height; width: win.width; height: Math.max(0, win.height - selBox.y - selBox.height); color: root.dimColor }
        Rectangle { x: 0; y: selBox.y; width: selBox.x; height: selBox.height; color: root.dimColor }
        Rectangle { x: selBox.x + selBox.width; y: selBox.y; width: Math.max(0, win.width - selBox.x - selBox.width); height: selBox.height; color: root.dimColor }

        // the selection geometry (glides between windows in Window mode, follows the mouse in Region mode)
        Item {
            id: selBox
            x: win.target.x
            y: win.target.y
            width: win.target.width
            height: win.target.height
            Behavior on x { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on y { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on width { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            Behavior on height { enabled: win.mode === "window"; NumberAnimation { duration: 170; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
        }

        // the ring outlines the area that will be captured
        GlassRing {
            readonly property real out: 3
            x: selBox.x - out
            y: selBox.y - out
            width: selBox.width + 2 * out
            height: selBox.height + 2 * out
            radius: 8 + out
            thickness: 2.5
            shade: win.mode === "window"
            trigger: root.winTick
            animated: visible
            opacity: ((win.open || win.flashing) && win.mode !== "pane" && selBox.width > 2 && selBox.height > 2)
                ? (win.flashing ? win.pv : 1) : 0
            visible: opacity > 0.01
            Behavior on opacity { enabled: !win.flashing; NumberAnimation { duration: 140 } }
        }

        // the capture flash
        Rectangle {
            x: win.flashRect.x; y: win.flashRect.y
            width: win.flashRect.width; height: win.flashRect.height
            color: "white"
            opacity: win.flashA
            visible: win.flashing && win.flashA > 0.01
        }

        // size / title chip above the selection
        Rectangle {
            id: chip
            visible: opacity > 0.01
            opacity: (win.open && win.mode !== "pane" && selBox.width > 30) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            x: Math.max(8, Math.min(selBox.x, win.width - width - 8))
            y: selBox.y > 52 ? selBox.y - height - 12 : selBox.y + 12
            height: 28
            width: chipText.width + 26
            radius: 14
            color: Qt.alpha(Theme.deep, 0.88)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.14)
            Txt {
                id: chipText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, 420)
                font.pixelSize: 13
                text: (win.mode === "window" && win.hoverWin ? win.hoverWin.t + "   \u00b7   " : "") + Math.round(selBox.width) + " \u00d7 " + Math.round(selBox.height)
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

        // ---- Region mode: crosshair, snap guides, handles, magnifier ----
        Item {
            id: regionUi
            anchors.fill: parent
            opacity: (win.mode === "region" && win.open) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            // crosshair: two hairlines and a small ring at the cursor
            Rectangle { x: Math.round(area.mouseX); y: 0; width: 1; height: win.height; color: Qt.rgba(1, 1, 1, 0.32); visible: area.containsMouse && win.zoneNow === "" }
            Rectangle { x: 0; y: Math.round(area.mouseY); width: win.width; height: 1; color: Qt.rgba(1, 1, 1, 0.32); visible: area.containsMouse && win.zoneNow === "" }
            Rectangle {
                x: Math.round(area.mouseX) - 6; y: Math.round(area.mouseY) - 6
                width: 12; height: 12; radius: 6
                color: "transparent"
                border.width: 1.5
                border.color: Qt.rgba(1, 1, 1, 0.95)
                visible: area.containsMouse && win.zoneNow === ""
            }

            // snap guides (shown while an edge snaps to a window or screen edge)
            Rectangle { visible: win.dragging && win.guideX >= 0; x: win.guideX; y: 0; width: 1; height: win.height; color: Theme.accent }
            Rectangle { visible: win.dragging && win.guideY >= 0; x: 0; y: win.guideY; width: win.width; height: 1; color: Theme.accent }

            // eight round resize handles on the kept region
            Repeater {
                model: 8
                delegate: Rectangle {
                    required property int index
                    readonly property real fx: [0, 0.5, 1, 1, 1, 0.5, 0, 0][index]
                    readonly property real fy: [0, 0, 0, 0.5, 1, 1, 1, 0.5][index]
                    visible: win.selW >= 12 && win.selH >= 12 && !(win.dragging && win.dragKind === "new")
                    x: selBox.x + fx * selBox.width - 6
                    y: selBox.y + fy * selBox.height - 6
                    width: 12; height: 12
                    radius: 6
                    color: Theme.fg
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.35)
                }
            }

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
                readonly property bool flipY: area.mouseY + gapPx + box + 34 > win.height - 8
                x: flipX ? area.mouseX - gapPx - box : area.mouseX + gapPx
                y: flipY ? area.mouseY - gapPx - box - 34 : area.mouseY + gapPx
                width: box
                height: box + 34

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
                Rectangle { x: 0; y: mag.box / 2 - 0.5; width: mag.box; height: 1; color: Qt.rgba(1, 1, 1, 0.18) }
                Rectangle { x: mag.box / 2 - 0.5; y: 0; width: 1; height: mag.box; color: Qt.rgba(1, 1, 1, 0.18) }
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
                    border.color: Qt.rgba(1, 1, 1, 0.92)
                }
                Rectangle {
                    y: mag.box + 8
                    width: mag.box; height: 26
                    radius: 13
                    color: Qt.alpha(Theme.deep, 0.88)
                    border.width: 1
                    border.color: Qt.alpha(Theme.fg, 0.14)
                    Txt {
                        anchors.centerIn: parent
                        font.pixelSize: 13
                        text: Math.floor(area.mouseX) + ",  " + Math.floor(area.mouseY)
                    }
                }
            }
        }

        // ---- Capture / Redo bar under the kept region ----
        Item {
            id: pill
            readonly property bool show: win.open && win.mode === "region" && win.selW >= 4 && win.selH >= 4 && !win.dragging
            opacity: show ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140 } }
            width: pillRow.width + 44
            height: 58
            x: Math.max(8, Math.min(win.width - width - 8, selBox.x + selBox.width / 2 - width / 2))
            y: (selBox.y + selBox.height + 20 + height < win.height - 6) ? selBox.y + selBox.height + 20 : selBox.y + selBox.height - height - 16

            Rectangle {
                anchors.fill: parent
                radius: 29
                color: Qt.alpha(Theme.deep, 0.90)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.10)
            }
            MouseArea { anchors.fill: parent }      // clicks on the bar never start a new selection

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 22

                // Redo
                Item {
                    width: redoRow.width
                    height: 38
                    Row {
                        id: redoRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 9
                        Rectangle {
                            width: escText.implicitWidth + 14; height: 20; radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.alpha(Theme.fg, 0.07)
                            border.width: 1
                            border.color: Qt.alpha(Theme.fg, 0.22)
                            Txt { id: escText; anchors.centerIn: parent; text: "Esc"; font.pixelSize: 11; color: Theme.fgDim }
                        }
                        Txt { anchors.verticalCenter: parent.verticalCenter; text: "Redo"; font.pixelSize: 14; color: Theme.fgDim }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.back() }
                }

                // Capture: the focused button wears the ring
                Item {
                    id: capBtn
                    width: capRow.width + 38
                    height: 38
                    Rectangle { anchors.fill: parent; radius: 19; color: Theme.fg }
                    Row {
                        id: capRow
                        anchors.centerIn: parent
                        spacing: 10
                        Txt { anchors.verticalCenter: parent.verticalCenter; text: win.kind === "rec" ? "Record" : "Capture"; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#0b0d12" }
                        Rectangle {
                            width: capKey.implicitWidth + 12; height: 18; radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(0, 0, 0, 0.12)
                            Txt { id: capKey; anchors.centerIn: parent; text: "Enter"; font.pixelSize: 10; color: "#0b0d12" }
                        }
                    }
                    GlassRing {
                        readonly property real out: 3.5
                        x: -out; y: -out
                        width: capBtn.width + 2 * out
                        height: capBtn.height + 2 * out
                        radius: 19 + out
                        thickness: 2
                        shade: false
                        animated: pill.visible
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.snap() }
                }
            }
        }

        // ---- the panel: Region / Window / Screen ----
        Item {
            id: bar
            readonly property real pad: 22
            readonly property real tileW: 150
            readonly property real tileH: 118
            readonly property real gap: 14
            readonly property real tilesY: 62
            readonly property var tiles: win.kind === "shot"
                ? [ { n: "Region", i: "region" }, { n: "Window", i: "window" }, { n: "Screen", i: "screen" } ]
                : [ { n: "Region", i: "region" }, { n: "Screen", i: "screen" }, { n: "Sound", i: "sound" } ]
            readonly property string desc: win.kind === "shot"
                ? ["Select an area of the screen", "Capture a single window", "Capture the whole screen"][win.choice]
                : (win.choice === 2
                    ? ["Video only, no sound", "Record the system audio", "Record system audio and microphone"][win.sound]
                    : ["Record an area of the screen", "Record the whole screen"][win.choice])
            readonly property var hints: [
                { k: "\u2190  \u2192", t: "Move" },
                { k: "Enter", t: win.kind === "rec" && win.choice === 2 ? "Change" : "Choose" },
                { k: "Tab", t: win.kind === "shot" ? "Record" : "Screenshot" },
                { k: "Esc", t: "Cancel" }
            ]

            width: pad * 2 + tileW * 3 + gap * 2
            height: 238
            scale: win.s * (0.92 + 0.08 * win.pop)
            transformOrigin: Item.Bottom
            x: (win.width - width) / 2
            y: win.height - height - 44 * win.s + (1 - win.pop) * 26
            opacity: (win.open && win.mode === "pane") ? Math.min(1, win.pv * 1.4) : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: 28
                color: Qt.alpha(Theme.deep, 0.90)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.10)
            }
            MouseArea { anchors.fill: parent }      // clicks on the panel itself do nothing (they used to dismiss it)

            // header
            Row {
                id: tabs
                x: bar.pad
                y: 18
                spacing: 24
                Item {
                    id: tabShot
                    width: tabShotText.implicitWidth
                    height: 26
                    Txt {
                        id: tabShotText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Screenshot"
                        font.pixelSize: 18
                        font.weight: win.kind === "shot" ? Font.DemiBold : Font.Medium
                        color: win.kind === "shot" ? Theme.fg : Theme.fgDim
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.setKind("shot") }
                }
                Item {
                    id: tabRec
                    width: recDot.width + 8 + tabRecText.implicitWidth
                    height: 26
                    Rectangle { id: recDot; width: 9; height: 9; radius: 4.5; color: "#ff4d57"; anchors.verticalCenter: parent.verticalCenter }
                    Txt {
                        id: tabRecText
                        x: recDot.width + 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Record"
                        font.pixelSize: 18
                        font.weight: win.kind === "rec" ? Font.DemiBold : Font.Medium
                        color: win.kind === "rec" ? Theme.fg : Theme.fgDim
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.setKind("rec") }
                }
            }
            Rectangle {
                y: 46
                height: 2
                radius: 1
                color: Theme.fg
                x: bar.pad + (win.kind === "shot" ? tabShot.x : tabRec.x)
                width: win.kind === "shot" ? tabShot.width : tabRec.width
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            }
            Txt {
                anchors.right: parent.right
                anchors.rightMargin: bar.pad
                y: 23
                width: Math.min(implicitWidth, 270)
                horizontalAlignment: Text.AlignRight
                text: bar.desc
                font.pixelSize: 13
                color: Theme.fgDim
            }

            // the three options
            Repeater {
                model: bar.tiles
                delegate: Item {
                    id: opt
                    required property var modelData
                    required property int index
                    readonly property bool selected: win.choice === index

                    x: bar.pad + index * (bar.tileW + bar.gap)
                    y: bar.tilesY
                    width: bar.tileW
                    height: bar.tileH

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: opt.selected ? Qt.alpha(Theme.fg, 0.10) : Qt.alpha(Theme.fg, 0.045)
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Item {
                        id: icon
                        x: (parent.width - width) / 2
                        y: 26
                        width: 48; height: 38
                        property color ink: opt.selected ? Theme.fg : Theme.fgDim
                        Behavior on ink { ColorAnimation { duration: 180 } }
                        scale: opt.selected ? 1.1 : 1
                        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: win.spring } }

                        // Region: four rounded corner brackets and a centre dot
                        Item {
                            anchors.fill: parent
                            visible: opt.modelData.i === "region"
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    startX: 3; startY: 14
                                    PathLine { x: 3; y: 9 }
                                    PathQuad { x: 9; y: 3; controlX: 3; controlY: 3 }
                                    PathLine { x: 15; y: 3 }
                                }
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    startX: 33; startY: 3
                                    PathLine { x: 39; y: 3 }
                                    PathQuad { x: 45; y: 9; controlX: 45; controlY: 3 }
                                    PathLine { x: 45; y: 14 }
                                }
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    startX: 3; startY: 24
                                    PathLine { x: 3; y: 29 }
                                    PathQuad { x: 9; y: 35; controlX: 3; controlY: 35 }
                                    PathLine { x: 15; y: 35 }
                                }
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    startX: 33; startY: 35
                                    PathLine { x: 39; y: 35 }
                                    PathQuad { x: 45; y: 29; controlX: 45; controlY: 35 }
                                    PathLine { x: 45; y: 24 }
                                }
                            }
                            Rectangle { x: 21.5; y: 16.5; width: 5; height: 5; radius: 2.5; color: icon.ink }
                        }

                        // Window: a rounded window with a title bar and three dots
                        Item {
                            anchors.fill: parent
                            visible: opt.modelData.i === "window"
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    startX: 10; startY: 3
                                    PathLine { x: 38; y: 3 }
                                    PathQuad { x: 45; y: 10; controlX: 45; controlY: 3 }
                                    PathLine { x: 45; y: 28 }
                                    PathQuad { x: 38; y: 35; controlX: 45; controlY: 35 }
                                    PathLine { x: 10; y: 35 }
                                    PathQuad { x: 3; y: 28; controlX: 3; controlY: 35 }
                                    PathLine { x: 3; y: 10 }
                                    PathQuad { x: 10; y: 3; controlX: 3; controlY: 3 }
                                }
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    startX: 3; startY: 14
                                    PathLine { x: 45; y: 14 }
                                }
                            }
                            Rectangle { x: 9; y: 7; width: 3; height: 3; radius: 1.5; color: icon.ink }
                            Rectangle { x: 15; y: 7; width: 3; height: 3; radius: 1.5; color: icon.ink }
                            Rectangle { x: 21; y: 7; width: 3; height: 3; radius: 1.5; color: icon.ink }
                        }

                        // Screen: a monitor on a stand
                        Item {
                            anchors.fill: parent
                            visible: opt.modelData.i === "screen"
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    startX: 9; startY: 3
                                    PathLine { x: 39; y: 3 }
                                    PathQuad { x: 45; y: 9; controlX: 45; controlY: 3 }
                                    PathLine { x: 45; y: 21 }
                                    PathQuad { x: 39; y: 27; controlX: 45; controlY: 27 }
                                    PathLine { x: 9; y: 27 }
                                    PathQuad { x: 3; y: 21; controlX: 3; controlY: 27 }
                                    PathLine { x: 3; y: 9 }
                                    PathQuad { x: 9; y: 3; controlX: 3; controlY: 3 }
                                }
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    startX: 24; startY: 27
                                    PathLine { x: 24; y: 34 }
                                }
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    startX: 15; startY: 35
                                    PathLine { x: 33; y: 35 }
                                }
                            }
                        }

                        // Sound: a speaker. No wave = off, one wave = system audio, two = system + microphone
                        Item {
                            anchors.fill: parent
                            visible: opt.modelData.i === "sound"
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: icon.ink; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    startX: 5; startY: 14
                                    PathLine { x: 12; y: 14 }
                                    PathLine { x: 22; y: 6 }
                                    PathLine { x: 22; y: 32 }
                                    PathLine { x: 12; y: 24 }
                                    PathLine { x: 5; y: 24 }
                                    PathLine { x: 5; y: 14 }
                                }
                                ShapePath {
                                    strokeColor: win.sound >= 1 ? icon.ink : "transparent"; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    startX: 29; startY: 14
                                    PathQuad { x: 29; y: 24; controlX: 34; controlY: 19 }
                                }
                                ShapePath {
                                    strokeColor: win.sound >= 2 ? icon.ink : "transparent"; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    startX: 34; startY: 9
                                    PathQuad { x: 34; y: 29; controlX: 45; controlY: 19 }
                                }
                                ShapePath {
                                    strokeColor: win.sound === 0 ? icon.ink : "transparent"; strokeWidth: 3; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    startX: 30; startY: 12
                                    PathLine { x: 42; y: 26 }
                                }
                            }
                        }
                    }

                    Txt {
                        visible: opt.modelData.i === "sound"
                        x: 0; y: 97
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: ["Off", "System", "System + Mic"][win.sound]
                        font.pixelSize: 12
                        color: Theme.fgDim
                    }

                    Txt {
                        x: 0; y: opt.modelData.i === "sound" ? 74 : 80
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: opt.modelData.n
                        font.pixelSize: 17
                        font.weight: opt.selected ? Font.DemiBold : Font.Medium
                        color: opt.selected ? Theme.fg : Theme.fgDim
                        Behavior on color { ColorAnimation { duration: 180 } }
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

            // the same ring as the hub, gliding between the three options
            GlassRing {
                readonly property real out: 3.5
                x: bar.pad + win.choice * (bar.tileW + bar.gap) - out
                y: bar.tilesY - out
                width: bar.tileW + 2 * out
                height: bar.tileH + 2 * out
                radius: 16 + out
                thickness: 2.5
                shade: true
                trigger: win.choice
                animated: bar.visible
                z: 3
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out } }
            }

            // key hints
            Row {
                x: bar.pad
                y: bar.height - bar.pad - 20
                spacing: 20
                Repeater {
                    model: bar.hints
                    delegate: Row {
                        required property var modelData
                        spacing: 8
                        Rectangle {
                            width: keyText.implicitWidth + 14; height: 20; radius: 6
                            color: Qt.alpha(Theme.fg, 0.07)
                            border.width: 1
                            border.color: Qt.alpha(Theme.fg, 0.22)
                            Txt { id: keyText; anchors.centerIn: parent; text: modelData.k; font.pixelSize: 11; color: Theme.fgDim }
                        }
                        Txt { anchors.verticalCenter: parent.verticalCenter; text: modelData.t; font.pixelSize: 13; color: Theme.fgDim }
                    }
                }
            }
        }

        // ---- recording countdown: shown over the live screen, gone before the recording starts ----
        Item {
            id: cd
            visible: win.counting
            x: win.cdX - width / 2
            y: win.cdY - 80
            width: 160
            height: 200
            Rectangle { x: 0; y: 0; width: 160; height: 160; radius: 80; color: Qt.alpha(Theme.deep, 0.80) }
            GlassRing {
                readonly property real out: 4
                x: -out; y: -out
                width: 160 + 2 * out
                height: 160 + 2 * out
                radius: 80 + out
                thickness: 3
                shade: false
                animated: cd.visible
            }
            Txt {
                id: cdNum
                x: 0; y: 0
                width: 160; height: 160
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: String(Math.max(1, win.countN))
                font.pixelSize: 78
                font.weight: Font.DemiBold
                transformOrigin: Item.Center
            }
            Rectangle {
                x: (parent.width - width) / 2
                y: 170
                width: cdHint.width + 28
                height: 32
                radius: 16
                color: Qt.alpha(Theme.deep, 0.82)
            }
            Row {
                id: cdHint
                y: 176
                x: (parent.width - width) / 2
                spacing: 8
                Rectangle {
                    width: cdEsc.implicitWidth + 14; height: 20; radius: 6
                    color: Qt.alpha(Theme.fg, 0.07)
                    border.width: 1
                    border.color: Qt.alpha(Theme.fg, 0.22)
                    Txt { id: cdEsc; anchors.centerIn: parent; text: "Esc"; font.pixelSize: 11; color: Theme.fgDim }
                }
                Txt { anchors.verticalCenter: parent.verticalCenter; text: "Cancel"; font.pixelSize: 13; color: Theme.fgDim }
            }
        }
        NumberAnimation { id: cdPop; target: cdNum; property: "scale"; from: 1.3; to: 1; duration: 380; easing.type: Easing.OutBack }
        Connections { target: win; function onCountNChanged() { cdPop.restart(); } }
        Timer { id: countTimer; interval: 1000; repeat: true; running: win.counting; onTriggered: win.tickCountdown() }
        // the overlay is already gone when this fires, so it never ends up in the video
        Timer { id: startDelay; interval: 450; onTriggered: win.beginRecording() }
    }
}
