# Stateful native reference session (experimental, fixture-only)

This is the next milestone after the fixed [OCG diagnostic](OCG_CORE_DIAGNOSTIC.md):
one **real, persistent native duel per isolated child process**, controlled from
Godot through nonblocking pipes. It executes user-selected core choices instead
of replaying a hard-coded smoke scenario.

**It is not the production game's backend.** `EngineSession`, `DuelBoard`, real
decks, card effects and normal startup are unchanged. It is not a drop-in
`EngineSession` substitute: snapshots contain only public counts, and all
supported decisions use offer indices. No battle, real card database, effect Lua,
networked opponent, card artwork, or animation is supplied by this milestone.

## Supported scope

- Two synthetic 40-card level-4 Normal Monster decks; player 0 starts.
- Normal Summon, selecting a legal main monster zone, shuffling one's own hand,
  ending turns and choosing one hand-limit discard.
- Actual core-driven deck-out completion, including both viewer results and
  native duel destruction. The supported choices are explicitly a **subset** of
  the core's possible actions; battle, setting and position changes are omitted.
- Independently numbered player prompts; wrong-player, stale and out-of-range
  responses rejected by the native process, not merely by UI convention.
- Public deck/hand/monster/graveyard counts; no card codes, instance IDs, seeds,
  raw events or private card data leave the native process.

This is a development reference fixture, not a deck legality claim or a claim
that any real card matchup is playable. The core still enforces the actions
actually selected, including the once-per-turn Normal Summon allowance.

## Build and use

```bash
python3 Tools/build_ocg_probe.py --fetch  # first build; cached builds omit --fetch
python3 Tools/ocg/test_probe.py
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh --import
GODOT_BIN=/path/to/godot bash Tools/run_tests.sh RunOcgSessionTests
```

The same pinned MIT core/Lua dependencies and license notices as the diagnostic
apply. Only Linux development use is implemented; no exported-game or other
platform support is claimed.

```gdscript
var reference := OcgReferenceSession.new()
if not reference.start_fixture(42):
    push_error(reference.last_error())

# In the owner thread's frame loop; poll() does not block:
for viewer in [0, 1]:
    for message in reference.poll(viewer):
        if message.type == "prompt":
            # Present only to message.player. Labels describe core-offered choices.
            # On a later user selection:
            reference.submit(message.player, message.prompt_id, {"offer": chosen_index})

# On Close, cancellation or owner teardown:
reference.stop()
```

`start_fixture()` starts at most once. `poll(viewer)` drains copied dictionaries
from that player's channel. `submit()` permits one request in flight and returns
whether it was queued, **not** whether the core accepted it. A `rejected` message
leaves the same prompt open. The producer accepts only `ANSWER player prompt_id
choice` or `STOP`; no shell command, script path or arbitrary core response is
accepted. `stop()` is idempotent, cooperatively requests shutdown and caps its
wait at 250 ms before killing the owned child. Dropping the last reference also
terminates the child. EOF on the parent pipe destroys the native duel.

Messages are `prompt`, `rejected`, `over`, `error` or `stopped`. Prompts contain
`player`, `prompt_id`, `mode` (`ACTION` or `DECISION`), `offers` (`kind`, `label`)
and the count-only `view`. The `ready` handshake stays inside the adapter.

## Failure and privacy boundary

Godot uses [`OS.execute_with_pipe(..., false)`](https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-execute-with-pipe),
buffers partial lines across polls and limits per-poll work and packet size.
The native worker limits input lines and total commands, and applies its
10-second watchdog **while processing**, not while a person is deciding.
Godot also bounds awaited responses. A complete duel needs two consistent
terminal reports **and a confirmed zero child exit** before either `over` result
is published. A crash after printing success is an error; incomplete or hung
completion is bounded and terminates the process.

The adapter rejects unknown top-level fields, extra offer fields, unsupported
actions/modes, malformed IDs, non-count snapshot fields, duplicate terminal
reports and inconsistent terminal results. A player's channel receives only
their own prompts/rejections and the terminal result. No global prompt counter
is exposed. Wrong-player rejections do not republish the active player's prompt.
This does not claim full shared-screen timing privacy, OS-level sandboxing, or
the ability to execute untrusted effect scripts safely.

## Next real-card/Lua/UI milestone

A bounded next slice should use existing verified project data, not pretend
that all 77 GDScript effects become Lua-compatible automatically:

1. **The user-selected real-card pair:** The Portrait's Secret (`32541773`, a
   level-4 EARTH Fiend Normal Monster, 1200 ATK / 1500 DEF) and Newdoria
   (`04335645` printed, integer core ID `4335645`, level-4 DARK Fiend Effect
   Monster, 1200 ATK / 800 DEF). Record official data provenance explicitly;
   do not redistribute a third-party database with unclear rights.
2. **A reviewed minimal Newdoria Lua effect.** Implement the mandatory trigger
   when it is destroyed by battle and sent to the GY, targeting any monster on
   either field and destroying the still-related target at resolution. Use
   the official text and pinned core API, not an invented optional effect or
   opponent-only restriction. No GPL script collection is silently imported;
   choosing upstream scripts requires its own license and matching-version review.
3. **A genuine battle scenario.** On normal turn 2, Portrait attacks Newdoria in
   face-up Defense Position. Newdoria reaches the GY; its mandatory trigger at
   the end of the Damage Step targets and destroys Portrait. Verify both
   graveyards, target authorization, chain resolution and unchanged LP.
4. **Protocol/projection/UI expansion.** Decode actual battle, forced-chain and
   target prompts before exposing this narrow slice in a separate opt-in UI.
   Retain hidden-information filtering and lifecycle checks. Keep the existing
   playable board/engine as default; expand one tested effect group at a time.

The source of truth remains the project's official rules trail and existing
card tests. A native simulator is a secondary reference, not a replacement for
that evidence. See [the session verification record](../Reports/OCG_SESSION_RESULTS.md).
