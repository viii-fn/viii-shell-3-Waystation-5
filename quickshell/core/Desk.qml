pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Where the desktop stands: which monitors have an empty workspace (hub is the base layer there),
// whether the hub was summoned on top of windows, the PS-button tap/hold logic, the Control Center
// open state, and brightness (shared by the Control Center, the brightness keys and the OSD).
Singleton {
    id: root

    property bool summoned: false      // hub forced open over windows (launcher key)
    property bool ccOpen: false        // Control Center open (PS button tap)
    property real notifSeen: Date.now() // notifications newer than this are "unread" (Control Center bell badge)
    property var empty: ({})           // monitor name -> true when its active workspace has no windows
    property bool psHoldFired: false
    property bool psIsDown: false      // guards against key repeat and double release events
    property var lastActive: null      // last focused window (Wayland toplevel), for the Control Center's Active app

    property int brightness: -1        // percent, -1 = unknown
    property int briPending: 0

    signal libraryRequested()
    signal hubRequested()              // viii-hub-root: launcher key goes to the hub's root page
    signal settingsRequested()
    signal wardRequested()
    signal shotRequested()
    signal psTap()
    signal ccRegrab()                  // ask the Control Center window to take the keyboard again (after a workspace switch)

    function openSettings() {
        summoned = true;
        settingsRequested();
    }
    signal psHold()
    signal osdRequested(string kind, int value)

    function isEmpty(name) { return empty[name] === true; }

    function openLibrary() { summoned = true; libraryRequested(); }
    function openHub() { ccOpen = false; summoned = true; hubRequested(); }   // viii-hub-root
    function openHistory() { notifSeen = Date.now(); summoned = true; wardRequested(); }
    function openShot() { shotRequested(); }

    // PS button: bound twice in Hyprland (press, and release). Short press = tap, long press = hold.
    // Both functions are safe to call more than once per physical press.
    function psDown() {
        if (psIsDown) return;
        psIsDown = true;
        psHoldFired = false;
        holdTimer.restart();
    }
    function psUp() {
        if (!psIsDown) return;
        psIsDown = false;
        holdTimer.stop();
        if (!psHoldFired) psTap();
    }

    // Tap = Control Center. (Hold is reserved for the power menu, not built yet.)
    onPsTap: ccOpen = !ccOpen

    // ---- brightness (brightnessctl) ----
    // Steps are queued so fast key repeat never drops a press.
    function briStep(delta) { briPending += delta; briKick(); }
    function briRefresh() { briCmd(["brightnessctl", "-m"], false); }

    function briKick() {
        if (briProc.running || briPending === 0) return;
        const d = briPending;
        briPending = 0;
        briCmd(["brightnessctl", "-m", "--min-value=1", "set", Math.abs(d) + "%" + (d > 0 ? "+" : "-")], true);
    }

    function briCmd(cmd, announce) {
        if (briProc.running) return;
        briAnnounce = announce;
        briProc.command = cmd;
        briProc.running = true;
    }

    // brightnessctl -m prints: device,class,current,percent%,max
    function briParsed(text, announce) {
        const f = text.trim().split(",");
        if (f.length < 4) return;
        const v = parseInt(f[3]);
        if (isNaN(v)) return;
        brightness = v;
        if (announce) osdRequested("brightness", v);
    }

    property bool briAnnounce: false

    Process {
        id: briProc
        stdout: StdioCollector { onStreamFinished: root.briParsed(this.text, root.briAnnounce) }
        onExited: root.briKick()
    }

    // ---- workspaces ----
    // Hyprland's models already carry the active workspace and its toplevel list, so a
    // window opening/closing is one model update instead of two `hyprctl` processes.
    // The process path below is only the first snapshot, used while the models are still
    // empty during shell startup (and as a fallback if they are unavailable).
    function computeEmpty() {
        const next = {};
        const monitors = Hyprland.monitors.values;
        for (let i = 0; i < monitors.length; i++) {
            const m = monitors[i];
            const ws = m.activeWorkspace;
            const ipc = m.lastIpcObject;
            const special = ipc && ipc.specialWorkspace && ipc.specialWorkspace.name !== "";
            const top = ws && ws.toplevels ? ws.toplevels.values : null;
            next[m.name] = !special && (!ws || (top ? top.length === 0 : false));
        }
        return next;
    }

    readonly property var modelEmpty: computeEmpty()
    onModelEmptyChanged: publish(modelEmpty)

    function publish(next) {
        // publish only when something changed, otherwise every listener (hub visibility,
        // backdrop, ...) re-evaluates for nothing
        const keys = Object.keys(next);
        if (keys.length === Object.keys(empty).length && keys.every(k => empty[k] === next[k])) return;
        empty = next;
    }

    function apply(workspaces, monitors) {
        const next = {};
        for (let i = 0; i < monitors.length; i++) {
            const m = monitors[i];
            const id = m.activeWorkspace ? m.activeWorkspace.id : -1;
            const ws = workspaces.find(w => w.id === id);
            const special = m.specialWorkspace && m.specialWorkspace.name !== "";
            next[m.name] = !special && (!ws || ws.windows === 0);
        }
        publish(next);
    }

    function refresh() {
        if (Hyprland.monitors.values.length === 0) {
            // startup: the models have not received their first snapshot yet
            if (!wsProc.running) wsProc.running = true;
            return;
        }
        publish(computeEmpty());
    }

    property var wsCache: []

    function parseJson(text) { try { return JSON.parse(text); } catch (e) { return null; } }

    Process {
        id: wsProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: { root.wsCache = root.parseJson(this.text) || []; monProc.running = true; }
        }
    }

    Process {
        id: monProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: root.apply(root.wsCache, root.parseJson(this.text) || [])
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "workspace" || n === "workspacev2" || n === "focusedmon" || n === "focusedmonv2"
                || n === "createworkspace" || n === "createworkspacev2" || n === "destroyworkspace"
                || n === "destroyworkspacev2" || n === "openwindow" || n === "closewindow"
                || n === "movewindow" || n === "movewindowv2" || n === "moveworkspace"
                || n === "moveworkspacev2" || n === "monitoradded" || n === "monitorremoved"
                || n === "activespecial" || n === "activespecialv2")
                debounce.restart();
        }
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { if (ToplevelManager.activeToplevel) root.lastActive = ToplevelManager.activeToplevel; }
    }

    Timer { id: debounce; interval: 40; onTriggered: root.refresh() }
    Timer { id: holdTimer; interval: 480; onTriggered: { root.psHoldFired = true; root.psHold(); } }

    Component.onCompleted: { refresh(); briRefresh(); if (ToplevelManager.activeToplevel) lastActive = ToplevelManager.activeToplevel; }
}
