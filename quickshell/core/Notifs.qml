pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.UPower

// The shell's notification daemon, the notification history, and charger plug/unplug events.
// No Behavior in here (Qt 6.12 singleton crash): notif/NotifPopup.qml does all the animating.
//
// An entry is a plain object:
//   { id, t (ms since epoch), kind ("app" | "power"), plugged (power only), app, icon, title, body, urgency (0 low, 1 normal, 2 critical) }
// History (newest first, max 100) is kept in memory and appended to ~/.local/state/viii/notifs.jsonl,
// so it survives `viii restart`.
Singleton {
    id: root

    // ---- public state ----
    property var history: []            // newest first
    property var current: null          // entry on screen (kept until the exit animation is done)
    property bool shown: false          // true while the toast should be visible
    property bool popups: true          // Settings > Notifications > Pop-up Notifications
    property var queue: []              // entries waiting behind the current toast

    readonly property int maxHistory: 100
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/viii"
    readonly property string file: stateDir + "/notifs.jsonl"

    property int plugState: -1          // -1 unknown, 0 unplugged, 1 plugged in
    property bool armed: false          // charger events are silent for the first 2.5 s after startup
    property bool mainsDirty: false
    property int seq: 0

    function newId() { seq = (seq + 1) % 1000; return Date.now() * 1000 + seq; }

    // how long a toast stays up
    function holdFor(e) {
        if (e.kind === "power") return 3500;
        if (e.urgency === 2) return 9000;
        if (e.urgency === 0) return 3000;
        return 4500;
    }

    // ---- recording ----
    function record(e) {
        const h = root.history.slice(0, root.maxHistory - 1);
        h.unshift(e);
        root.history = h;
        persist(JSON.stringify(e));
    }

    function clear() {
        root.history = [];
        root.queue = [];
        clearProc.running = true;
    }

    // ---- showing ----
    // regular notification: waits its turn behind the toast on screen
    function post(e) {
        record(e);
        if (!popups) return;
        if (!root.current) present(e);
        else root.queue = root.queue.concat([e]);
    }

    // charger events: replace whatever is on screen right away
    function postNow(e) {
        record(e);
        if (!popups) return;
        present(e);
    }

    function present(e) {
        gapTimer.stop();
        root.current = e;
        root.shown = true;
        holdTimer.interval = holdFor(e);
        holdTimer.restart();
    }

    function dismiss() {
        holdTimer.stop();
        root.shown = false;
        gapTimer.restart();
    }

    Timer { id: holdTimer; onTriggered: root.dismiss() }

    // after the exit animation: next queued toast, or clear the stage
    Timer {
        id: gapTimer
        interval: 340
        onTriggered: {
            if (root.queue.length > 0) {
                const q = root.queue.slice();
                const n = q.shift();
                root.queue = q;
                root.present(n);
            } else {
                root.current = null;
            }
        }
    }

    // ---- regular notifications (org.freedesktop.Notifications) ----
    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: false
        imageSupported: false
        persistenceSupported: false
        onNotification: notification => {
            const title = notification.summary || notification.appName || "";
            const body = notification.body || "";
            if (title === "" && body === "") return;
            root.post({
                id: root.newId(),
                t: Date.now(),
                kind: "app",
                plugged: false,
                app: notification.appName || "",
                icon: notification.appIcon || "",
                title: title,
                body: body,
                urgency: notification.urgency === NotificationUrgency.Critical ? 2 : (notification.urgency === NotificationUrgency.Low ? 0 : 1)
            });
        }
    }

    // ---- charger plugged in / out ----
    // Ground truth is the Mains supply's "online" file in sysfs. It is re-read the moment the kernel reports a
    // power_supply change (udevadm monitor pushes it to us), and also whenever UPower's view of the battery flips.
    // So there is no polling and no timer lag; a 20 ms debounce just merges the burst of events one plug makes.
    readonly property var disp: UPower.displayDevice
    readonly property bool upPlugged: !!disp && (disp.state === UPowerDeviceState.Charging || disp.state === UPowerDeviceState.FullyCharged || disp.state === UPowerDeviceState.PendingCharge)
    onUpPluggedChanged: readTimer.restart()

    function readMains() {
        if (mains.running) root.mainsDirty = true;
        else mains.running = true;
    }

    function setPlug(v) {
        if (v === root.plugState) return;
        const first = root.plugState < 0;
        root.plugState = v;
        if (first || !root.armed) return;
        const p = root.disp ? Math.round(root.disp.percentage * 100) : -1;
        postNow({
            id: newId(),
            t: Date.now(),
            kind: "power",
            plugged: v === 1,
            app: "Power",
            icon: "",
            title: v === 1 ? "Charger connected" : "Charger disconnected",
            body: p >= 0 ? "Battery " + p + "%" : "",
            urgency: 1
        });
    }

    Timer { id: readTimer; interval: 20; onTriggered: root.readMains() }
    Timer { running: true; interval: 2500; onTriggered: root.armed = true }

    Process {
        id: mains
        command: ["bash", "-c", "for d in /sys/class/power_supply/*; do [ \"$(cat \"$d/type\" 2>/dev/null)\" = Mains ] && cat \"$d/online\"; done; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "") return;
                root.setPlug(t.indexOf("1") >= 0 ? 1 : 0);
            }
        }
        onExited: {
            if (root.mainsDirty) { root.mainsDirty = false; mains.running = true; }
        }
    }

    Process {
        id: udev
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=power_supply"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("power_supply") >= 0 && line.indexOf("change") >= 0) readTimer.restart();
            }
        }
    }

    // ---- history file ----
    property var pending: []

    function persist(line) {
        root.pending = root.pending.concat([line]);
        kickAppend();
    }

    function kickAppend() {
        if (appender.running || root.pending.length === 0) return;
        const p = root.pending.slice();
        const l = p.shift();
        root.pending = p;
        appender.command = ["bash", "-c", "printf '%s\\n' \"$1\" >> \"$HOME/.local/state/viii/notifs.jsonl\"", "_", l];
        appender.running = true;
    }

    Process { id: appender; onExited: root.kickAppend() }

    Process {
        id: clearProc
        command: ["bash", "-c", ": > \"$HOME/.local/state/viii/notifs.jsonl\""]
    }

    // at startup: keep only the last 100 lines on disk, then load them
    Process {
        id: trimmer
        running: true
        command: ["bash", "-c", "f=\"$HOME/.local/state/viii/notifs.jsonl\"; mkdir -p \"$(dirname \"$f\")\"; if [ -f \"$f\" ]; then tail -n 100 \"$f\" > \"$f.tmp\" && mv \"$f.tmp\" \"$f\"; fi; true"]
        onExited: loader.path = root.file
    }

    FileView {
        id: loader
        onLoaded: {
            const lines = text().split("\n");
            const have = {};
            for (let i = 0; i < root.history.length; i++) have[root.history[i].id] = true;
            const old = [];
            for (let i = lines.length - 1; i >= 0 && old.length < root.maxHistory; i--) {
                if (lines[i].length === 0) continue;
                try {
                    const e = JSON.parse(lines[i]);
                    if (!have[e.id]) old.push(e);
                } catch (err) {}
            }
            root.history = root.history.concat(old).slice(0, root.maxHistory);
        }
    }

    Component.onCompleted: readMains()
}
