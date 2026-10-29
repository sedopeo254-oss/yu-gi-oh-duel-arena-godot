# Optional YGOPro-core diagnostic

This project now has a **real, opt-in native core diagnostic** callable from Godot.
It is an integration vertical slice, **not** a replacement gameplay backend. The
playable board, `GameState`, `DuelSession`, and existing verified card effects are
unchanged. A missing binary is a clear error, never a silent fallback or fake pass.

## Which upstream is actually used?

| Requested repository | Role here | License observed |
| --- | --- | --- |
| [Fluorohydride/ygopro-core](https://github.com/Fluorohydride/ygopro-core) | Pinned native core compiled by the opt-in build | MIT |
| [Fluorohydride/ygopro](https://github.com/Fluorohydride/ygopro) | Reference client only; not copied, compiled, or linked | GPL-2.0 repository license |
| [knight00/ocgcore-KCG](https://github.com/knight00/ocgcore-KCG) | Alternative fork to evaluate separately; not linked | AGPL-3.0-or-later plus inherited MIT notices |

All three inspected revisions and distinct roles are recorded in the manifest;
`references_not_linked` entries are provenance, not installed dependencies.
These are not three complementary libraries to combine. The client consumes a
core; KCG is another core family with a different API/protocol. Passing one fork's
structs or responses into another is not supported. Nothing here grants rights
to card art, audio, commercial assets, or card-script collections.

In particular, [Fluorohydride's effect-card scripts](https://github.com/Fluorohydride/ygopro-scripts/blob/master/LICENSE)
use GPL-2.0, not the core's MIT license. No such scripts are used here. A complete
playable stack needs its own license review; process separation is not a blanket
copyleft exemption. The inspected client also pins an older matched core/script
pair than this standalone core probe; the manifest preserves those distinct
revisions rather than pretending they have been tested interchangeably.

The exact core commit and Lua archive checksum are in
[`ThirdParty/ocg/lock.json`](../ThirdParty/ocg/lock.json). MIT copyright/permission
notices for both compiled dependencies are in
[`ThirdParty/ocg/licenses`](../ThirdParty/ocg/licenses). Preserve those notices
when distributing a locally built diagnostic. This does not add an open-source
license to the surrounding project.

## Build and run (Linux development environment)

Requires Python 3.11.4+ (safe tar extraction), Git, and a C++14-capable `g++`.
No system install, Godot extension SDK, Python package, CMake, or card assets are
required. The first command explicitly downloads the pinned MIT sources:

```bash
python3 Tools/build_ocg_probe.py --fetch
python3 Tools/ocg/test_probe.py
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh --import
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh RunOcgCoreTests
```

Subsequent builds omit `--fetch` and use only the verified local cache. An
existing **clean, exact pinned revision** can be supplied with
`--core-dir /path/to/ygopro-core`. The build rejects a wrong revision, changed
checkout, or wrong Lua archive checksum. It builds in `.cache/ocg/`, smoke-tests a
pending executable, and only then replaces `Tools/ocg/bin/ocg_probe`. Downloaded
source, objects, and executable are ignored by Git; they are not prerequisites
for the normal Godot tests.

An interrupted initial fetch can be resumed with `--fetch`. Compilation uses
files extracted from the pinned Git tree, not mutable or ignored checkout files.

Godot usage (development/headless or a worker thread, not the render loop):

```gdscript
var diagnostic := OcgCoreDiagnostic.run(42)
if not diagnostic.ok:
    push_error(diagnostic.error)
else:
    print(diagnostic.report)
```

The adapter validates the JSON schema, pinned core revision, seed, all expected
checkpoints, and transcript digest format. Repeatability tests compare the
actual transcripts' fingerprints; this is not a cryptographic authenticity
check. The adapter passes an argv array rather than a shell
command. The native program has a 10-second wall-clock watchdog and a per-prompt
step/packet-size limit. Each call owns and destroys its own duel in a separate
process, isolating the core's global callbacks from the game and other probes.
This is a synchronous development API. No exported-game path, Windows/macOS,
mobile, web, or GDExtension support is claimed.

## What the native test actually exercises

The native program calls the real `ocgapi.h` functions, not a mocked model:

1. Registers card, script and error callbacks; creates a duel with
   `create_duel_v2` and a documented eight-word seed expansion.
2. Populates two 40-card **synthetic, level-4 Normal Monster** decks and sets
   8000 LP, five opening cards, one normal draw, and the pinned core's current
   Master Rule (2020).
3. Processes actual binary events until player 0 receives an idle command;
   verifies five cards in each hand and five legal Normal Summon candidates.
4. Sends an invalid command; requires the actual core's `MSG_RETRY` and
   unchanged card counts.
5. Shuffles the hand through the core response API, exercising seeded RNG.
6. Selects an actual legal Normal Summon candidate and allowed monster zone;
   verifies one summon, four cards remaining in hand, one monster on field, and
   zero further Normal Summon candidates that turn.
7. Ends the turn through the response API; verifies player 1 reaches Main Phase
   1 with six cards, 34 cards remaining in deck, and six summon candidates.
8. Destroys the duel and emits aggregate counts plus a deterministic transcript
   fingerprint. No raw card identities or gameplay private state cross to Godot.

The fixture's base Lua files are deliberately empty; the core's native logic is
sufficient for these Normal Monsters. A request for any card effect script or
unknown fixture card fails. The protocol decoder likewise rejects unsupported
messages; it does not guess lengths or silently skip unknown prompts. This is
**not evidence of all Yu-Gi-Oh! rules or card effects being supported**.

## Remaining work before a real optional gameplay backend

- Decide the target core family/license and pin matching, separately reviewed
  card database and Lua script versions. Do not mix KCG with this ABI.
- Implement all protocol prompts, per-viewer hidden-information projection,
  response authorization, replay/versioning, cancellation, lifecycle and
  export/platform packaging.
- Map the game's backend/session contract explicitly; test complete real-deck
  duels and every supported effect against the existing engine tests.
- Only then expose an experimental backend selector. Nothing here changes the
  production engine, expands the claimed card roster, or marks core differences
  as official rules. Upstream simulators are secondary behavioral references,
  not Konami rules sources.

## Verification record

See [the local verification record](../Reports/OCG_DIAGNOSTIC_RESULTS.md) for
actual commands/results. CI also explicitly builds and checks the optional
adapter; a developer's ordinary local suite does not. Tests are designed
to fail rather than skip when the optional native runner is explicitly invoked
without its binary. The ordinary Godot suite remains independent of native
build availability.
