# Portrait presentation polish — 2026-10-29

This continues the initial procedural animation checkpoint at `5d046e8` on
`codex/event-driven-card-animations`. The initial flat illustration has been replaced;
the engine-event boundary, production card pool and gameplay rules remain unchanged.
No push, PR or merge is part of this local checkpoint.

## Substantial visual changes

- A gaunt, shaded face with recessed eyes, brows, nose, mouth and luminous pupils.
- Separate curved, segmented fingers, hooked nails and an opposable thumb, with skin
  shading, joints and an emerging forearm rather than one flat mitten polygon.
- Mitred/bevelled wooden frame with grain, scratches, gilt lining, carved details and
  corner fittings; canvas weave, irregular opening, folded edges and loose fibers.
- Layered dark pink aura, offset shadows, atmospheric fog shader, suspended dust,
  floating gallery stage and restrained light changes driven by the current cue.
- Anticipation/recoil before the tilted lunge, eased recovery, tapered curved
  green/purple slashes, branching cracks, wood splinters, frayed cloth and diffuse dust.
- Faceted/shaded holograms, landing rings, light trails and shards replace the flat
  fallback diamond used for other visible monsters.
- Redesigned showcase: large hero portrait, restrained serif typography, facts panel,
  compact target column, five-moment timeline and styled playback controls.
- Optional demo-only sound: four original synthesized cues plus a subtle looping drone.
  No third-party recording, sample, music, copyrighted image or downloaded game art.
  The regular board remains silent. Sound has an independent mute toggle.

## Verification

Godot **4.6.3.stable.official.7d41c59c4**, Linux:

| Check | Result |
| --- | --- |
| `SceneAnimationCheck` | **44 assertions**, PASS |
| New `SceneAnimationRenderCheck` | **24 assertions, 182 sampled draw states, zero renderer/script/shader errors**, PASS |
| `SceneBoardCheck` | **30 assertions**, PASS |
| `SceneBoardDuelCheck` | **134 accepted actions**, turn-6 natural LP-zero result; zero rejected/refused actions |
| Full `RunTests` | **10,653 assertions / 101 suites**, PASS |
| Python tooling | **26 tests**, PASS |
| Production card matrix | Unchanged, **77/77** |
| Whitespace/diff checks | PASS |

The draw-path check is a separate CI step. It samples the real fixture's queued
animations, not only message dispatch. A test-only thread-safe Logger traps rendering
errors, following the [Godot Logger contract](https://docs.godotengine.org/en/4.5/classes/class_logger.html).
It also verifies actual non-silent, non-clipped PCM cue buffers, replay while active,
reduced-motion cues and frozen atmosphere. Headless checks cannot validate actual GPU
shader compilation; the real-render capture below does.

### Defects caught during this pass

1. Expanded Bézier finger outlines could self-intersect and fail triangulation.
   Each limb now uses guarded triangles; all sampled drawing states are error-free.
2. The initial hard frame cutoff could quit while audio playback resources were still
   being retired. Dedicated capture/record runners now free the scene, release sound
   resources and allow the mixer to retire playback before quitting.
3. A lingering crack was still visible across the air after the canvas halves separated.
   The crack now fades as the tear opens. Falling debris also fades above the controls.

## Actual visual evidence

Rendered and inspected 15 still frames at **1600×900**, OpenGL compatibility,
Mesa llvmpipe 25.0.7. The atmosphere shader compiled and all stages drew without script,
shader or triangulation errors. A complete movie is recorded from the actual scene and
real-engine fixture, with synthesized audio; no composited animation or fake event feed.
The preview contains **669 frames at 30 FPS / 22.30 seconds**, H.264 video and AAC audio.
The inspected audio stream is non-silent and unclipped (peak approximately −17.8 dBFS).

Runtime evidence (local artifacts, not published URLs):

- `/tmp/portrait-polish-captures/`: sampled stages.
- `/tmp/animation-polish-movie.log`: recording outcome and renderer timings.
- `/workspace/shared/card-animation-preview/portrait-polish-demo.mp4`: new preview.
- `/workspace/shared/card-animation-preview/portrait-polish-{summon,attack,destruction}.png`:
  selected refined frames.

## Remaining honest limits

This is a much more detailed **original procedural 2.5D study**, not production-quality
painted assets, a skeletal character rig or a true 3D model. One custom monster profile
is implemented; the rest use the abstract fallback. Atmospheric set and sound are
showcase-only. Portrait remains an opt-in accurate fixture, not an addition to the
production decks. Forward+, other GPUs/OSes and CI's Godot 4.7.1 remain unverified here.

The compact production board still uses small art windows; its broader visual redesign
is separate work. See `docs/CARD_ANIMATIONS.md` for launch, extension and privacy details.
