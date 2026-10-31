import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "../core"

// Full-screen PS5-inspired settings surface. It deliberately leaves the existing wallpaper visible;
// all colour comes from the active Matugen wallpaper palette through Theme.
Item {
    id: root

    signal closeRequested()
    signal wallstoreRequested()
    signal libraryRequested()

    property bool active: false
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
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool wifiConnected: wifiName.length > 0
    property bool wifiOn: false
    property string wifiName: ""
    property string storageText: "Checking storage…"
    property string kernelText: "Checking kernel…"

    readonly property var currentCategory: categories[categoryIndex]
    readonly property var currentRows: rowsForCategory()

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

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
        case 1: return [
            { title: "Wi-Fi", desc: "Turn the wireless radio on or off", action: "wifi", kind: "toggle" },
            { title: "Active connection", desc: "Currently connected wireless network", action: "network-info", kind: "info" },
            { title: "Manage connections", desc: "Open the NetworkManager connection editor", action: "nmtui", kind: "action" }
        ];
        case 2: return [
            { title: "Output volume", desc: "Adjust the default audio output level", action: "volume", kind: "slider" },
            { title: "Mute audio", desc: "Mute or unmute the default output", action: "mute", kind: "toggle" },
            { title: "Output device", desc: "Current default PipeWire output", action: "audio-output", kind: "info" }
        ];
        case 3: return [
            { title: "Screen brightness", desc: "Adjust the built-in display backlight", action: "brightness", kind: "slider" },
            { title: "Display configuration", desc: "Arrange displays, resolution and scaling", action: "displays", kind: "action" },
            { title: "Desktop session", desc: "Current compositor and display protocol", action: "session", kind: "info" }
        ];
        case 4: return [
            { title: "Bluetooth", desc: "Turn Bluetooth on or off", action: "bluetooth", kind: "toggle" },
            { title: "Cursor theme", desc: "Current cursor theme, when exported by the session", action: "cursor", kind: "info" },
            { title: "Keyboard layout", desc: "Keyboard layout environment variable", action: "keyboard", kind: "info" }
        ];
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
            { title: "File manager", desc: "Browse disks and mounted locations", action: "filemanager", kind: "action" }
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
            { title: "App library", desc: "Browse applications installed on this computer", action: "library", kind: "action" },
            { title: "Package manager", desc: "Open yay in a terminal", action: "packages", kind: "action" },
            { title: "File manager", desc: "Open PCManFM", action: "filemanager", kind: "action" }
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
        switch (action) {
        case "wifi": return wifiOn ? "On" : "Off";
        case "network-info": return wifiName || (wifiOn ? "Not connected" : "Wi-Fi off");
        case "volume": return sink && sink.audio ? Math.round(sink.audio.volume * 100) + "%" : "Unavailable";
        case "mute": return sink && sink.audio ? (sink.audio.muted ? "Muted" : "On") : "Unavailable";
        case "audio-output": return sink ? "Default output active" : "No output detected";
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

    function refreshWifi() { wifiProc.running = true; }

    function wifiParsed(text) {
        const lines = text.trim().split("\n");
        wifiOn = (lines[0] || "").trim() === "enabled";
        const active = (lines[1] || "").trim();
        const splitAt = active.indexOf(":");
        wifiName = splitAt >= 0 ? active.slice(splitAt + 1).replace(/\\:/g, ":") : "";
    }

    function selectCategory(index) {
        categoryIndex = Math.max(0, Math.min(categories.length - 1, index));
        rowIndex = 0;
        pane = 0;
        armed = "";
    }

    function adjust(delta) {
        const row = currentRows[rowIndex];
        if (!row) return;
        if (row.action === "volume" && sink && sink.audio)
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + 0.05 * delta));
        else if (row.action === "brightness")
            Desk.briStep(5 * delta);
    }

    function runPower(action) {
        if (action === "restart" || action === "poweroff") {
            if (armed !== action) { armed = action; armTimer.restart(); return; }
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
        switch (row.action) {
        case "wifi":
            Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "off" : "on"]);
            wifiOn = !wifiOn;
            wifiTimer.restart();
            break;
        case "mute":
            if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
            break;
        case "bluetooth":
            if (adapter) adapter.enabled = !adapter.enabled;
            break;
        case "nmtui":
            Quickshell.execDetached(["kitty", "-e", "nmtui"]);
            break;
        case "displays":
            Quickshell.execDetached(["nwg-displays"]);
            break;
        case "wallpaper":
            wallstoreRequested();
            break;
        case "library":
            libraryRequested();
            break;
        case "packages":
            Quickshell.execDetached(["kitty", "-e", "yay"]);
            break;
        case "filemanager":
            Quickshell.execDetached(["pcmanfm"]);
            break;
        case "lock": case "suspend": case "restart": case "poweroff":
            runPower(row.action);
            break;
        }
    }

    function handleKey(event) {
        let handled = true;
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Back:
            closeRequested();
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            if (pane === 1 && currentRows[rowIndex] && currentRows[rowIndex].kind === "slider")
                adjust(-1);
            else if (pane === 1) pane = 0;
            else closeRequested();
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            if (pane === 0) pane = 1;
            else if (currentRows[rowIndex] && currentRows[rowIndex].kind === "slider")
                adjust(1);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            if (pane === 0) selectCategory(categoryIndex - 1);
            else rowIndex = Math.max(0, rowIndex - 1);
            armed = "";
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            if (pane === 0) selectCategory(categoryIndex + 1);
            else rowIndex = Math.min(currentRows.length - 1, rowIndex + 1);
            armed = "";
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (pane === 0) pane = 1;
            else activate();
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
        id: wifiProc
        command: ["sh", "-c", "nmcli -t -f WIFI g; nmcli -t -f TYPE,NAME connection show --active | grep '^802-11-wireless' | head -n1"]
        stdout: StdioCollector { onStreamFinished: root.wifiParsed(this.text) }
    }
    Timer { id: wifiTimer; interval: 5000; repeat: true; running: root.active; onTriggered: root.refreshWifi() }
    Timer { id: armTimer; interval: 3500; onTriggered: root.armed = "" }
    Process {
        id: storageProc
        command: ["sh", "-c", "df -h / | awk 'NR==2 {print $3 \" used of \" $2 \" (\" $5 \")\"}'"]
        stdout: StdioCollector { onStreamFinished: root.storageText = this.text.trim() || "Unavailable" }
    }
    Process {
        id: kernelProc
        command: ["uname", "-r"]
        stdout: StdioCollector { onStreamFinished: root.kernelText = this.text.trim() || "Unavailable" }
    }

    function refreshDetails() {
        refreshWifi();
        storageProc.running = true;
        kernelProc.running = true;
        Desk.briRefresh();
    }

    onActiveChanged: if (active) refreshDetails()
    Component.onCompleted: if (active) refreshDetails()

    // Wallpaper remains visible beneath this restrained translucent surface.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.78)
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.26) }
            GradientStop { position: 1.0; color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.68) }
        }
    }

    SettingsText {
        x: 66; y: 40
        text: "Settings"
        font.pixelSize: 38
        font.weight: Font.Bold
    }
    SettingsText {
        anchors.right: parent.right
        anchors.rightMargin: 68
        y: 56
        text: "SYSTEM CONFIGURATION"
        font.pixelSize: 12
        font.letterSpacing: 2
        color: Theme.fgDim
    }

    // Left category rail.
    Rectangle {
        x: 58; y: 126
        width: 326; height: 560
        radius: 20
        color: Theme.glass
        border.width: 1
        border.color: Theme.glassBorder
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
                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: cat.selected ? Theme.glassHi : "transparent"
                    border.width: cat.selected && root.pane === 0 ? 1 : 0
                    border.color: Theme.glassBorder
                }
                Text {
                    x: 13; anchors.verticalCenter: parent.verticalCenter
                    text: cat.modelData.icon
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                    color: cat.selected ? Theme.fg : Theme.fgDim
                }
                SettingsText {
                    x: 46; anchors.verticalCenter: parent.verticalCenter
                    width: 236
                    text: cat.modelData.title
                    font.pixelSize: 16
                    font.weight: cat.selected ? Font.DemiBold : Font.Medium
                    color: cat.selected ? Theme.fg : Theme.fgDim
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.selectCategory(cat.index)
                }
            }
        }
    }

    // Right-hand settings panel.
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

    Column {
        x: 424; y: 226
        width: 868
        spacing: 3
        Repeater {
            model: root.currentRows
            delegate: Item {
                id: settingRow
                required property var modelData
                required property int index
                width: 868
                height: 74
                readonly property bool selected: root.rowIndex === index && root.pane === 1
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: settingRow.selected ? Theme.glassHi : "transparent"
                    border.width: settingRow.selected ? 1 : 0
                    border.color: Theme.glassBorder
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
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 14
                    color: settingRow.selected ? Theme.fg : Theme.fgDim
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
                    }
                }
                SettingsText {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: settingRow.modelData.kind === "action" ? "›" : (settingRow.selected ? "‹ ›" : "")
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
                    anchors.fill: parent
                    onClicked: {
                        root.pane = 1;
                        root.rowIndex = settingRow.index;
                        root.activate();
                    }
                }
            }
        }
    }

    // A second press is required before destructive power actions run.
    SettingsText {
        x: 420; y: 658
        visible: root.armed !== ""
        text: "Press Enter again to confirm " + (root.armed === "poweroff" ? "shut down" : "restart")
        font.pixelSize: 13
        color: Theme.accent
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 68
        y: parent.height - 43
        spacing: 24
        KeyHint { keyLabel: "↑ ↓"; description: "Navigate" }
        KeyHint { keyLabel: "← →"; description: "Categories / Adjust" }
        KeyHint { keyLabel: "Enter"; description: "Select" }
        KeyHint { keyLabel: "Esc"; description: "Back" }
    }
}
