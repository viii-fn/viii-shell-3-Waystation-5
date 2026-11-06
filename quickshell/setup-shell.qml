import QtQuick
import Quickshell
import "core"
import "hub"
import "setup"

// viii first-run setup entry point (Waystation). Lives in the quickshell/ root so that core/, hub/ and settings/
// are inside this instance's config folder (Quickshell ignores qmldir files outside it).
// Started by `viii start` only while ~/.local/state/viii/setup-done does not exist:
//   qs -p ~/.config/quickshell/viii/setup-shell.qml
// A separate instance means a mistake in here can never take the main shell down.
ShellRoot {
    ThemeDriver {}      // glides Theme colours (same as the main shell)
    ShadeDriver {}      // the shared GlassRing shade clock
    SetupRoot {}
}
