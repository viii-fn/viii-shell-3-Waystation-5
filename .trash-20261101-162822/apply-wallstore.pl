#!/usr/bin/perl
# Exact-string patches for the existing Hub/HomePage/AppTile/Apps/shell files. Dies on the first anchor that is missing.
use strict; use warnings;
my $Q = "$ENV{HOME}/viii-shell-3/quickshell";
sub slurp { my $f = shift; open my $h, '<', $f or die "cannot read $f\n"; local $/; my $s = <$h>; close $h; $s }
sub spew  { my ($f, $s) = @_; open my $h, '>', $f or die "cannot write $f\n"; print $h $s; close $h }
sub edit {
    my ($rel, $old, $new, $marker) = @_;
    my $f = "$Q/$rel"; my $s = slurp($f);
    return if index($s, $marker) >= 0;
    my $i = index($s, $old);
    die "PATCH FAIL: $rel: anchor not found: $old\n" if $i < 0;
    substr($s, $i, length $old) = $new;
    spew($f, $s);
}

# ---- Hub ----
edit("hub/Hub.qml",
  'home.entries = Apps.ranked(16).concat([{ isLibrary: true, name: "Library", id: "viii.library" }]);',
  'home.entries = [{ isWall: true, name: "Wallstore", id: "viii.wallstore" }].concat(Apps.ranked(16)).concat([{ isLibrary: true, name: "Library", id: "viii.library" }]);',
  'isWall: true');
edit("hub/Hub.qml",
  'if (!entry || entry.isLibrary === true) return "";',
  'if (!entry || entry.isLibrary === true || entry.isWall === true) return "";',
  'entry.isWall === true) return ""');
edit("hub/Hub.qml",
  '    // ---- actions ----',
  "    property bool storeOpen: false\n    function openStore() { storeOpen = true; Theme.applyWallpaper(); }\n\n    // ---- actions ----",
  'function openStore()');
edit("hub/Hub.qml",
  'if (entry.isLibrary === true) { page = 1; tabsFocus = false; return; }',
  'if (entry.isWall === true) { openStore(); return; }' . "\n        " . 'if (entry.isLibrary === true) { page = 1; tabsFocus = false; return; }',
  'openStore(); return;');
edit("hub/Hub.qml",
  'if (launching) { e.accepted = true; return; }',
  'if (storeOpen) { store.handleKey(e); return; }' . "\n        " . 'if (launching) { e.accepted = true; return; }',
  'store.handleKey(e)');
edit("hub/Hub.qml",
  'onTriggered: { fx.reset(); win.launching = false;',
  'onTriggered: { win.storeOpen = false; fx.reset(); win.launching = false;',
  'win.storeOpen = false;');
edit("hub/Hub.qml",
  "            LaunchFx {\n                id: fx",
  "            WallstorePage {\n                id: store\n                anchors.fill: parent\n                open: win.storeOpen\n                onCloseRequested: win.storeOpen = false\n            }\n\n            LaunchFx {\n                id: fx",
  'id: store');

# ---- Apps ----
edit("core/Apps.qml",
  'if (entry.isLibrary === true) return;',
  'if (entry.isLibrary === true || entry.isWall === true) return;',
  'entry.isWall === true) return;');
edit("core/Apps.qml",
  'if (entry.isLibrary === true) return fallback("library");',
  'if (entry.isWall === true) return Theme.wp || fallback("wall");' . "\n        " . 'if (entry.isLibrary === true) return fallback("library");',
  'Theme.wp || fallback');

# ---- HomePage ----
edit("hub/HomePage.qml",
  'if (e.isLibrary === true) return "Browse every installed app";',
  'if (e.isWall === true) return "Wallpapers \u00b7 the whole interface follows the one you pick";' . "\n        " . 'if (e.isLibrary === true) return "Browse every installed app";',
  'the whole interface follows');
edit("hub/HomePage.qml",
  'function reset() { animateF = false; current = 0; f = 0; animateF = true; }',
  'function reset() { animateF = false; current = (entries.length > 1 && entries[0].isWall === true) ? 1 : 0; f = current; animateF = true; }',
  'entries[0].isWall');
