pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Where the desktop stands: which monitors have an empty workspace (hub is the base layer there),
// whether the hub was summoned on top of windows, and the PS-button tap/hold logic.
Singleton {
    id: root

    property bool summoned: false      // hub forced open over windows (PS button / launcher key)
    property var empty: ({})           // monitor name -> true when its active workspace has no windows
    property bool psHoldFired: false

    signal libraryRequested()
    signal psTap()
    signal psHold()

    function isEmpty(name) { return empty[name] === true; }

    function openLibrary() { summoned = true; libraryRequested(); }

    // PS button: bound twice in Hyprland (press, and release). Short press = tap, long press = hold.
    function psDown() { psHoldFired = false; holdTimer.restart(); }
    function psUp() { holdTimer.stop(); if (!psHoldFired) psTap(); }

    onPsTap: summoned = !summoned

    function refresh() { wsProc.running = true; }

    function apply(workspaces, monitors) {
        const next = {};
        for (let i = 0; i < monitors.length; i++) {
            const m = monitors[i];
            const id = m.activeWorkspace ? m.activeWorkspace.id : -1;
            const ws = workspaces.find(w => w.id === id);
            const special = m.specialWorkspace && m.specialWorkspace.name !== "";
            next[m.name] = !special && (!ws || ws.windows === 0);
        }
        empty = next;
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

    Timer { id: debounce; interval: 40; onTriggered: root.refresh() }
    Timer { id: holdTimer; interval: 480; onTriggered: { root.psHoldFired = true; root.psHold(); } }

    Component.onCompleted: refresh()
}
