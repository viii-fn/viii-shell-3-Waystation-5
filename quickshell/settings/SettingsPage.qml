import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Networking
import "../core"
import "../hub"

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

    readonly property var categories: [
        { title: "System", icon: "", description: "System software, power and device information" },
        { title: "Network", icon: "", description: "Internet connection and network settings" },
        { title: "Sound", icon: "", description: "Audio output, volume and mute controls" },
        { title: "Display", icon: "", description: "Brightness and connected displays" },
        { title: "Accessories", icon: "", description: "Bluetooth, keyboard, mouse and connected devices" },
        { title: "Notifications", icon: "", description: "Desktop notification services" },
        { title: "Personalisation", icon: "", description: "Wallpaper, colours and visual appearance" },
        { title: "Storage", icon: "", description: "Disk space and storage information" },
        { title: "Privacy & Security", icon: "", description: "Screen locking and session security" },
        { title: "Users & Accounts", icon: "", description: "Current user and desktop session" },
        { title: "Applications", icon: "", description: "Installed applications and app library" },
        { title: "About", icon: "", description: "System and shell versions" }
    ]

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
    readonly property var currentRows: rowsForCategory()
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

    function rowsForCategory() {
        switch (categoryIndex) {
        case 0: return [
            { title: "Lock screen", desc: "Lock the current desktop session", action: "lock", kind: "action" },
            { title: "Suspend", desc: "Put the computer into sleep mode", action: "suspend", kind: "action" },
            { title: "Restart", desc: "Restart the computer", action: "restart", kind: "action" },
            { title: "Shut down", desc: "Power off the computer", action: "poweroff", kind: "action" }
        ];
        case 1: {
            const rows = [
                { title: "Wi-Fi", desc: "Wireless radio · NetworkManager", action: "wifi", kind: "toggle" },
                { title: "Connected network", desc: "Current wireless connection", action: "network-info", kind: "info" },
                { title: "Scan for networks", desc: "Discover nearby wireless networks", action: "wifi-scan", kind: "action" }
            ];
            const networks = wifiNetworks;
            for (let i = 0; i < Math.min(3, networks.length); i++) {
                const n = networks[i];
                rows.push({ title: n.name,
                    desc: (n.known ? "Saved network" : "Available network") + " · " + Math.round(n.signalStrength * 100) + "% signal",
                    action: "wifi-network:" + i, kind: "action" });
            }
            return rows;
        }
        case 2: return [
            { title: "Output volume", desc: "Adjust the default audio output level", action: "volume", kind: "slider" },
            { title: "Audio", desc: "Mute or unmute the default output", action: "mute", kind: "toggle" },
            { title: "Output device", desc: "Choose the active PipeWire output", action: "audio-output", kind: "cycle" },
            { title: "Input device", desc: "Choose the active PipeWire microphone", action: "audio-input", kind: "cycle" }
        ];
        case 3: return [
            { title: "Screen brightness", desc: "Adjust the built-in display backlight", action: "brightness", kind: "slider" },
            { title: "Display configuration", desc: "Monitor layout and resolution are managed by Hyprland", action: "display-info", kind: "info" },
            { title: "Desktop session", desc: "Current compositor and display protocol", action: "session", kind: "info" }
        ];
        case 4: {
            const rows = [
                { title: "Bluetooth", desc: "Bluetooth radio and adapter", action: "bluetooth", kind: "toggle" },
                { title: "Discover devices", desc: "Scan for nearby Bluetooth accessories", action: "bt-scan", kind: "toggle" },
                { title: "Cursor theme", desc: "Current cursor theme", action: "cursor", kind: "info" },
                { title: "Keyboard layout", desc: "Current keyboard layout", action: "keyboard", kind: "info" }
            ];
            for (let i = 0; i < Math.min(2, btDevices.length); i++) {
                const d = btDevices[i];
                rows.push({ title: d.name || d.deviceName || "Bluetooth device",
                    desc: d.paired ? "Paired accessory" : "Nearby accessory",
                    action: "bt-device:" + i, kind: "action" });
            }
            return rows;
        }
        case 5: return [
            { title: "Notification service", desc: "Notification daemon status is not exposed by VIII yet", action: "notifications", kind: "info" },
            { title: "Notification preferences", desc: "Notification controls are not implemented in this shell yet", action: "notifications-info", kind: "info" }
        ];
        case 6: return [
            { title: "Wallpaper", desc: "Choose a wallpaper in Wallstore", action: "wallpaper", kind: "action" },
            { title: "Colour palette", desc: "Matugen generates the shell palette from your wallpaper", action: "palette", kind: "info" },
            { title: "Active wallpaper", desc: "Wallpaper currently driving the system palette", action: "wallpaper-name", kind: "info" },
            { title: "Cursor theme", desc: "Bibata cursor theme package is installed", action: "cursor", kind: "info" }
        ];
        case 7: return [
            { title: "Root filesystem", desc: "Usage of the system partition", action: "storage", kind: "info" },
            { title: "Mounted storage", desc: "Disk browsing is handled by the desktop file manager", action: "storage", kind: "info" }
        ];
        case 8: return [
            { title: "Lock screen", desc: "Lock the session using Hyprlock", action: "lock", kind: "action" },
            { title: "Session security", desc: "Hyprland Wayland session", action: "session", kind: "info" }
        ];
        case 9: return [
            { title: "Current user", desc: "Linux account running this shell", action: "user", kind: "info" },
            { title: "Desktop session", desc: "Current graphical session", action: "session", kind: "info" }
        ];
        case 10: return [
            { title: "App library", desc: "Browse and launch installed applications", action: "library", kind: "action" },
            { title: "Package manager", desc: "Package management is not exposed as a native Quickshell control", action: "packages-info", kind: "info" },
            { title: "Installed applications", desc: "Application discovery is available in the Library", action: "library", kind: "action" }
        ];
        default: return [
            { title: "Operating system", desc: "Linux distribution", action: "os", kind: "info" },
            { title: "Kernel", desc: "Currently running Linux kernel", action: "kernel", kind: "info" },
            { title: "Window manager", desc: "Desktop compositor", action: "hyprland", kind: "info" },
            { title: "Shell", desc: "Quickshell version", action: "quickshell", kind: "info" },
            { title: "Theme engine", desc: "Wallpaper colour generation", action: "matugen", kind: "info" }
        ];
        }
    }

    function valueFor(action) {
        if (action.indexOf("wifi-network:") === 0) {
            const n = wifiNetworks[parseInt(action.split(":")[1])];
            return !n ? "Unavailable" : (n.connected ? "Connected" : (n.stateChanging ? "Connecting…" : (n.known ? "Saved" : "Available")));
        }
        if (action.indexOf("bt-device:") === 0) {
            const d = btDevices[parseInt(action.split(":")[1])];
            return !d ? "Unavailable" : (d.connected ? "Connected" : (d.pairing ? "Pairing…" : (d.paired ? "Paired" : "Available")));
        }
        switch (action) {
        case "wifi": return !Networking.wifiHardwareEnabled ? "Hardware blocked" : (wifiOn ? "On" : "Off");
        case "network-info": return wifiName || (wiredDevice ? "Ethernet · " + wiredDevice.name : (wifiOn ? "Not connected" : "Wi-Fi off"));
        case "wifi-scan": return wifiDevice && wifiDevice.scannerEnabled ? "Scanning…" : "Scan";
        case "display-info": return "Hyprland · Wayland";
        case "packages-info": return "Available via system package tools";
        case "bt-scan": return adapter ? (adapter.discovering ? "Scanning…" : "Off") : "Unavailable";
        case "volume": return sink && sink.audio ? Math.round(volumeShown * 100) + "%" : "Unavailable";
        case "mute": return sink && sink.audio ? (sink.audio.muted ? "Muted" : "On") : "Unavailable";
        case "audio-output": return sink ? (sink.description || sink.name || "Default output") : "No output detected";
        case "audio-input": return source ? (source.description || source.name || "Default input") : "No input detected";
        case "brightness": return Desk.brightness >= 0 ? Math.round(brightnessShown * 100) + "%" : "Unavailable";
        case "bluetooth": return !adapter ? "No adapter" : (adapter.enabled ? "On" : "Off");
        case "cursor": return Quickshell.env("XCURSOR_THEME") || "Not reported · Bibata installed";
        case "keyboard": return Quickshell.env("XKB_DEFAULT_LAYOUT") || "Not reported";
        case "wallpaper": return "Open Wallstore";
        case "palette": return "Matugen · Wallpaper";
        case "wallpaper-name": return Wall.name(Wall.current) || "No wallpaper selected";
        case "storage": return storageText;
        case "notifications": return "Not exposed";
        case "notifications-info": return "Not configured";
        case "user": return Quickshell.env("USER") || "Unknown";
        case "session": return "Hyprland · Wayland";
        case "os": return "Arch Linux";
        case "kernel": return kernelText;
        case "hyprland": return "Hyprland 0.57";
        case "quickshell": return "Quickshell 0.3.2";
        case "matugen": return "Matugen 4.2.0";
        case "restart":
        case "poweroff": return armed === action ? "Press Enter to confirm" : "";
        default: return "";
        }
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
        passwordPrompt = true;
        setStatus("Enter the network password", "info");
        passwordField.forceActiveFocus();
    }

    function submitWifiPassword() {
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
        rowIndex = 0;
        armed = "";
        pane = 1;
        if (wifiDevice) wifiDevice.scannerEnabled = next === 1;
        if (adapter && next !== 4) adapter.discovering = false;
        if (next === 1) refreshWifi();
    }

    function closeCategory() {
        pane = 0;
        armed = "";
        endSliderDrag();
        if (wifiDevice) wifiDevice.scannerEnabled = false;
        if (adapter) adapter.discovering = false;
    }

    function menuRowClicked(index) {
        if (pane !== 1) return;
        const row = currentRows[index];
        if (!row) return;
        if (index !== rowIndex) {
            rowIndex = index;
            armed = "";
            return;
        }
        if (row.kind === "cycle") adjust(1);
        else if (row.kind !== "slider" && row.kind !== "info") activate();
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
        case "mute": return sink && sink.audio ? !sink.audio.muted : false;
        case "bluetooth": return adapter ? adapter.enabled : false;
        case "bt-scan": return adapter ? adapter.discovering : false;
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
        else if (row.action === "audio-output" && audioSinks.length > 0) {
            let i = audioSinks.indexOf(sink);
            i = (i + delta + audioSinks.length) % audioSinks.length;
            Pipewire.preferredDefaultAudioSink = audioSinks[i];
            setStatus("Output: " + (audioSinks[i].description || audioSinks[i].name), "success");
        } else if (row.action === "audio-input" && audioSources.length > 0) {
            let i = audioSources.indexOf(source);
            i = (i + delta + audioSources.length) % audioSources.length;
            Pipewire.preferredDefaultAudioSource = audioSources[i];
            setStatus("Input: " + (audioSources[i].description || audioSources[i].name), "success");
        }
    }

    function runPower(action) {
        if (action === "restart" || action === "poweroff") {
            if (armed !== action) {
                armed = action;
                armTimer.restart();
                setStatus("Press Enter again to confirm " + (action === "poweroff" ? "shut down" : "restart"), "info");
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
        if (row.action !== "restart" && row.action !== "poweroff") armed = "";
        if (row.action.indexOf("wifi-network:") === 0) {
            const n = wifiNetworks[parseInt(row.action.split(":")[1])];
            connectNetwork(n);
            return;
        }
        if (row.action.indexOf("bt-device:") === 0) {
            const d = btDevices[parseInt(row.action.split(":")[1])];
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
        switch (row.action) {
        case "wifi":
            Networking.wifiEnabled = !Networking.wifiEnabled;
            if (!Networking.wifiEnabled && wifiDevice) wifiDevice.scannerEnabled = false;
            setStatus("Wi-Fi " + (Networking.wifiEnabled ? "enabled" : "disabled"), "success");
            break;
        case "wifi-scan":
            refreshWifi();
            break;
        case "mute":
            if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
            setStatus(sink && sink.audio && sink.audio.muted ? "Audio muted" : "Audio unmuted", "success");
            break;
        case "bluetooth":
            if (adapter) {
                adapter.enabled = !adapter.enabled;
                setStatus("Bluetooth " + (adapter.enabled ? "enabled" : "disabled"), "success");
            } else setStatus("No Bluetooth adapter detected", "error");
            break;
        case "bt-scan":
            if (!adapter) setStatus("No Bluetooth adapter detected", "error");
            else if (!adapter.enabled) setStatus("Turn Bluetooth on before scanning", "error");
            else {
                adapter.discovering = !adapter.discovering;
                setStatus(adapter.discovering ? "Scanning for Bluetooth devices…" : "Bluetooth scan stopped", "info");
            }
            break;
        case "wallpaper":
            wallstoreRequested();
            break;
        case "library":
            libraryRequested();
            break;
        case "lock": case "suspend": case "restart": case "poweroff":
            runPower(row.action);
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
        const adjustable = row && (row.kind === "slider" || row.kind === "cycle");
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

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Back:
            closeCategory();
            break;
        case Qt.Key_Left:
            if (adjustable) adjust(-1);
            break;
        case Qt.Key_Right:
            if (adjustable) adjust(1);
            break;
        case Qt.Key_Up:
            if (rowIndex > 0) rowIndex = rowIndex - 1;
            clearConfirmHint();
            break;
        case Qt.Key_Down:
            if (rowIndex < currentRows.length - 1) rowIndex = rowIndex + 1;
            clearConfirmHint();
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (row && row.kind === "cycle") adjust(1);
            else activate();
            break;
        case Qt.Key_Home:
            rowIndex = 0;
            break;
        case Qt.Key_End:
            rowIndex = Math.max(0, currentRows.length - 1);
            break;
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            adjust(1);
            break;
        case Qt.Key_Minus:
            adjust(-1);
            break;
        default:
            handled = false;
        }
        event.accepted = handled;
    }

    Process {
        id: storageProc
        command: ["sh", "-c", "df -h / | awk 'NR==2 {print $3 \" used of \" $2 \" (\" $5 \")\"}'"]
        stdout: StdioCollector {
            onStreamFinished: root.storageText = this.text.trim() || "Unavailable"
        }
        onExited: (code, status) => {
            if (code !== 0) root.storageText = "Storage information unavailable";
        }
    }
    Process {
        id: kernelProc
        command: ["uname", "-r"]
        stdout: StdioCollector { onStreamFinished: root.kernelText = this.text.trim() || "Unavailable" }
        onExited: (code, status) => {
            if (code !== 0) root.kernelText = "Kernel information unavailable";
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
        storageText = "Checking storage…";
        kernelText = "Checking kernel…";
        storageProc.running = true;
        kernelProc.running = true;
        Desk.briRefresh();
        if (categoryIndex === 1 && pane === 1) refreshWifi();
    }

    onActiveChanged: {
        if (active) {
            refreshDetails();
            forceActiveFocus();
        } else {
            pane = 0;
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
        if (adapter && !(active && pane === 1 && categoryIndex === 4)) adapter.discovering = false;
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
                    text: tile.modelData.icon
                    font.family: Theme.iconFont
                    font.pixelSize: 25
                    color: tile.selected ? Theme.fg : Theme.fgDim
                    Behavior on color { ColorAnimation { duration: 180 } }
                }

                Column {
                    x: 90
                    width: parent.width - 90 - 28
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    SettingsText {
                        width: parent.width
                        text: tile.modelData.title
                        font.pixelSize: 20
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    SettingsText {
                        width: parent.width
                        text: tile.modelData.description
                        font.pixelSize: 13
                        color: tile.selected ? Theme.fgDim : Qt.alpha(Theme.fg, 0.38)
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
            animated: gridLayer.visible
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
            rows: root.currentRows
            currentIndex: root.rowIndex
            armed: root.armed
            running: menuLayer.visible
            valueOf: root.valueFor
            toggleOf: root.toggleOn
            fractionOf: root.fractionFor

            onActivated: root.activate()
            onAdjusted: delta => root.adjust(delta)
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
                    running: root.statusKindShown === "loading" && pill.visible
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
            text: "Connect to " + (root.pendingNetwork ? root.pendingNetwork.name : "Wi-Fi")
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }
        SettingsText {
            x: 30; y: 66
            text: "Enter the network password"
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
                echoMode: TextInput.Password
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
            text: "Enter  ·  Connect          Esc  ·  Cancel"
            font.pixelSize: 13
            color: Theme.fgDim
        }
    }
}
