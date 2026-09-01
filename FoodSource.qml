import QtQuick
import Quickshell
import Quickshell.Io

// Turns real AI-coding token usage into fish food. Reads the same records the
// omarchy.agents collectors write (~/.local/state/omarchy/agents/usage/*.json) —
// never raw sessions. Per record it tracks a cursor over cumulative tokens
// (modelUsage inputTokens+outputTokens); a positive delta drops pellets and
// triggers births via scene.feed(). The first load of each record baselines the
// cursor WITHOUT feeding, so launching fresh doesn't dump all history as one meal.
Item {
  id: root
  visible: false

  property var scene: null          // the AquariumScene to feed
  property int tokensPerPellet: 400 // delta→pellet scaling
  property int maxPellets: 12        // cap pellets per feed event
  property int refreshSec: 120       // how often we re-list the usage dir for new agents

  readonly property string home: Quickshell.env("HOME") || ""
  // Where the omarchy.agents collectors write their per-agent usage records.
  property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"

  property var agentIds: []
  property var cursors: ({})         // agentId -> last cumulative token total

  // ------------------------------------------------------------- discovery
  Process {
    id: listProc
    command: ["find", root.usageDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyListing(text) }
  }

  function rescan() { if (!listProc.running) listProc.running = true }

  function applyListing(out) {
    var ids = [], lines = String(out || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
      var n = lines[i].trim();
      if (n.slice(-5) === ".json") ids.push(n.slice(0, -5));
    }
    ids.sort();
    if (JSON.stringify(ids) !== JSON.stringify(agentIds)) agentIds = ids;
  }

  // -------------------------------------------------------------- feeding
  function tokenTotal(rec) {
    if (!rec || typeof rec !== "object") return 0;
    var mu = rec.modelUsage, sum = 0;
    if (mu && typeof mu === "object") {
      for (var m in mu) {
        var b = mu[m] || {};
        sum += (Number(b.inputTokens) || 0) + (Number(b.outputTokens) || 0);
      }
    }
    // Fallback when the collector reports only a daily aggregate.
    if (sum === 0) sum = Number(rec.todayTotalTokens) || 0;
    return sum;
  }

  function onRecord(id, rec) {
    var total = tokenTotal(rec), prev = cursors[id];
    if (prev === undefined) { cursors[id] = total; return; }   // baseline, no feed
    if (total > prev) {
      var delta = total - prev;
      cursors[id] = total;
      if (scene) {
        var pellets = Math.max(1, Math.min(maxPellets, Math.round(delta / tokensPerPellet)));
        scene.feed(pellets);
      }
    } else if (total < prev) {
      cursors[id] = total;   // series reset — re-baseline, never negative-feed
    }
  }

  function parse(content) {
    try { var p = JSON.parse(String(content || "")); return p && typeof p === "object" ? p : null; }
    catch (e) { return null; }
  }

  Instantiator {
    model: root.agentIds
    delegate: Item {
      required property var modelData
      FileView {
        path: root.usageDir + "/" + modelData + ".json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.onRecord(modelData, root.parse(text()))
        onLoadFailed: {}
      }
    }
  }

  // Re-list the usage dir on a gentle timer so agent records that appear
  // mid-session get a FileView. This is a read-only `find`, safe to run per
  // monitor. The external collector that WRITES those files
  // (`omarchy-agent-usage-update`) runs once at the service level in Aquarium.qml,
  // not here — N monitors launching it in parallel would duplicate work and race.
  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.rescan()
  }

  Component.onCompleted: rescan()
}
