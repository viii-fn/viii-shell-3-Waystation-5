import QtQuick
import Quickshell
import Quickshell.Hyprland
import "core"
import "hub"
import "cc"
import "wall"
import "notif"
import "shot"

// viii-shell-3 entry point. Run with:  qs -c viii   (or: viii start)
ShellRoot {
    // exactly one ThemeDriver (it glides the Theme colours)
    ThemeDriver {}

    // exactly one ShadeDriver (the shared GlassRing shade interval)
    ShadeDriver {}

    // the wallpaper (drawn here, so it always matches the palette)
    Variants {
        model: Quickshell.screens
        WallpaperLayer {
            required property var modelData
            screen: modelData
        }
    }

    // one hub window per monitor
    Variants {
        model: Quickshell.screens
        Hub {
            required property var modelData
            screen: modelData
        }
    }

    // Control Center (PS button tap). Content only loads while it is open.
    Variants {
        model: Quickshell.screens
        ControlCenter {
            required property var modelData
            screen: modelData
        }
    }

    // brightness pop-up for the brightness keys
    Variants {
        model: Quickshell.screens
        Osd {
            required property var modelData
            screen: modelData
        }
    }

    // Notifications: this shell is the notification daemon (core/Notifs.qml). Toasts and charger events pop up top-centre.
    Variants {
        model: Quickshell.screens
        NotifPopup {
            required property var modelData
            screen: modelData
        }
    }

    // Screenshot pane (Print key): one window per monitor, hidden until the key is pressed.
    Variants {
        model: Quickshell.screens
        ShotPane {
            required property var modelData
            screen: modelData
        }
    }

    // Hyprland global shortcuts, app id "shell". These are the same names the old shell answered to,
    // so your existing binds (SUPER+Return, brightness keys, ...) keep working unchanged.
    GlobalShortcut {
        appid: "shell"; name: "launcher"; description: "Open the hub (root page)"
        onPressed: Desk.openHub()      // viii-hub-root
    }
    // PS button: hypr/viii.lua binds one key twice (press and release) to tell a tap from a hold.
    // Desk.psDown/psUp ignore repeats, so it is safe if Hyprland also reports the release on the press bind.
    GlobalShortcut {
        appid: "shell"; name: "settings"; description: "Open Settings"
        onPressed: Desk.openSettings()
    }
    GlobalShortcut {
        appid: "shell"; name: "ward"; description: "Open notification history"
        onPressed: Desk.openHistory()
    }
    GlobalShortcut {
        appid: "shell"; name: "shot"; description: "Screenshot pane"
        onPressed: Desk.openShot()
    }
    GlobalShortcut {
        appid: "shell"; name: "psDown"; description: "PS button pressed"
        onPressed: Desk.psDown()
        onReleased: Desk.psUp()
    }
    GlobalShortcut {
        appid: "shell"; name: "psUp"; description: "PS button released"
        onPressed: Desk.psUp()
    }
    // Brightness keys (show the OSD). --min-value stops the screen going fully black.
    GlobalShortcut {
        appid: "shell"; name: "briUp"; description: "Brightness up"
        onPressed: Desk.briStep(5)
    }
    GlobalShortcut {
        appid: "shell"; name: "briDown"; description: "Brightness down"
        onPressed: Desk.briStep(-5)
    }
}
