# Responsive arena presentation

This pass builds on the playable board and the refined Portrait animation branch
(`0c1bee0`, tree-equivalent to local `b8894b9`). It is
presentation-only: no engine, rules, card effects, session projection, or animation
profiles changed.

## What changed

- A quiet architectural arena backdrop, navy/teal/coral palette, clearer active
  phase and turn-player markers, and life-point meters with explicit numeric LP.
- Original procedural illustrations: alpine daylight for monsters, flowing water
  for spells, protective shields for traps, and woven card backs. These are
  **category illustrations**, not licensed or individually faithful card artwork.
  Nothing was downloaded; there are no copied game assets or occult motifs.
- Names, type/level information, stats, keyboard focus/hover borders and ellipsis
  for long compact names; the inspector retains full names and printed text.
- Desktop keeps the board, legal moves and inspector together. Below 1450 logical
  pixels, **Arena / Moves / Cards & feed** tabs preserve readable text and 48-pixel
  action targets rather than scaling the whole desktop to phone size.
- Below 700 pixels, the five field lanes remain together and side piles move into
  a separate strip. The board scrolls vertically; the hand scrolls horizontally.
  Small-screen phases use D / S / M1 / B / M2 / E, with GY for the graveyard.
  Compact monster stats use separate A (ATK) / D (DEF) rows, preserving all digits.
  Inspector opens when a card is tapped. Repeated tab changes and returning to desktop preserve the prompt.
- **Reduce motion** is stored in `user://presentation.cfg`. It remains cosmetic;
  legal choices never wait for animation. The backdrop is always static.
- A handoff conceals tabs, details, logs and animation together, then returns to
  the Arena tab on reveal. Actor overlays are hidden on non-arena tabs.
- Surrender/new-duel confirmation text wraps within narrow windows.

The regular board still has no CPU opponent, campaign, 3D arena or save/resume. It now
includes [original synthesized action sounds](DUEL_AUDIO.md), with persistent volume/mute
and a touch-sized Sound settings dialog that fits the same narrow layouts. The separate
opt-in Portrait showcase retains its own original synthesized
sound and an atmospheric stage; see `CARD_ANIMATIONS.md`. Touch sizing and layout are tested in desktop windows; physical Android,
iOS, high-DPI devices and screen readers have not been exercised. Pass-and-play
handoff timing retains the privacy limitations in `PLAYABLE_BOARD.md`.

## Verification

```bash
bash Tools/run_tests.sh --import
bash Tools/run_tests.sh SceneVisualCheck
bash Tools/run_tests.sh SceneDuelAudioCheck
bash Tools/run_tests.sh SceneBoardCheck
bash Tools/run_tests.sh SceneBoardDuelCheck
bash Tools/run_tests.sh SceneAnimationCheck
bash Tools/run_tests.sh SceneAnimationRenderCheck
bash Tools/run_tests.sh SceneSpikeCheck
bash Tools/run_tests.sh RunTests
```

`SceneVisualCheck` now has 144 assertions (the original 125 plus 19 audio integration
checks) using the actual board/session at 1600×900,
1280×720, 800×600, 480×900, 390×844, 360×800 and 320×640. It checks resize/prompt
preservation, visible tab button connections, all five phone lanes fitting, large
opponent hands wrapping, reachable reduced-motion controls, 48-pixel targets,
inspector opening, actor concealment, private handoff, confirmation fit,
preference reload and returning to the desktop layout. Sound-button reachability,
first-open dialog fit, touch-sized audio controls and resize while open are also checked.
Existing gameplay/privacy and animation assertions remain intact.

A reproducible visual capture drives a real Normal Summon, then saves desktop,
tablet, phone, moves, inspector and cover PNGs, plus a labeled synthetic 3000/2500
stat-layout fixture at four compact card widths:

```bash
godot --path . --rendering-method gl_compatibility --audio-driver Dummy \
  --script res://Scripts/tests/CaptureArenaPresentation.gd
```

It requires an available display. Output defaults to `user://arena-previews`;
`DUEL_ARENA_PREVIEW_DIR` can select a local output directory. The local inspection
used Godot **4.6.3** with Mesa/OpenGL, not CI-pinned 4.7.1 or Forward+. Screenshots
were visually inspected at 1600×900, 1280×720, 390×844 and 320×640 before audio integration.
The audio integration's layout checks are headless; its screenshot attempt could not
create an X11 display in the sandbox. Independent
read-only review found no remaining blocker after the narrow-stat correction.
This is not a claim of full human-playthrough or hardware-touch acceptance.
