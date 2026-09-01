import QtQuick

// The aquarium: fish + food pellets + the Life simulation, embedded by the
// wallpaper Tank. One FrameAnimation drives everything; one clock feeds the
// shared wave shader. Call feed(n) to drop food + produce births.
Item {
  id: scene
  clip: false

  // ---- tunables (QML props must be lowercase-initial) ----
  readonly property real refW: 900
  readonly property real refH: 675
  readonly property real newborn: 0.09
  readonly property real adultMin: 0.24
  readonly property real adultMax: 0.45
  readonly property real ageToAdult: 22
  readonly property real maxA: 60 * Math.PI / 180
  readonly property real sepGap: 0.85
  readonly property real sepStrength: 45
  readonly property real sepMax: 60
  readonly property real sepEase: 3
  readonly property int simRadius: 450
  readonly property real simKillProb: 0.35
  readonly property int simBirthsPerFeed: 2

  // Resolution scale: multiplies every spatial constant below (fish size, crowding/
  // separation radii, swim speed, margins, pellet size/speed) so the tank looks and
  // moves the same at any monitor resolution / compositor scale. 1.0 on a 1536×864
  // logical tank (1920×1080 @ scale 1.25); min() keeps fish sane on non-16:9 aspects.
  readonly property real refTankW: 1536
  readonly property real refTankH: 864
  readonly property real resScale: (width > 0 && height > 0)
                                   ? Math.min(width / refTankW, height / refTankH) : 1
  readonly property real crowdRadius: simRadius * resScale
  readonly property real bandMargin: 60 * resScale

  property int startCount: 5

  // Live-tunable from the settings panel (bound in Tank.qml).
  property bool frozen: false    // stop the sim entirely (0 CPU when no GPU)
  property real speedScale: 1.0  // swim-speed multiplier (also drives wave)
  property real sizeScale: 1.0   // multiplies fish size
  property int popMax: 16        // max living fish
  property int densityMax: 3     // neighbours before overcrowding
  property bool food: true       // show falling food pellets
  property int fps: 30           // frame cap; 0 = uncapped (vsync)

  // Liveliness (0 calm .. 1 lively): comes from the speed slider, but when the
  // foodLively toggle is on, food presence eases it toward 1 so fish get energetic
  // while there are pellets (they settle back once the food is gone).
  property bool foodLively: true                 // bound from Settings
  readonly property real baseLiv: Math.max(0, Math.min(1, (speedScale - 0.5) / 1.5))
  property real foodEnv: 0                        // eased 0..1 food presence
  readonly property real liv: Math.max(baseLiv, foodEnv)

  // shared wave uniforms (scale with liveliness) + clock. Animation RATES top out
  // at ~1.5× the calm rate when fully lively (amplitudes still grow more, below).
  readonly property real waveAmp: (8 + 8 * liv) / refH
  readonly property real waveFreq: 0.55 + 0.275 * liv      // 0.55 → 0.825 Hz (1.5×)
  readonly property real waveK: 1 / (1.05 - 0.20 * liv)
  readonly property real waveHeadStill: 0.30
  // gill breathing + lip-hinge mouth, scaled by liveliness (calm → lively):
  readonly property real gillAmp: (22 + 16 * liv) / 800    // 22→38 viewBox px / VIEWBOX_W
  readonly property real gillFreq: 0.5 + 0.25 * liv         // 0.5 → 0.75 Hz (1.5×; mouth rides this)
  readonly property real lipAngle: 0.28 + 0.32 * liv        // MOUTH_ANG 0.28 → 0.6
  property real clock: 0        // seconds, for the CPU eye/blink/pupil timing
  property real wavePhase: 0    // accumulated body-wave phase (cycles), wrapped [0,1)
  property real gillPhase: 0    // accumulated gill/mouth phase (cycles), wrapped [0,1)

  // counters (bound by the wallpaper-corner overlay in Tank.qml)
  property int sushiCount: 0     // cumulative deaths (fish → sushi)
  property int living: 0         // current live fish

  // Warm-up gate: the driver runs until the fish are seeded AND the texture has
  // loaded (one proper paint) even when frozen — otherwise a tank that STARTS
  // frozen shows nothing (blank fish) until you toggle. Once ready, freeze wins.
  property bool texReady: false
  readonly property bool ready: seeded && texReady

  // shared fish texture (the SVG art; eye baked in)
  readonly property ShaderEffectSource fishTex: ShaderEffectSource {
    hideSource: true
    sourceItem: Image {
      source: Qt.resolvedUrl("assets/fish.svg")
      sourceSize.width: 700
      sourceSize.height: 525
      onStatusChanged: if (status === Image.Ready) scene.texReady = true
    }
  }

  // sushi texture for the death crossfade (square art). Not part of the warm-up
  // `ready` gate — it is only ever sampled once a fish is dying, well after start.
  readonly property ShaderEffectSource sushiTex: ShaderEffectSource {
    hideSource: true
    sourceItem: Image {
      source: Qt.resolvedUrl("assets/sushi.svg")
      sourceSize.width: 512
      sourceSize.height: 512
    }
  }

  Item { id: fishLayer; anchors.fill: parent }
  Item { id: pelletLayer; anchors.fill: parent }
  Component { id: fishComp; Fish {} }
  Component { id: pelletComp; Pellet {} }

  property var fish: []
  property var pellets: []
  property bool seeded: false
  property real genAcc: 0
  readonly property var pcolors: ["#cf9a3e", "#a5632a", "#8f9a3c", "#c1552b", "#d9b25a", "#7a5a2a"]

  function rnd(a, b) { return a + Math.random() * (b - a); }
  function smoothstep(g) { return g * g * (3 - 2 * g); }
  function scaleOf(f) { return newborn + (f.adult - newborn) * smoothstep(Math.min(1, f.age / ageToAdult)); }
  function effScale(f) { return scaleOf(f) * sizeScale * resScale; }
  // Base swim speed from the slider, bumped up to +50% while food excites the fish.
  function speed() { return 55 * speedScale * (1 + 0.5 * foodEnv) * resScale; }

  function makeFish(dir, adult, age, x, y) {
    var W = width, H = height;
    var f = {
      dir: dir, sx: dir < 0 ? 1 : -1,
      cx: (x === undefined ? Math.random() * W : x),
      cy: (y === undefined ? rnd(bandMargin, Math.max(bandMargin, H - bandMargin)) : y),
      theta: 0, target: rnd(-maxA, maxA), sinceRe: 0, nextRe: rnd(2.5, 5),
      sepX: 0, sepY: 0, age: age, adult: adult,
      fade: age > 0 ? 1 : 0, dying: false,
      blinkNext: -1, eyePhase: Math.random() * 6.2831853, sushiCounted: false,
      item: null, ghost: null
    };
    f.item = fishComp.createObject(fishLayer, { scene: scene });
    f.ghost = fishComp.createObject(fishLayer, { scene: scene, visible: false });
    return f;
  }

  function seed() {
    for (var i = 0; i < startCount; i++)
      fish.push(makeFish(Math.random() < 0.5 ? -1 : 1, rnd(adultMin, adultMax), rnd(2, 30)));
  }

  // Shortest horizontal delta on the wrap torus: the tank wraps in x (stepFish and
  // the ghost render both treat x=0 and x=W as the same seam), so neighbour and
  // separation math must use the seam-crossing distance — otherwise two fish that
  // are visibly adjacent across the seam neither crowd nor push off each other.
  function wrapDX(dx, W) {
    if (W > 0) { if (dx > W * 0.5) dx -= W; else if (dx < -W * 0.5) dx += W; }
    return dx;
  }

  function countNeighbours(f, r) {
    var r2 = r * r, c = 0, W = width;
    for (var i = 0; i < fish.length; i++) {
      var o = fish[i];
      if (o === f || o.dying) continue;
      var dx = wrapDX(o.cx - f.cx, W), dy = o.cy - f.cy;
      if (dx * dx + dy * dy <= r2) c++;
    }
    return c;
  }

  function applyOvercrowding() {
    for (var i = 0; i < fish.length; i++) {
      var f = fish[i];
      if (f.dying) continue;
      if (countNeighbours(f, crowdRadius) > densityMax && Math.random() < simKillProb) f.dying = true;
    }
  }

  function spawnPellets(n) {
    for (var i = 0; i < n; i++) {
      var p = {
        x: rnd(20 * resScale, width - 20 * resScale), y: rnd(-30, -8) * resScale, vx: rnd(-15, 15) * resScale, vy: rnd(45, 70) * resScale,
        r: rnd(5, 9) * resScale, color: pcolors[Math.floor(Math.random() * pcolors.length)], life: 0, item: null
      };
      p.item = pelletComp.createObject(pelletLayer, { color: p.color, width: p.r * 2, height: p.r * 2 });
      pellets.push(p);
    }
  }

  // feed: drop pellets + produce births near not-crowded parents (well-fed).
  // Frozen means fully paused: swallow feed impulses so no un-animated pellets
  // or newborns get spawned while the driver is stopped (tokens spent while
  // frozen simply don't feed — FoodSource still advances its cursor).
  function feed(n) {
    if (!seeded || frozen) return;
    if (food) spawnPellets(n);
    var living = 0, parents = [];
    for (var i = 0; i < fish.length; i++) {
      if (fish[i].dying) continue;
      living++;
      if (countNeighbours(fish[i], crowdRadius) < densityMax) parents.push(fish[i]);
    }
    var room = popMax - living;
    for (var k = 0; k < simBirthsPerFeed && room > 0 && parents.length; k++, room--) {
      var p = parents[Math.floor(Math.random() * parents.length)];
      var ang = Math.random() * Math.PI * 2, d = (40 + Math.random() * 60) * resScale;
      fish.push(makeFish(Math.random() < 0.5 ? -1 : 1, rnd(adultMin, adultMax), 0,
                         p.cx + Math.cos(ang) * d, p.cy + Math.sin(ang) * d));
    }
  }

  function separation(dt) {
    var n = fish.length, scl = [], W = width;
    for (var i = 0; i < n; i++) scl.push(effScale(fish[i]));
    var tX = new Array(n), tY = new Array(n);
    for (i = 0; i < n; i++) { tX[i] = 0; tY[i] = 0; }
    for (i = 0; i < n; i++) {
      var hi = 450 * scl[i];
      for (var j = i + 1; j < n; j++) {
        var dx = wrapDX(fish[i].cx - fish[j].cx, W), dy = fish[i].cy - fish[j].cy;
        var d = Math.hypot(dx, dy) || 0.001;
        var want = sepGap * (hi + 450 * scl[j]);
        if (d < want) {
          var mag = ((want - d) / want) * sepStrength * resScale, ux = dx / d, uy = dy / d;
          tX[i] += ux * mag; tY[i] += uy * mag; tX[j] -= ux * mag; tY[j] -= uy * mag;
        }
      }
    }
    var ez = Math.min(1, dt * sepEase);
    for (i = 0; i < n; i++) {
      var mx = tX[i], my = tY[i], m = Math.hypot(mx, my);
      var sm = sepMax * resScale; if (m > sm) { mx *= sm / m; my *= sm / m; }
      fish[i].sepX += (mx - fish[i].sepX) * ez;
      fish[i].sepY += (my - fish[i].sepY) * ez;
    }
  }

  function stepFish(f, dt, spd) {
    var W = width, H = height, loY = bandMargin, hiY = Math.max(loY, H - bandMargin);
    f.sinceRe += dt;
    if (f.sinceRe > f.nextRe) { f.target = rnd(-maxA, maxA); f.sinceRe = 0; f.nextRe = rnd(2.5, 5); }
    var band = hiY - loY;
    if (band > 1) {
      var top = loY + band * 0.15, bot = hiY - band * 0.15;
      if (f.cy < top) f.target = Math.abs(f.target);
      else if (f.cy > bot) f.target = -Math.abs(f.target);
    }
    f.theta += (f.target - f.theta) * Math.min(1, dt * 0.8);
    f.theta = Math.max(-maxA, Math.min(maxA, f.theta));
    var vx = f.dir * Math.cos(f.theta), vy = Math.sin(f.theta);
    f.cx += (vx * spd + f.sepX) * dt;
    f.cy += (vy * spd + f.sepY) * dt;
    f.cy = Math.max(loY, Math.min(hiY, f.cy));
    if (f.cx < 0) f.cx += W; else if (f.cx >= W) f.cx -= W;
  }

  function step(dt) {
    if (!seeded && width > 0 && height > 0) { seed(); seeded = true; }
    if (!seeded) return;
    var W = width, H = height, limit = H * 0.75, i, f;

    // ease food-driven liveliness toward whether pellets are on screen (toggle-gated)
    var foodTarget = (foodLively && pellets.length > 0) ? 1 : 0;
    foodEnv += (foodTarget - foodEnv) * Math.min(1, dt * 2.0);
    var spd = speed();   // read after foodEnv so the food speed-bump is current

    separation(dt);
    var live = 0;
    for (i = 0; i < fish.length; i++) {
      f = fish[i];
      stepFish(f, dt, spd);
      f.age += dt;
      f.fade = f.dying ? Math.max(0, f.fade - dt / 1.6) : Math.min(1, f.fade + dt / 0.7);
      if (f.dying) { if (!f.sushiCounted) { f.sushiCounted = true; sushiCount++; } }
      else live++;
    }
    living = live;
    for (i = fish.length - 1; i >= 0; i--) {
      f = fish[i];
      if (f.dying && f.fade <= 0) { if (f.item) f.item.destroy(); if (f.ghost) f.ghost.destroy(); fish.splice(i, 1); }
    }
    genAcc += dt; if (genAcc > 2.5) { genAcc = 0; applyOvercrowding(); }

    var t = clock;
    for (i = 0; i < fish.length; i++) {
      f = fish[i];
      var sc = effScale(f), w = refW * sc, h = refH * sc, halfW = w / 2, halfH = h / 2;
      var op = f.dying ? Math.min(1, f.fade * 2) : f.fade;
      var sushiMix = f.dying ? Math.min(1, (1 - f.fade) / 0.35) : 0;   // dissolve ~0.55s
      // per-fish eye: staggered blink (0.16s) + gentle pupil drift
      var eyeBlink = 1;
      if (f.blinkNext < 0) f.blinkNext = t + Math.random() * 4;
      if (t >= f.blinkNext) {
        var pr = (t - f.blinkNext) / 0.16;
        if (pr < 1) eyeBlink = 1 - 0.9 * Math.sin(Math.PI * pr);
        else f.blinkNext = t + 3 + Math.random() * 4;
      }
      var poff = Qt.vector2d(0.003 * Math.sin(6.2831853 * 0.13 * t + f.eyePhase),
                             0.002 * Math.sin(6.2831853 * 0.19 * t + f.eyePhase + 1.3));
      var it = f.item;
      it.width = w; it.height = h; it.x = f.cx - halfW; it.y = f.cy - halfH;
      it.facing = f.sx; it.opacity = op; it.visible = true;
      it.eyeBlink = eyeBlink; it.pupilOff = poff; it.sushiMix = sushiMix;
      var gx = f.cx < W / 2 ? f.cx + W : f.cx - W, g = f.ghost;
      if (gx > -halfW && gx < W + halfW) {
        g.width = w; g.height = h; g.x = gx - halfW; g.y = f.cy - halfH;
        g.facing = f.sx; g.opacity = op; g.visible = true;
        g.eyeBlink = eyeBlink; g.pupilOff = poff; g.sushiMix = sushiMix;
      } else g.visible = false;
    }

    for (i = pellets.length - 1; i >= 0; i--) {
      var p = pellets[i];
      p.life += dt; p.y += p.vy * dt; p.x += p.vx * dt;
      if (p.y > limit) { if (p.item) p.item.destroy(); pellets.splice(i, 1); continue; }
      var a = p.life < 0.3 ? p.life / 0.3 : 1, near = limit - p.y;
      var fade = 80 * resScale; if (near < fade) a = Math.min(a, near / fade);
      p.item.x = p.x - p.r; p.item.y = p.y - p.r; p.item.opacity = a * 0.95;
    }
  }

  // One static layout pass (no sim advance) — used to apply size changes while
  // frozen, when the driver that would otherwise re-sync is stopped.
  function resync() { if (seeded) step(0); }
  onSizeScaleChanged: if (frozen && ready) resync()

  // Manual feed: the panel's Feed button bumps feedNonce (via settings.json).
  // Baselining off "the first value we see" is wrong on a fresh install: settings
  // starts at feedNonce 0 and the load never changes it, so no change signal fires
  // and the first real click (0→1) gets swallowed as the baseline. Instead baseline
  // when feedReady flips (bound from settings.loaded in Tank.qml) — by then the
  // persisted value is applied, and any later change is a genuine user feed. Feed
  // once per increment so a coalesced settings.json write (nonce jumps by >1) still
  // maps every click to a meal; never feed on a decrease (a reset re-baselines).
  // feed() itself no-ops while frozen / unseeded.
  property int feedNonce: 0
  property int lastFeedNonce: 0
  property bool feedReady: false
  // A single notification can coalesce several rapid clicks, so we process the
  // whole delta. Only an implausibly large one-shot jump — a corrupt or
  // hand-edited nonce, not human clicking — is rejected: we adopt it as the new
  // baseline rather than spawn an unbounded feast.
  readonly property int maxFeedBurst: 64
  onFeedReadyChanged: if (feedReady) lastFeedNonce = feedNonce;
  onFeedNonceChanged: {
    if (!feedReady) return;
    var d = feedNonce - lastFeedNonce;
    lastFeedNonce = feedNonce;                     // always adopt the newest value
    if (d <= 0 || d > maxFeedBurst) return;        // decrease/reset or anomaly → re-baseline, no feed
    for (var i = 0; i < d; i++) feed(4 + Math.floor(Math.random() * 4));
  }

  // Advance the sim + the shared clock/phases by dt seconds. Phases are integrated
  // (phase += freq*dt) so wave/gill frequency changes stay smooth; wrapped to [0,1)
  // to keep float precision over long runtimes (sin is periodic in cycles).
  function tick(dt) {
    scene.clock += dt;
    scene.wavePhase = (scene.wavePhase + scene.waveFreq * dt) % 1;
    scene.gillPhase = (scene.gillPhase + scene.gillFreq * dt) % 1;
    scene.step(dt);
  }

  // Run while unfrozen, OR until the warm-up gate is ready (seeded + textured),
  // so a frozen start still seeds, loads its texture, and paints once.
  // Uncapped: vsync-aligned FrameAnimation (smoothest, best on GPU).
  FrameAnimation {
    running: (!scene.frozen || !scene.ready) && scene.fps <= 0
    onTriggered: scene.tick(frameTime)
  }

  // Capped: fixed-interval Timer. Cheaper on CPU/software rendering, which is
  // what this runs on until the GPU reboot. dt is the nominal frame time.
  Timer {
    running: (!scene.frozen || !scene.ready) && scene.fps > 0
    interval: scene.fps > 0 ? Math.round(1000 / scene.fps) : 16
    repeat: true
    onTriggered: scene.tick(interval / 1000)
  }
}
