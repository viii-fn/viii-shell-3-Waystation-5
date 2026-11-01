#!/usr/bin/perl
# Hub follows the wallpaper palette only: no per-app colours. Reversible: set usePerApp to true in core/Apps.qml.
use strict; use warnings;
my $f = "$ENV{HOME}/viii-shell-3/quickshell/core/Apps.qml";
open my $h, '<', $f or die "cannot read $f\n"; local $/; my $s = <$h>; close $h;
sub edit { my ($old, $new, $marker) = @_; return if index($s, $marker) >= 0; my $i = index($s, $old); die "PATCH FAIL: anchor not found: $old\n" if $i < 0; substr($s, $i, length $old) = $new; }
edit('    property var failed: ({})',
     "    // false = every tile and the whole hub use the wallpaper palette (Theme.wp). true = old per-app colours.\n    readonly property bool usePerApp: false\n    property var failed: ({})",
     'readonly property bool usePerApp');
edit('if (entry.isWall === true) return Theme.wp || fallback("wall");',
     'if ((usePerApp !== true || entry.isWall === true) && Theme.wp) return Theme.wp;' . "\n        " . 'if (entry.isWall === true) return fallback("wall");',
     'usePerApp !== true || entry.isWall');
edit('if (entry.isLibrary === true || entry.isWall === true) return;',
     'if (usePerApp !== true || entry.isLibrary === true || entry.isWall === true) return;',
     'usePerApp !== true || entry.isLibrary');
open my $o, '>', $f or die "cannot write $f\n"; print $o $s; close $o;
print "wallpalette patch ok\n";
