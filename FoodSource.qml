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

  // Hard caps so discovery can never balloon regardless of the directory's contents.
  readonly property int maxAgents: 64    // most agent records we will track
  readonly property int maxNameLen: 128  // ignore absurdly long filenames
  property var pendingIds: []            // accumulates during one scan

  // ------------------------------------------------------------- discovery
  // Stream the `find` output line-by-line through a SplitParser (bounded) rather than
  // buffering the whole listing in a StdioCollector, applying per-line caps as we go.
  // `-type f` keeps it to regular files only.
  Process {
    id: listProc
    command: ["find", root.usageDir, "-maxdepth", "1", "-type", "f", "-name", "*.json", "-printf", "%f\n"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        if (root.pendingIds.length >= root.maxAgents) return;   // cap agent count
        var n = line.trim();
        if (n.length === 0 || n.length > root.maxNameLen) return;   // cap name length
        if (n.slice(-5) === ".json") root.pendingIds.push(n.slice(0, -5));
      }
    }
    onRunningChanged: if (!running) root.finishListing()
  }

  function rescan() { if (!listProc.running) { pendingIds = []; listProc.running = true; } }

  function finishListing() {
    var ids = pendingIds.slice();
    ids.sort();
    if (JSON.stringify(ids) !== JSON.stringify(agentIds)) agentIds = ids;
    pendingIds = [];
  }

  // -------------------------------------------------------------- feeding
  // Coerce x to a finite non-negative number, or null when it is not a usable numeric value.
  // A real 0 returns 0 (a valid value); booleans, arrays, objects, null, "", NaN, Infinity,
  // "Infinity", and negatives return null — so a legitimate zero stays distinguishable from
  // "no value".
  function finiteNonNeg(x) {
    var n;
    if (typeof x === "number") n = x;
    else if (typeof x === "string" && x.trim() !== "") n = Number(x);
    else return null;
    return (isFinite(n) && n >= 0) ? n : null;
  }
  // Cumulative token total for a record, or null when the record has no valid token source.
  // A modelUsage entry is trusted only if BOTH its token fields are valid finite non-negative
  // numbers; any malformed or partially-invalid entry rejects the whole record (returns null)
  // rather than accept a partial/undercounted total. With no usable modelUsage entries, fall
  // back to the daily todayTotalTokens aggregate. Returning null (vs 0) lets onRecord leave
  // the cursor untouched for invalid records, while a legitimately validated 0 still updates
  // it.
  function tokenTotal(rec) {
    if (!rec || typeof rec !== "object" || Array.isArray(rec)) return null;
    var mu = rec.modelUsage, sum = 0, sawEntry = false;
    if (mu && typeof mu === "object" && !Array.isArray(mu)) {
      for (var m in mu) {
        var b = mu[m];
        if (!b || typeof b !== "object" || Array.isArray(b)) return null;   // malformed entry
        var it = finiteNonNeg(b.inputTokens), ot = finiteNonNeg(b.outputTokens);
        if (it === null || ot === null) return null;   // incomplete entry → reject the record
        sum += it + ot; sawEntry = true;
      }
      if (sawEntry)   // clamp so summing extreme values can never store a non-finite cursor
        return isFinite(sum) ? Math.min(sum, Number.MAX_SAFE_INTEGER) : Number.MAX_SAFE_INTEGER;
      // empty modelUsage → fall through to the daily aggregate
    }
    // Fallback when the collector reports only a daily aggregate (no modelUsage entries).
    return finiteNonNeg(rec.todayTotalTokens);   // null when absent/invalid
  }

  function onRecord(id, rec) {
    // tokenTotal returns null when the record has no valid token source; leave the cursor
    // untouched for it, so an invalid or empty record cannot reset the cursor and cause a
    // spurious feed on the next valid read. A legitimately validated 0 is a real value and
    // still updates the cursor.
    var total = tokenTotal(rec);
    if (total === null) return;
    var prev = cursors[id];
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
