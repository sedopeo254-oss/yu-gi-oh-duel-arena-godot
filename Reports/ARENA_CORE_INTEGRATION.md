# Responsive/audio arena + optional native core — local integration

Date: 2026-10-29. Work branch: `codex/arena-core-integrated`.

## Verified inputs and scope

- Audio/visual base: local `0313d6f`, content-identical to remote
  `codex/arena-audio-integrated` at `645ee0bf31016c90392afc2f330989f5a7169157`.
  Both Git trees verified as `d9dbda502c31975cb6f8e911df2b61838c6138ad`.
- Native core/Lua/session/lab input: `9b719c1cca43573d4c45124aba2d64df7483b45e`.
- Source merge had no conflicts. Existing visual assets, animation timeline,
  original sound synthesis, privacy controls and saved preferences are retained.
- The production engine, its session/projection, rules, card data, decks and
  `project.godot` are unchanged. The normal startup remains the arena.

This integrates the **available bounded native slice into the application**, not
all three upstream engines into one ABI or the entire production card pool into
Lua. The native fixture still has two reviewed real cards, one effect and synthetic
decks. The GPL client and AGPL-family KCG remain references; their sources are
not combined into the MIT-core binary. No unlicensed database or scripts are added.

## Entry, cancellation and ownership

**Core lab** is in the responsive toolbar and **Experimental core lab** is on the
cover. Requesting it conceals private UI and cancels current presentation/audio.
The confirmation explicitly says the current duel will end without saving and
returning starts a fresh duel. Cancel preserves the same arena session/prompt.
An absent Linux build shows prerequisites without stopping the arena or silently
building/downloading anything.

Confirmed entry joins/stops the original engine worker, clears private views and
logs, then hosts the native lab in an opaque overlay. **Return to arena** stops
and reaps the native process before deferred overlay removal and one fresh,
covered original-engine duel. Double-clicks cannot duplicate entry/return.
Closing the host while the lab runs also closes its child. Existing sound and
reduced-motion preferences survive the round trip; no lab-to-arena sound events
or animation events are fabricated.

The lab now reflows its toolbar, action buttons and monster grid at narrow window
widths. Scrolling remains necessary for the full field/actions on small screens;
this is not a claim of mobile native-core export support.

## Verification

Local Linux x86_64, Godot **4.6.3**, G++ 14.2, Python 3.12.14. Pinned native build
recreated in this worktree from exact core revision/checksum-verified Lua inputs.

| Check | Result |
| --- | --- |
| Navigation integration | **43 assertions**, PASS |
| Responsive arena | **144 assertions**, PASS |
| Original sound/settings/privacy | **81 assertions**, PASS |
| Event-driven animation | **44 assertions**, PASS |
| Procedural draw checks | **24 assertions / 182 draw states**, PASS |
| Original board interaction | **30 assertions**, PASS |
| Original natural board duel | **134 actions**, LP victory, no rejections/refusals |
| Original hidden identity | **46 assertions**, PASS |
| Original session boundary | **220 assertions**, PASS |
| Native diagnostic | **26 assertions**, PASS |
| Stateful native session | **663 assertions**, PASS |
| Native Newdoria/Lua/privacy/LP finish | **74 assertions**, PASS |
| Native lab interaction | **30 assertions**, PASS |
| Native Python groups | **10**, PASS |
| Python helper tests | **38**, PASS |
| Smoke / main-scene spike | PASS |
| Full original engine suite | **10,653 / 10,653, 101 suites**, PASS |
| Cross-process determinism | **6 duels identical across 2 processes**, PASS |

Navigation covers real Newdoria battle/target resolution through the integrated
entry, confirmation/cancel, absent binary, width changes down to 320×640, cover,
repeated entry/return, old-worker teardown, active child teardown, and retained
sound settings. Independent read-only review additionally exercised actual
Escape input and a separate navigation harness; no privacy/lifecycle blocker found.

Actual Godot OpenGL/Mesa renders were captured and visually inspected for the
main arena, confirmation over an opaque cover, native lab, narrow lab, and
returned arena (1600×900 desktop; 390×844 narrow). This is visual verification,
not a physical-touch or subjective speaker/headphone audition claim.

All runners exited cleanly; no script errors or ObjectDB/resource-leak warnings.
Python compilation, workflow YAML parsing, integration documentation links and
`git diff --check` pass. Regenerating the existing card matrix leaves it unchanged.

## Remaining work / limits

No general database import, complete real-deck construction, full Lua card pool,
native protocol coverage, native presentation/audio event adapter, backend choice
for production duels, native export packaging, CPU opponent or networking is
implemented by this integration. The arena audio/animations work in the original
engine; the separate lab does not acquire those through a cosmetic merge.
General imports need rights/provenance and schema review, then independently tested
card/protocol groups. No public push or remote CI is part of this local checkpoint.
