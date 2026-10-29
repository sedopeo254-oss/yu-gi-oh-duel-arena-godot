# Responsive arena + original audio integration — 2026-10-29

Branch: `codex/arena-audio-integrated`, based on responsive visual commit `c31aeb7`.
Integrates original audio commit `c8f58a1`. Local-only integration; no push or remote CI.

## Preserved and resolved

- Preserved original arena/card illustrations, LP meters, phone lanes, tab navigation,
  handoff cover, animation profiles, and saved reduced-motion preferences.
- Added original action audio, saved mute/volume, timeline/privacy cancellation, and
  replaceable AudioStream resources. No third-party audio was acquired or included.
- Resolved `DuelBoard.gd` and `PROJECT_STATE.md` conflicts by retaining both features,
  not replacing either header, preference system or presentation checkpoint.
- Sound lives in the responsive wrapping toolbar and is also reachable on the cover.
  The settings dialog adapts to viewport width, including resize while open; volume
  and mute have 48-pixel touch targets.

## Integration defects caught and corrected

1. The visual branch's shared button helper wraps text. Without an explicit width,
   Sound collapsed to **20×196 pixels** in the flow toolbar. It now has a 120-pixel
   minimum width and measures **120×48**.
2. The wrapped description initially measured at nearly zero width, making the first
   settings dialog **2578 pixels tall**. Its actual text/content width is established
   before popup minimum-size calculation and refreshed on resize. First and repeated
   opens now fit through **320×640**.
3. The audio test originally inherited headless SceneTree's **64×64** default window.
   The responsive board correctly followed that size, unlike the previous fixed-size
   board. The integration test now explicitly creates the supported **1600×900**
   desktop viewport before instantiating the board; no assertion was weakened.

## Verification

Local Linux / Godot **4.6.3**, headless/Dummy audio, using the repository runners:

| Check | Result |
| --- | --- |
| SmokeCheck | PASS |
| Responsive `SceneVisualCheck` | **144 assertions**, PASS (original 125 + 19 audio/layout checks) |
| `SceneDuelAudioCheck` | **81 assertions**, PASS |
| `SceneAnimationCheck` | **44 assertions**, PASS |
| `SceneAnimationRenderCheck` | **24 assertions / 182 draw states / 0 errors**, PASS |
| `SceneBoardCheck` | **30 assertions**, PASS |
| Natural board duel | **134 accepted actions**, turn-6 LP-zero result, no refusals/rejections |
| Main-scene spike | Real Normal Summon, PASS |
| Hidden identity | **46 assertions**, PASS |
| Session boundary | **220 assertions**, PASS |
| Full engine regression | **10,653 assertions / 101 suites**, PASS; counts unchanged |
| Cross-process determinism | **6 duels**, identical across 2 processes |
| Python helper tests | **26 tests**, PASS; card matrix regeneration unchanged |

No final script errors or ObjectDB/resource leak warnings. Independent read-only review
rechecked first/repeated dialog opens and button geometry from desktop through 320×640,
and found no remaining logic/privacy blocker. Engine, rules, cards, session projection,
decks and card data are unchanged.

The visual branch's earlier screenshots are not new audio-integration screenshots.
Screenshot creation for this audio work was blocked by denied X11 listening sockets;
new layout verification is headless. No subjective listening match to official anime
or game recordings, physical touch hardware test, Godot 4.7.1 CI run, or publication is claimed.
