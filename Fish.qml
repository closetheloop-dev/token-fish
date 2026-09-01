import QtQuick

// One fish: a ShaderEffect sampling the shared fish texture (and the sushi texture
// for the death crossfade). The scene sets x/y/width/height/opacity/facing plus
// the per-fish eye/sushi uniforms each frame; the wave + gill + mouth uniforms are
// shared from the scene so all fish undulate/breathe on one clock. Facing flips the
// geometry via xScale (no re-render of the art). Uniform NAMES must match wave.frag.
ShaderEffect {
  id: root
  property var scene

  // textures (both are ShaderEffectSources on the scene)
  property variant src: scene ? scene.fishTex : null
  property variant sushi: scene ? scene.sushiTex : null

  // body wave (scene-global). wavePhase is accumulated on the CPU (phase += freq*dt)
  // so a changing frequency stays smooth — see AquariumScene.tick() / wave.frag.
  property real amp: scene ? scene.waveAmp : 0.03
  property real waveK: scene ? scene.waveK : 1.05
  property real headStill: scene ? scene.waveHeadStill : 0.30
  property real wavePhase: scene ? scene.wavePhase : 0

  // gill breathing + lip-hinge mouth (scene-global; gillPhase also accumulated)
  property real gillAmp: scene ? scene.gillAmp : 0.0275
  property real gillPhase: scene ? scene.gillPhase : 0
  property real lipAngle: scene ? scene.lipAngle : 0.28

  // per-fish (set imperatively by AquariumScene.step(); defaults keep a warm-up /
  // frozen first paint correct: eye open, alive, no drift)
  property real eyeBlink: 1
  property vector2d pupilOff: Qt.vector2d(0, 0)
  property real sushiMix: 0

  property real facing: 1   // +1 face left (art default), -1 mirror

  blending: true
  fragmentShader: Qt.resolvedUrl("shaders/wave.frag.qsb")
  transform: Scale { origin.x: root.width / 2; origin.y: root.height / 2; xScale: root.facing }
}
