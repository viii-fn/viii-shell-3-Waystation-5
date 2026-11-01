#!/usr/bin/perl
# apply-wallstore2.pl: exact-string patches for the Wallstore v2 changes. Backup + brace check + rollback.
use strict; use warnings;
my $P = "$ENV{HOME}/viii-shell-3";
my $root = "$P/quickshell";
my $bak = "$P/.bak-wallstore2";
my %orig;

sub slurp { open my $f, '<:raw', $_[0] or die "cannot read $_[0]: $!\n"; local $/; my $t = <$f>; close $f; return $t; }
sub spit { open my $f, '>:raw', $_[0] or die "cannot write $_[0]: $!\n"; print $f $_[1]; close $f; }
sub rollback { spit("$root/$_", $orig{$_}) for keys %orig; }
sub fail { rollback(); print STDERR "FAILED: $_[0]\nRolled back: nothing was changed.\n"; exit 1; }
sub load {
    my $rel = shift;
    return if exists $orig{$rel};
    $orig{$rel} = slurp("$root/$rel");
    my $dir = "$bak/$rel"; $dir =~ s{/[^/]*$}{};
    system("mkdir", "-p", $dir);
    spit("$bak/$rel", $orig{$rel}) unless -e "$bak/$rel";
}
sub once {
    my ($rel, $old, $new) = @_;
    load($rel);
    my $t = slurp("$root/$rel");
    my $i = index($t, $old);
    fail("anchor not found in $rel: " . (split /\n/, $old)[0]) if $i < 0;
    fail("anchor not unique in $rel: " . (split /\n/, $old)[0]) if index($t, $old, $i + 1) >= 0;
    substr($t, $i, length $old) = $new;
    spit("$root/$rel", $t);
}
sub bal { my $t = shift; my $o = () = $t =~ /\{/g; my $c = () = $t =~ /\}/g; return $o == $c; }

my $hub = slurp("$root/hub/Hub.qml");
if (index($hub, "wallpaper: win.page === 0") >= 0) { print "already applied\n"; exit 0; }

# ---- core/Wall.qml: scan + apply state ----
once("core/Wall.qml", "    property bool busy: false\n",
     "    property bool busy: false\n    property bool scanned: false\n    property bool scanFailed: false\n    property string error: \"\"\n");
once("core/Wall.qml", "    function refresh() { if (!lister.running) lister.running = true; }",
     "    function refresh() { if (!lister.running) { scanFailed = false; lister.running = true; } }");
once("core/Wall.qml", "        busy = true;\n", "        busy = true;\n        error = \"\";\n");
once("core/Wall.qml", "        id: lister\n",
     "        id: lister\n        onExited: (code, status) => { root.scanned = true; if (code !== 0 && root.files.length === 0) root.scanFailed = true; }\n");
once("core/Wall.qml", "                root.files = l;\n",
     "                root.files = l;\n                root.scanned = true;\n                if (l.length > 0) root.scanFailed = false;\n");
once("core/Wall.qml", "        onExited: root.busy = false\n",
     "        onExited: (code, status) => {\n            root.busy = false;\n            if (code !== 0) root.error = \"Couldn\\u2019t apply that wallpaper (viii-theme exit \" + code + \")\";\n        }\n");

# ---- hub/Backdrop.qml: full-bleed wallpaper layer ----
once("hub/Backdrop.qml", "    property bool shown: true\n", "    property bool shown: true\n    property bool wallpaper: false\n");
my $layer = <<'EOT';
    // full-bleed current wallpaper, shown while the Wallstore tile is selected (unloaded otherwise: 2 GB RAM)
    Item {
        id: wpLayer
        anchors.fill: parent
        opacity: (root.wallpaper && wpImg.status === Image.Ready) ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Image {
            id: wpImg
            anchors.fill: parent
            source: (root.wallpaper || wpLayer.opacity > 0.01) ? Wall.src(Wall.current) : ""
            sourceSize.width: 1366
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
        }
        // light dim so tiles and text stay readable on bright wallpapers
        Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.deep, 0.28) }
    }

EOT
once("hub/Backdrop.qml", "    // ghost of the selected app's icon\n", $layer . "    // ghost of the selected app's icon\n");

# ---- hub/Hub.qml: tell the backdrop when the Wallstore tile is selected ----
once("hub/Hub.qml", "            icon: win.iconUrl(win.sel)\n            shown: win.shown\n",
     "            icon: win.iconUrl(win.sel)\n            shown: win.shown\n            wallpaper: win.page === 0 && !!win.sel && win.sel.isWall === true\n");

# ---- hub/HomePage.qml: Wallstore first, no side preview card ----
once("hub/HomePage.qml", "current = (entries.length > 1 && entries[0].isWall === true) ? 1 : 0;", "current = 0;");
load("hub/HomePage.qml");
my $hp = slurp("$root/hub/HomePage.qml");
my $label = <<'EOT';
        // name of the current wallpaper, shown while the Wallstore tile is selected
        Txt {
            y: 176
            opacity: root.cur && root.cur.isWall === true ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            text: "CURRENT WALLPAPER  \u00b7  " + Wall.name(Wall.current)
            font.pixelSize: 12
            font.letterSpacing: 1.6
            color: Theme.fgDim
        }

EOT
my $n = ($hp =~ s{        // current wallpaper, shown while.*?\n        \}\n\n(?=        InfoCards \{)}{$label}s);
fail("preview card block not found in hub/HomePage.qml") unless $n == 1;
spit("$root/hub/HomePage.qml", $hp);

# ---- hub/WallstorePage.qml: whole file replaced ----
load("hub/WallstorePage.qml");
spit("$root/hub/WallstorePage.qml", slurp("$P/wallstore2/WallstorePage.qml"));

for my $rel (sort keys %orig) {
    fail("brace imbalance in $rel") unless bal(slurp("$root/$rel"));
}
print "patched: " . join(", ", sort keys %orig) . "\n";
