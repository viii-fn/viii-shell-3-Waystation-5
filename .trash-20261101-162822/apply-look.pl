#!/usr/bin/perl
# apply-look.pl: installs hypr/hyprland/look.lua and wires it into hyprland.lua; drops viii.lua's own window animations.
use strict; use warnings;
my $P = "$ENV{HOME}/viii-shell-3";
my $H = "$P/hypr";
my $bak = "$P/.bak-look";
my %orig;
sub slurp { open my $f, '<:raw', $_[0] or die "cannot read $_[0]: $!\n"; local $/; my $t = <$f>; close $f; return $t; }
sub spit { open my $f, '>:raw', $_[0] or die "cannot write $_[0]: $!\n"; print $f $_[1]; close $f; }
sub rollback { spit("$H/$_", $orig{$_}) for keys %orig; unlink "$H/hyprland/look.lua" unless $ENV{KEEP_LOOK}; }
sub fail { rollback(); print STDERR "FAILED: $_[0]\nRolled back: nothing was changed.\n"; exit 1; }
sub load {
    my $rel = shift;
    return if exists $orig{$rel};
    $orig{$rel} = slurp("$H/$rel");
    system("mkdir", "-p", "$bak/hypr");
    spit("$bak/hypr/" . ($rel =~ s{/}{_}gr), $orig{$rel}) unless -e "$bak/hypr/" . ($rel =~ s{/}{_}gr);
}

my $main = slurp("$H/hyprland.lua");
if (index($main, "hyprland.look") >= 0) { print "already applied\n"; exit 0; }

# 1. wire look.lua in, before viii.lua
load("hyprland.lua");
my $old = "-- pcall: a mistake in viii.lua can never break the rest.";
my $i = index($main, $old);
fail("anchor not found in hyprland.lua: pcall comment") if $i < 0;
fail("anchor not unique in hyprland.lua") if index($main, $old, $i + 1) >= 0;
my $new = "-- look and feel (borders, rounding, shadow, blur, animations). pcall: can never break the rest.\npcall(require, \"hyprland.look\")\n\n" . $old;
substr($main, $i, length $old) = $new;
spit("$H/hyprland.lua", $main);

# 2. viii.lua: remove its own window animations (the demo's set in look.lua replaces them)
load("viii.lua");
my $v = slurp("$H/viii.lua");
my $n = ($v =~ s/^try\("anim (?:windowsIn|windowsOut|windowsMove|fadeIn|fadeOut)",.*\n//mg);
fail("expected 5 window animation lines in viii.lua, found $n") unless $n == 5;
$v =~ s/^-- workspaces are left alone on purpose.*\n//m;
my $c = "-- Windows: an app opening slides in from the right while fading up, like a game starting.\n-- (speed is in 100ms units: 5.5 = 550ms.)\n-- Want it subtler? Change \"slide right\" to \"popin 92%\".\n";
my $ci = index($v, $c);
fail("comment block not found in viii.lua") if $ci < 0;
substr($v, $ci, length $c) = "-- Window and layer animations now live in hyprland/look.lua (the demo's spring set).\n";
spit("$H/viii.lua", $v);

# 3. the new file
system("mkdir", "-p", "$H/hyprland");
spit("$H/hyprland/look.lua", slurp("$P/look/look.lua"));

print "patched: hyprland.lua, viii.lua; added hyprland/look.lua\n";
