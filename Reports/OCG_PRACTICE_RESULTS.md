# Native practice pool — local verification (2026-10-29)

Based on integrated arena/core/audio checkpoint `e015347`, developed separately
on `codex/native-practice-pool`. Linux x86_64, Godot 4.6.3, G++ 14.2, Python 3.12.14.
No public push, remote CI or exported-game support is claimed.

## Demonstrated expansion

- Six existing low-level Normal Monsters are admitted through strict offline
  metadata validation, with official names/stats, Flamvell's Tuner bit, archetype
  encodings and Zure's printed leading zero preserved. Alias values are zero.
- Two selectable, real-card 40-entry practice presets start from empty fields.
  Copy limits are deliberately relaxed; these are not legal tournament decks.
- Starting decks are explicitly shuffled by the host with seeded per-player
  `std::mt19937` streams, deterministic Fisher–Yates and rejection sampling.
  The core API does not automatically shuffle host-provided starting decks.
- Native Set, later Flip Summon and face-up battle-position changes work. A Set
  consumes the Normal Summon/Set allowance, and repeated position changes are not
  invented when the core does not offer them.
- Actual battle into a face-down defender reveals/resolves it through the core,
  removes the weaker defending monster and causes no invented LP damage.
- Owner hand identities/stats are available only on that viewer's channel.
  Opponent hand arrays are empty, and face-down opposing monsters have no code
  or stats. Unknown fields and unapproved card codes fail closed.
- Script admission is an explicit exact code/path/SHA-256 manifest for the
  existing authored Newdoria script. Arbitrary Lua/path/URL imports are rejected;
  practice cards need no effect scripts. Reads are bounded before parsing.
- Native readiness includes the selected profile and embedded metadata hash;
  Godot rejects a changed pool/stale metadata binary and reaps its process.

## Passed final checks

| Check | Result |
| --- | --- |
| Native practice wrapper | **55 assertions**, PASS |
| Practice mode/hand UI | **32 assertions**, PASS |
| Native practice Python groups | **5**, PASS |
| Original native Python groups | **10**, PASS |
| Import/build/Python helper tests | **47**, PASS |
| Original native diagnostic | **26 assertions**, PASS |
| Original native session | **663 assertions**, PASS |
| Newdoria battle/Lua/LP session | **74 assertions**, PASS |
| Newdoria lab UI | **30 assertions**, PASS |
| Arena/core navigation | **43 assertions**, PASS |
| Responsive arena layout | **144 assertions**, PASS |
| Original audio | **81 assertions**, PASS |
| Original animation | **44 assertions**, PASS |
| Procedural draw-path checks | **24 assertions / 182 draw states**, PASS |
| Original engine regression | **10,653 assertions / 101 suites**, PASS |
| Original hidden identity / session | **46 / 220 assertions**, PASS |
| Original board / natural duel / spike / smoke | PASS |
| Cross-process determinism | **6 original-engine duels identical across 2 processes**, PASS |

The practice native tests cover Set/Flip/position flow, hidden field/hand snapshots,
face-down battle destruction, LP wins for both profiles at seeds 0, 42 and uint32-max,
repeatable same-seed and differing-seed opening hands, and invalid profiles including
an empty string/path/shell-looking text. Godot continues a Set/Flip practice session
through native LP victory and validates both private terminal projections only
after clean exit. The wrapper count changed from 64 before host shuffling to 55
because the seeded hand needs fewer core choices for that scripted LP finish;
no assertions or acceptance conditions were removed.

UI tests cover profile selection without side effects until Start, process cleanup
on restart, correct private names/slots, ignoring a planted opponent hand, handoff
cover, actual Set/Flip buttons and responsive controls down to 320×640.

## Corrections and review

1. An empty native CLI profile initially fell back to the old scenario, even though
   Godot rejected it. Native entry now requires exactly `mixed` or `dragons` and
   the empty-string regression fails closed.
2. Long dropdown labels exceeded phone width. Shortened labels and clipped text
   now pass both narrow UI checks without reducing touch target height.
3. Starting-deck shuffling must be host-provided, so explicit tested shuffling was
   added before calling `start_duel`; original diagnostic output is unchanged.

Independent read-only review found no metadata/script-boundary, protocol, shuffle
or privacy blocker. On the **final shuffled build**, it independently completed
**122 randomized two-sided LP duels**, checked **6,525 hidden-field projections**,
and observed a maximum of 383 responses. A further **six no-action deck-outs**
(both profiles × seeds 0, 42 and uint32-max) each ended at turn 72 after 139
responses with clean exit. Tracking every draw/discard proved exactly 40 cards
per player and identical expected composition: mixed 7/7/7/7/6/6, Dragons 14/13/13.
These final results are separate from the earlier 120 pre-shuffle stress runs.

Full pinned native rebuild, strict integration-unit warnings-as-errors check
(third-party headers marked as system includes), Python compilation, YAML parsing,
normalized-pool reproducibility and `git diff --check` pass. Card matrix regeneration
is unchanged. No final test-runner script/resource-leak warnings.

Actual Godot OpenGL/Mesa screenshots were inspected for desktop and narrow practice
selection, owner hand/actions and return to the arena. This does not verify physical
touch hardware, subjective sound audition or mobile native-core packaging.

## Still outside scope

No generic `.cdb` loader, arbitrary Lua execution, legal deck editor/banlist,
Tribute/Synchro/Extra Deck suite, broad effects, native animation/audio event adapter,
AI/networking or production-backend switch. The existing 77-card arena engine,
original sound and animation behavior remain intact. See
[`docs/OCG_PRACTICE_POOL.md`](../docs/OCG_PRACTICE_POOL.md) for admission and use.
