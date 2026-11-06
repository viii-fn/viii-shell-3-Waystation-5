pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpapers: the list in the configured folder (the project's assets/ until the user picks another
// one in Settings), the current one, and "apply" (= viii-theme <file>, which re-themes the whole UI
// from it). The wallpaper itself is drawn by wall/WallpaperLayer.qml.
// No Behavior in here (Qt 6.12 singleton crash).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // assets/ lives next to quickshell/ in the project. Resolve it once (below) so the `..` in
    // ~/.config/quickshell/viii/../assets cannot be folded the wrong way by a path normaliser.
    property string defaultDir: Quickshell.shellDir + "/../assets"
    property string customDir: ""            // persisted in ~/.config/viii/wallpaper-dir; "" = default
    readonly property string dir: customDir !== "" ? customDir : defaultDir
    property var files: []
    property string current: ""
    property bool busy: false
    property bool scanned: false
    property bool scanFailed: false
    property string error: ""
    property var added: ({})              // viii-psstore: path -> modification time in seconds (the Wallstore's "New")

    function src(p) { return p ? "file://" + encodeURI(p) : ""; }
    function name(p) {
        if (!p) return "none";
        const b = p.split("/").pop();
        const i = b.lastIndexOf(".");
        return i > 0 ? b.slice(0, i) : b;
    }
    function prettyDir(p) {
        if (!p) return "";
        if (p === home) return "~";
        if (p.indexOf(home + "/") === 0) return "~" + p.slice(home.length);
        return p;
    }
    function expandDir(p) {
        let d = String(p || "").trim();
        if (d === "~") d = home;
        else if (d.indexOf("~/") === 0) d = home + d.slice(1);
        return d;
    }
    // "" restores the default (the project's assets/ folder).
    function setDir(p) {
        const d = expandDir(p);
        customDir = d;
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/viii\" && printf '%s\\n' \"$1\" > \"$HOME/.config/viii/wallpaper-dir\"",
            "sh", d]);
        scanned = false;
        scanFailed = false;
        refresh();
    }
    function refresh() { if (!lister.running) { scanFailed = false; lister.running = true; } }
    function apply(path) {
        if (busy || !path) return;
        busy = true;
        error = "";
        setter.command = [home + "/.local/bin/viii-theme", path];
        setter.running = true;
    }

    Process {
        id: lister
        onExited: (code, status) => { root.scanned = true; if (code !== 0 && root.files.length === 0) root.scanFailed = true; }
        command: ["find", root.dir, "-maxdepth", "2", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")", "-printf", "%T@ %p\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                // viii-psstore: each line is "<mtime> <path>"
                const l = [];
                const added = {};
                const rows = this.text.split("\n");
                for (let i = 0; i < rows.length; i++) {
                    const r = rows[i];
                    const k = r.indexOf(" ");
                    if (k <= 0) continue;
                    const p = r.slice(k + 1);
                    if (p.length === 0) continue;
                    added[p] = Number(r.slice(0, k)) || 0;
                    l.push(p);
                }
                root.added = added;
                l.sort((a, b) => a.localeCompare(b));
                root.files = l;
                root.scanned = true;
                if (l.length > 0) root.scanFailed = false;
            }
        }
    }

    Process {
        id: setter
        onExited: (code, status) => {
            root.busy = false;
            if (code !== 0) root.error = "Couldn\u2019t apply that wallpaper (viii-theme exit " + code + ")";
        }
    }

    // The folder chosen in Settings (one line). Missing or empty = the default assets/ folder.
    FileView {
        path: root.home + "/.config/viii/wallpaper-dir"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.customDir = text().trim()
    }

    // Canonical path of the default folder, so the UI shows a clean path even though the shell
    // runs from the ~/.config/quickshell/viii symlink.
    Process {
        id: canon
        command: ["readlink", "-f", Quickshell.shellDir + "/../assets"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim();
                if (p !== "") root.defaultDir = p;
            }
        }
    }

    onDirChanged: {
        root.files = [];
        root.scanned = false;
        root.scanFailed = false;
        if (lister.running) lister.running = false;
        restart.start();
    }
    Timer { id: restart; interval: 0; onTriggered: root.refresh() }

    FileView {
        path: root.home + "/.local/state/viii/wallpaper"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.current = text().trim()
    }

    // wallpapers you applied, most recent first (written by bin/viii-theme)
    property var history: []
    FileView {
        path: root.home + "/.local/state/viii/wallpaper-history"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.history = text().split("\n").filter(s => s.length > 0)
    }

    // "Top wallpapers": the history, then the rest of the folder, so the row is never empty
    readonly property var recent: {
        const out = [];
        const seen = {};
        for (let i = 0; i < history.length && out.length < 12; i++) {
            const p = history[i];
            if (!seen[p] && (!scanned || files.indexOf(p) >= 0)) { seen[p] = true; out.push(p); }
        }
        if (current && !seen[current] && out.length < 12 && (!scanned || files.indexOf(current) >= 0)) { seen[current] = true; out.unshift(current); }
        for (let i = 0; i < files.length && out.length < 12; i++) {
            if (!seen[files[i]]) { seen[files[i]] = true; out.push(files[i]); }
        }
        return out;
    }

    Component.onCompleted: { canon.running = true; refresh(); }
}
