import QtQuick
import QtQuick.Shapes
import "../core"

// The PS5 "Games" card grid, shown while the Welcome tile is selected. Three columns, tall and small
// cards alternating, measured from the PS5 reference scaled to 1366 wide. v1: frames and titles only.
//
//   col 1: Screen time (tall)    col 2: Most used app (small)   col 3: Batteries (small)
//          Network (small)              About the app (tall)           Weather (tall)
Item {
    id: root
    readonly property real colW: 358
    readonly property real gutter: 23
    readonly property real tall: 233
    readonly property real small: 108
    readonly property real rowGap: 17
    width: 3 * colW + 2 * gutter
    height: tall + rowGap + small

    // one card: glass slot, a small line icon and a title (like "Online Friends" / "Trophies" in the PS5)
    component Card: Item {
        id: card
        property string title: ""
        property string icon: ""               // SVG path, 24x24, drawn as a line icon
        default property alias content: body.data
        width: root.colW

        GlassSlot { anchors.fill: parent; radius: 16 }

        Item {
            x: 18; y: 16
            width: 20; height: 20
            Shape {
                width: 24; height: 24
                scale: 20 / 24
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 2
                    strokeColor: Theme.fg
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: card.icon }
                }
            }
        }
        Txt {
            x: 46; y: 15
            text: card.title
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }
        Item { id: body; anchors.fill: parent }   // content goes here in the next steps
    }

    // column 1
    Card {
        x: 0; y: 0
        height: root.tall
        title: "Screen time"
        icon: "M12 3 a9 9 0 1 0 0.001 0 Z M12 7 V12 L15 14"
    }
    Card {
        x: 0; y: root.tall + root.rowGap
        height: root.small
        title: "Network"
        icon: "M2 9 A15 15 0 0 1 22 9 M5.5 12.5 A10 10 0 0 1 18.5 12.5 M9 16 A5 5 0 0 1 15 16 M12 19.5 H12.01"
    }

    // column 2
    Card {
        x: root.colW + root.gutter; y: 0
        height: root.small
        title: "Most used"
        icon: "M12 2.5 L14.9 8.6 L21.5 9.4 L16.6 13.9 L17.9 20.5 L12 17.2 L6.1 20.5 L7.4 13.9 L2.5 9.4 L9.1 8.6 Z"
    }
    Card {
        x: root.colW + root.gutter; y: root.small + root.rowGap
        height: root.tall
        title: "About"
        icon: "M12 3 a9 9 0 1 0 0.001 0 Z M12 11 V16.5 M12 7.8 H12.01"
    }

    // column 3
    Card {
        x: 2 * (root.colW + root.gutter); y: 0
        height: root.small
        title: "Batteries"
        icon: "M3 8 H18 A1 1 0 0 1 19 9 V15 A1 1 0 0 1 18 16 H3 A1 1 0 0 1 2 15 V9 A1 1 0 0 1 3 8 Z M21.5 11 V13"
    }
    Card {
        x: 2 * (root.colW + root.gutter); y: root.small + root.rowGap
        height: root.tall
        title: "Weather"
        icon: "M12 8 a4 4 0 1 0 0.001 0 Z M12 2 V4 M12 20 V22 M2 12 H4 M20 12 H22 M4.9 4.9 L6.3 6.3 M17.7 17.7 L19.1 19.1 M4.9 19.1 L6.3 17.7 M17.7 6.3 L19.1 4.9"
    }
}
