#!/usr/bin/perl
# apply-hyprcolors.pl: matugen template for Hyprland border colours + viii-theme hook. Backup + rollback.
use strict; use warnings;
my $P = "$ENV{HOME}/viii-shell-3";
my $bak = "$P/.bak-hyprcolors";
my %orig;
sub slurp { open my $f, '<:raw', $_[0] or die "cannot read $_[0]: $!\n"; local $/; my $t = <$f>; close $f; return $t; }
sub spit { open my $f, '>:raw', $_[0] or die "cannot write $_[0]: $!\n"; print $f $_[1]; close $f; }
sub rollback { spit("$P/$_", $orig{$_}) for keys %orig; unlink "$P/matugen/templates/hypr-colors.lua"; }
sub fail { rollback(); print STDERR "FAILED: $_[0]\nRolled back: nothing was changed.\n"; exit 1; }
sub load {
    my $rel = shift;
    return if exists $orig{$rel};
    $orig{$rel} = slurp("$P/$rel");
    system("mkdir", "-p", $bak);
    my $n = $rel =~ s{/}{_}gr;
    spit("$bak/$n", $orig{$rel}) unless -e "$bak/$n";
}
sub once {
    my ($rel, $old, $new) = @_;
    load($rel);
    my $t = slurp("$P/$rel");
    my $i = index($t, $old);
    fail("anchor not found in $rel: " . (split /\n/, $old)[0]) if $i < 0;
    fail("anchor not unique in $rel") if index($t, $old, $i + 1) >= 0;
    substr($t, $i, length $old) = $new;
    spit("$P/$rel", $t);
}

my $cfg = slurp("$P/matugen/config.toml");
if (index($cfg, "[templates.hypr]") >= 0) { print "already applied\n"; exit 0; }

# 1. template + config block (full theme only, not --shell-only)
spit("$P/matugen/templates/hypr-colors.lua", slurp("$P/hyprcolors/hypr-colors.lua"));
load("matugen/config.toml");
$cfg .= "\n" unless $cfg =~ /\n\z/;
$cfg .= "\n[templates.hypr]\ninput_path = '~/viii-shell-3/matugen/templates/hypr-colors.lua'\noutput_path = '~/.cache/viii/hypr-colors.lua'\n";
spit("$P/matugen/config.toml", $cfg);

# 2. viii-theme: validate the generated file, reload Hyprland (full theme only)
my $hook = <<'EOT';
[ "$cfg" = "config.toml" ] && pkill -USR1 -x kitty 2>/dev/null
if [ "$cfg" = "config.toml" ]; then
  # border colours for Hyprland; if matugen did not render it properly, drop it so look.lua keeps its defaults
  grep -Eq 'rgba\([0-9a-fA-F]{6}ee\)' "$HOME/.cache/viii/hypr-colors.lua" 2>/dev/null || { rm -f "$HOME/.cache/viii/hypr-colors.lua"; echo "viii-theme: hypr-colors.lua not rendered (borders keep the default)"; }
  [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && hyprctl reload >/dev/null 2>&1
fi
EOT
once("bin/viii-theme", "[ \"\$cfg\" = \"config.toml\" ] && pkill -USR1 -x kitty 2>/dev/null\n", $hook);

# 3. make sure a hypr reload re-reads look.lua (drop the require cache first)
load("hypr/hyprland.lua");
my $m = slurp("$P/hypr/hyprland.lua");
if (index($m, 'pcall(require, "hyprland.look")') >= 0 && index($m, 'package.loaded["hyprland.look"]') < 0) {
    $m =~ s/pcall\(require, "hyprland\.look"\)/package.loaded["hyprland.look"] = nil\npcall(require, "hyprland.look")/;
    spit("$P/hypr/hyprland.lua", $m);
}
print "patched: matugen/config.toml, bin/viii-theme, hypr/hyprland.lua; added matugen/templates/hypr-colors.lua\n";
