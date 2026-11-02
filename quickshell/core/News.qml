pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// viii-explore: today's Linux + PlayStation news, read from ~/.cache/viii/news/news.json (written by
// ~/.local/bin/viii-news, at most once per calendar day). Only reads the small json; pictures are loaded
// by the Explore page and only while it is on screen. No Behavior in here (Qt 6.12 singleton crash).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property var items: []
    property string day: ""
    property bool loaded: false
    property bool busy: false
    property bool failed: false
    property double lastTry: 0

    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }
    function stale() { return day !== today(); }
    function src(p) { return p ? "file://" + encodeURI(p) : ""; }

    // run the fetcher (it does nothing if today's news is already cached); at most once per 10 minutes
    function refresh() {
        if (busy || fetcher.running) return;
        const now = Date.now();
        if (now - lastTry < 600000) return;
        lastTry = now;
        busy = true;
        failed = false;
        fetcher.running = true;
    }

    function host(link) {
        const p = String(link || "").split("/");
        return p.length > 2 ? p[2].replace("www.", "") : "";
    }

    function ago(ts) {
        if (!ts) return "";
        const d = new Date(ts * 1000);
        const n = new Date();
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const b = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime();
        const days = Math.round((b - a) / 86400000);
        if (days <= 0) return "Today";
        if (days === 1) return "Yesterday";
        if (days < 7) return days + " days ago";
        return Qt.formatDate(d, "d MMM");
    }

    FileView {
        id: cache
        path: root.home + "/.cache/viii/news/news.json"
        printErrors: false
        onLoaded: {
            let list = [];
            let d = "";
            try {
                const j = JSON.parse(cache.text());
                d = String(j.day || j.date || "");
                const raw = j.items || [];
                for (let i = 0; i < raw.length; i++) {
                    const it = raw[i];
                    if (it && it.title && it.img && String(it.link).indexOf("http") === 0) list.push(it);
                }
            } catch (e) {
                list = [];
            }
            root.items = list;
            root.day = d;
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    Process {
        id: fetcher
        command: ["nice", "-n", "19", root.home + "/.local/bin/viii-news"]
        onExited: (code, status) => {
            root.busy = false;
            if (code === 0) cache.reload();
            else root.failed = true;
        }
    }
}
