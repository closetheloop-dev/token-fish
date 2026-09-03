import QtQuick
import Quickshell
import Quickshell.Io

// Shared, persisted settings bridge between the controls panel (writer) and the
// running aquarium service (reader). Lives under ~/.local/state so
// FileView.watchChanges gets inotify events and changes apply live. The panel
// sets a property + calls save(); the service binds AquariumScene props to these
// and updates the instant the file changes.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/io.github.closetheloop-dev.token-fish"
  readonly property string path: dir + "/settings.json"

  // Defaults (also the fresh-install values). fps 30 by default because we ship
  // on software rendering today; the user can uncap after the GPU reboot.
  property bool frozen: false
  property real speedScale: 1.0
  property real sizeScale: 1.0
  property int popMax: 16
  property int densityMax: 3
  property bool food: true
  property int fps: 30
  property bool foodLively: true   // fish get lively while there's food
  property bool showCounter: true  // 🐟/🍣 wallpaper-corner overlay
  property int feedNonce: 0        // bumped by the panel's Feed button (one-shot signal)

  property bool loaded: false
  signal changed()

  // Create the plugin-owned state dir owner-only. `mkdir -m 700` sets the mode atomically
  // on a newly-created dir; we deliberately do NOT chmod an existing path afterward, since a
  // plain chmod would follow a symlink planted at this location.
  Process { id: mkdir; command: ["mkdir", "-m", "700", "-p", root.dir] }
  Component.onCompleted: mkdir.running = true

  FileView {
    id: file
    path: root.path
    watchChanges: true
    // Persist via temp-file + rename (same as Omarchy's first-party clipboard/agents
    // plugins): no partial writes, and the rename replaces a destination rather than
    // following it. Defaults to true in Quickshell; set explicitly to document it.
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: { root.loaded = true; root.changed(); }   // no file yet → keep defaults
  }

  // Coerce a persisted value to a finite number clamped to [lo, hi]; fall back to
  // the current value when it is missing, non-numeric, NaN, or infinite. Without
  // this a hand-edited or stale settings.json could inject NaN/negative/huge values
  // into animation rates, dimensions, population logic, and timer selection — e.g.
  // a non-numeric fps stops both frame drivers, a NaN speedScale poisons fish
  // positions and shader uniforms. Ranges mirror the Controls.qml sliders.
  // Coerce only real numbers and non-empty numeric strings. null, undefined, "",
  // whitespace, booleans, arrays and objects all return NaN — Number() would
  // otherwise turn null/""/[] into 0 and true into 1, silently injecting a
  // (clamped) zero/one where the contract promises the current value is kept.
  function toNumber(v) {
    if (typeof v === "number") return v;
    if (typeof v === "string" && v.trim() !== "") return Number(v);
    return NaN;
  }
  function clampNum(v, lo, hi, cur) {
    var n = toNumber(v);
    if (!isFinite(n)) return cur;
    return Math.max(lo, Math.min(hi, n));
  }
  function clampInt(v, lo, hi, cur) {
    var n = toNumber(v);
    if (!isFinite(n)) return cur;
    return Math.max(lo, Math.min(hi, Math.round(n)));
  }

  function apply(content) {
    try {
      var d = JSON.parse(String(content || ""));
      if (d && typeof d === "object") {
        if (d.frozen !== undefined) frozen = !!d.frozen;
        if (d.speedScale !== undefined) speedScale = clampNum(d.speedScale, 0.3, 2.5, speedScale);
        if (d.sizeScale !== undefined) sizeScale = clampNum(d.sizeScale, 0.5, 1.8, sizeScale);
        if (d.popMax !== undefined) popMax = clampInt(d.popMax, 4, 24, popMax);
        if (d.densityMax !== undefined) densityMax = clampInt(d.densityMax, 1, 6, densityMax);
        if (d.food !== undefined) food = !!d.food;
        if (d.fps !== undefined) fps = clampInt(d.fps, 0, 60, fps);   // 0 = uncapped/vsync
        if (d.foodLively !== undefined) foodLively = !!d.foodLively;
        if (d.showCounter !== undefined) showCounter = !!d.showCounter;
        if (d.feedNonce !== undefined) feedNonce = clampInt(d.feedNonce, 0, 1e9, feedNonce);
      }
    } catch (e) { /* keep current values on bad JSON */ }
    loaded = true;
    changed();
  }

  function save() {
    var d = { frozen: frozen, speedScale: speedScale, sizeScale: sizeScale, popMax: popMax,
              densityMax: densityMax, food: food, fps: fps,
              foodLively: foodLively, showCounter: showCounter, feedNonce: feedNonce };
    file.setText(JSON.stringify(d, null, 2) + "\n");
  }

  // Restore every setting to its factory default and persist.
  function reset() {
    frozen = false;
    speedScale = 1.0;
    sizeScale = 1.0;
    popMax = 16;
    densityMax = 3;
    food = true;
    fps = 30;
    foodLively = true;
    showCounter = true;
    save();
  }
}
