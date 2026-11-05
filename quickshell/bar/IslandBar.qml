// viii-island-bar-v1
// A small, floating Dynamic Island that replaces the old Waybar presentation.
// Compact at rest; expands on hover or when pinned. The ring and diagonal shade
// are the real shared viii GlassRing / Shade implementation, not a second effect.
// No blur, ShaderEffect, MultiEffect, layer cache, polling loop or background process.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Networking
import "../core"
import "../hub"

PanelWindow {
    id: win

    // A transparent top overlay. The mask limits input to the island itself, so
    // the rest of this full-width layer surface remains click-through.
    anchors { top: true; left: true; right: true }
    implicitHeight: Math.round(140 * win.s)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "viii-island"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: hitbox }

    readonly property real s: screen
        ? Math.max(0.76, Math.min(1.22, screen.width / 1366, screen.height / 768))
        : 1
    readonly property real compactW: 470 * s
    readonly property real fullW: Math.min(Math.max(0, width - 28 * s), 820 * s)

    // On an empty workspace the PS5 hub already owns the top of the screen.
    // The island returns when a normal desktop is visible again.
    readonly property bool desktopActive: !!screen
        && !Desk.isEmpty(screen.name)
        && !Desk.summoned
        && !Desk.ccOpen
    property real revealT: desktopActive ? 1 : 0
    Behavior on revealT {
        NumberAnimation {
            duration: win.desktopActive ? Motion.reveal : Motion.hide
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.desktopActive ? Motion.out : Motion.inOut
        }
    }
    visible: desktopActive || revealT > 0.002

    // Hover expands the island. Clicking pins it open; SUPER+ALT+I toggles the pin.
    property bool pinned: false
    property bool hoverOpen: false
    readonly property bool expanded: pinned || hoverOpen
    property real expandT: expanded ? 1 : 0
    Behavior on expandT {
        NumberAnimation {
            duration: Motion.focus + 70
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.out
        }
    }

    readonly property var focusedMonitor: Hyprland.focusedMonitor
    readonly property bool isFocusedMonitor: focusedMonitor
        ? focusedMonitor.name === screen.name : true

    // NetworkManager: derive the active adapter and network from the same model
    // already used by Settings and Welcome; there is no nmcli polling here.
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
    readonly property var activeNetwork: {
        const networks = wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : [];
        for (let i = 0; i < networks.length; i++)
            if (networks[i].connected) return networks[i];
        return null;
    }
    readonly property bool online: activeNetwork !== null || wiredDevice !== null
    readonly property string networkName: activeNetwork
        ? activeNetwork.name
        : (wiredDevice ? (wiredDevice.name || "Ethernet") : (Networking.wifiEnabled ? "Offline" : "Wi-Fi off"))
    readonly property string networkGlyph: wiredDevice && !activeNetwork
        ? "\uf0e8" : (online ? "\uf1eb" : "\uf071")

    // UPower is event-driven. The percentage remains hidden on desktops without a battery.
    readonly property real batteryPct: UPower.displayDevice ? UPower.displayDevice.percentage : -1
    readonly property bool batteryCharging: !!UPower.displayDevice
        && (UPower.displayDevice.state === UPowerDeviceState.Charging
            || UPower.displayDevice.state === UPowerDeviceState.FullyCharged
            || UPower.displayDevice.state === UPowerDeviceState.PendingCharge)
    readonly property string batteryGlyph: batteryCharging ? "\uf0e7"
        : (batteryPct >= 0.80 ? "\uf240"
        : (batteryPct >= 0.60 ? "\uf241"
        : (batteryPct >= 0.40 ? "\uf242"
        : (batteryPct >= 0.20 ? "\uf243" : "\uf244"))))

    // MPRIS: prefer the currently playing player, otherwise the first available player.
    readonly property var player: {
        const all = Mpris.players ? Mpris.players.values : [];
        for (let i = 0; i < all.length; i++) if (all[i].isPlaying) return all[i];
        return all.length > 0 ? all[0] : null;
    }
    readonly property string playerTitle: player
        ? String(player.title || player.identity || "Now playing") : "viii"
    readonly property string playerArtist: player
        ? String(player.artist || player.identity || "") : "SYSTEM READY"
    readonly property string playerGlyph: player && player.isPlaying ? "\uf04c" : "\uf04b"

    // Native window list, ordered with the last focused app first. Icons are decoded
    // at a deliberately small source size to keep the bar inexpensive on 2 GB RAM.
    readonly property var windowList: {
        const all = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : [];
        const last = Desk.lastActive;
        const ordered = [];
        if (last && all.indexOf(last) >= 0) ordered.push(last);
        for (let i = 0; i < all.length; i++)
            if (all[i] !== last) ordered.push(all[i]);
        return ordered.slice(0, 5);
    }
    function iconFor(tl) {
        if (!tl || !tl.appId) return "";
        return Quickshell.iconPath(String(tl.appId).toLowerCase(), true);
    }
    function focusWindow(tl) {
        if (tl && tl.activate) tl.activate();
    }
    readonly property var monitorInfo: {
        const monitors = Hyprland.monitors.values;
        for (let i = 0; i < monitors.length; i++)
            if (screen && monitors[i].name === screen.name) return monitors[i];
        return null;
    }
    readonly property string workspaceLabel: monitorInfo && monitorInfo.activeWorkspace
        ? String(monitorInfo.activeWorkspace.id) : "—"
    readonly property string activeTitle: Desk.lastActive
        ? String(Desk.lastActive.title || Desk.lastActive.appId || "Application") : "Desktop"

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // One fixed-size design canvas. The surface morphs with Scale transforms rather
    // than animating width/height, and the text stays crisp because it is not scaled.
    Item {
        id: stage
        anchors.fill: parent
        opacity: win.revealT

        // This transformed item is both the glass body and the input-mask geometry.
        // Horizontal and vertical scale are animated from the compact capsule to the
        // expanded two-row island; the full content layer below never gets stretched.
        Item {
            id: hitbox
            x: (parent.width - width) / 2
            y: 7 * win.s
            width: win.fullW
            height: 116 * win.s
            transform: Scale {
                origin.x: hitbox.width / 2
                origin.y: 0
                xScale: 0.56 + 0.44 * win.expandT
                yScale: 0.45 + 0.55 * win.expandT
                Behavior on xScale {
                    NumberAnimation { duration: Motion.focus + 70; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                }
                Behavior on yScale {
                    NumberAnimation { duration: Motion.focus + 70; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                }
            }

            GlassSlot {
                anchors.fill: parent
                radius: 30 * win.s
                bottomLeft: Qt.alpha(Theme.mid, 0.97)
                topRight: Qt.alpha(Theme.deep, 0.99)
                edge: Theme.glassBorder
            }

            MouseArea {
                id: islandMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    collapseTimer.stop();
                    win.hoverOpen = true;
                }
                onExited: collapseTimer.restart()
                onClicked: win.pinned = !win.pinned
            }
        }

        // Left status group: icons in compact mode; readable network and battery
        // details appear as the capsule opens.
        Item {
            id: statusGroup
            x: hitbox.x + ((hitbox.width - win.compactW) / 2) * (1 - win.expandT) + 18 * win.s
            y: hitbox.y + 12 * win.s
            width: 190 * win.s
            height: 34 * win.s
            z: 12

            Text {
                x: 0; y: 5 * win.s
                width: 22 * win.s; height: 24 * win.s
                text: win.networkGlyph
                color: win.online ? Theme.fg : Theme.fgDim
                font.family: Theme.iconFont
                font.pixelSize: 18 * win.s
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                x: 25 * win.s; y: 7 * win.s
                width: 108 * win.s; height: 20 * win.s
                text: win.networkName
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 12 * win.s
                elide: Text.ElideRight
                opacity: win.expandT
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            Text {
                id: batteryIcon
                x: (34 + 105 * win.expandT) * win.s
                y: 5 * win.s
                width: 22 * win.s; height: 24 * win.s
                text: win.batteryGlyph
                color: win.batteryPct >= 0 && win.batteryPct < 0.15 ? "#ff7777" : Theme.fg
                font.family: Theme.iconFont
                font.pixelSize: 18 * win.s
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Behavior on x { NumberAnimation { duration: Motion.focus; easing.type: Easing.OutCubic } }
            }
            Text {
                x: (58 + 105 * win.expandT) * win.s
                y: 7 * win.s
                width: 38 * win.s; height: 20 * win.s
                text: win.batteryPct >= 0 ? Math.round(win.batteryPct * 100) + "%" : ""
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 12 * win.s
                opacity: win.expandT
                visible: opacity > 0.01 && win.batteryPct >= 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: { win.pinned = true; Desk.ccOpen = true; }
            }
        }

        // Media controls and title take the centre. Previous/next unfold with the bar;
        // play/pause remains available even in the compact state.
        Item {
            id: mediaGroup
            x: hitbox.x + (hitbox.width - width) / 2
            y: hitbox.y + 11 * win.s
            width: (210 + 170 * win.expandT) * win.s
            height: 38 * win.s
            z: 13

            Row {
                anchors.centerIn: parent
                spacing: 7 * win.s

                Item {
                    width: win.expandT > 0.25 && win.player ? 22 * win.s : 0
                    height: 28 * win.s
                    visible: width > 0
                    opacity: win.expandT
                    Text {
                        anchors.centerIn: parent
                        text: "\uf04a"
                        color: Theme.fgDim
                        font.family: Theme.iconFont
                        font.pixelSize: 15 * win.s
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (win.player && win.player.canGoPrevious) win.player.previous()
                    }
                }

                Item {
                    width: 26 * win.s
                    height: 28 * win.s
                    Text {
                        anchors.centerIn: parent
                        text: win.player ? win.playerGlyph : "\uf001"
                        color: Theme.fg
                        font.family: Theme.iconFont
                        font.pixelSize: 16 * win.s
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !!win.player && win.player.canTogglePlaying
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (win.player && win.player.canTogglePlaying) win.player.togglePlaying()
                    }
                }

                Item {
                    width: win.expandT > 0.25 && win.player ? 22 * win.s : 0
                    height: 28 * win.s
                    visible: width > 0
                    opacity: win.expandT
                    Text {
                        anchors.centerIn: parent
                        text: "\uf04e"
                        color: Theme.fgDim
                        font.family: Theme.iconFont
                        font.pixelSize: 15 * win.s
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (win.player && win.player.canGoNext) win.player.next()
                    }
                }

                Text {
                    width: (win.player ? (135 + 125 * win.expandT) : 112) * win.s
                    height: 28 * win.s
                    text: win.playerTitle
                    color: win.player ? Theme.fg : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 13 * win.s
                    font.weight: win.player && win.player.isPlaying ? Font.DemiBold : Font.Medium
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }

        // Clock stays on the right edge of the compact capsule and glides outward
        // as the island grows. Date and the small chevron only show in expanded mode.
        Item {
            id: clockGroup
            width: 126 * win.s
            height: 40 * win.s
            x: hitbox.x
                + ((hitbox.width - win.compactW) / 2) * (1 - win.expandT)
                + (win.compactW - width - 18 * win.s) * (1 - win.expandT)
                + (hitbox.width - width - 18 * win.s) * win.expandT
            y: hitbox.y + 6 * win.s
            z: 12

            Text {
                x: 0; y: 0
                width: 80 * win.s; height: 26 * win.s
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 21 * win.s
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                x: 0; y: 25 * win.s
                width: 94 * win.s; height: 17 * win.s
                text: Qt.formatDateTime(clock.date, "ddd, dd MMM")
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 10 * win.s
                opacity: win.expandT
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            Text {
                x: 96 * win.s; y: 6 * win.s
                width: 20 * win.s; height: 22 * win.s
                text: "\uf078"
                color: Theme.fgDim
                font.family: Theme.iconFont
                font.pixelSize: 12 * win.s
                rotation: win.expanded ? 180 : 0
                opacity: win.expandT
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on rotation { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: Desk.ccOpen = true
            }
        }

        // Expanded detail row: current workspace and focused window at left, then
        // a compact native taskbar of open-window icons and a Control Center action.
        Item {
            id: detailRow
            x: hitbox.x + 18 * win.s
            y: hitbox.y + 70 * win.s
            width: hitbox.width - 36 * win.s
            height: 32 * win.s
            opacity: win.expandT
            visible: opacity > 0.01
            z: 12
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Rectangle {
                x: 0; y: 0
                width: 34 * win.s; height: 24 * win.s
                radius: 8 * win.s
                color: Theme.glassHi
                border.width: 1
                border.color: Theme.glassBorder
            }
            Text {
                x: 0; y: 0
                width: 34 * win.s; height: 24 * win.s
                text: win.workspaceLabel
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 12 * win.s
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                x: 46 * win.s; y: 1 * win.s
                width: Math.max(80, 300 - win.windowList.length * 28) * win.s
                height: 22 * win.s
                text: win.activeTitle
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 12 * win.s
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Row {
                id: taskbar
                anchors.right: parent.right
                anchors.rightMargin: 42 * win.s
                y: 0
                spacing: 5 * win.s

                Repeater {
                    model: win.windowList
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: 26 * win.s
                        height: 26 * win.s

                        Rectangle {
                            anchors.fill: parent
                            radius: 8 * win.s
                            color: modelData === Desk.lastActive ? Theme.glassHi : "transparent"
                            border.width: modelData === Desk.lastActive ? 1 : 0
                            border.color: Theme.glassBorder
                        }
                        Image {
                            id: appIcon
                            anchors.centerIn: parent
                            width: 19 * win.s
                            height: 19 * win.s
                            source: win.iconFor(modelData)
                            sourceSize.width: 38
                            sourceSize.height: 38
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData && modelData.appId
                                ? String(modelData.appId).charAt(0).toUpperCase() : "•"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12 * win.s
                            visible: appIcon.status !== Image.Ready
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.focusWindow(modelData)
                        }
                    }
                }
            }

            Item {
                x: parent.width - 30 * win.s
                y: 0
                width: 28 * win.s
                height: 26 * win.s
                Text {
                    anchors.centerIn: parent
                    text: "\uf013"
                    color: Theme.fg
                    font.family: Theme.iconFont
                    font.pixelSize: 16 * win.s
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { win.pinned = false; Desk.ccOpen = true; }
                }
            }
        }

        // The actual viii ring is last so its shared diagonal shade overlays both
        // content rows. It claims the one global Shade clock only while visible.
        GlassRing {
            id: islandRing
            x: hitbox.x - 4 * win.s
            y: hitbox.y - 4 * win.s
            width: hitbox.width + 8 * win.s
            height: hitbox.height + 8 * win.s
            transform: Scale {
                origin.x: islandRing.width / 2
                origin.y: 4 * win.s
                xScale: 0.56 + 0.44 * win.expandT
                yScale: 0.45 + 0.55 * win.expandT
                Behavior on xScale {
                    NumberAnimation { duration: Motion.focus + 70; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                }
                Behavior on yScale {
                    NumberAnimation { duration: Motion.focus + 70; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.out }
                }
            }
            radius: 34 * win.s
            thickness: 2.5 * win.s
            shade: true
            animated: win.revealT > 0.01
            visible: win.revealT > 0.01
            opacity: win.revealT
            z: 30
        }
    }

    Timer {
        id: collapseTimer
        interval: 420
        repeat: false
        onTriggered: if (!win.pinned && !islandMouse.containsMouse) win.hoverOpen = false
    }

    Connections {
        target: Desk
        function onIslandToggleRequested() {
            if (!win.isFocusedMonitor) return;
            win.pinned = !win.pinned;
            win.hoverOpen = win.pinned;
        }
    }

    onDesktopActiveChanged: {
        if (!desktopActive) {
            pinned = false;
            hoverOpen = false;
        }
    }
}
