pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screen recorder state. The recording itself is done by ~/.local/bin/viii-record (gpu-screen-recorder),
// detached from the shell, so reloading Quickshell never stops a recording.
Singleton {
    id: root

    property bool active: false
    property double startedAt: 0            // ms since epoch

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/viii-record"

    function start(target, geom, sound) {
        startProc.command = [bin, "start", target, geom, sound];
        startProc.running = true;
    }
    function stop() {
        if (stopProc.running) return;
        active = false;
        stopProc.command = [bin, "stop"];
        stopProc.running = true;
    }
    function refresh() {
        if (!statusProc.running) { statusProc.command = [bin, "status"]; statusProc.running = true; }
    }

    Process {
        id: startProc
        onExited: root.refresh()
    }
    Process {
        id: stopProc
        onExited: root.refresh()
    }
    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim().split(" ");
                root.active = t[0] === "recording";
                root.startedAt = root.active ? Number(t[1]) * 1000 : 0;
            }
        }
    }
    // notice when a recording ends by itself (crash, disk full); polls only while recording
    Timer {
        interval: 4000
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()
}
