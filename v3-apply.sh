#!/usr/bin/env bash
# viii-shell-3 v3 patch: volume OSD (Osd.qml already extracted), Hub binding-loop fix, log dir fix.
set -u
P="$HOME/viii-shell-3"
HUB="$P/quickshell/hub/Hub.qml"
LUA="$P/hypr/viii.lua"
cp "$HUB" "$HUB.bak-v3" || exit 1

# 1) Hub: `shown` becomes a plain property updated by Desk signals (no binding => no loop)
if grep -q 'recalcShown' "$HUB"; then echo "Hub: already patched"; else
perl -0pi -e 's/\n    readonly property bool shown: Desk\.isEmpty\(screen\.name\) \|\| Desk\.summoned\n/\n    property bool shown: false\n    function recalcShown() { shown = Desk.isEmpty(screen.name) || Desk.summoned; }\n    Connections {\n        target: Desk\n        function onEmptyChanged() { win.recalcShown(); }\n        function onSummonedChanged() { win.recalcShown(); }\n    }\n/; s/Component\.onCompleted: \{\n        if \(shown\) \{/Component.onCompleted: {\n        recalcShown();\n        if (shown) {/' "$HUB"
fi
grep -q 'function recalcShown' "$HUB" && grep -q '^        recalcShown();' "$HUB" || { echo "Hub patch FAILED, restoring"; cp "$HUB.bak-v3" "$HUB"; exit 1; }
o=$(tr -cd '{' < "$HUB" | wc -c); c=$(tr -cd '}' < "$HUB" | wc -c)
[ "$o" = "$c" ] || { echo "Hub braces unbalanced, restoring"; cp "$HUB.bak-v3" "$HUB"; exit 1; }

# 2) log dir must exist or the hypr-lua logger fails silently
mkdir -p "$HOME/.cache/viii"
if ! grep -q 'mkdir -p' "$LUA"; then
  sed -i '/^local log_path/a os.execute("mkdir -p \\"" .. home .. "/.cache/viii\\"")' "$LUA"
fi

echo "v3 applied. Restarting shell..."
exec "$HOME/.local/bin/viii" restart
