pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpapers: the list in ~/Pictures/Wallpapers, the current one, and "apply" (= viii-theme <file>,
// which re-themes the whole UI from it). The wallpaper itself is drawn by wall/WallpaperLayer.qml.
// No Behavior in here (Qt 6.12 singleton crash).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/Pictures/Wallpapers"
    property var files: []
    property string current: ""
    property bool busy: false

    function src(p) { return p ? "file://" + encodeURI(p) : ""; }
    function name(p) {
        if (!p) return "none";
        const b = p.split("/").pop();
        const i = b.lastIndexOf(".");
        return i > 0 ? b.slice(0, i) : b;
    }
    function refresh() { if (!lister.running) lister.running = true; }
    function apply(path) {
        if (busy || !path) return;
        busy = true;
        setter.command = [home + "/.local/bin/viii-theme", path];
        setter.running = true;
    }

    Process {
        id: lister
        command: ["find", root.dir, "-maxdepth", "2", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = this.text.split("\n").filter(s => s.length > 0);
                l.sort((a, b) => a.localeCompare(b));
                root.files = l;
            }
        }
    }

    Process {
        id: setter
        onExited: root.busy = false
    }

    FileView {
        path: root.home + "/.local/state/viii/wallpaper"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.current = text().trim()
    }

    Component.onCompleted: refresh()
}