edit("hub/HomePage.qml",
  'text: root.cur && root.cur.isLibrary === true ? "Browse" : "Open"',
  'text: root.cur && (root.cur.isLibrary === true || root.cur.isWall === true) ? "Browse" : "Open"',
  'root.cur.isWall === true) ? "Browse"');
edit("hub/HomePage.qml",
  'opacity: root.cur && root.cur.isLibrary === true ? 0 : 1',
  'opacity: root.cur && (root.cur.isLibrary === true || root.cur.isWall === true) ? 0 : 1',
  'root.cur.isWall === true) ? 0 : 1');
edit("hub/HomePage.qml",
  "        InfoCards {\n            y: 176",
  <<'QML' . "        InfoCards {\n            y: 176",
        // current wallpaper, shown while the Wallstore tile is selected
        Item {
            x: 640; y: 0
            width: 540; height: 304
            opacity: root.cur && root.cur.isWall === true ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            Rectangle { anchors.fill: parent; radius: 18; color: Theme.glass; border.width: 1; border.color: Theme.glassBorder }
            Image {
                anchors.fill: parent
                anchors.margins: 6
                source: Wall.src(Wall.current)
                sourceSize.width: 640
                fillMode: Image.PreserveAspectCrop
                clip: true
                asynchronous: true
            }
            Txt {
                x: 6; y: parent.height + 10
                text: "CURRENT WALLPAPER  \u00b7  " + Wall.name(Wall.current)
                font.pixelSize: 11
                font.letterSpacing: 1.6
                color: Theme.fgDim
            }
        }

QML
  'CURRENT WALLPAPER');

# ---- AppTile ----
edit("hub/AppTile.qml",
  'readonly property bool isLib: entry !== null && entry !== undefined && entry.isLibrary === true',
  'readonly property bool isLib: entry !== null && entry !== undefined && entry.isLibrary === true' . "\n" . '    readonly property bool isWall: entry !== null && entry !== undefined && entry.isWall === true',
  'readonly property bool isWall');
edit("hub/AppTile.qml",
  'if (!entry || isLib) return "";',
  'if (!entry || isLib || isWall) return "";',
  'isLib || isWall) return');
edit("hub/AppTile.qml",
  'visible: !root.isLib && img.status !== Image.Ready',
  'visible: !root.isLib && !root.isWall && img.status !== Image.Ready',
  '!root.isWall && img.status');
edit("hub/AppTile.qml",
  '    // dim overlay for unfocused tiles',
  <<'QML' . '    // dim overlay for unfocused tiles',
    // Wallstore glyph: a picture frame with a sun and two hills
    Item {
        anchors.centerIn: parent
        visible: root.isWall
        opacity: root.iconOpacity
        width: Math.min(root.width, root.height) * 0.50
        height: width * 0.74
        Rectangle {
            anchors.fill: parent
            radius: width * 0.14
            color: "transparent"
            border.width: Math.max(2, width * 0.07)
            border.color: Theme.fg
            clip: true
            Rectangle { x: parent.width * 0.66; y: parent.height * 0.18; width: parent.width * 0.16; height: width; radius: width / 2; color: Theme.fg }
            Rectangle { x: parent.width * 0.06; y: parent.height * 0.52; width: parent.width * 0.46; height: width; rotation: 45; radius: width * 0.08; color: Theme.fg; opacity: 0.85 }
            Rectangle { x: parent.width * 0.38; y: parent.height * 0.62; width: parent.width * 0.40; height: width; rotation: 45; radius: width * 0.08; color: Theme.fg; opacity: 0.65 }
        }
    }

QML
  'Wallstore glyph');

# ---- shell.qml ----
edit("shell.qml", 'import "cc"', "import \"cc\"\nimport \"wall\"", 'import "wall"');
edit("shell.qml",
  '    // one hub window per monitor',
  "    // the wallpaper (drawn here, so it always matches the palette)\n    Variants {\n        model: Quickshell.screens\n        WallpaperLayer {\n            required property var modelData\n            screen: modelData\n        }\n    }\n\n    // one hub window per monitor",
  'WallpaperLayer {');
print "patches ok\n";
