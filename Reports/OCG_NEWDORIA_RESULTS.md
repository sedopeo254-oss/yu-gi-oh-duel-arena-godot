# Native Newdoria/Lua/battle UI verification — 2026-10-29

Local environment: Linux x86_64, G++ 14.2, Python 3.12.14, Godot 4.6.3.
Pinned core `c4ccbab40702e4af6da4f4ad1d7a04c3ea80ad02`, Lua 5.4.8.
This is an opt-in arranged-board/two-real-card slice, not full real-deck coverage.
Remote CI and exported-game/non-Linux behavior have not been verified.

## Real native behavior

- Official Portrait/Newdoria metadata is strictly converted from owned JSON;
  `04335645` preserves its printed form and becomes integer core ID `4335645`.
- Newly authored Newdoria Lua SHA-256:
  `0a26731b4681e555ed0e0a98c9a964295562c0b842565e83507e066dbddfe3dc`.
- On ordinary turn 2, Portrait attacks Newdoria in face-up Defense Position.
  Newdoria reaches the GY by `REASON_BATTLE`; its mandatory chain targets and
  destroys Portrait by `REASON_EFFECT`. One solved chain, LP `[8000,8000]`,
  graveyard counts `[1,1]` and empty fields.
- An own-field Portrait variant proves targeting is not restricted to opponents:
  graveyards `[2,0]`, with the attacking opposing Portrait still on the field.
  Both variants pass at seeds 0, 42 and 4294967295. The pinned core auto-enqueues
  this forced trigger; these runs produce zero separate chain-decline prompts.
- Equal-ATK mutual battle destruction leaves no monster targets. The mandatory
  chain still resolves once, with two battle-destroyed cards and **zero**
  fabricated effect destruction.
- Predicate-level Lua negative controls reject effect destruction in the GY,
  battle destruction outside the GY, and effect destruction outside the GY.
  They do not substitute for full-duel banishment/replacement tests.
- The same persistent Godot-controlled duel continues after Newdoria's effect
  to actual player-0 LP victory (native reason code 1), with the defeated LP
  displayed as zero and both terminal messages withheld until clean child exit.

## Passed checks

- **72 Godot real-card assertions:** native battle/target flow, correct metadata,
  same-session LP victory, rich-view privacy, unknown hidden fields rejected,
  occupancy/number validation and matching terminal projections.
- **30 main-loop lab assertions:** field/name/stat rendering, active-player cover,
  real button-driven effect resolution, double-click prevention, hidden identity
  ignored by rendering, restart, Close and native child cleanup.
- **663 session assertions:** original stateful tests plus deterministic final-output
  race regression. The worker may write terminal output between the final read
  and its exit; the adapter drains again and does not falsely reject that finish.
- **26 original diagnostic assertions** and unchanged seed-42 fingerprint
  `374a2c7c8549d21e`.
- **10 native Python groups**, including all prior normal-session tests and new
  Newdoria variants; **38 Python tooling tests**, including metadata validation.
- Actual Godot OpenGL/Mesa renders captured and visually inspected at 1600×900:
  opening, attack selection and resolved battle. Five-zone rows, labels, LP,
  choices and final GY counts fit without overlap; no card art is claimed.

Independent review found no blocker in the authored effect, battle response
encodings, viewer redaction, matching terminal projections or final-drain fix.
The scene is opt-in; normal startup and the existing engine remain untouched.

Final aggregate regression: **10,653 / 10,653 existing assertions** across 101
suites; original board interaction and natural LP-win duel; six deterministic
duels byte-identical across two independent processes. Existing card matrix
regeneration is unchanged. Strict integration-unit C++ warnings-as-errors check
(pinned third-party headers marked as system includes), Python compilation,
workflow YAML parsing, local documentation links and `git diff --check` pass.
Full pinned build is verified from immutable core and checksum-verified Lua inputs.
