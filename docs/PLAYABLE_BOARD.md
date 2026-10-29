# First playable 2D duel board

`Scenes/ui/DuelBoard.tscn` is now the default F5 scene. The original
`Scenes/ui/DuelSpike.tscn` remains available for session debugging.

This is an early **local two-human-player** client for the existing 77-card engine,
not a finished Duel Generation equivalent. There is no CPU opponent, campaign,
collection progression, networking, 3D arena, audio, save/resume or replay browser.
The board now has an [event-driven animation prototype](CARD_ANIMATIONS.md), with a separate
opt-in Portrait showcase; these are procedural placeholders, not finished artwork.
The UI is English. All illustrations are original procedural vector placeholders;
no Konami game artwork has been copied or downloaded.

## Playing

1. Open `project.godot` in Godot and press F5. The two existing real decks load.
2. Pass the screen to the named player and click **I am ready**.
3. Use the right-hand action panel. Every action was offered by `EngineSession`;
   the UI never decides legality or implements effects.
4. Click cards for printed text and current statistics. Graveyard and banished
   buttons list the cards the current viewer may inspect.
5. When an action needs targets, tribute groups or positions, select the required
   options and confirm. **Back to actions** cancels an unsubmitted action.
6. Resolution choices support optional zero picks, every allowed selection count,
   and custom trigger ordering. Choices are not capped at the spike's twelve
   combinations. Position choices are named; unknown/hidden card identities are
   never reconstructed from a deck list.
7. A player change covers the entire screen, including hands, inspector and log.
   **Cover board / Escape** also hides it manually. Each player gets only their
   own session view and event feed.
8. **Surrender** requires confirmation. **New duel** requires confirmation and
   starts a fresh seed; after a result, **Play again** starts another duel.

### Privacy scope

The cover prevents accidental display of the next player's private cards. It is
**not a claim of full side-channel-safe shared-screen play**: the timing and
frequency of handoffs can disclose that the other player received a prompt.
A fully analyzed handoff/timing policy remains separate work. Players must still
look away before the other player reveals their screen. Opaque hidden-card
handles at the session boundary are supplied by the separate identity fix.

## Structure

- `Scripts/ui/DuelBoard.gd`: session polling, board/inspector/log presentation,
  guarded submissions, cover and confirmation flows, selection wizard.
- `Scripts/ui/ArenaCard.gd`: original vector card faces/backs; never infers hidden
  identities. Printed text is looked up by an already visible card name only.
- `Scripts/ui/ArenaBackdrop.gd`: original geometric arena background.
- `Scripts/tests/SceneBoardCheck.gd`: real-main-loop board and flow regressions.

The only gameplay boundary is `EngineSession`. No engine objects are retained or
queried by the UI. Submissions carry an offered-action index or decision indices;
all legality remains revalidated by the existing worker-thread engine.

## Verification

```bash
bash Tools/run_tests.sh --import
bash Tools/run_tests.sh SceneBoardCheck
bash Tools/run_tests.sh SceneSpikeCheck
bash Tools/run_tests.sh SceneBoardDuelCheck
bash Tools/run_tests.sh RunTests
```

`SceneBoardCheck` covers initial concealment, covered-input rejection, reveal,
opening hand rendering, min/max choice bounds, deselection, trigger permutation,
position labels, all tribute groups, a real successful Normal Summon, player
handoff, hidden-card inspection, manual cover, restart cleanup, surrender
cancel/confirm and game-over/rematch UI. `SceneSpikeCheck` continues to drive the
configured main scene and assert a real successful Normal Summon.
`SceneBoardDuelCheck` runs an unarranged duel through the board handlers to a
natural result, rejecting stale/refused submissions. Its conservative test-only
policy summons, tributes and attacks but passes optional effects; it is not a
CPU-opponent feature or coverage of every card-specific decision.

The first local validation used the environment's installed **Godot 4.6.3**, not
the repository's CI-pinned 4.7.1. The board was also rendered with Mesa/OpenGL at
1600×900 and visually inspected. Default Forward+ and other devices are not
visually verified by that check. Full human playthroughs and all card-specific
UI combinations remain broader acceptance work; engine regression tests do not
substitute for those UI checks.
