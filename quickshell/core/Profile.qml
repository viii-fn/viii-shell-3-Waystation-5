pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// viii-ps5-settings: the user's profile (name + round avatar). Plain state only, no Behavior here.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    property string name: ""
    property string pic: ""      // round avatar png made by Settings ("" = none)
    property string src: ""      // original picture that was chosen
    readonly property string display: name !== "" ? name : (Quickshell.env("USER") || "user")
    readonly property string picUrl: pic !== "" ? "file://" + encodeURI(pic) : ""

    function reload() { reader.running = true; }
    function save(n, p, s) {
        name = n; pic = p; src = s;
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/viii\" && printf '%s' \"$1\" > \"$HOME/.config/viii/profile.json\"",
            "sh", JSON.stringify({ name: n, pic: p, src: s })]);
    }

    Process {
        id: reader
        command: ["sh", "-c", "cat \"$HOME/.config/viii/profile.json\" 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(this.text);
                    root.name = o.name || "";
                    root.pic = o.pic || "";
                    root.src = o.src || "";
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: reload()
}
