# Native real-card practice pool — bounded, experimental

The native lab now offers an empty-field duel using six real Normal Monsters
from the existing project pool. Both players draw, summon/set, change battle
position or Flip Summon when legal, attack and finish by native LP loss or
deck-out. This remains separate from the normal arena's original engine.

## Play

Build the optional Linux binary as described in [the core guide](OCG_CORE_DIAGNOSTIC.md).
Enter **Core lab** from the arena, then select **Practice · Mixed Normal Monsters**
or **Practice · Dragons + Normal Tuner** and press **Start / restart selected**.
Selection alone does not stop a current duel; Start explicitly restarts it.
The Newdoria Lua battle scenario remains the default mode.

The two practice presets contain 40 real card entries and start with empty fields.
They deliberately exceed three copies per card: six supported names cannot fill a
legal 40-card deck. **These are not tournament-legal decks.** Both players use the
same preset composition, shuffled independently with deterministic seeded
Fisher–Yates and rejection sampling. The host must shuffle starting decks; the
core API does not do that automatically. Repeating a seed reproduces the layout,
not a secure online shuffle. The UI uses seed 42 for repeatable practice.

Your hand panel shows only your own names/stats and slot numbers. Normal Summon
and Set offers refer to those slots. An opponent's hand has no identities; an
opposing face-down monster has no code or stats. Handoff/cover hides the private
hand with the field. Set uses the turn's Normal Summon/Set allowance; a newly Set
monster cannot immediately Flip Summon. The core—not UI heuristics—decides that.

## Exactly which cards?

| Card | Printed passcode | Level / Attribute / Race | ATK / DEF | Additional type |
| --- | --- | --- | --- | --- |
| Alexandrite Dragon | 43096270 | 4 / LIGHT / Dragon | 2000 / 100 | Normal |
| Flamvell Guard | 21615956 | 1 / FIRE / Dragon | 100 / 2000 | Normal **and Tuner** |
| Gladiator Beast Andal | 90582719 | 4 / EARTH / Beast-Warrior | 1900 / 1500 | Normal |
| Luster Dragon | 11091375 | 4 / WIND / Dragon | 1900 / 1600 | Normal |
| Sabersaurus | 37265642 | 4 / EARTH / Dinosaur | 1900 / 500 | Normal |
| Zure, Knight of Dark World | **07459013** | 4 / DARK / Fiend | 1800 / 1500 | Normal |

Official sources: [Alexandrite](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=9863&ope=2&request_locale=en),
[Flamvell](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=7535&ope=2&request_locale=en),
[Andal](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=7365&ope=2&request_locale=en),
[Luster](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=5644&ope=2&request_locale=en),
[Sabersaurus](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=6796&ope=2&request_locale=en),
[Zure](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=6497&ope=2&request_locale=en).

Native alias values are zero. Archetype encodings are retained: Flamvell `0x2c`,
Gladiator Beast `0x1019`, Saber `0x0d` (not X-Saber), Dark World `0x06`;
Alexandrite/Luster have no setcode. Encodings were cross-checked against the pinned
simulator data/strings, not imported as a database bundle. Normal status is not
lost because a name belongs to an archetype: Andal has no tag-out script and Zure
has no discard effect. Tuner metadata is preserved, but Synchro/Extra Deck play
is **not** implemented by this slice. These six cards need no card Lua scripts.

## Safe offline metadata admission

```bash
# Preview/validate existing data without writing anything:
python3 Tools/import_ocg_cards.py
# Regenerate the committed normalized subset:
python3 Tools/import_ocg_cards.py --output Data/reference_cards/native_pool.json
# Optional user-supplied JSON in the same cards-array schema:
python3 Tools/import_ocg_cards.py --source /path/to/owned-cards.json --output /path/to/validated-pool.json
```

This importer is intentionally constrained, not a promise of arbitrary card or
SQLite `.cdb` support. All six approved records are required. It ignores other
well-formed source passcodes instead of silently admitting unsupported cards;
for approved IDs it requires exact reviewed facts/types and rejects duplicates,
missing records, malformed passcodes and coerced numeric/boolean types. Only the
selected numeric facts and official names/URLs are emitted; source descriptions,
paths, executable code and effect text are not loaded into the native provider.
The input must be a regular file and is bounded before parsing.

The build revalidates `native_pool.json` against the existing project data and
fixed reviewed list. An edited pool cannot silently alter card behavior. Its byte
SHA-256 is embedded into the native binary and checked by the Godot ready handshake,
including the selected profile. A stale binary fails closed with rebuild guidance.
This protects accidental mismatch; it is not a cryptographic trust system against
someone who can edit the application and its manifest together.

## Script boundary

`Data/reference_cards/scripts.json` explicitly admits only the project-authored
Newdoria code, exact local filename and reviewed SHA-256. Build-time validation
rejects extra scripts, different IDs/paths, hash mismatch and paths escaping the
project root; reads are bounded. The runtime core receives in-memory callbacks,
not an arbitrary filesystem reader. Practice decks use only scriptless Normal
Monsters. No UI/JSON argument can execute an arbitrary Lua file, load a database,
fetch a URL or run a shell command.

A new real effect still requires independent rules/API review, an authored or
rights-cleared script, supported protocol decisions and tests before expanding
that allowlist. This is not a sandbox for untrusted Lua.

## Tests and limits

```bash
python3 -m unittest discover -s Tools -p 'test_*.py'
python3 Tools/ocg/test_probe.py
python3 Tools/ocg/test_practice.py
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh RunOcgPracticeTests
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh SceneOcgPracticeCheck
```

See [verification](../Reports/OCG_PRACTICE_RESULTS.md). No Tribute Summon, spell/trap
activation, general deck editor/import, broad effect library, Extra Deck, banlist,
networking, native animation/audio event adapter or exported-game native packaging
is claimed. Original arena rules, cards, sounds and animations remain unchanged.
The next useful expansion is a reviewed effect/Tribute family plus its exact
protocol decisions, then enough supported cards and deck validation for legal decks.
