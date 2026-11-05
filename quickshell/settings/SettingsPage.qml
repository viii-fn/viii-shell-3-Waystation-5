import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Networking
import "../core"
import "../hub"
// viii-ps5-settings

// PS5-inspired settings surface.
//
// Two layers share the same focus:
//   * pane 0: every category as one row of a centred vertical list;
//   * pane 1: the reusable SettingsMenu (30% item list / 70% control) for the chosen category.
// The transition between them is a fade + zoom. The wallpaper is never covered by a scrim:
// Hub.qml keeps Backdrop.wallpaper on while settings is open, so the current wallpaper is
// always the background and all colour comes from the wallpaper's Matugen palette.
//
// Motion / performance rules used throughout this file:
//  * only opacity, x/y, scale, rotation and colour are animated (no layout-driven size animation);
//  * no layer.enabled, no shader effects, no blur: nothing here allocates an offscreen buffer;
//  * one opacity at the root instead of several stacked multiplications;
//  * the row Repeater is keyed on a COUNT, so live Wi-Fi / Bluetooth updates change text in
//    place instead of destroying and rebuilding every row (no flicker, no GC churn);
//  * brightness / volume writes are coalesced so dragging never spawns a process per mouse event;
//  * infinite animations run only while visible, and the spinner runs on the render thread.
FocusScope {
    id: root
    focus: active
    Keys.onPressed: event => root.handleKey(event)

    signal closeRequested()
    signal wallstoreRequested()
    signal libraryRequested()

    property bool active: false
    property real reveal: active ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.active ? 560 : 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.active ? Motion.out : Motion.inOut
        }
    }

    // ---- navigation state ----
    property int categoryIndex: 0        // highlighted category in the grid
    property int rowIndex: 0             // highlighted row inside the open category
    property int pane: 0                 // 0 = category grid, 1 = category page
    property string armed: ""            // destructive action waiting for a second Enter

    // Fade + zoom between the grid and a category page. The Behavior is disabled while the
    // whole settings surface is closing, so a reset never animates behind a fading page.
    property real pageT: pane === 1 ? 1 : 0
    Behavior on pageT {
        enabled: root.active
        NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }

    // ---- slider state (coalesced writes) ----
    property string dragAction: ""
    property real dragFraction: -1
    property real volTarget: -1
    property int briTarget: -1
    property int briSent: -1

    // ---- geometry: a real list, centred horizontally, starting at the top (viii-vlist2) ----
    readonly property real padX: Math.round(width * 0.05)
    readonly property real innerW: width - 2 * padX
    readonly property real listW: Math.min(920, innerW)
    readonly property real listX: Math.round((width - listW) / 2)
    readonly property real rowH: 72
    readonly property real listTop: 142
    readonly property real listBottom: height - 36
    readonly property real viewH: listBottom - listTop
    // The list only scrolls when the highlighted row would leave the visible area.
    // scrollGoal is where it should end up; scrollY and selPos glide there together (same
    // curve and duration) so the ring and the rows never drift apart while moving.
    property real scrollGoal: 0
    property real scrollY: scrollGoal
    property real selPos: categoryIndex
    Behavior on scrollY {
        enabled: root.active
        NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }
    Behavior on selPos {
        enabled: root.active
        NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
    }
    function rowTop(i) { return listTop + i * rowH - scrollY; }
    // rows fade out as they slide under the top edge / past the bottom edge of the list area
    function rowFade(top) {
        return Math.max(0, Math.min(1, (top - listTop + rowH) / rowH, (listBottom - top) / rowH));
    }
    function ensureVisible() {
        const top = categoryIndex * rowH;
        let goal = scrollGoal;
        if (top < goal) goal = top;
        else if (top + rowH > goal + viewH) goal = top + rowH - viewH;
        scrollGoal = Math.max(0, Math.min(Math.max(0, categories.length * rowH - viewH), goal));
    }

    // viii-ps5-settings: categories in the order and with the names of the PS5 Settings.
    readonly property int netIdx: 1
    readonly property int accIdx: 7
    readonly property var categories: [
        { key: "accessibility", title: "Accessibility", icon: "\uf29a" },
        { key: "network", title: "Network", icon: "\uf1eb" },
        { key: "users", title: "Users and Accounts", icon: "\uf007" },
        { key: "system", title: "System", icon: "\uf013" },
        { key: "storage", title: "Storage", icon: "\uf0a0" },
        { key: "sound", title: "Sound", icon: "\uf028" },
        { key: "screen", title: "Screen and Video", icon: "\uf108" },
        { key: "accessories", title: "Accessories", icon: "\uf11b" },
        { key: "notifications", title: "Notifications", icon: "\uf0f3" },
        { key: "captures", title: "Captures and Broadcasts", icon: "\uf030" }
    ]
    readonly property var kbLayouts: [
        { code: "gb", name: "English (United Kingdom)" }, { code: "us", name: "English (United States)" },
        { code: "ng", name: "English (Nigeria)" }, { code: "fr", name: "French" },
        { code: "de", name: "German" }, { code: "es", name: "Spanish" },
        { code: "pt", name: "Portuguese" }, { code: "br", name: "Portuguese (Brazil)" },
        { code: "it", name: "Italian" }, { code: "ru", name: "Russian" }
    ]

    property int itemIndex: 0            // highlighted sub-menu in the left list
    property bool inPane: false          // focus is on the right pane
    onItemIndexChanged: { rowIndex = 0; armed = ""; }
    property string promptKind: "wifi"   // what the text dialog is for: "wifi" or "name"
    property string kbLayout: "gb"
    property bool reduceMotion: false
    property string ipText: ""
    property string sysOs: ""
    property string sysKernel: ""
    property string sysHypr: ""
    property string sysQs: ""
    property string sysMatugen: ""
    property string sysTz: ""
    property string stUsed: ""
    property string stFree: ""
    property string stTotal: ""
    property string stPct: ""
    property string testResult: ""
    property var monitors: []
    property var pfpFiles: []
    property string pfpSrc: ""
    property string pfpOut: ""

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var audioSinks: Pipewire.nodes.values.filter(n => n.isSink && n.audio)
    readonly property var audioSources: Pipewire.nodes.values.filter(n => !n.isSink && n.audio)
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var wifiDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wifi) return devices[i];
        return null;
    }
    readonly property var wiredDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wired && devices[i].connected) return devices[i];
        return null;
    }
    readonly property var wifiNetworks: wifiDevice && wifiDevice.networks
        ? wifiDevice.networks.values : []
    readonly property var btDevices: adapter && adapter.devices
        ? adapter.devices.values : []
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property string wifiName: {
        for (let i = 0; i < wifiNetworks.length; i++)
            if (wifiNetworks[i].connected) return wifiNetworks[i].name;
        return "";
    }
    readonly property bool wifiConnected: wifiName.length > 0
    property string storageText: "Checking storage…"
    property string kernelText: "Checking kernel…"
    property string statusText: ""
    property string statusKind: "info"
    property string statusShown: ""          // last non-empty message, kept while the pill fades out
    property string statusKindShown: "info"
    property bool passwordPrompt: false
    property real promptT: passwordPrompt ? 1 : 0
    property real promptPop: passwordPrompt ? 1 : 0
    Behavior on promptT { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on promptPop { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
    property string wifiPassword: ""
    property var pendingNetwork: null
    property var pendingBluetooth: null
    property bool networkBusy: false

    readonly property var currentCategory: categories[Math.max(0, Math.min(categories.length - 1, categoryIndex))]
    readonly property var currentItems: itemsFor(categoryIndex)
    readonly property var currentRows: {
        const it = currentItems[Math.max(0, Math.min(currentItems.length - 1, itemIndex))];
        return it ? it.rows : [];
    }
    onCurrentRowsChanged: rowIndex = Math.max(0, Math.min(rowIndex, currentRows.length - 1))

    readonly property real volumeShown: {
        if (dragAction === "volume" && dragFraction >= 0) return dragFraction;
        if (volTarget >= 0) return volTarget;
        return sink && sink.audio ? Math.max(0, Math.min(1, sink.audio.volume)) : 0;
    }
    readonly property real brightnessShown: briTarget >= 0 ? briTarget / 100
        : (Desk.brightness >= 0 ? Desk.brightness / 100 : 0)

    PwObjectTracker { objects: [root.sink, root.source].filter(n => n !== null) }

    // ---- timers ----
    Timer {
        id: statusTimer
        interval: 4200
        onTriggered: if (root.statusKind !== "loading") root.statusText = ""
    }
    Timer {
        id: connectionTimer
        interval: 15000
        onTriggered: {
            if (root.networkBusy) {
                root.networkBusy = false;
                root.setStatus("Connection timed out · check the network and try again", "error");
            }
        }
    }
    Timer {
        id: bluetoothTimer
        interval: 15000
        onTriggered: {
            if (root.statusKind === "loading")
                root.setStatus("Bluetooth operation timed out · check the accessory", "error");
        }
    }
    Timer { id: armTimer; interval: 3500; onTriggered: root.armed = "" }
    Timer { id: scanTimer; interval: 8000; onTriggered: {
        if (root.wifiDevice) root.wifiDevice.scannerEnabled = false;
        if (root.statusKind === "loading") root.setStatus("Network scan finished", "success");
    } }

    // Coalesced hardware writes: at most one brightness process / volume write per interval,
    // always ending on the final value.
    Timer { id: briFlush; interval: 70; onTriggered: root.flushBrightness() }
    Timer { id: briIdle; interval: 700; onTriggered: { root.flushBrightness(); root.briTarget = -1; root.briSent = -1; } }
    Timer { id: volFlush; interval: 40; onTriggered: root.commitVolume() }
    Timer { id: volIdle; interval: 600; onTriggered: { root.commitVolume(); root.volTarget = -1; } }

    component SettingsText: Text {
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 16
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    function rowsOr(list, message) {
        return list.length > 0 ? list : [{ title: message, action: "none", kind: "info" }];
    }
    function baseName(p) { const s = String(p).split("/"); return s[s.length - 1]; }

    // Every category is a list of sub-menus; every sub-menu is a list of rows for the right pane.
    // row kinds: info (value only) · action (Enter) · toggle · slider · choice (check mark)
    function itemsFor(ci) {
        const key = categories[Math.max(0, Math.min(categories.length - 1, ci))].key;
        switch (key) {
        case "accessibility": return [
            { title: "Display and Sound", rows: [
                { title: "Reduce Motion", desc: "Turn off window animations until Hyprland restarts.", action: "reduce-motion", kind: "toggle" } ] } ];
        case "network": {
            const nets = [];
            for (let i = 0; i < Math.min(12, wifiNetworks.length); i++) {
                const n = wifiNetworks[i];
                nets.push({ title: n.name, desc: (n.known ? "Saved  ·  " : "") + Math.round(n.signalStrength * 100) + "% signal",
                            action: "wifi-network:" + i, kind: "action" });
            }
            return [
                { title: "Connection Status", rows: [
                    { title: "Status", action: "net-status", kind: "info" },
                    { title: "Network Name", action: "net-name", kind: "info" },
                    { title: "Signal Strength", action: "net-signal", kind: "info" },
                    { title: "IP Address", action: "net-ip", kind: "info" } ] },
                { title: "Set Up Internet Connection", rows: [
                    { title: "Wi-Fi", desc: "Turn the wireless radio on or off.", action: "wifi", kind: "toggle" },
                    { title: "Scan for Networks", desc: "Look for nearby wireless networks.", action: "wifi-scan", kind: "action" }
                ].concat(nets) },
                { title: "Test Internet Connection", rows: [
                    { title: "Test Internet Connection", desc: "Check that this computer can reach the internet.", action: "net-test", kind: "action" } ] } ];
        }
        case "users": {
            const pics = pfpFiles.map((p, i) => ({ title: baseName(p), action: "pfp:" + i, kind: "choice", thumb: p }));
            return [
                { title: "Account", rows: [
                    { title: "Profile Name", desc: "Shown in the top bar.", action: "profile-name", kind: "action" } ] },
                { title: "Profile Picture", rows: [
                    { title: "Use Initial Only", desc: "Remove the picture and show the first letter of your name.", action: "pfp-clear", kind: "choice" }
                ].concat(pics) },
                { title: "Login Settings", rows: [
                    { title: "Lock Screen", desc: "Lock the session with Hyprlock.", action: "lock", kind: "action" } ] } ];
        }
        case "system": {
            const kb = kbLayouts.map(k => ({ title: k.name, action: "kb:" + k.code, kind: "choice" }));
            return [
                { title: "System Software", rows: [
                    { title: "Operating System", action: "os", kind: "info" },
                    { title: "Kernel", action: "kernel", kind: "info" },
                    { title: "Compositor", action: "hyprland", kind: "info" },
                    { title: "Shell", action: "quickshell", kind: "info" },
                    { title: "Theme Engine", action: "matugen", kind: "info" } ] },
                { title: "Language", rows: kb },
                { title: "Date and Time", rows: [
                    { title: "Time", action: "time", kind: "info" },
                    { title: "Date", action: "date", kind: "info" },
                    { title: "Time Zone", action: "tz", kind: "info" } ] },
                { title: "Power Saving", rows: [
                    { title: "Lock Screen", desc: "Lock the current desktop session.", action: "lock", kind: "action" },
                    { title: "Enter Sleep Mode", desc: "Put the computer to sleep.", action: "suspend", kind: "action" },
                    { title: "Restart", desc: "Restart the computer.", action: "restart", kind: "action" },
                    { title: "Turn Off", desc: "Power off the computer.", action: "poweroff", kind: "action" } ] } ];
        }
        case "storage": return [
            { title: "System Storage", rows: [
                { title: "Used", action: "st-used", kind: "info" },
                { title: "Free", action: "st-free", kind: "info" },
                { title: "Capacity", action: "st-total", kind: "info" },
                { title: "Usage", action: "st-pct", kind: "info" } ] } ];
        case "sound": {
            const outs = audioSinks.map((n, i) => ({ title: n.description || n.name, action: "out:" + i, kind: "choice" }));
            const ins = audioSources.map((n, i) => ({ title: n.description || n.name, action: "in:" + i, kind: "choice" }));
            return [
                { title: "Microphone", rows: [
                    { title: "Mute Microphone", desc: "Stop the default microphone from picking up sound.", action: "mic-mute", kind: "toggle" }
                ].concat(ins) },
                { title: "Audio Output", rows: rowsOr(outs, "No audio output found") },
                { title: "Volume", rows: [
                    { title: "Volume", desc: "Level of the default audio output.", action: "volume", kind: "slider" },
                    { title: "Mute", desc: "Silence the default audio output.", action: "mute", kind: "toggle" } ] } ];
        }
        case "screen": {
            const mons = monitors.map((m, i) => ({ title: m.name, action: "mon:" + i, kind: "info" }));
            return [
                { title: "Screen", rows: [
                    { title: "Brightness", desc: "Backlight of the built-in display.", action: "brightness", kind: "slider" } ] },
                { title: "Video Output", rows: rowsOr(mons, "No display information") },
                { title: "Wallpaper", rows: [
                    { title: "Change Wallpaper", desc: "Browse and apply wallpapers in Wallstore.", action: "wallpaper", kind: "action" },
                    { title: "Current Wallpaper", action: "wallpaper-name", kind: "info" } ] } ];
        }
        case "accessories": {
            const devs = [];
            for (let i = 0; i < Math.min(10, btDevices.length); i++) {
                const d = btDevices[i];
                devs.push({ title: d.name || d.deviceName || "Bluetooth device", desc: d.paired ? "Paired accessory" : "Nearby accessory",
                            action: "bt-device:" + i, kind: "action" });
            }
            return [
                { title: "General", rows: [
                    { title: "Bluetooth", desc: "Turn the Bluetooth adapter on or off.", action: "bluetooth", kind: "toggle" },
                    { title: "Discover Devices", desc: "Look for nearby Bluetooth accessories.", action: "bt-scan", kind: "toggle" }
                ].concat(devs) },
                { title: "Other Accessories", rows: [
                    { title: "Keyboard Layout", action: "keyboard", kind: "info" },
                    { title: "Cursor Theme", action: "cursor", kind: "info" } ] } ];
        }
        case "notifications": return [
            { title: "Pop-up Notifications", rows: [
                { title: "Show Pop-up Notifications", desc: "Display a banner when a notification arrives. Resets when the shell restarts.", action: "popups", kind: "toggle" } ] },
            { title: "Notification History", rows: [
                { title: "View Notification History", action: "history", kind: "action" },
                { title: "Clear History", desc: "Remove every stored notification.", action: "history-clear", kind: "action" } ] } ];
        default: return [
            { title: "Captures", rows: [
                { title: "Create Screenshot", desc: "Select a region, a window or the whole screen.", action: "shot", kind: "action" },
                { title: "Screenshot Folder", action: "shot-dir", kind: "info" } ] } ];
        }
    }

    function valueFor(action) {
        if (action.indexOf("wifi-network:") === 0) {
            const n = wifiNetworks[parseInt(action.split(":")[1])];
            return !n ? "" : (n.connected ? "Connected" : (n.stateChanging ? "Connecting…" : ""));
        }
        if (action.indexOf("bt-device:") === 0) {
            const d = btDevices[parseInt(action.split(":")[1])];
            return !d ? "" : (d.connected ? "Connected" : (d.pairing ? "Pairing…" : ""));
        }
        if (action.indexOf("mon:") === 0) {
            const m = monitors[parseInt(action.split(":")[1])];
            return m ? m.width + "×" + m.height + " @ " + Math.round(m.refreshRate) + " Hz" : "";
        }
        if (action.indexOf("kb:") === 0) return action.slice(3);
        switch (action) {
        case "wifi-scan": return wifiDevice && wifiDevice.scannerEnabled ? "Scanning…" : "";
        case "net-status": return wifiConnected || wiredDevice ? "Connected" : "Not Connected";
        case "net-name": return wifiName || (wiredDevice ? "Ethernet" : "—");
        case "net-signal": {
            for (let i = 0; i < wifiNetworks.length; i++)
                if (wifiNetworks[i].connected) return Math.round(wifiNetworks[i].signalStrength * 100) + "%";
            return "—";
        }
        case "net-ip": return ipText || "—";
        case "net-test": return testResult;
        case "profile-name": return Profile.display;
        case "volume": return sink && sink.audio ? Math.round(volumeShown * 100) + "%" : "Unavailable";
        case "brightness": return Desk.brightness >= 0 ? Math.round(brightnessShown * 100) + "%" : "Unavailable";
        case "os": return sysOs || "…";
        case "kernel": return sysKernel || "…";
        case "hyprland": return sysHypr || "…";
        case "quickshell": return sysQs || "…";
        case "matugen": return sysMatugen || "…";
        case "time": return Qt.formatDateTime(new Date(), "HH:mm");
        case "date": return Qt.formatDate(new Date(), "ddd d MMM yyyy");
        case "tz": return sysTz || "—";
        case "st-used": return stUsed || "…";
        case "st-free": return stFree || "…";
        case "st-total": return stTotal || "…";
        case "st-pct": return stPct || "…";
        case "keyboard": return kbName(kbLayout);
        case "cursor": return Quickshell.env("XCURSOR_THEME") || "default";
        case "wallpaper-name": return Wall.name(Wall.current) || "None";
        case "shot-dir": return "Pictures/Screenshots";
        case "restart":
        case "poweroff": return armed === action ? "Press Enter to confirm" : "";
        default: return "";
        }
    }

    function checkedFor(action) {
        if (action.indexOf("kb:") === 0) return kbLayout === action.slice(3);
        if (action.indexOf("out:") === 0) return audioSinks[parseInt(action.split(":")[1])] === sink;
        if (action.indexOf("in:") === 0) return audioSources[parseInt(action.split(":")[1])] === source;
        if (action.indexOf("pfp:") === 0) return Profile.src !== "" && Profile.src === pfpFiles[parseInt(action.split(":")[1])];
        if (action === "pfp-clear") return Profile.pic === "";
        return false;
    }

    function fractionFor(action) {
        if (action === "volume") return volumeShown;
        if (action === "brightness") return brightnessShown;
        return 0;
    }

    function setStatus(message, kind) {
        statusKind = kind || "info";
        statusShown = message;
        statusKindShown = statusKind;
        statusText = message;
        statusTimer.restart();
    }

    function refreshWifi() {
        if (!wifiDevice) {
            setStatus("No NetworkManager Wi-Fi adapter detected", "error");
            return;
        }
        if (!wifiOn) {
            setStatus("Turn Wi-Fi on to scan for networks", "info");
            return;
        }
        wifiDevice.scannerEnabled = true;
        scanTimer.restart();
        setStatus("Scanning for nearby networks…", "loading");
    }

    function connectNetwork(network) {
        if (!network || network.stateChanging) return;
        if (network.connected) {
            pendingNetwork = network;
            networkBusy = true;
            connectionTimer.restart();
            network.disconnect();
            setStatus("Disconnecting from " + network.name + "…", "loading");
            return;
        }
        if (network.known || network.security === WifiSecurityType.Open) {
            pendingNetwork = network;
            networkBusy = true;
            connectionTimer.restart();
            setStatus("Connecting to " + network.name + "…", "loading");
            network.connect();
            return;
        }
        if (network.security !== WifiSecurityType.WpaPsk
            && network.security !== WifiSecurityType.Wpa2Psk
            && network.security !== WifiSecurityType.Sae) {
            setStatus("This network requires credentials not supported by the in-shell prompt.", "error");
            return;
        }
        pendingNetwork = network;
        wifiPassword = "";
        promptKind = "wifi";
        passwordPrompt = true;
        setStatus("Enter the network password", "info");
        passwordField.forceActiveFocus();
    }

    function submitWifiPassword() {
        if (promptKind === "name") { submitName(); return; }
        if (!pendingNetwork || wifiPassword.length < 1) {
            setStatus("Enter the Wi-Fi password first", "error");
            return;
        }
        networkBusy = true;
        connectionTimer.restart();
        passwordPrompt = false;
        forceActiveFocus();
        setStatus("Connecting to " + pendingNetwork.name + "…", "loading");
        pendingNetwork.connectWithPsk(wifiPassword);
        wifiPassword = "";
    }

    function moveGrid(dx, dy) {
        // vertical list: only up / down move the highlight (dx is ignored)
        categoryIndex = Math.max(0, Math.min(categories.length - 1, categoryIndex + dy));
        armed = "";
    }

    function openCategory(index) {
        const next = Math.max(0, Math.min(categories.length - 1, index));
        categoryIndex = next;
        itemIndex = 0;
        rowIndex = 0;
        inPane = false;
        armed = "";
        pane = 1;
        if (wifiDevice) wifiDevice.scannerEnabled = next === netIdx;
        if (adapter && next !== accIdx) adapter.discovering = false;
        if (next === netIdx) refreshWifi();
        if (categories[next].key === "users") picScan.running = true;
    }

    function closeCategory() {
        pane = 0;
        inPane = false;
        armed = "";
        endSliderDrag();
        scanTimer.stop();
        if (statusKind === "loading") statusText = "";
        if (wifiDevice) wifiDevice.scannerEnabled = false;
        if (adapter) adapter.discovering = false;
    }

    function enterPane() { if (currentRows.length > 0) inPane = true; }

    function menuItemClicked(index) {
        if (pane !== 1) return;
        itemIndex = index;
        rowIndex = 0;
        armed = "";
        inPane = false;
    }

    function menuRowClicked(index) {
        if (pane !== 1) return;
        const row = currentRows[index];
        if (!row) return;
        if (!inPane || index !== rowIndex) {
            inPane = true;
            rowIndex = index;
            armed = "";
            return;
        }
        if (row.kind !== "slider" && row.kind !== "info") activate();
    }

    // ---- coalesced hardware writes ----
    function queueBrightness(percent) {
        briTarget = Math.max(1, Math.min(100, Math.round(percent)));
        if (!briFlush.running) briFlush.start();
        briIdle.restart();
    }

    function flushBrightness() {
        if (briTarget < 0 || Desk.brightness < 0) return;
        const base = briSent >= 0 ? briSent : Desk.brightness;
        if (briTarget !== base) {
            Desk.briStep(briTarget - base);
            briSent = briTarget;
        }
    }

    function queueVolume(fraction) {
        volTarget = Math.max(0, Math.min(1, fraction));
        if (!volFlush.running) volFlush.start();
        volIdle.restart();
    }

    function commitVolume() {
        if (volTarget >= 0 && sink && sink.audio) sink.audio.volume = volTarget;
    }

    function setSliderAt(action, fraction) {
        const value = Math.max(0, Math.min(1, fraction));
        dragAction = action;
        dragFraction = value;
        if (action === "volume" && sink && sink.audio) queueVolume(value);
        else if (action === "brightness" && Desk.brightness >= 0) queueBrightness(value * 100);
    }

    function endSliderDrag() {
        dragAction = "";
        dragFraction = -1;
    }

    function toggleOn(action) {
        switch (action) {
        case "wifi": return Networking.wifiHardwareEnabled && Networking.wifiEnabled;
        case "mute": return sink && sink.audio ? sink.audio.muted : false;
        case "mic-mute": return source && source.audio ? source.audio.muted : false;
        case "bluetooth": return adapter ? adapter.enabled : false;
        case "bt-scan": return adapter ? adapter.discovering : false;
        case "reduce-motion": return reduceMotion;
        case "popups": return Notifs.popups;
        default: return false;
        }
    }

    function adjust(delta) {
        if (pane !== 1) return;
        const row = currentRows[rowIndex];
        if (!row) return;
        if (row.action === "volume" && sink && sink.audio)
            queueVolume(volumeShown + 0.05 * delta);
        else if (row.action === "brightness" && Desk.brightness >= 0)
            queueBrightness(brightnessShown * 100 + 5 * delta);
    }

    // viii-kb: the layout is switched by bin/viii-kb, which tries Lua eval, the old keyword and a reload, and only
    // exits 0 when the keyboard is really using the new layout. The check mark moves after that, not before.
    property string kbPending: ""
    function kbName(code) {
        for (let i = 0; i < kbLayouts.length; i++)
            if (kbLayouts[i].code === code) return kbLayouts[i].name;
        return code;
    }
    function setKeyboard(code) {
        if (kbSet.running || code === kbLayout) return;
        kbPending = code;
        kbSet.command = ["sh", "-c", "exec \"$HOME/.local/bin/viii-kb\" \"$1\"", "sh", code];
        kbSet.running = true;
        setStatus("Switching keyboard layout\u2026", "info");
    }

    function setReduceMotion(on) {
        reduceMotion = on;
        Quickshell.execDetached(["hyprctl", "keyword", "animations:enabled", on ? "false" : "true"]);
        setStatus(on ? "Window animations off" : "Window animations on", "success");
    }

    function runTest() {
        if (testProc.running) return;
        testResult = "Testing…";
        testProc.running = true;
        setStatus("Testing the internet connection…", "loading");
    }

    readonly property string pfpScript: [
        "set -e",
        "d=\"$HOME/.config/viii\"; mkdir -p \"$d\"",
        "magick \"$1\" -auto-orient -resize 256x256^ -gravity center -extent 256x256 \\( -size 256x256 xc:none -fill white -draw 'circle 128,128 128,0' \\) -compose DstIn -composite \"$2\"",
        "magick \"$1\" -auto-orient -resize 512x512^ -gravity center -extent 512x512 -quality 92 \"$HOME/pfp.jpg\"",
        "ls \"$d\"/avatar-*.png | grep -v -F \"$2\" | xargs -r rm -f"
    ].join("\n")

    function setPicture(path) {
        if (pfpProc.running) return;
        pfpSrc = path;
        pfpOut = Profile.home + "/.config/viii/avatar-" + Date.now() + ".png";
        setStatus("Applying picture…", "loading");
        pfpProc.command = ["sh", "-c", pfpScript, "sh", path, pfpOut];
        pfpProc.running = true;
    }

    function openNamePrompt() {
        promptKind = "name";
        wifiPassword = Profile.display;
        passwordPrompt = true;
        passwordField.forceActiveFocus();
        passwordField.selectAll();
    }

    function submitName() {
        const n = wifiPassword.trim();
        passwordPrompt = false;
        wifiPassword = "";
        forceActiveFocus();
        if (n.length < 1) { setStatus("Enter a name first", "error"); return; }
        Profile.save(n, Profile.pic, Profile.src);
        setStatus("Profile name saved", "success");
    }

    function runPower(action) {
        if (action === "restart" || action === "poweroff") {
            if (armed !== action) {
                armed = action;
                armTimer.restart();
                setStatus("Press Enter again to confirm " + (action === "poweroff" ? "turning off" : "restart"), "info");
                return;
            }
        }
        closeRequested();
        if (action === "lock") Quickshell.execDetached(["hyprlock"]);
        else if (action === "suspend") Quickshell.execDetached(["systemctl", "suspend"]);
        else if (action === "restart") Quickshell.execDetached(["systemctl", "reboot"]);
        else if (action === "poweroff") Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    function activate() {
        if (pane !== 1) return;
        const row = currentRows[rowIndex];
        if (!row) return;
        const a = String(row.action);
        if (a !== "restart" && a !== "poweroff") armed = "";
        if (a.indexOf("wifi-network:") === 0) {
            connectNetwork(wifiNetworks[parseInt(a.split(":")[1])]);
            return;
        }
        if (a.indexOf("bt-device:") === 0) {
            const d = btDevices[parseInt(a.split(":")[1])];
            if (!d) return;
            pendingBluetooth = d;
            bluetoothTimer.restart();
            if (d.paired) {
                d.connected = !d.connected;
                setStatus((d.connected ? "Connecting to " : "Disconnecting from ") + (d.name || d.deviceName) + "…", "loading");
            } else {
                d.pair();
                setStatus("Pairing with " + (d.name || d.deviceName) + "…", "loading");
            }
            return;
        }
        if (a.indexOf("kb:") === 0) { setKeyboard(a.slice(3)); return; }
        if (a.indexOf("out:") === 0) {
            const n = audioSinks[parseInt(a.split(":")[1])];
            if (n) { Pipewire.preferredDefaultAudioSink = n; setStatus("Output: " + (n.description || n.name), "success"); }
            return;
        }
        if (a.indexOf("in:") === 0) {
            const n = audioSources[parseInt(a.split(":")[1])];
            if (n) { Pipewire.preferredDefaultAudioSource = n; setStatus("Input: " + (n.description || n.name), "success"); }
            return;
        }
        if (a.indexOf("pfp:") === 0) {
            const p = pfpFiles[parseInt(a.split(":")[1])];
            if (p) setPicture(p);
            return;
        }
        switch (a) {
        case "wifi":
            Networking.wifiEnabled = !Networking.wifiEnabled;
            if (!Networking.wifiEnabled && wifiDevice) wifiDevice.scannerEnabled = false;
            break;
        case "wifi-scan": refreshWifi(); break;
        case "net-test": runTest(); break;
        case "mute":
            if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
            setStatus(sink && sink.audio && sink.audio.muted ? "Audio muted" : "Audio unmuted", "success");
            break;
        case "mic-mute":
            if (source && source.audio) source.audio.muted = !source.audio.muted;
            setStatus(source && source.audio && source.audio.muted ? "Microphone muted" : "Microphone unmuted", "success");
            break;
        case "bluetooth":
            if (adapter) adapter.enabled = !adapter.enabled;
            else setStatus("No Bluetooth adapter detected", "error");
            break;
        case "bt-scan":
            if (!adapter) setStatus("No Bluetooth adapter detected", "error");
            else if (!adapter.enabled) setStatus("Turn Bluetooth on before scanning", "error");
            else {
                adapter.discovering = !adapter.discovering;
                setStatus(adapter.discovering ? "Scanning for Bluetooth devices…" : "Bluetooth scan stopped", "info");
            }
            break;
        case "reduce-motion": setReduceMotion(!reduceMotion); break;
        case "popups": Notifs.popups = !Notifs.popups; break;
        case "profile-name": openNamePrompt(); break;
        case "pfp-clear":
            Profile.save(Profile.name, "", "");
            setStatus("Profile picture removed", "success");
            break;
        case "wallpaper": wallstoreRequested(); break;
        case "history": closeRequested(); Desk.openHistory(); break;
        case "history-clear": Notifs.clear(); setStatus("Notification history cleared", "success"); break;
        case "shot": closeRequested(); Desk.openShot(); break;
        case "lock": case "suspend": case "restart": case "poweroff":
            runPower(a);
            break;
        }
    }

    function clearConfirmHint() {
        armed = "";
        if (statusText.indexOf("Press Enter again") === 0) { statusText = ""; statusTimer.stop(); }
    }

    function handleKey(event) {
        if (passwordPrompt) {
            if (event.key === Qt.Key_Escape) {
                passwordPrompt = false;
                wifiPassword = "";
                forceActiveFocus();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                submitWifiPassword();
                event.accepted = true;
                return;
            }
            event.accepted = false;
            return;
        }

        const row = currentRows[rowIndex];
        const adjustable = false;
        let handled = true;

        if (pane === 0) {
            switch (event.key) {
            case Qt.Key_Left: moveGrid(-1, 0); break;
            case Qt.Key_Right: moveGrid(1, 0); break;
            case Qt.Key_Up: moveGrid(0, -1); break;
            case Qt.Key_Down: moveGrid(0, 1); break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                openCategory(categoryIndex);
                break;
            case Qt.Key_Escape:
            case Qt.Key_Back:
                closeRequested();
                break;
            case Qt.Key_Home:
                categoryIndex = 0;
                break;
            case Qt.Key_End:
                categoryIndex = categories.length - 1;
                break;
            default:
                handled = false;
            }
            event.accepted = handled;
            return;
        }

        const rowsN = currentRows.length;
        const itemsN = currentItems.length;
        const isSlider = !!row && row.kind === "slider";

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Back:
            if (inPane) { inPane = false; clearConfirmHint(); }
            else closeCategory();
            break;
        case Qt.Key_Left:
            if (inPane && isSlider) adjust(-1);
            else if (inPane) { inPane = false; clearConfirmHint(); }
            break;
        case Qt.Key_Right:
            if (!inPane) enterPane();
            else if (isSlider) adjust(1);
            break;
        case Qt.Key_Up:
            if (inPane) { if (rowIndex > 0) rowIndex = rowIndex - 1; clearConfirmHint(); }
            else if (itemIndex > 0) itemIndex = itemIndex - 1;
            break;
        case Qt.Key_Down:
            if (inPane) { if (rowIndex < rowsN - 1) rowIndex = rowIndex + 1; clearConfirmHint(); }
            else if (itemIndex < itemsN - 1) itemIndex = itemIndex + 1;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (!inPane) enterPane();
            else activate();
            break;
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            if (inPane) adjust(1);
            break;
        case Qt.Key_Minus:
            if (inPane) adjust(-1);
            break;
        default:
            handled = false;
        }
        event.accepted = handled;
    }

    // one process for everything that is read from the system when Settings opens
    Process {
        id: sysProc
        command: ["sh", "-c", [
            ". /etc/os-release 2>/dev/null; echo \"${PRETTY_NAME:-Linux}\"",
            "uname -r",
            "hyprctl version 2>/dev/null | sed -n 's/^Hyprland \\([0-9][0-9.]*\\).*/\\1/p' | head -n1 | grep . || echo -",
            "quickshell --version 2>/dev/null | head -n1 | grep . || echo -",
            "matugen --version 2>/dev/null | head -n1 | grep . || echo -",
            "timedatectl show -p Timezone --value 2>/dev/null | grep . || echo -",
            "df -h / | awk 'NR==2 {print $3; print $4; print $2; print $5}'"
        ].join("; ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = this.text.split("\n");
                root.sysOs = l[0] || "";
                root.sysKernel = l[1] || "";
                root.sysHypr = l[2] || "";
                root.sysQs = (l[3] || "").split(" (")[0];
                root.sysMatugen = l[4] || "";
                root.sysTz = l[5] || "";
                root.stUsed = l[6] || "";
                root.stFree = l[7] || "";
                root.stTotal = l[8] || "";
                root.stPct = l[9] || "";
            }
        }
    }
    Process {
        id: ipProc
        command: ["sh", "-c", "ip -4 -o addr show scope global | awk '{print $4}' | head -n1 | cut -d/ -f1"]
        stdout: StdioCollector { onStreamFinished: root.ipText = this.text.trim() }
    }
    Process {
        id: monProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.monitors = JSON.parse(this.text); } catch (e) { root.monitors = []; }
            }
        }
    }
    Process {
        id: kbSet
        stdout: StdioCollector { onStreamFinished: console.log("[viii-settings] viii-kb:", String(this.text).trim()) }
        onExited: (code, status) => {
            if (code === 0) {
                root.kbLayout = root.kbPending;
                root.setStatus("Keyboard layout: " + root.kbName(root.kbPending), "success");
            } else {
                root.setStatus("Couldn\u2019t switch the keyboard layout (see: viii log)", "error");
            }
            root.kbPending = "";
        }
    }
    Process {
        id: kbProc
        command: ["sh", "-c", "\"$HOME/.local/bin/viii-kb\" --get 2>/dev/null || cat \"$HOME/.config/viii/kb_layout\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.kbLayout = this.text.trim() || "gb" }
    }
    Process {
        id: picScan
        command: ["sh", "-c", "find \"$HOME/Pictures\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort | head -n 40"]
        stdout: StdioCollector {
            onStreamFinished: root.pfpFiles = this.text.split("\n").filter(s => s.length > 0)
        }
    }
    Process {
        id: pfpProc
        onExited: (code, status) => {
            if (code === 0) {
                Profile.save(Profile.name, root.pfpOut, root.pfpSrc);
                root.setStatus("Profile picture updated", "success");
            } else {
                root.setStatus("Could not apply the picture (is ImageMagick installed?)", "error");
            }
        }
    }
    Process {
        id: testProc
        command: ["sh", "-c", "ping -c 3 -W 2 1.1.1.1 2>/dev/null | tail -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.match(new RegExp("= [0-9.]+/([0-9.]+)/"));
                if (m) {
                    root.testResult = "Connected  ·  " + Math.round(parseFloat(m[1])) + " ms";
                    root.setStatus("Internet connection is working", "success");
                } else {
                    root.testResult = "No connection";
                    root.setStatus("Could not reach the internet", "error");
                }
            }
        }
    }

    Connections {
        target: root.pendingNetwork
        function onConnectionFailed(reason) {
            root.networkBusy = false;
            connectionTimer.stop();
            root.passwordPrompt = false;
            root.setStatus("Connection failed · check the password or try again", "error");
        }
        function onConnectedChanged() {
            if (root.pendingNetwork && root.networkBusy) {
                root.networkBusy = false;
                connectionTimer.stop();
                root.setStatus((root.pendingNetwork.connected ? "Connected to " : "Disconnected from ")
                    + root.pendingNetwork.name, "success");
            }
        }
    }
    Connections {
        target: root.pendingBluetooth
        function onConnectedChanged() {
            bluetoothTimer.stop();
            root.setStatus((root.pendingBluetooth.connected ? "Connected to " : "Disconnected from ")
                + (root.pendingBluetooth.name || root.pendingBluetooth.deviceName), "success");
        }
        function onPairedChanged() {
            if (root.pendingBluetooth && root.pendingBluetooth.paired) {
                bluetoothTimer.stop();
                root.setStatus("Paired with " + (root.pendingBluetooth.name || root.pendingBluetooth.deviceName), "success");
            }
        }
        function onPairingChanged() {
            if (root.pendingBluetooth && !root.pendingBluetooth.pairing && !root.pendingBluetooth.paired) {
                bluetoothTimer.stop();
                root.setStatus("Pairing failed · try again", "error");
            }
        }
    }
    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            root.setStatus("Wi-Fi " + (Networking.wifiEnabled ? "enabled" : "disabled"), "success");
        }
    }
    Connections {
        target: root.adapter
        function onEnabledChanged() {
            root.setStatus("Bluetooth " + (root.adapter.enabled ? "enabled" : "disabled"), "success");
        }
    }

    function refreshDetails() {
        sysProc.running = true;
        ipProc.running = true;
        monProc.running = true;
        kbProc.running = true;
        Desk.briRefresh();
        Profile.reload();
        if (categoryIndex === netIdx && pane === 1) refreshWifi();
    }

    onActiveChanged: {
        if (active) {
            refreshDetails();
            forceActiveFocus();
        } else {
            pane = 0;
            inPane = false;
            passwordPrompt = false;
            networkBusy = false;
            armed = "";
            endSliderDrag();
            connectionTimer.stop();
            bluetoothTimer.stop();
            if (wifiDevice) wifiDevice.scannerEnabled = false;
            scanTimer.stop();
            if (adapter) adapter.discovering = false;
        }
    }
    onCategoryIndexChanged: {
        if (wifiDevice) wifiDevice.scannerEnabled = active && pane === 1 && categoryIndex === 1;
        if (adapter && !(active && pane === 1 && categoryIndex === accIdx)) adapter.discovering = false;
    }
    Component.onCompleted: if (active) refreshDetails()

    opacity: reveal
    visible: active || reveal > 0.01

    // =====================================================================
    // pane 0 · the category grid
    // =====================================================================
    Item {
        id: gridLayer
        anchors.fill: parent
        enabled: root.pane === 0
        visible: opacity > 0.01
        opacity: 1 - root.pageT
        scale: 1 + 0.045 * root.pageT
        transformOrigin: Item.Center

        SettingsText {
            x: root.padX; y: 65
            text: "Settings"
            font.pixelSize: 29
        }
        SettingsText {
            anchors.right: parent.right
            anchors.rightMargin: root.padX
            y: 52
            text: "Esc   Close"
            font.pixelSize: 12
            color: Theme.fgDim
            horizontalAlignment: Text.AlignRight
        }

        // A real list: rows keep their place, the ring moves to the highlighted row and the
        // list scrolls only when it has to. Per frame only y / opacity change.
        Repeater {
            model: root.categories

            delegate: Item {
                id: tile
                required property var modelData
                required property int index

                readonly property bool selected: root.categoryIndex === index
                readonly property real rowTopY: root.rowTop(index)

                x: root.listX
                y: rowTopY
                width: root.listW
                height: root.rowH
                opacity: root.rowFade(rowTopY)
                visible: opacity > 0.02

                Text {
                    x: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: iconImg.ok ? "" : tile.modelData.icon
                    font.family: Theme.iconFont
                    font.pixelSize: 25
                    color: tile.selected ? Theme.fg : Theme.fgDim
                    Behavior on color { ColorAnimation { duration: 180 } }
                }

                // viii-ps5-settings: SVG override (settings/icons/<key>.svg), Nerd Font glyph otherwise
                Image {
                    id: iconImg
                    readonly property bool ok: status === Image.Ready
                    x: 30
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    source: Qt.resolvedUrl("icons/" + tile.modelData.key + ".svg")
                    sourceSize.width: 56
                    sourceSize.height: 56
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: ok
                    opacity: tile.selected ? 1 : 0.6
                }
                Column {
                    x: 80
                    width: parent.width - 90 - 28
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    SettingsText {
                        width: parent.width
                        text: tile.modelData.title
                        font.pixelSize: 20
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }

                // very faint separator under every row except the last
                Rectangle {
                    visible: tile.index < root.categories.length - 1
                    x: 0
                    y: parent.height - 1
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Theme.fg, 0.07)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openCategory(tile.index)
                }
            }
        }

        // keep the highlighted row inside the visible area
        Connections {
            target: root
            function onCategoryIndexChanged() { root.ensureVisible(); }
        }

        // The same ring and overlay shade as everywhere; it glides from row to row.
        GlassRing {
            readonly property real out: 3.5
            x: root.listX - out
            y: root.listTop + root.selPos * root.rowH - root.scrollY + 5 - out
            width: root.listW + 2 * out
            height: root.rowH - 10 + 2 * out
            radius: 3 + out
            thickness: 2.5
            shade: true
            trigger: root.categoryIndex
            animated: gridLayer.visible && root.visible
            z: 3
        }

        // mouse wheel / touchpad: one row per notch
        WheelHandler {
            property real acc: 0
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                acc += event.angleDelta.y;
                while (acc >= 120) { acc -= 120; root.moveGrid(0, -1); }
                while (acc <= -120) { acc += 120; root.moveGrid(0, 1); }
            }
        }
    }

    // =====================================================================
    // pane 1 · the reusable category page
    // =====================================================================
    Item {
        id: menuLayer
        anchors.fill: parent
        enabled: root.pane === 1
        visible: opacity > 0.01
        opacity: root.pageT
        scale: 0.955 + 0.045 * root.pageT
        transformOrigin: Item.Center

        SettingsMenu {
            x: root.padX
            y: 38
            width: root.innerW
            height: root.height - 38 - 70

            category: root.currentCategory
            items: root.currentItems
            rows: root.currentRows
            itemIndex: root.itemIndex
            currentIndex: root.rowIndex
            inPane: root.inPane
            armed: root.armed
            running: menuLayer.visible
            valueOf: root.valueFor
            toggleOf: root.toggleOn
            fractionOf: root.fractionFor
            checkedOf: root.checkedFor

            onActivated: root.activate()
            onItemClicked: index => root.menuItemClicked(index)
            onRowClicked: index => root.menuRowClicked(index)
            onSliderAt: (action, fraction) => root.setSliderAt(action, fraction)
            onSliderEnd: root.endSliderDrag()
        }
    }

    // ---- inline feedback: loading, success and error stay inside the shell ----
    Item {
        id: pill
        readonly property bool shown: root.statusText !== ""
        x: root.padX - (shown ? 0 : 10)
        y: root.height - 66
        width: Math.min(520, pillRow.implicitWidth)
        height: 30
        visible: opacity > 0.01
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.96
        transformOrigin: Item.Left
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Row {
            id: pillRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            SettingsText {
                id: spinner
                text: root.statusKindShown === "error" ? "!" : (root.statusKindShown === "success" ? "✓" : "◌")
                font.pixelSize: 15
                font.weight: Font.Bold
                color: root.statusKindShown === "error" ? "#ff6b6b" : Theme.accent
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 900
                    loops: Animation.Infinite
                    running: root.visible && root.statusKindShown === "loading" && pill.visible
                }
            }
            SettingsText {
                id: pillLabel
                width: Math.min(430, implicitWidth)
                text: root.statusShown
                font.pixelSize: 13
                color: Theme.fg
            }
        }
    }

    // ---- Wi-Fi credentials: entered here, no terminal or external connection editor ----
    Rectangle {
        anchors.fill: parent
        z: 20
        visible: root.passwordPrompt || root.promptT > 0.01
        opacity: root.promptT
        color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.58)
        MouseArea { anchors.fill: parent; enabled: root.passwordPrompt }
    }
    Rectangle {
        id: dialog
        anchors.centerIn: parent
        z: 21
        width: 480; height: 260
        radius: 24
        color: Theme.deep
        border.width: 1
        border.color: Theme.glassBorder
        visible: root.passwordPrompt || root.promptT > 0.01
        opacity: root.promptT
        scale: 0.92 + 0.08 * root.promptPop
        SettingsText {
            x: 30; y: 26
            text: root.promptKind === "name" ? "Profile Name" : "Connect to " + (root.pendingNetwork ? root.pendingNetwork.name : "Wi-Fi")
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }
        SettingsText {
            x: 30; y: 66
            text: root.promptKind === "name" ? "Enter the name to show in the shell" : "Enter the network password"
            font.pixelSize: 14
            color: Theme.fgDim
        }
        Rectangle {
            x: 30; y: 112
            width: 420; height: 48
            radius: 12
            color: Theme.glass
            border.width: 1
            border.color: passwordField.activeFocus ? Theme.accent : Theme.glassBorder
            Behavior on border.color { ColorAnimation { duration: 160 } }
            TextInput {
                id: passwordField
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: 16
                text: root.wifiPassword
                echoMode: root.promptKind === "name" ? TextInput.Normal : TextInput.Password
                onTextChanged: root.wifiPassword = text
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.passwordPrompt = false;
                        root.wifiPassword = "";
                        root.forceActiveFocus();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.submitWifiPassword();
                        event.accepted = true;
                    }
                }
            }
        }
        SettingsText {
            x: 30; y: 184
            text: root.promptKind === "name" ? "Enter  ·  Save          Esc  ·  Cancel" : "Enter  ·  Connect          Esc  ·  Cancel"
            font.pixelSize: 13
            color: Theme.fgDim
        }
    }
}
