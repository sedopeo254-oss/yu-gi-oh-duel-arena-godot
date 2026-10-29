# Native Newdoria battle lab — experimental Linux slice

A real persistent Fluorohydride-core duel now loads two reviewed card records,
executes an authored Newdoria Lua effect, and receives choices from a separate
Godot UI. **The original `EngineSession`, playable board, card roster, main
scene and existing effects are unchanged.** This is not a full YGOPro client,
a merge of incompatible cores, or a complete real-deck implementation.

## Additional selectable practice mode

The same lab now offers [six reviewed real Normal Monsters](OCG_PRACTICE_POOL.md)
with empty-field starting positions, private hand identities, Set/Flip/position
choices and two seeded practice presets. That later mode is distinct from this
page's unchanged Newdoria arranged-board scenario; its copy limits are explicitly
relaxed and it is not a complete legal-deck backend.

## Integrated arena entry

The responsive, audio-enabled arena remains the normal startup scene. **Core lab**
in its toolbar, or **Experimental core lab** on the handoff cover, opens a scope
warning and asks for confirmation before ending the current duel. Cancel keeps
the existing session/prompt intact and the screen covered; reveal to resume.
If the optional Linux binary is missing, the arena stays alive and a build
instruction is shown. The UI never downloads, builds or installs dependencies.

After confirmation the old arena worker is stopped, private views/logs cleared,
and the separate native lab is hosted above the covered arena. **Return to arena**
stops/reaps the native child and starts one fresh original-engine duel. Repeated
clicks cannot launch multiple labs or multiple returning duels. Sound/mute and
reduced-motion preferences remain intact. Existing arena audio/animations are
preserved; they are not connected to the lab’s different native event protocol.
The lab reflows its controls at phone widths but is still a Linux development
feature, not a mobile/exported native-core package.

## Run it

```bash
python3 Tools/build_ocg_probe.py --fetch  # explicit first download; omit --fetch when cached
/path/to/godot --path . --editor --import
/path/to/godot --path . res://Scenes/dev/OcgBattleLab.tscn
```

Alternatively, open `Scenes/dev/OcgBattleLab.tscn` in Godot and run the current
scene (F6). Normal F5 startup still opens the original board. On a software-only
Linux display, add `--rendering-method gl_compatibility`.

1. Reveal for **Player 1**, then choose **End turn**.
2. Pass/reveal for **Player 2**, enter Battle Phase, attack from monster zone 1,
   and select Player 1's zone 1 (Newdoria).
3. Pass/reveal for **Player 1**. Newdoria is already in the GY; select Player 2's
   zone 1 (The Portrait's Secret) as its mandatory effect target.
4. Both monsters are now in their owners' GYs. LP stays 8000–8000. Continue
   summoning and attacking with synthetic Normal Monsters until the core
   reports an LP win or deck-out, or close/restart the fixture.

Choices always come from the native core. Submitting immediately consumes the
UI prompt, preventing double-clicks. Handoff and Escape cover the field; restart
and Close terminate the previous native child. There is no AI, network peer,
card artwork or animation in this lab.

## Card data and Lua provenance

`Data/reference_cards/newdoria_battle.json` contains only these reviewed facts:

| Card | Printed passcode / core integer | Attributes | ATK / DEF |
| --- | --- | --- | --- |
| The Portrait's Secret | `32541773` / `32541773` | Level 4, EARTH, Fiend, Normal | 1200 / 1500 |
| Newdoria | `04335645` / `4335645` | Level 4, DARK, Fiend, Effect | 1200 / 800 |

Primary evidence: [Portrait, Konami CID 5219](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=5219&ope=2&request_locale=en),
[Newdoria, Konami CID 5484](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=5484&ope=2&request_locale=en),
and [Newdoria's Japanese timing/ruling supplement](https://www.db.yugioh-card.com/yugiohdb/faq_search.action?cid=5484&ope=4&request_locale=ja).
Newdoria's effect is mandatory after battle destruction and reaching the GY,
at the end of the Damage Step; it targets one monster on either field and
destroys the still-related target. Equal-ATK mutual destruction also triggers it.

`Tools/ocg/lua/c4335645.lua` is newly authored against those rules and the pinned
core API, not copied from an upstream card-script collection. The build converts
strictly validated metadata and the owned Lua source into an embedded header,
preserves the printed leading zero, and records the script SHA-256. Lua constants
are exported from the actual pinned MIT core headers. Empty utility/procedure
fixtures are sufficient for this one script, not for arbitrary card scripts.

No third-party `.cdb`, card art or GPL card-script bundle is redistributed.
The existing [core/Lua pins and notices](OCG_CORE_DIAGNOSTIC.md) still apply.
The GPL YGOPro client and AGPL-family KCG fork remain references, not linked
engines. This work does not relicense the surrounding project.

## Session and privacy boundary

`OcgReferenceSession.start_newdoria_fixture(seed)` opts into the richer mode.
`start_fixture(seed)` retains the original count-only Normal Monster mode.
Both use the same bounded nonblocking pipe/ownership/exit checks documented in
[the session adapter](OCG_REFERENCE_SESSION.md).

The battle mode adds core-offered battle entry, attacks, single monster targets,
chain offers and Main Phase 2. Supported actions remain a deliberate subset;
unknown native messages fail closed. Snapshots contain both players' LP and
public zone counts, plus five main monster slots each. A known card includes
code, ATK and DEF only when face-up or controlled by the viewer. An opposing
face-down card has only slot, position and `known: false`. Hand/deck identities
remain absent. Unknown extra message/offer/view/card fields are rejected.
The displayed phase is a broad phase, not a Damage Step subphase indicator.

Two matching terminal results and confirmed exit zero are required before
success is delivered. Terminal-view comparison masks permitted differences in
concealed identities; the lab renders only its current viewer's report.
These checks are not an OS sandbox for untrusted scripts or a claim of complete
shared-screen timing privacy.

## Verification and remaining work

```bash
python3 Tools/ocg/test_probe.py
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh RunOcgNewdoriaTests
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh SceneOcgBattleLabCheck
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh SceneCoreNavigationCheck
# Target either side, or test a mandatory trigger with no surviving target:
Tools/ocg/bin/ocg_probe --newdoria --seed 42
Tools/ocg/bin/ocg_probe --newdoria --seed 42 --target-own
Tools/ocg/bin/ocg_probe --newdoria --seed 42 --mutual
```

See [measured results](../Reports/OCG_NEWDORIA_RESULTS.md). The opening field is
arranged, both 40-card decks are synthetic, and only two real records/one real
effect are admitted. No claim is made that all production cards/decks now work.
The tests cover a full LP finish after the Newdoria effect, not a comprehensive
rules/conformance suite. Negative effect-destruction/non-GY checks exercise the
Lua condition directly; they are not full-duel banishment/replacement scenarios.

Next bounded expansion: a rights-reviewed user-supplied card-data import format,
real deck construction/validation, another effect family and its protocol choices,
then production-board integration behind an explicit backend choice. That work
must retain the original engine and independently test scripts, hidden information
and platform packaging. General script/database loading remains intentionally absent.
