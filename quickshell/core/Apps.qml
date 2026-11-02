pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The app list plus one matugen palette per app.
// Palettes come from bin/viii-palette (icon -> matugen -> cached JSON). Until one arrives,
// a colour derived from the app's name is used, so tiles are never grey.
Singleton {
    id: root

    property var palettes: ({})     // safeKey -> { primary, onPrimary, primaryContainer, surface }
    property var failed: ({})
    property var queue: []
    property string busyKey: ""

    function safeKey(entry) { return String(entry.id || entry.name).toLowerCase().replace(/[^a-z0-9._-]/g, "_"); }

    function visible() { return DesktopEntries.applications.values.filter(e => !e.noDisplay); }

    function alphabetical() { return visible().sort((a, b) => a.name.localeCompare(b.name)); }

    // Most used (last 7 days) first, then A-Z. Taken as a snapshot when the hub opens,
    // so the row never reshuffles under your fingers.
    function ranked(n) {
        const list = visible().map(e => ({ e: e, s: ScreenTime.sum(e, 7) }));
        list.sort((a, b) => (b.s - a.s) || a.e.name.localeCompare(b.e.name));
        return list.slice(0, n).map(x => x.e);
    }

    function iconPath(entry) {
        const name = entry.icon || "application-x-executable";
        if (name.charAt(0) === "/") return name;
        const p = Quickshell.iconPath(name, true);
        return p !== "" ? p : Quickshell.iconPath("application-x-executable", true);
    }

    function fallback(key) {
        // plain black and white until (or unless) a real palette arrives; it used to be a hue made up from the app name
        return {
            primary: "#f2f2f2",
            onPrimary: "#161616",
            primaryContainer: "#2c2c2c",
            surface: "#0f0f0f"
        };
    }

    function paletteFor(entry) {
        if (entry.isWall === true) return Theme.wp || fallback("wall");
        if (entry.isLibrary === true) return fallback("library");
        const k = safeKey(entry);
        return palettes[k] || fallback(k);
    }

    // Ask for a palette (queued, one matugen run at a time, low priority).
    function request(entry) {
        if (entry.isLibrary === true || entry.isWall === true) return;
        const k = safeKey(entry);
        if (palettes[k] || failed[k] || busyKey === k) return;
        if (!queue.some(q => q.key === k)) queue.push({ key: k, icon: iconPath(entry) });
        pump();
    }

    function pump() {
        if (queue.length === 0) return;
        if (proc.running || busyKey !== "") { pumpTimer.restart(); return; }
        const job = queue.shift();
        if (!job.icon) { failed[job.key] = true; Qt.callLater(pump); return; }
        busyKey = job.key;
        proc.command = ["nice", "-n", "19", Quickshell.env("HOME") + "/.local/bin/viii-palette", job.icon, job.key];
        proc.running = true;
    }

    function done(text) {
        const p = parse(text);
        if (p) {
            const next = Object.assign({}, palettes);
            next[busyKey] = p;
            palettes = next;
        } else {
            console.warn("[viii] palette failed for", busyKey, "output:", String(text).slice(0, 160));
            failed[busyKey] = true;
        }
        busyKey = "";
        pumpTimer.restart();
    }

    // Reads matugen's JSON whatever the exact layout is:
    //   colors.primary.{dark|default}   or   colors.dark.primary
    function parse(text) {
        const a = text.indexOf("{"), b = text.lastIndexOf("}");
        if (a < 0 || b < a) return null;
        let j;
        try { j = JSON.parse(text.slice(a, b + 1)); } catch (e) { return null; }
        const c = j.colors || j;
        const str = x => typeof x === "string" ? x : ((x && (x.color || x.hex)) || null);
        const val = name => {
            const v = c[name];
            if (v !== undefined && v !== null) {
                if (typeof v === "string") return v;
                if (v.dark !== undefined) return str(v.dark);
                if (v.default !== undefined) return str(v.default);
            }
            if (c.dark && c.dark[name] !== undefined) return str(c.dark[name]);
            if (c.default && c.default[name] !== undefined) return str(c.default[name]);
            return null;
        };
        const fix = s => s ? (s.charAt(0) === "#" ? s : "#" + s) : null;
        const p = {
            primary: fix(val("primary")),
            onPrimary: fix(val("on_primary")),
            primaryContainer: fix(val("primary_container")),
            surface: fix(val("surface"))
        };
        return (p.primary && p.onPrimary && p.primaryContainer && p.surface) ? p : null;
    }

    // the output of one job can finish a moment before its process exits: retry until the process is gone
    Timer {
        id: pumpTimer
        interval: 60
        onTriggered: root.pump()
    }

    // Palettes that are already on disk are read once, in a single process, so opening the hub never launches
    // viii-palette for an app it has seen before. (Cache files are named <key>.json; dotfiles are skipped.)
    Process {
        id: cacheLoad
        running: true
        command: ["sh", "-c", 'cd "$HOME/.cache/viii/palettes" 2>/dev/null || exit 0; for f in *.json; do [ -s "$f" ] || continue; printf "%s\\t" "${f%.json}"; tr -d "\\n" < "$f"; echo; done']
        stdout: StdioCollector { onStreamFinished: root.cacheLoaded(this.text) }
    }

    function cacheLoaded(text) {
        const loaded = {};
        const lines = String(text).split("\n");
        for (let i = 0; i < lines.length; i++) {
            const tab = lines[i].indexOf("\t");
            if (tab <= 0) continue;
            const p = parse(lines[i].slice(tab + 1));
            if (p) loaded[lines[i].slice(0, tab)] = p;
        }
        palettes = Object.assign({}, loaded, palettes);    // anything fresher already in memory wins
    }

    Process {
        id: proc
        stdout: StdioCollector { onStreamFinished: root.done(this.text) }
    }
}
