# Event-driven card animation prototype

This is an **original procedural 2D blocking pass**, not finished high-fidelity artwork,
3D monsters, or a copy of another game's assets. The production 77-card pool and both
real decks are unchanged. No engine/rules/card implementation is modified.

## Try it

- **F5 / normal board:** face-up field monsters receive generic summon, attack,
  position and destruction cues from the real session event stream.
- **Portrait showcase:** open `Scenes/presentation/PortraitAnimationDemo.tscn` and
  press F6, or run:

  ```bash
  godot --path . res://Scenes/presentation/PortraitAnimationDemo.tscn
  ```

  It is an explicitly arranged test fixture, not a new campaign or CPU opponent.
  Auto play runs five real, legally offered actions. Uncheck it to use **Next engine
  action**. **Replay fixture** resets cleanly. Complete turns advance between position
  changes, because manually changing position on the summon turn or twice per turn
  would be illegal. Destruction comes from the opponent's stronger battle attacker.
- **Reduce motion:** skips queued/active effects and shows static field representations.
  It never affects legality or engine speed. The board's cover/Escape cancels visible
  effects immediately; uncovering does not replay a canceled private timeline.

The opt-in fixture uses The Portrait's Secret's verified identity: **32541773**, Level 4,
EARTH / Fiend / Normal, **1200 ATK / 1500 DEF**. Reference:
[official card database](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=5219&ope=2).
It is not silently added to the approved production card library or deck lists.

## Choreography

| Cue | Portrait blocking pass |
| --- | --- |
| Successful summon | Dark pink aura; empty wooden frame; green claw breaks the canvas; head and glowing eyes emerge |
| Idle | Subtle aura, head and claw motion |
| Attack declaration | Frame lunges toward the offered target; green / purple three-claw slash |
| Face-up Defense Position | Hand and head retract; frame turns to a covered wooden reverse |
| Face-up Attack Position | Reverse sequence uncovers the frame and creature |
| Actual destruction | Frame crack; canvas splits vertically; halves separate and fade into gray dust |

The covered reverse is **artistic Defense Position choreography**, not a rules change
from face-up Defense to face-down. Truly face-down monsters show no identifying field
actor, including cards whose owner privately knows their identity.

## Architecture / adding another card

- `CardAnimationDirector.gd` consumes only `EngineSession`'s **per-viewer plain-data
  logs and snapshots** on the main thread. It never reads a `DuelEngine`, computes a
  legal action, changes state, or delays submissions. The demo's engine driver is a
  separate opt-in test fixture, not the normal board boundary.
- A bounded FIFO preserves event order. Summon cues use success events, not declarations;
  Flip Summon's redundant position event is coalesced. Destruction uses `CARD_DESTROYED`,
  never every move, tribute, bounce or discard. Attack cues represent **declaration**,
  not a promise that damage will be inflicted; later negation is not embellished yet.
- Anchors are rebound by player/monster-slot after each board rebuild and track scrolling.
  Public destroyed targets remain cosmetic ghosts until their destruction cue starts.
  Unknown historical positions are skipped instead of guessed.
- Each viewer has separate pending events and snapshots. Switching/covering clears the
  visible timeline; hidden identities never select profiles. If a fresh snapshot hides
  or removes an actor, its obsolete identifying animation is canceled.
- `CardAnimationRegistry.gd` selects profiles by an **already visible name**. Unregistered
  cards use `GenericAnimationProfile.gd`. Register another profile with
  `registry.register_profile(visible_name, profile)`; no director/event rules change.
- A profile implements `duration(action)` and
  `draw(canvas, rect, action, progress, time, defense, target)` for
  `idle`, `summon`, `attack`, `position`, `destroy`. Progress is normalized; a profile
  must restore any CanvasItem draw transform it changes. Profiles can be replaced by
  art-backed renderers later without inventing a second rules engine.

## Verification

```bash
bash Tools/run_tests.sh --import
bash Tools/run_tests.sh SceneAnimationCheck
bash Tools/run_tests.sh SceneBoardCheck
bash Tools/run_tests.sh SceneBoardDuelCheck
bash Tools/run_tests.sh SceneSpikeCheck
bash Tools/run_tests.sh RunHiddenIdentityTests
bash Tools/run_tests.sh RunSessionTests
bash Tools/run_tests.sh RunTests
bash Tools/check_determinism.sh
```

`SceneAnimationCheck` covers all five Portrait beats from real engine actions and
projected events, real production-board/session summon wiring, public-ID/hidden-handle
separation, interruption by a new hidden snapshot, owner-known face-down cards, viewer
handoff, manual cover/uncover, restart, reduced motion, duplicate render drains,
negated summons, Flip Summon coalescing, Special Summon dispatch, non-destruction moves,
profile registration, burst bounding, control/target relocation cancellation and finite completion.

Optional real-render capture (needs a display, not `--headless`):

```bash
ANIMATION_CAPTURE_DIR=/tmp/portrait-animation-captures \
  godot --path . --rendering-method gl_compatibility --audio-driver Dummy \
  --script res://Scripts/tests/CapturePortraitAnimations.gd
```

The capture script writes 15 frames spanning empty/ emerging summon, both position
changes, lunge/slash, crack, split and dust. See `Reports/CARD_ANIMATION_TEST_RESULTS.md`
for measured checks and render environment.

## Remaining limits

- One bespoke procedural profile, with intentionally simple geometry; other monsters
  have abstract generic cues. No production textures, skeletal rigging, sound, particle
  shaders, 3D camera, cinematic cut-ins or animation editor tooling.
- The current compact card art windows are small. The showcase magnifies the same profile
  for review; this does not claim that the production board is finished visual design.
- Effects are cosmetic and do not block actions. Rapid play, new snapshots, handoff or
  bursts beyond 32 pending cues can cancel/skip old effects instead of delaying gameplay.
- A destroyed card must have been publicly observed on the field in that viewer's prior
  snapshot. Cards summoned and removed entirely between prompts lack a trustworthy slot
  and are skipped. No raw engine information is queried to fill that gap.
- The pass-and-play board's existing handoff timing side-channel limitation remains.
- Local Godot 4.6.3 / Mesa compatibility validation is distinct from the project's
  Godot 4.7.1 CI pin and default Forward+ renderer. No remote CI run or publishing is
  implied by local checks.
