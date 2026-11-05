pragma Singleton
import QtQuick
import Quickshell

// One clock for every GlassRing shade sweep in the shell.
//
// Plain state only: no animations, no Behaviors (a Behavior inside a singleton segfaults
// Qt 6.12; see Theme.qml). ShadeDriver.qml, created once in shell.qml, advances `phase`
// forever. Because every ring reads this same phase:
//   * the interval is shared by the whole shell and never restarts when the selection moves,
//   * only one animation runs instead of one per ring,
//   * rings that appear later join the sweep already in progress.
Singleton {
    // 0..1 across one complete cycle (sweep + pause)
    property real phase: 0

    // How many rings currently need the sweep. GlassRing claims a slot only while it is
    // actually on screen; ShadeDriver stops the clock when this reaches zero, so a hidden
    // hub (a workspace with windows) does not keep a 60 fps animation alive all day.
    property int users: 0

    // design values
    readonly property int upMs: 10              // shade 0 -> peak
    readonly property int holdMs: 4             // shade stays at its peak
    readonly property int downMs: 1300          // shade peak -> 0 (the diagonal sweep)
    readonly property int repeatMs: 3600        // pause before the next sweep (the interval)
    readonly property int sweepMs: upMs + holdMs + downMs
    readonly property int cycleMs: sweepMs + repeatMs

    // 0..1 across the sweep; clamped at 1 during the pause
    readonly property real band: Math.min(1, phase * cycleMs / sweepMs)

    // shade strength: rises, holds, falls, then stays 0 until the next interval
    readonly property real pulse: {
        const t = phase * cycleMs;
        if (t >= sweepMs) return 0;
        if (t < upMs) {
            const x = t / upMs;
            return 1 - Math.pow(1 - x, 3);      // Easing.OutCubic
        }
        if (t < upMs + holdMs) return 1;
        const x = (t - upMs - holdMs) / downMs;
        return 0.5 + 0.5 * Math.cos(Math.PI * x); // Easing.InOutSine, 1 -> 0
    }
}
