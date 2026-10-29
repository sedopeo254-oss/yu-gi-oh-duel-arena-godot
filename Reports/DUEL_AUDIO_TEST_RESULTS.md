# Duel audio verification — 2026-10-29

The initial audio-only checkpoint below is retained. Combined responsive-board
integration is documented in [`ARENA_AUDIO_INTEGRATION.md`](ARENA_AUDIO_INTEGRATION.md).

Local branch: `codex/duel-audio`, based on `codex/event-driven-card-animations` at
`b8894b9`. Runtime: **Godot 4.6.3**, headless/Dummy audio on Linux; this is not a
claim that the project's pinned Godot 4.7.1 remote CI has run. No push or deployment.

## Measured checks

| Check | Result |
| --- | --- |
| Baseline SmokeCheck | PASS |
| Baseline full regression | 10,653 passed, 0 failed, 101 suites |
| `SceneDuelAudioCheck` | 81 assertions, PASS |
| `SceneAnimationCheck` | 44 assertions, PASS |
| `SceneAnimationRenderCheck` | 24 assertions, 182 draw states, 0 errors, PASS |
| `SceneBoardCheck` | 30 assertions, PASS |
| `SceneBoardDuelCheck` | Natural LP-zero outcome on turn 6; 134 accepted actions, 0 rejected/refused, PASS |
| `SceneSpikeCheck` | Actual main scene Normal Summon, PASS |
| `RunHiddenIdentityTests` | 46 passed, 0 failed |
| `RunSessionTests` | 220 passed, 0 failed, 2 suites |
| Full regression after implementation | 10,653 passed, 0 failed, 101 suites; pre-existing assertion counts unchanged |
| Cross-process determinism | 6 duels byte-identical across 2 processes, PASS |
| Python helper tests / generated card matrix | 26 passed; matrix regenerated unchanged |
| Repeated rapid-exit cleanup | Spike, natural duel and audio scene checks each rerun 3 times: PASS, no ObjectDB/resource leak warnings |

`SceneDuelAudioCheck` covers deterministic distinct PCM, silent endpoints, finite
length/non-clipping buffers, replaceable resources, real engine action order,
production-board/session sound wiring, hidden/owner-known face-down cards, per-viewer
queues, cover/uncover, fresh hidden snapshots, stale slots, negated summons, ordinary
moves, response timing silence, Flip Summon coalescing, duplicate renders, mute,
zero volume, reduced motion, no late replay, saved/malformed settings, dialog reopen,
layout bounds and actual mixer-resource retirement through weak references.

## PCM measurements

Normalized amplitude of the synthesized raw buffers, before the player's additional
0.40 output gain and the user's volume (default 0.60):

| Cue | Seconds | Peak | RMS |
| --- | ---: | ---: | ---: |
| summon | 0.85 | 0.6026 | 0.0970 |
| attack | 0.72 | 0.5836 | 0.1012 |
| position | 0.65 | 0.3772 | 0.0693 |
| destroy | 0.90 | 0.4510 | 0.0806 |

All use mono 22,050 Hz / 16-bit PCM, no looping, one playback voice. This verifies
waveforms and playback dispatch, not a subjective listening match to the anime.

## Findings and corrections

1. The pre-existing animation director had start/finish signals but no cancellation
   notification. Simply wiring sound to starts would leave a cue running after cover,
   hidden snapshots, or motion reduction. Added `playback_cancelled` at those existing
   cancellation boundaries, and stop on finish as well (including longer replacements).
2. Rapid headless scene teardown intermittently reported one retained
   `AudioStreamPlaybackWAV`/`AudioStreamWAV` pair even after stopping and clearing the
   stream. A 0.15-second teardown grace was insufficient here. Scene-only runners now
   allow 1.1 seconds for asynchronous mixer retirement; the new suite also asserts that
   all weak references to real playbacks have become null. This is test teardown, not
   an animation, rules, or input delay. Existing assertions were not weakened.
3. Mute/volume reload validates types and finite values. Non-numeric saved values fall
   back to defaults; numeric values clamp to 0–1. Unmuting never resumes a stale cue.

## Verification limits

- A real screenshot attempt using a private Xorg dummy display failed: the sandbox
  denied creation of its X11 listening sockets, and Godot could not create a display.
  No screenshot or subjective speaker/headphone audition was verified. Headless UI
  interaction/layout checks and the existing procedural draw test passed.
- These are original anime-inspired substitutes for the Japanese Duel Monsters
  direction (episodes 1–224), not official audio or an audited sonic match. No episode
  recordings, game rips, copyrighted samples, music, or voice lines were obtained.
- No engine, rules, cards, production decks or card pool changed. No new audio promise
  for draw/set/spell/trap/LP events or individual monster voices is implied.

Implementation and replacement-resource guidance: [`docs/DUEL_AUDIO.md`](../docs/DUEL_AUDIO.md).
