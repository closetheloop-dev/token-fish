import QtQuick
import Quickshell
import Quickshell.Io

// Service entry point (headless singleton). Mounts one click-through, transparent
// Bottom-layer overlay per monitor (the living aquarium), and runs the single
// token-usage collector for the plugin.
Item {
  id: root

  // One Tank window per screen; Variants rebuilds the set as monitors change.
  Variants {
    model: Quickshell.screens
    Tank {}
  }

  // Single, service-level token-usage collector. A Tank (and its FoodSource) is
  // built per monitor, but the external collector must run ONCE per plugin
  // instance: N monitors each running `omarchy-agent-usage-update` on their own
  // timer duplicates work and races on the usage files it writes. Run it here in
  // the lone service singleton — every FoodSource's FileView.watchChanges picks up
  // the writes and feeds its own tank, so per-screen feeding is preserved.
  // No stdout/stderr parser is attached: Quickshell closes those channels, so the
  // updater's output is discarded rather than buffered in an unbounded collector.
  Process {
    id: usageUpdater
    running: false
    command: ["omarchy-agent-usage-update"]
  }

  Timer {
    interval: 120 * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: if (!usageUpdater.running) usageUpdater.running = true
  }
}
