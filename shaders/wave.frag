#version 440

// Fish body-wave + gill breathing + lip-hinge mouth + eye blink/pupil + sushi
// death crossfade.
//
// We work in an art-space UV where y=1 is the TOP of the fish; Qt's qt_TexCoord0
// has y=0 at the top, so we use `v = (x, 1 - y)` — every calibrated constant
// (eye/gill/mouth/sushi) is expressed in that space — and flip y back only when
// sampling the texture. Facing is a geometry Scale in Fish.qml, so the shader
// always sees art-space UV. Baked to wave.frag.qsb with qsb.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;      // required by Qt Quick
    float qt_Opacity;     // required by Qt Quick
    float amp;            // body-wave amplitude (fraction of height)
    float waveK;          // 1 / wavelengthFrac
    float headStill;      // rigid front fraction
    float wavePhase;      // accumulated body-wave phase (cycles) — see note below
    float gillAmp;        // gill horizontal pulse (UV units)
    float gillPhase;      // accumulated gill/mouth phase (cycles)
    float lipAngle;       // mouth max open angle (radians); 0 disables the mouth
    float eyeBlink;       // 1 open .. ~0.1 closed
    float sushiMix;       // 0 fish .. 1 sushi (death crossfade)
    vec2  pupilOff;       // pupil drift (UV) — keep LAST (std140 vec2 alignment)
} ubuf;

// Phases arrive PRE-ACCUMULATED (phase += freq*dt on the CPU) rather than as
// freq*time: when the frequency changes (food-lively transition, speed slider)
// that keeps the phase rate smooth. Computing freq*time here would spike the
// rate by time*d(freq)/dt and make the fish spasm.

layout(binding = 1) uniform sampler2D src;    // fish art
layout(binding = 2) uniform sampler2D sushi;  // sushi death texture

void main() {
    vec2 v = vec2(qt_TexCoord0.x, 1.0 - qt_TexCoord0.y);   // art-space UV (y up)
    float u = v.x;                                          // 0 head (left) .. 1 tail

    // body wave: held rigid at the head, grows toward the tail, travels head->tail
    float e   = max(0.0, (u - ubuf.headStill) / (1.0 - ubuf.headStill));
    float env = pow(e, 1.3);
    float dy  = ubuf.amp * env * sin(6.2831853 * (ubuf.wavePhase - u * ubuf.waveK));

    // shared breathing phase; the mouth rides it in OPPOSITE phase (pumping water)
    float gillPh = 6.2831853 * ubuf.gillPhase + 0.6;

    // gill breathing: a soft, localized horizontal pulse over the operculum
    const vec2 GILL_C = vec2(0.26, 0.47);
    const vec2 GILL_R = vec2(0.05, 0.20);
    vec2  gd   = v - GILL_C;
    float genv = exp(-(gd.x * gd.x) / (GILL_R.x * GILL_R.x)
                     - (gd.y * gd.y) / (GILL_R.y * GILL_R.y));
    float gdx  = ubuf.gillAmp * genv * sin(gillPh);

    // lip-hinge mouth: rotate the lower lip about the mouth's V-vertex, masked to
    // the lower-lip side and faded with distance. Skipped when lipAngle ~ 0.
    float mdx = 0.0, mdy = 0.0;
    if (ubuf.lipAngle > 0.001) {
        const vec2  LIP_P = vec2(0.113, 0.447);
        const vec2  LIP_N = vec2(-0.5, -0.87);
        const float LIP_REACH = 0.06, LIP_BAND = 0.04;
        float openv = 0.5 - 0.5 * sin(gillPh);        // 0..1, peaks when gill is in
        vec2  d     = v - LIP_P;
        float side  = smoothstep(-LIP_BAND, LIP_BAND, dot(d, LIP_N));
        float reach = exp(-dot(d, d) / (2.0 * LIP_REACH * LIP_REACH));
        float m     = side * reach;
        float th    = ubuf.lipAngle * openv;
        float ca = cos(th), sa = sin(th);
        vec2  rot = LIP_P + vec2(ca * d.x - sa * d.y, sa * d.x + ca * d.y);
        vec2  sUV = mix(v, rot, m);
        mdx = v.x - sUV.x;
        mdy = v.y - sUV.y;
    }

    // sample the fish art (flip y back to Qt space); pupil drift shifts the pupil
    const vec2 EYE_C = vec2(0.145, 0.579);
    const vec2 EYE_R = vec2(0.045, 0.055);
    float pupMask = 1.0 - smoothstep(0.7, 1.0, length((v - EYE_C) / vec2(0.014, 0.016)));
    vec2  samp    = vec2(v.x - gdx - mdx, v.y - dy - mdy) - ubuf.pupilOff * pupMask;
    vec4  c       = texture(src, vec2(samp.x, 1.0 - samp.y));

    // eyelid: a skin-coloured lid descends top-down as eyeBlink -> 0 (colour
    // overlay, no UV warp). Skip the lid fetch when the eye is open.
    if (ubuf.eyeBlink < 0.999) {
        float eyeMask = 1.0 - smoothstep(0.9, 1.15, length((v - EYE_C) / EYE_R));
        vec3  lidCol  = texture(src, vec2(0.135, 1.0 - 0.51)).rgb;   // cheek skin below eye
        float lidY    = (EYE_C.y + EYE_R.y) - (1.0 - ubuf.eyeBlink) * (2.2 * EYE_R.y);
        float lidCover = smoothstep(lidY, lidY + 0.006, v.y) * eyeMask;
        c.rgb = mix(c.rgb, lidCol, lidCover);
    }

    // death: crossfade into a centred square of the sushi texture (fits the 4:3
    // quad; transparent outside so the fish's wide sides dissolve away). Skip the
    // fetch entirely while alive.
    vec4 outc = c;
    if (ubuf.sushiMix > 0.0) {
        vec2 sushiUV = vec2((v.x - 0.5) / 0.75 + 0.5, v.y);
        vec4 s = (sushiUV.x < 0.0 || sushiUV.x > 1.0)
               ? vec4(0.0)
               : texture(sushi, vec2(sushiUV.x, 1.0 - sushiUV.y));
        outc = mix(c, s, clamp(ubuf.sushiMix, 0.0, 1.0));
    }

    fragColor = vec4(outc.rgb, outc.a) * ubuf.qt_Opacity;
}
