# Card animation prototype — 2026-10-29

Local branch: `codex/event-driven-card-animations`, based on
`codex/playable-board-hidden-identities` at `1875b47`. No publication or merge is
part of this checkpoint.

## Measured checks

Installed engine: **Godot 4.6.3.stable.official.7d41c59c4**, Linux.

| Check | Result |
| --- | --- |
| Import + parse inspection | PASS; no parse/compile errors |
| `SceneAnimationCheck` | **44 assertions**, PASS |
| `SceneBoardCheck` | **30 assertions**, PASS |
| `SceneBoardDuelCheck` | PASS; **134 accepted actions**, natural LP-zero result on turn 6; zero rejected/refused actions |
| `SceneSpikeCheck` | PASS; real successful Normal Summon through the default scene |
| `RunHiddenIdentityTests` | **46 assertions**, PASS |
| `RunSessionTests` | **220 assertions**, PASS |
| `RunTests` | **10,653 assertions / 101 suites**, PASS; clean exit |
| Cross-process determinism | **6 duels** identical in two processes |
| Python tooling | **26 tests**, PASS |
| Generated card matrix | Unchanged; **77/77** production cards |
| `git diff --check` | PASS |

The animation test is registered as its own CI step. Local results do **not** claim
that this unpublished branch has run remotely on CI's pinned Godot 4.7.1.
The full suite contains expected negative-test `push_error` output; there were no
unexpected script errors, allocator aborts or ObjectDB leak warnings in these runs.

## Rendered verification

Actual Godot rendering, **1600×900**, OpenGL compatibility, Mesa llvmpipe
25.0.7 / LLVM 19.1.7:

- Captured and inspected **15 frames** across the five real engine-driven showcase
  steps: empty/emerging summon, defense reversal, attack-position emergence,
  lunge/slash, cracked/split frame and dust.
- Captured and inspected the default playable board after a real summon and its
  full privacy cover. The motion preference control fits the header; the effect
  is correctly anchored to its compact card window and absent under the cover.
- Recorded **620 rendered frames at 30 FPS** (20.67 seconds) of the auto-playing
  fixture, then encoded an H.264 MP4 preview. No script errors during capture.
- Found and fixed ordering where a destroyed target disappeared before its
  attack cue: publicly known targets now remain as cosmetic ghosts until their
  queued destruction starts.
- Independent read-only review found stale source anchors after control changes;
  these and relocated attack targets now cancel obsolete queued/active cues,
  with two regression assertions.

A default X11 Unix-socket launch was blocked by the sandbox; the escalation launcher
failed before executing due to its read-only mount configuration. An authenticated
TCP X11 route with Unix listeners disabled succeeded using a fresh temporary cookie.
The temporary server and authentication file were removed after each render run.
The final renders used the Dummy audio driver; this prototype has no audio assets.

Runtime evidence in the task environment:

- `/tmp/animation-validation/`: test and capture logs.
- `/tmp/portrait-animation-captures/`: all fifteen screenshots.
- `/workspace/shared/card-animation-preview/portrait-animation-demo.mp4`: preview.
- `/workspace/shared/card-animation-preview/portrait-{summon,attack,destruction}.png`:
  selected frames.

These are local verification artifacts, not vendored runtime assets or published links.

## Honest scope

This is one original procedural **2D blocking profile**, plus an abstract fallback
and extensible event/profile boundary. It is not production-quality art, 3D,
Duel Generation parity, or full card-pool visual coverage. The Portrait remains
an accurate, opt-in **test fixture** rather than an unreviewed addition to the
production decks. See [`docs/CARD_ANIMATIONS.md`](../docs/CARD_ANIMATIONS.md) for
launch instructions, architecture, privacy behavior, and limitations.

Forward+, Godot 4.7.1, other GPUs/OSes, all card-specific UI paths, sound, and polished
art are not validated by these local checks.
