import QtQuick
import Quickshell
import Quickshell.Hyprland
import "core"
import "hub"

// viii-shell-3 entry point. Run with:  qs -c viii   (or: viii start)
ShellRoot {
    ThemeDriver {}

    ThemeDriver {}

    // one hub window per monitor
    Variants {
        model: Quickshell.screens
        Hub {
            required property var modelData
            screen: modelData
        }
    }

    // Hyprland global shortcuts, app id "shell". These are the same names the old shell answered to,
    // so your existing binds (SUPER+Return, brightness keys, ...) keep working unchanged.
    GlobalShortcut {
        appid: "shell"; name: "launcher"; description: "Open the app library"
        onPressed: Desk.openLibrary()
    }
    // PS button: hypr/viii.lua binds one key twice (press and release) to tell a tap from a hold.
    GlobalShortcut {
        appid: "shell"; name: "psDown"; description: "PS button pressed"
        onPressed: Desk.psDown()
    }
    GlobalShortcut {
        appid: "shell"; name: "psUp"; description: "PS button released"
        onPressed: Desk.psUp()
    }
    // Brightness keys (no on-screen indicator yet). --min-value stops the screen going fully black.
    GlobalShortcut {
        appid: "shell"; name: "briUp"; description: "Brightness up"
        onPressed: Quickshell.execDetached(["brightnessctl", "--min-value=1", "set", "5%+"])
    }
    GlobalShortcut {
        appid: "shell"; name: "briDown"; description: "Brightness down"
        onPressed: Quickshell.execDetached(["brightnessctl", "--min-value=1", "set", "5%-"])
    }
}
