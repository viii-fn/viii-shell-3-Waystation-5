import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Networking
import "../core"

// Full-screen PS5-inspired settings surface. It deliberately leaves the existing wallpaper visible;
// all colour comes from the active Matugen wallpaper palette through Theme.
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
            duration: root.active ? 620 : 360
            easing.type: Easing.OutCubic
        }
    }
    property real contentT: 1
    property real contentOffset: 0
    property int categoryIndex: 0
    property int rowIndex: 0
    property int pane: 0                 // 0 = categories, 1 = settings
    property string armed: ""

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
    property bool passwordPrompt: false
    property string wifiPassword: ""
    property var pendingNetwork: null
    property var pendingBluetooth: null
    property bool networkBusy: false

    readonly property var currentCategory: categories[categoryIndex]
    readonly property var currentRows: rowsForCategory()
    onCurrentRowsChanged: rowIndex = Math.max(0, Math.min(rowIndex, currentRows.length - 1))

    PwObjectTracker { objects: [root.sink, root.source].filter(n => n !== null) }

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
    SequentialAnimation {
        id: contentTransition
        NumberAnimation { target: root; property: "contentT"; to: 0; duration: 90; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "contentOffset"; to: 18; duration: 1 }
        NumberAnimation { target: root; property: "contentOffset"; to: 0; duration: 280; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "contentT"; to: 1; duration: 300; easing.type: Easing.OutCubic }
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
        case "volume": return sink && sink.audio ? Math.round(sink.audio.volume * 100) + "%" : "Unavailable";
        case "mute": return sink && sink.audio ? (sink.audio.muted ? "Muted" : "On") : "Unavailable";
        case "audio-output": return sink ? (sink.description || sink.name || "Default output") : "No output detected";
        case "audio-input": return source ? (source.description || source.name || "Default input") : "No input detected";
        case "brightness": return Desk.brightness >= 0 ? Desk.brightness + "%" : "Unavailable";
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
        default: return "";
        }
    }

    function setStatus(message, kind) {
        statusText = message;
        statusKind = kind || "info";
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
        categoryIndex = next;
        rowIndex = 0;
        pane = 0;
        armed = "";
        contentTransition.restart();
        if (wifiDevice) wifiDevice.scannerEnabled = active && categoryIndex === 1;
        if (adapter && categoryIndex !== 4) adapter.discovering = false;
        if (categoryIndex === 1 && wifiDevice) refreshWifi();
    }

    function setSliderAt(action, fraction) {
        const value = Math.max(0, Math.min(1, fraction));
        if (action === "volume" && sink && sink.audio) {
            sink.audio.volume = value;
            setStatus("Output volume · " + Math.round(value * 100) + "%", "info");
        } else if (action === "brightness" && Desk.brightness >= 0) {
            const target = Math.max(1, Math.min(100, Math.round(value * 100)));
            Desk.briStep(target - Desk.brightness);
        }
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
        const row = currentRows[rowIndex];
        if (!row) return;
        if (row.action === "volume" && sink && sink.audio)
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + 0.05 * delta));
        else if (row.action === "brightness")
            Desk.briStep(5 * delta);
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
            if (pane === 0) selectCategory(categoryIndex - 1);
            else rowIndex = Math.max(0, rowIndex - 1);
            armed = "";
            if (statusText.indexOf("Press Enter again") === 0) { statusText = ""; statusTimer.stop(); }
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            if (pane === 0) selectCategory(categoryIndex + 1);
            else rowIndex = Math.min(currentRows.length - 1, rowIndex + 1);
            armed = "";
            if (statusText.indexOf("Press Enter again") === 0) { statusText = ""; statusTimer.stop(); }
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
            else rowIndex = currentRows.length - 1;
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
            refreshDetails();
            forceActiveFocus();
        } else {
            passwordPrompt = false;
            networkBusy = false;
            connectionTimer.stop();
            bluetoothTimer.stop();
            if (wifiDevice) wifiDevice.scannerEnabled = false;
            scanTimer.stop();
            if (adapter) adapter.discovering = false;
        }
    }
    onCategoryIndexChanged: {
        if (wifiDevice) wifiDevice.scannerEnabled = active && categoryIndex === 1;
    }
    Component.onCompleted: if (active) refreshDetails()

    // Wallpaper remains visible beneath the animated, Matugen-tinted Settings surface.
    opacity: reveal
    y: (1 - reveal) * 26
    scale: 0.985 + 0.015 * reveal
    visible: active || reveal > 0.01

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.78)
        opacity: reveal
        Behavior on opacity { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        opacity: reveal
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.26) }
            GradientStop { position: 1.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.68) }
        }
    }

    SettingsText {
        x: 66 - (1 - root.reveal) * 24; y: 40
        opacity: root.reveal
        text: "Settings"
        font.pixelSize: 38
        font.weight: Font.Bold
    }
    SettingsText {
        anchors.right: parent.right
        anchors.rightMargin: 68
        y: 56
        opacity: root.reveal
        text: "SYSTEM CONFIGURATION"
        font.pixelSize: 12
        font.letterSpacing: 2
        color: Theme.fgDim
    }

    // Left category rail.
    Rectangle {
        x: 58 - (1 - root.reveal) * 34; y: 126
        width: 326; height: 560
        opacity: root.reveal
        radius: 20
        color: Theme.glass
        border.width: 1
        border.color: Theme.glassBorder
    }
    Rectangle {
        x: 72
        y: 140 + root.categoryIndex * 46
        width: 298; height: 44
        radius: 11
        color: Theme.glassHi
        border.width: root.pane === 0 ? 1 : 0
        border.color: Theme.glassBorder
        opacity: root.reveal
        Behavior on y { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Behavior on border.width { NumberAnimation { duration: 180 } }
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
                x: (1 - root.reveal) * 18
                opacity: Math.max(0, Math.min(1, (root.reveal - index * 0.028) * 1.8))
                readonly property bool selected: root.categoryIndex === index
                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: catArea.containsMouse && !cat.selected ? Theme.glass : "transparent"
                    border.width: 0
                    border.color: Theme.glassBorder
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                Text {
                    x: 13; anchors.verticalCenter: parent.verticalCenter
                    text: cat.modelData.icon
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                    color: cat.selected ? Theme.fg : Theme.fgDim
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

    // Right-hand settings panel.
    SettingsText {
        x: 420 + (1 - root.contentT) * 18 + root.contentOffset; y: 132
        opacity: root.reveal * root.contentT
        text: root.currentCategory.title
        font.pixelSize: 28
        font.weight: Font.DemiBold
    }
    SettingsText {
        x: 420 + (1 - root.contentT) * 18 + root.contentOffset; y: 174
        opacity: root.reveal * root.contentT
        width: 850
        text: root.currentCategory.description
        font.pixelSize: 14
        color: Theme.fgDim
    }

    Rectangle {
        x: 408 + (1 - root.contentT) * 18 + root.contentOffset; y: 210
        width: 900; height: 476
        opacity: root.reveal * root.contentT
        radius: 20
        color: Theme.glass
        border.width: 1
        border.color: Theme.glassBorder
    }

    Rectangle {
        x: 424
        y: 226 + root.rowIndex * 77
        width: 868; height: 74
        radius: 12
        color: Theme.glassHi
        border.width: root.pane === 1 ? 1 : 0
        border.color: Theme.glassBorder
        opacity: root.reveal * root.contentT
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on border.width { NumberAnimation { duration: 160 } }
    }
    Column {
        x: 424 + (1 - root.contentT) * 18 + root.contentOffset
        y: 226
        width: 868
        spacing: 3
        opacity: root.reveal * root.contentT
        Repeater {
            model: root.currentRows
            delegate: Item {
                id: settingRow
                required property var modelData
                required property int index
                width: 868
                height: 74
                x: (1 - root.contentT) * 12
                opacity: root.reveal * root.contentT
                readonly property bool selected: root.rowIndex === index && root.pane === 1
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: rowArea.containsMouse && !settingRow.selected ? Theme.glass : "transparent"
                    border.width: 0
                    border.color: Theme.glassBorder
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                Column {
                    x: 20
                    anchors.verticalCenter: parent.verticalCenter
                    width: 540
                    spacing: 5
                    SettingsText {
                        width: parent.width
                        text: settingRow.modelData.title
                        font.pixelSize: 17
                        font.weight: settingRow.selected ? Font.DemiBold : Font.Medium
                    }
                    SettingsText {
                        width: parent.width
                        text: settingRow.modelData.desc
                        font.pixelSize: 12
                        color: Theme.fgDim
                    }
                }
                SettingsText {
                    anchors.right: parent.right
                    anchors.rightMargin: 48
                    anchors.verticalCenter: parent.verticalCenter
                    width: 230
                    text: root.valueFor(settingRow.modelData.action)
                    visible: settingRow.modelData.kind !== "toggle"
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 14
                    color: settingRow.selected ? Theme.fg : Theme.fgDim
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 50
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 24
                    radius: 12
                    visible: settingRow.modelData.kind === "toggle"
                    color: root.toggleOn(settingRow.modelData.action) ? Theme.accent : Theme.glassHi
                    border.width: 1
                    border.color: Theme.glassBorder
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Rectangle {
                        y: 3
                        x: root.toggleOn(settingRow.modelData.action) ? 23 : 3
                        width: 18; height: 18
                        radius: 9
                        color: root.toggleOn(settingRow.modelData.action) ? Theme.accentText : Theme.fgDim
                        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 48
                    y: 55
                    width: 112
                    height: 3
                    radius: 2
                    visible: settingRow.modelData.action === "volume" || settingRow.modelData.action === "brightness"
                    color: Theme.glassHi
                    Rectangle {
                        height: parent.height
                        radius: 2
                        width: parent.width * (settingRow.modelData.action === "volume"
                            ? (root.sink && root.sink.audio ? Math.max(0, Math.min(1, root.sink.audio.volume)) : 0)
                            : (Desk.brightness >= 0 ? Desk.brightness / 100 : 0))
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        z: 2
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: {
                            root.pane = 1;
                            root.rowIndex = settingRow.index;
                            root.setSliderAt(settingRow.modelData.action, mouse.x / width);
                        }
                        onPositionChanged: if (pressed)
                            root.setSliderAt(settingRow.modelData.action, mouse.x / width)
                    }
                }
                SettingsText {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: settingRow.modelData.kind === "action" ? "›"
                        : ((settingRow.modelData.kind === "cycle" || settingRow.modelData.kind === "slider") && settingRow.selected ? "‹ ›" : "")
                    font.pixelSize: settingRow.modelData.kind === "action" ? 25 : 13
                    color: Theme.fgDim
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
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.pane = 1;
                        root.rowIndex = settingRow.index;
                        if (settingRow.modelData.kind === "cycle") root.adjust(1);
                        else root.activate();
                    }
                }
            }
        }
    }

    // Inline feedback keeps loading, success and error states inside the shell.
    Rectangle {
        x: 58; y: root.statusText !== "" ? 694 : 700
        width: Math.min(500, Math.max(300, statusLabel.implicitWidth + 54))
        height: 30
        radius: 17
        visible: root.statusText !== "" || opacity > 0.01
        opacity: root.statusText !== "" ? root.reveal : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        color: Theme.glassHi
        border.width: 1
        border.color: Theme.glassBorder
        Row {
            anchors.centerIn: parent
            spacing: 10
            SettingsText {
                text: root.statusKind === "error" ? "!" : (root.statusKind === "success" ? "✓" : "◌")
                font.pixelSize: 15
                font.weight: Font.Bold
                color: Theme.accent
                NumberAnimation on rotation {
                    from: 0; to: 360; duration: 850
                    loops: Animation.Infinite
                    running: root.statusKind === "loading" && root.statusText !== ""
                }
            }
            SettingsText {
                id: statusLabel
                width: Math.min(430, implicitWidth)
                text: root.statusText
                font.pixelSize: 13
                color: Theme.fg
            }
        }
    }

    // Wi-Fi credentials are entered here; no terminal or external connection editor is opened.
    Rectangle {
        anchors.fill: parent
        z: 20
        visible: root.passwordPrompt
        color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.58)
    }
    Rectangle {
        anchors.centerIn: parent
        z: 21
        width: 480; height: 260
        radius: 24
        color: Theme.deep
        border.width: 1
        border.color: Theme.glassBorder
        visible: root.passwordPrompt
        opacity: visible ? 1 : 0
        scale: visible ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
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
