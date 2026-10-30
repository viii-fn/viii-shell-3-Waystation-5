import QtQuick
import "../core"

// Shared text style. Theme.fontFamily is the first installed font from a preferred list.
Text {
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: 16
    renderType: Text.NativeRendering
    elide: Text.ElideRight
}
