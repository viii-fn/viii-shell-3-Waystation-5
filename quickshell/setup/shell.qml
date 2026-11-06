import QtQuick
import Quickshell
import "../core"
import "../hub"

// viii first-run setup (Waystation). Its own Quickshell instance, started by `viii start` only while
// ~/.local/state/viii/setup-done does not exist:  qs -p ~/.config/quickshell/viii/setup/shell.qml
// A separate instance means a mistake in here can never take the main shell down.
ShellRoot {
    ThemeDriver {}      // glides Theme colours (same as the main shell)
    ShadeDriver {}      // the shared GlassRing shade clock
    SetupRoot {}
}
