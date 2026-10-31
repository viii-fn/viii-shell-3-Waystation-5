import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Networking
import "../core"

// Full-screen PS5-inspired settings surface. It deliberately leaves the existing wallpaper visible;
// all colour comes from the active Matugen wallpaper palette through Theme.
//
// Motion / performance rules used throughout this file:
//  * only opacity, x/y, scale, rotation and colour are animated (no layout-driven size animation);
//  * no layer.enabled, no shader effects, no blur: nothing here allocates an offscreen buffer;
//  * one opacity at the root instead of several stacked multiplications;
//  * a single full-screen scrim (one blend pass instead of two);
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
    property int categoryIndex: 0        // highlighted in the rail (changes instantly)
    property int shownCategory: 0        // what the right-hand panel currently displays (swaps mid-transition)
    property int rowIndex: 0
    property int pane: 0                 // 0 = categories, 1 = settings
    property string armed: ""

    // ---- motion state ----
    property real contentT: 1            // right-hand panel fade
    property real contentShift: 0        // right-hand panel vertical slide
    property int switchDir: 1
    property bool switching: false
    property real nudge: 0               // edge-of-list bump
    property real nudgeDir: 1
    property real pulse: 0               // activation pulse on the focus highlight
    property real promptT: passwordPrompt ? 1 : 0
    property real promptPop: passwordPrompt ? 1 : 0
    Behavior on promptT { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on promptPop { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

    // ---- slider state (coalesced writes) ----
    property string dragAction: ""
    property real dragFraction: -1
    property real volTarget: -1
    property int briTarget: -1
    property int briSent: -1

    readonly property int rowPitch: 77

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

    readonly property var emptyRow: ({ title: "", desc: "", action: "", kind: "info" })

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
    property string wifiPassword: ""
    property var pendingNetwork: null
    property var pendingBluetooth: null
    property bool networkBusy: false

    readonly property var currentCategory: categories[shownCategory]
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

    // ---- animations ----
    // Category switch: old content slides/fades out, the data swaps while invisible, new content
    // slides/fades in. Holding an arrow key keeps restarting the exit, so the heavy swap happens once.
    SequentialAnimation {
        id: contentTransition
        ParallelAnimation {
            NumberAnimation { target: root; property: "contentT"; to: 0; duration: 110; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "contentShift"; to: -root.switchDir * 14; duration: 110; easing.type: Easing.InQuad }
        }
        ScriptAction { script: { root.shownCategory = root.categoryIndex; root.contentShift = root.switchDir * 14; } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "contentT"; to: 1; duration: 340; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "contentShift"; to: 0; duration: 340; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: root.switching = false }
    }
    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: root; property: "pulse"; to: 1; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "pulse"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }
    SequentialAnimation {
        id: nudgeAnim
        NumberAnimation { target: root; property: "nudge"; to: root.nudgeDir; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "nudge"; to: 0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }

    component SettingsText: Text {
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 16
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    component KeyHint: Row {
        id: keyHint
        property string keyLabel: ""
        property string description: ""
        spacing: 9
        Rectangle {
            height: 24
            width: Math.max(24, keyText.width + 16)
            radius: 7
            color: Theme.glassHi
            border.width: 1
            border.color: Theme.glassBorder
            SettingsText {
                id: keyText
                anchors.centerIn: parent
                text: keyHint.keyLabel
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
        SettingsText {
            y: (24 - height) / 2
            text: keyHint.description
            font.pixelSize: 14
            color: Theme.fgDim
        }
    }

    function rowsForCategory() {
        switch (shownCategory) {
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
            { title: "Mute audio", desc: "Mute or unmute the default output", action: "mute", kind: "toggle" },
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

    function selectCategory(index) {
        const next = Math.max(0, Math.min(categories.length - 1, index));
        if (next === categoryIndex) return;
        switchDir = next > categoryIndex ? 1 : -1;
        switching = true;                    // set first so the focus highlight does not glide through the swap
        categoryIndex = next;
        rowIndex = 0;
        pane = 0;
        armed = "";
        contentTransition.restart();
        if (wifiDevice) wifiDevice.scannerEnabled = active && categoryIndex === 1;
        if (adapter && categoryIndex !== 4) adapter.discovering = false;
        if (categoryIndex === 1 && wifiDevice) refreshWifi();
    }

    function bump(dir) {
        nudgeDir = dir;
        nudgeAnim.restart();
    }

    function bumpPulse() {
        pulseAnim.restart();
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
        if (switching) return;
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
            bumpPulse();
        } else if (row.action === "audio-input" && audioSources.length > 0) {
            let i = audioSources.indexOf(source);
            i = (i + delta + audioSources.length) % audioSources.length;
            Pipewire.preferredDefaultAudioSource = audioSources[i];
            setStatus("Input: " + (audioSources[i].description || audioSources[i].name), "success");
            bumpPulse();
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
        if (switching) return;
        const row = currentRows[rowIndex];
        if (!row) return;
        if (row.action !== "restart" && row.action !== "poweroff") armed = "";
        if (row.kind !== "info" && row.kind !== "slider") bumpPulse();
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
        let handled = true;
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Back:
            if (pane === 1) pane = 0;
            else closeRequested();
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            if (pane === 1 && currentRows[rowIndex]
                && (currentRows[rowIndex].kind === "slider" || currentRows[rowIndex].kind === "cycle"))
                adjust(-1);
            else if (pane === 1) pane = 0;
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            if (pane === 0) pane = 1;
            else if (currentRows[rowIndex]
                && (currentRows[rowIndex].kind === "slider" || currentRows[rowIndex].kind === "cycle"))
                adjust(1);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            if (pane === 0) {
                if (categoryIndex === 0) bump(-1);
                else selectCategory(categoryIndex - 1);
            } else {
                if (rowIndex === 0) bump(-1);
                else rowIndex = rowIndex - 1;
            }
            clearConfirmHint();
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            if (pane === 0) {
                if (categoryIndex === categories.length - 1) bump(1);
                else selectCategory(categoryIndex + 1);
            } else {
                if (rowIndex >= currentRows.length - 1) bump(1);
                else rowIndex = rowIndex + 1;
            }
            clearConfirmHint();
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (pane === 0) pane = 1;
            else activate();
            break;
        case Qt.Key_Tab:
            pane = 1 - pane;
            break;
        case Qt.Key_Home:
            if (pane === 0) selectCategory(0);
            else rowIndex = 0;
            break;
        case Qt.Key_End:
            if (pane === 0) selectCategory(categories.length - 1);
            else rowIndex = Math.max(0, currentRows.length - 1);
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
        if (categoryIndex === 1) refreshWifi();
    }

    onActiveChanged: {
        if (active) {
            contentTransition.stop();
            switching = false;
            contentT = 1;
            contentShift = 0;
            shownCategory = categoryIndex;
            refreshDetails();
            forceActiveFocus();
        } else {
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
        // Direct changes from the hub (reset to "System" on open) skip the transition.
        if (!switching) shownCategory = categoryIndex;
        if (wifiDevice) wifiDevice.scannerEnabled = active && categoryIndex === 1;
    }
    Component.onCompleted: if (active) refreshDetails()

    // The root only fades; the content layers below slide, so the dimmed backdrop never moves
    // and never exposes an edge.
    opacity: reveal
    visible: active || reveal > 0.01

    // One scrim, one blend pass. Wallpaper stays visible beneath it.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.84) }
            GradientStop { position: 1.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.93) }
        }
    }

    SettingsText {
        x: 66 - (1 - root.reveal) * 24; y: 40
        text: "Settings"
        font.pixelSize: 38
        font.weight: Font.Bold
    }
    SettingsText {
        anchors.right: parent.right
        anchors.rightMargin: 68 - (1 - root.reveal) * 24
        y: 56
        text: "SYSTEM CONFIGURATION"
        font.pixelSize: 12
        font.letterSpacing: 2
        color: Theme.fgDim
    }

    // ---- left category rail ----
    Item {
        id: rail
        x: -(1 - root.reveal) * 34

        Rectangle {
            x: 58; y: 126
            width: 326; height: 560
            radius: 20
            color: Theme.glass
            border.width: 1
            border.color: Theme.glassBorder
        }

        Rectangle {
            id: railHi
            x: 72
            y: 140 + root.categoryIndex * 46
            width: 298; height: 44
            radius: 11
            color: Theme.glassHi
            opacity: root.pane === 0 ? 1 : 0.55
            scale: 1 + 0.012 * root.pulse * (root.pane === 0 ? 1 : 0)
            transform: Translate { y: root.pane === 0 ? root.nudge * 5 : 0 }
            Behavior on y {
                NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
            }
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.glassBorder
                opacity: root.pane === 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            Rectangle {
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 20
                radius: 1.5
                color: Theme.accent
            }
        }

        Column {
            x: 72; y: 140
            width: 298
            spacing: 2
            Repeater {
                model: root.categories
                delegate: Item {
                    id: cat
                    required property var modelData
                    required property int index
                    width: 298
                    height: 44
                    readonly property bool selected: root.categoryIndex === index
                    readonly property real enter: Math.max(0, Math.min(1, root.reveal * 1.8 - index * 0.06))
                    x: (1 - enter) * 16
                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: Theme.glass
                        opacity: catArea.containsMouse && !cat.selected ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }
                    Text {
                        x: 13; anchors.verticalCenter: parent.verticalCenter
                        text: cat.modelData.icon
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: cat.selected ? Theme.fg : Theme.fgDim
                        scale: cat.selected ? 1.14 : 1
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    SettingsText {
                        x: 46; anchors.verticalCenter: parent.verticalCenter
                        width: 236
                        text: cat.modelData.title
                        font.pixelSize: 16
                        font.weight: cat.selected ? Font.DemiBold : Font.Medium
                        color: cat.selected ? Theme.fg : Theme.fgDim
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    MouseArea {
                        id: catArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectCategory(cat.index)
                    }
                }
            }
        }
    }

    // ---- right-hand settings panel ----
    // Everything inside contentLayer shares one opacity and one slide.
    Item {
        id: contentLayer
        x: (1 - root.reveal) * 40
        y: root.contentShift
        opacity: root.contentT

        SettingsText {
            x: 420; y: 132
            text: root.currentCategory.title
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }
        SettingsText {
            x: 420; y: 174
            width: 850
            text: root.currentCategory.description
            font.pixelSize: 14
            color: Theme.fgDim
        }

        Rectangle {
            x: 408; y: 210
            width: 900; height: 476
            radius: 20
            color: Theme.glass
            border.width: 1
            border.color: Theme.glassBorder
        }

        // focus highlight: glides between rows, pulses on activation, bumps at the list ends
        Rectangle {
            id: rowHi
            x: 424
            y: 226 + root.rowIndex * root.rowPitch
            width: 868; height: 74
            radius: 12
            color: Theme.glassHi
            visible: root.currentRows.length > 0
            opacity: root.pane === 1 ? 1 : 0.5
            scale: 1 + 0.012 * root.pulse * (root.pane === 1 ? 1 : 0)
            transform: Translate { y: root.pane === 1 ? root.nudge * 5 : 0 }
            Behavior on y {
                enabled: !root.switching
                NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
            }
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.glassBorder
                opacity: root.pane === 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
                opacity: root.armed !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
            Rectangle {
                x: 7
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 30
                radius: 1.5
                color: Theme.accent
                opacity: root.pane === 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
        }

        Column {
            x: 424; y: 226
            width: 868
            spacing: 3
            Repeater {
                // keyed on the count: live updates change text in place, they never rebuild rows
                model: root.currentRows.length
                delegate: Item {
                    id: settingRow
                    required property int index
                    readonly property var row: root.currentRows[index] || root.emptyRow
                    readonly property string action: row.action
                    readonly property string kind: row.kind
                    readonly property bool selected: root.rowIndex === index && root.pane === 1
                    readonly property bool isOn: kind === "toggle" && root.toggleOn(action)
                    readonly property bool armedNow: root.armed !== "" && root.armed === action
                    readonly property real enter: Math.max(0, Math.min(1, root.contentT * 1.5 - index * 0.07))
                    width: 868
                    height: 74
                    x: (1 - enter) * 14

                    // hover / press surface (opacity, not colour, so it never passes through black)
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: rowArea.pressed ? Theme.glassHi : Theme.glass
                        opacity: (rowArea.pressed || (rowArea.containsMouse && !settingRow.selected)) ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }
                    Column {
                        x: 20
                        anchors.verticalCenter: parent.verticalCenter
                        width: 540
                        spacing: 5
                        SettingsText {
                            width: parent.width
                            text: settingRow.row.title
                            font.pixelSize: 17
                            font.weight: settingRow.selected ? Font.DemiBold : Font.Medium
                        }
                        SettingsText {
                            width: parent.width
                            text: settingRow.row.desc
                            font.pixelSize: 12
                            color: Theme.fgDim
                        }
                    }
                    SettingsText {
                        id: valueLabel
                        anchors.right: parent.right
                        anchors.rightMargin: 48
                        anchors.verticalCenter: parent.verticalCenter
                        width: 230
                        text: root.valueFor(settingRow.action)
                        visible: settingRow.kind !== "toggle"
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: 14
                        color: settingRow.armedNow ? Theme.accent : (settingRow.selected ? Theme.fg : Theme.fgDim)
                        Behavior on color { ColorAnimation { duration: 160 } }
                        SequentialAnimation {
                            running: settingRow.armedNow && root.visible
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) valueLabel.opacity = 1
                            NumberAnimation { target: valueLabel; property: "opacity"; to: 0.45; duration: 520; easing.type: Easing.InOutSine }
                            NumberAnimation { target: valueLabel; property: "opacity"; to: 1; duration: 520; easing.type: Easing.InOutSine }
                        }
                    }

                    // toggle switch: the thumb squashes while pressed and settles with a small overshoot
                    Item {
                        visible: settingRow.kind === "toggle"
                        anchors.right: parent.right
                        anchors.rightMargin: 50
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 24
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: settingRow.isOn ? Theme.accent : Theme.glassHi
                            border.width: 1
                            border.color: Theme.glassBorder
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Rectangle {
                            y: 3
                            x: settingRow.isOn ? (rowArea.pressed ? 19 : 23) : 3
                            width: rowArea.pressed ? 22 : 18
                            height: 18
                            radius: 9
                            color: settingRow.isOn ? Theme.accentText : Theme.fgDim
                            Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                            Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }

                    // slider: generous hit area, knob that grows on hover / drag, no lag while dragging
                    Item {
                        id: slider
                        visible: settingRow.kind === "slider"
                        z: 2
                        anchors.right: parent.right
                        anchors.rightMargin: 48
                        y: 50
                        width: 112; height: 14
                        readonly property real value: settingRow.action === "volume" ? root.volumeShown : root.brightnessShown
                        Rectangle {
                            id: track
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 4
                            radius: 2
                            color: Theme.glassHi
                            Rectangle {
                                height: parent.height
                                radius: 2
                                width: parent.width * slider.value
                                color: Theme.accent
                                Behavior on width {
                                    enabled: !sliderArea.pressed
                                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                        Rectangle {
                            width: 12; height: 12
                            radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            x: track.width * slider.value - 6
                            color: Theme.fg
                            scale: sliderArea.pressed ? 1.35 : ((settingRow.selected || sliderArea.containsMouse) ? 1 : 0)
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                            Behavior on x {
                                enabled: !sliderArea.pressed
                                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                            }
                        }
                        MouseArea {
                            id: sliderArea
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => {
                                root.pane = 1;
                                root.rowIndex = settingRow.index;
                                root.setSliderAt(settingRow.action, (mouse.x - 10) / slider.width);
                            }
                            onPositionChanged: mouse => {
                                if (pressed) root.setSliderAt(settingRow.action, (mouse.x - 10) / slider.width);
                            }
                            onReleased: root.endSliderDrag()
                            onCanceled: root.endSliderDrag()
                        }
                    }

                    SettingsText {
                        anchors.right: parent.right
                        anchors.rightMargin: settingRow.selected && settingRow.kind === "action" ? 14 : 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: settingRow.kind === "action" ? "›"
                            : ((settingRow.kind === "cycle" || settingRow.kind === "slider") && settingRow.selected ? "‹ ›" : "")
                        font.pixelSize: settingRow.kind === "action" ? 25 : 13
                        color: Theme.fgDim
                        Behavior on anchors.rightMargin { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        height: 1
                        color: Theme.glassBorder
                        visible: index < root.currentRows.length - 1
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: settingRow.kind === "info" ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            root.pane = 1;
                            root.rowIndex = settingRow.index;
                            if (settingRow.kind === "cycle") root.adjust(1);
                            else root.activate();
                        }
                    }
                }
            }
        }
    }

    // ---- inline feedback: loading, success and error stay inside the shell ----
    Rectangle {
        id: pill
        readonly property bool shown: root.statusText !== ""
        x: 58 - (shown ? 0 : 10)
        y: 696
        width: Math.min(520, Math.max(260, pillRow.implicitWidth + 44))
        height: 30
        radius: 15
        visible: opacity > 0.01
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.96
        transformOrigin: Item.Left
        color: Theme.glassHi
        border.width: 1
        border.color: Theme.glassBorder
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Row {
            id: pillRow
            anchors.centerIn: parent
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

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 68
        y: parent.height - 43
        spacing: 24
        KeyHint { keyLabel: "↑ ↓"; description: "Navigate" }
        KeyHint { keyLabel: "← →"; description: "Select / Adjust" }
        KeyHint { keyLabel: "Enter"; description: "Open / Apply" }
        KeyHint { keyLabel: "Esc"; description: "Back" }
    }
}
