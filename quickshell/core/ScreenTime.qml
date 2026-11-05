pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Screen time per app (the "trophies" of this shell).
// Counts the seconds each window class is focused and stores them per day in
// ~/.local/state/viii/screentime.json. Nothing runs between events except one 30s timer.
Singleton {
    id: root

    property var days: ({})        // { "2026-10-30": { "firefox": 1234, ... } }
    property int revision: 0       // bumps on change so bindings re-evaluate
    property string current: ""    // window class that has focus right now
    property double since: 0       // when it got focus (ms)
    property bool dirty: false

    readonly property string file: Quickshell.env("HOME") + "/.local/state/viii/screentime.json"

    function dayKey(offset) {
        const n = new Date();
        return Qt.formatDate(new Date(n.getFullYear(), n.getMonth(), n.getDate() - offset), "yyyy-MM-dd");
    }

    // Give the current app the time since the last credit.
    function credit() {
        const now = Date.now();
        if (current !== "" && since > 0) {
            // cap at 2 minutes so a suspend/resume never credits hours
            const secs = Math.min((now - since) / 1000, 120);
            if (secs > 0) {
                const key = dayKey(0);
                const rec = days[key] || (days[key] = {});
                rec[current] = (rec[current] || 0) + secs;
                dirty = true;
                revision++;
            }
        }
        since = now;
    }

    function save() {
        if (!dirty) return;
        dirty = false;
        // keep 30 days
        const keep = {};
        for (let i = 0; i < 30; i++) {
            const k = dayKey(i);
            if (days[k]) keep[k] = days[k];
        }
        days = keep;
        store.setText(JSON.stringify(keep));
    }

    // Names an app can go by: StartupWMClass, desktop id, name (lower-cased).
    function keysFor(entry) {
        const out = [];
        const add = s => {
            if (!s) return;
            s = String(s).toLowerCase().replace(/\.desktop$/, "");
            if (out.indexOf(s) < 0) out.push(s);
        };
        add(entry.startupClass);
        add(entry.id);
        add(entry.name);
        return out;
    }

    // Seconds used over the last nDays days (1 = today).
    function sum(entry, nDays) {
        void revision;
        const keys = keysFor(entry);
        let total = 0;
        for (let i = 0; i < nDays; i++) {
            const rec = days[dayKey(i)];
            if (!rec) continue;
            for (let k = 0; k < keys.length; k++) total += rec[keys[k]] || 0;
        }
        return total;
    }

    function fmt(s) {
        if (s < 60) return "\u2014";
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    FileView {
        id: store
        path: root.file
        printErrors: false
        onLoaded: {
            try { root.days = JSON.parse(store.text()); root.revision++; } catch (e) {}
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activewindow") return;
            root.credit();
            root.current = String(event.data).split(",")[0].toLowerCase();
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: { root.credit(); root.save(); }
    }
}
