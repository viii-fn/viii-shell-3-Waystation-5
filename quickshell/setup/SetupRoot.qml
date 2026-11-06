import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../core"

// viii first-run setup: the state, the helper processes and the finish logic. The screens only draw it.
//
//   step 0  keyboard      (Super key to continue)
//   step 1  language      (picks the keyboard layout through viii-kb)
//   step 2  display       (read-only: resolution and HDR support, through viii-display)
//   step 3  user agreement
//   step 4  system software (viii-deps installs the dependencies; optional full update)
//
// Finishing writes ~/.local/state/viii/setup-done and quits this instance. Nothing here runs again after that.
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: home + "/.local/bin/"

    // ------------------------------------------------------------------ flow
    readonly property int stepCount: 5
    property int step: 0
    property bool closing: false
    property string mainScreen: ""          // the setup draws on one monitor (the focused one); the others just get the backdrop

    function next() { if (step < stepCount - 1) step += 1; }
    function prev() { if (step > 0) step -= 1; }

    function finish() {
        if (closing) return;
        pw = "";
        closing = true;
        flagProc.running = true;
        quitTimer.start();
    }
    Process {
        id: flagProc
        command: ["sh", "-c", "mkdir -p ~/.local/state/viii && date -u +%FT%TZ > ~/.local/state/viii/setup-done"]
    }
    Timer { id: quitTimer; interval: 700; onTriggered: Qt.quit() }

    onStepChanged: {
        if (step === 0) refreshKeyboards();
        if (step === 2 && !dispProc.running) { displaysLoaded = false; dispProc.running = true; }
        if (step === 4) updateEnter();
    }

    Component.onCompleted: {
        const screens = Quickshell.screens;
        const fm = Hyprland.focusedMonitor;
        let pick = screens.length > 0 ? screens[0].name : "";
        if (fm) {
            for (let i = 0; i < screens.length; i++) if (screens[i].name === fm.name) pick = fm.name;
        }
        mainScreen = pick;
        refreshKeyboards();
        kbGet.running = true;
    }

    // ------------------------------------------------------------------ step 0: keyboards
    property var keyboards: []
    function refreshKeyboards() { if (!kbList.running) kbList.running = true; }
    Process {
        id: kbList
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = [];
                try {
                    const ks = JSON.parse(this.text).keyboards || [];
                    for (let i = 0; i < ks.length; i++) {
                        const n = String(ks[i].name || "");
                        if (n === "" || /(power|sleep|lid|video|button|virtual|consumer|control|hotkey|wmi)/i.test(n)) continue;
                        if (ks[i].main) names.unshift(n); else names.push(n);
                    }
                } catch (e) {}
                root.keyboards = names;
            }
        }
    }
    // plug in or pair a keyboard while this screen is up and it shows
    Timer {
        interval: 2000
        repeat: true
        running: root.step === 0 && !root.closing
        onTriggered: root.refreshKeyboards()
    }

    // ------------------------------------------------------------------ step 1: language = keyboard layout
    // The same list as Settings > System > Language (settings/SettingsPage.qml, kbLayouts).
    readonly property var kbLayouts: [
        { code: "gb", name: "English (United Kingdom)" }, { code: "us", name: "English (United States)" },
        { code: "ng", name: "English (Nigeria)" }, { code: "fr", name: "French" },
        { code: "de", name: "German" }, { code: "es", name: "Spanish" },
        { code: "pt", name: "Portuguese" }, { code: "br", name: "Portuguese (Brazil)" },
        { code: "it", name: "Italian" }, { code: "ru", name: "Russian" }
    ]
    property string kbCode: ""
    property string kbPending: ""
    property string kbStatus: ""
    property string kbStatusKind: "info"
    function kbName(code) {
        for (let i = 0; i < kbLayouts.length; i++) if (kbLayouts[i].code === code) return kbLayouts[i].name;
        return code;
    }
    function setKeyboard(code) {
        if (kbSet.running || code === "") return;
        kbPending = code;
        kbStatus = "Switching keyboard layout…";
        kbStatusKind = "loading";
        kbSet.command = [bin + "viii-kb", code];
        kbSet.running = true;
    }
    Process {
        id: kbGet
        command: [root.bin + "viii-kb", "--get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const c = String(this.text).trim().split(",")[0];
                if (c !== "" && root.kbCode === "") root.kbCode = c;
            }
        }
    }
    Process {
        id: kbSet
        stdout: StdioCollector { onStreamFinished: console.log("[viii-setup] viii-kb:", String(this.text).trim()) }
        onExited: (code, status) => {
            if (code === 0) {
                root.kbCode = root.kbPending;
                root.kbStatus = "Keyboard layout: " + root.kbName(root.kbPending);
                root.kbStatusKind = "success";
            } else {
                root.kbStatus = "Couldn\u2019t switch the keyboard layout (see: viii log setup)";
                root.kbStatusKind = "error";
            }
            root.kbPending = "";
        }
    }

    // ------------------------------------------------------------------ step 2: displays (read-only)
    property var displays: []
    property bool displaysLoaded: false
    Process {
        id: dispProc
        command: [root.bin + "viii-display"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(this.text); } catch (e) { list = []; }
                root.displays = Array.isArray(list) ? list : [];
                root.displaysLoaded = true;
            }
        }
    }

    // ------------------------------------------------------------------ step 4: system software
    // updPhase: idle | check | auth | install | ask | full | finish | unsupported | error
    property string updPhase: "idle"
    property string family: ""
    property string pretty: ""
    property string authMode: ""            // root | no | yes | nosudo
    property string pw: ""                  // kept in memory only, cleared by finish(); passed to viii-deps through the environment
    property string authError: ""
    property var pkgs: []                   // [{ id, label, state, note }]
    property real progress: 0
    property bool indeterminate: false
    property string phaseText: ""
    property var logLines: []
    property bool fullRan: false
    property int missingCount: 0
    property string resultText: ""

    function addLog(s) {
        const l = logLines.slice(-199);
        l.push(String(s));
        logLines = l;
    }

    function updateEnter() {
        if (updPhase !== "idle") return;
        updPhase = "check";
        infoProc.running = true;
    }

    function retry() {
        updPhase = "idle";
        pkgs = [];
        progress = 0;
        indeterminate = false;
        updateEnter();
    }

    function submitPassword(p) {
        if (p === "") return;
        pw = p;
        authError = "";
        startInstall();
    }

    function skipInstall() {
        resultText = "Skipped. Waystation may be missing some programs it needs.";
        updPhase = "finish";
    }

    function startInstall() {
        pkgs = [];
        progress = 0;
        indeterminate = false;
        phaseText = "Checking your system";
        updPhase = "install";
        runDeps(["--install"]);
    }

    function startFullUpdate() {
        fullRan = true;
        progress = 0;
        indeterminate = true;
        phaseText = "Updating your system";
        updPhase = "full";
        runDeps(["--full-update"]);
    }

    function runDeps(args) {
        if (depProc.running) return;
        depProc.command = [bin + "viii-deps"].concat(args);
        depProc.running = true;
    }

    Process {
        id: infoProc
        command: [root.bin + "viii-deps", "--info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                const lines = String(this.text).split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const j = lines[i].indexOf("=");
                    if (j > 0) kv[lines[i].slice(0, j)] = lines[i].slice(j + 1).trim();
                }
                root.family = kv.family || "unknown";
                root.pretty = kv.pretty || "";
                root.authMode = kv.auth || "";
                if (root.family === "unknown") {
                    root.resultText = "Automatic installation supports Arch, Fedora and Debian-based systems.";
                    root.updPhase = "unsupported";
                } else if (root.authMode === "nosudo") {
                    root.resultText = "sudo is not installed and you are not root, so Waystation can\u2019t install packages for you.";
                    root.updPhase = "unsupported";
                } else if (root.authMode === "yes") {
                    root.updPhase = "auth";
                } else {
                    root.startInstall();
                }
            }
        }
        onExited: (code, status) => {
            // viii-deps itself could not run (not installed): carry on without it
            if (code !== 0 && root.updPhase === "check") {
                root.resultText = "The installer helper (viii-deps) could not run. Re-run install.sh.";
                root.updPhase = "error";
            }
        }
    }

    // safety net: if viii-deps never answers, do not sit on "Checking your system" forever
    Timer {
        interval: 20000
        running: root.updPhase === "check"
        onTriggered: {
            if (root.updPhase !== "check") return;
            root.resultText = "The installer helper (viii-deps) did not answer. Re-run install.sh, then: viii setup reset";
            root.updPhase = "error";
        }
    }

    Process {
        id: depProc
        environment: ({ "VIII_PW": root.pw })
        stdout: SplitParser { onRead: line => root.onDepLine(line) }
        onExited: (code, status) => root.onDepExit(code)
    }

    function onDepLine(line) {
        const t = String(line);
        if (t.charAt(0) !== "@") { if (t.trim() !== "") addLog(t); return; }
        const sp = t.indexOf(" ");
        const tag = sp > 0 ? t.slice(1, sp) : t.slice(1);
        const arg = sp > 0 ? t.slice(sp + 1) : "";
        if (tag === "plan" || tag === "pkg") {
            const f = arg.split("|");
            const list = pkgs.slice();
            let at = -1;
            for (let i = 0; i < list.length; i++) if (list[i].id === f[0]) { at = i; break; }
            if (tag === "plan") {
                const e = { id: f[0], label: f[1] || f[0], state: f[2] || "pending", note: "" };
                if (at >= 0) list[at] = e; else list.push(e);
            } else if (at >= 0) {
                list[at] = { id: list[at].id, label: list[at].label, state: f[1] || "", note: f[2] || "" };
            }
            pkgs = list;
        } else if (tag === "progress") {
            const v = parseFloat(arg);
            if (v < 0) indeterminate = true;
            else { indeterminate = false; progress = Math.max(0, Math.min(1, v)); }
        } else if (tag === "phase") {
            phaseText = arg;
        } else if (tag === "msg") {
            addLog(arg);
        } else if (tag === "auth") {
            authError = arg === "fail" ? "Incorrect password" : "";
        }
    }

    function onDepExit(code) {
        indeterminate = false;
        if (code === 77) { pw = ""; authError = "Incorrect password"; updPhase = "auth"; return; }
        if (code === 78) { updPhase = "auth"; return; }
        if (code === 3) { resultText = "Automatic installation isn\u2019t available on this system."; updPhase = "unsupported"; return; }
        let missing = 0;
        for (let i = 0; i < pkgs.length; i++) if (pkgs[i].state === "missing" || pkgs[i].state === "failed") missing += 1;
        missingCount = missing;
        if (updPhase === "install") {
            progress = 1;
            if (code !== 0 && code !== 10) { resultText = "The installer stopped unexpectedly (exit code " + code + ")."; updPhase = "error"; return; }
            updPhase = "ask";
        } else if (updPhase === "full") {
            progress = 1;
            if (code === 20) { resultText = "The full update did not finish. You can run it later from a terminal."; }
            else resultText = missing > 0 ? "Updated. A few optional or unavailable packages are still missing." : "Your system is up to date.";
            updPhase = "finish";
        }
    }

    // ------------------------------------------------------------------ one window per monitor
    Variants {
        model: Quickshell.screens
        SetupWindow {
            required property var modelData
            screen: modelData
            ctl: root
        }
    }
}
