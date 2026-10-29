# Original duel sound effects

The playable board now has four original, generated-in-code action sounds. The initial
reference direction was the **original Japanese Yu-Gi-Oh! Duel Monsters TV series,
episodes 1–224**; the user subsequently also accepted game-sound references. These remain
**original anime-inspired placeholders**, not official recordings, replicas, or a verified
match to an episode or game. Specific references can guide a later listening/design pass.

No audio samples, episode extracts, music, voice lines, downloads, or game rips are used.
The existing Portrait showcase retains its separate original wood/atmosphere palette.

## Use

- On the normal board, **Sound 60%** opens the effects volume/mute dialog. **Sound
  settings** is also available on the privacy cover before revealing a hand.
- Volume is 0–100%; 0 is silent. Mute and volume persist locally in
  `user://duel_audio.cfg`, and survive a new duel. Mute, zero volume, and cover stop
  currently playing audio rather than waiting for its tail.
- Reduce motion also skips/silences action cues. Restoring motion, sound, or volume
  never replays skipped events. The dialog explains this coupling.
- Audio is non-positional and uses one voice with conservative gain, so simultaneous
  effects cannot pile up into a louder stack. There is no board ambience or music.
- The integrated responsive board keeps Sound in the wrapping toolbar. Its volume/mute
  dialog uses 48-pixel controls, fits phone widths and adapts if resized while open.

## Palette

| Public action | Original substitute | Length |
| --- | --- | --- |
| Successful summon | Card flick, rising electronic energy, low seal and crystalline decay | 0.85 s |
| Attack declaration | Charging rush and a bright, bass-supported slash | 0.72 s |
| Face-up position change | Papery turn and short locking click | 0.65 s |
| Actual destruction | Granular fractures, low break and falling dust | 0.90 s |

An attack cue marks **declaration**, not confirmed damage; it does not announce an LP
result, effectiveness, a private response, or a guaranteed hit. No LP, draw, spell,
trap, set-card, or per-monster bespoke sound pack is claimed by this implementation.

`DuelSoundBank.gd` builds deterministic mono 22,050 Hz / 16-bit PCM using a local RNG,
not the engine's RNG. Buffers have silent, smoothed endpoints and conservative headroom.
Synthesis happens once at audio-node startup, never inside the duel worker or on each action.

## Event and privacy boundary

`DuelAudio.gd` only receives the `CardAnimationDirector`'s authorized timeline signals:
start, finish, and cancellation. It never reads engine state, raw logs, deck lists,
private decisions, or hidden handles. All four cues are shared across card identities.

- Summon success, not summon declaration; Flip Summon's position event is coalesced.
- Destruction, not every move, tribute, discard, or bounce.
- Only already-public face-up actors get sound; even owner-known face-down identities
  remain silent. A hidden snapshot cancels its old active cue immediately.
- Viewer changes, cover, skip, restart, and stale source/target slots cancel with visuals.
- Other viewers' pending events are silent until that viewer's authorized reveal.
- A finish signal stops a replacement resource even if that resource is longer or loops.
- Engine input never waits for sound. Bursts and interrupted cosmetics may be skipped.

The animation layer's existing limits still apply: a monster summoned and removed entirely
between projected snapshots may have no trustworthy location and is skipped; the known
pass-and-play handoff timing side channel is not solved by sound.

## Replace a cue later

`DuelAudio.cue_overrides` is an exported `Dictionary[String, AudioStream]`. Its keys are
`summon`, `attack`, `position`, and `destroy`; missing/null entries use synthesis.
Set resources before adding the audio node to the tree. The normal board creates the
node in `DuelBoard._build_layout()`, immediately before `add_child(_sound)`.

```gdscript
_sound = DuelSound.new()
_sound.cue_overrides["attack"] = preload("res://Assets/audio/authorized_attack.ogg")
add_child(_sound)
```

That example path is illustrative; no such recording is bundled. Use only recordings
the user has supplied and is authorized to use, with source/permission metadata retained.
Replacement does not change the event/privacy filter or imply permission to redistribute
an anime soundtrack. Match the short timeline lengths and normalize levels first.

## Verification

```bash
bash Tools/run_tests.sh --import
bash Tools/run_tests.sh SceneDuelAudioCheck
bash Tools/run_tests.sh SceneAnimationCheck
bash Tools/run_tests.sh SceneAnimationRenderCheck
bash Tools/run_tests.sh SceneBoardCheck
bash Tools/run_tests.sh SceneBoardDuelCheck
bash Tools/run_tests.sh SceneSpikeCheck
bash Tools/run_tests.sh RunHiddenIdentityTests
bash Tools/run_tests.sh RunSessionTests
bash Tools/run_tests.sh RunTests
bash Tools/check_determinism.sh
```

`SceneDuelAudioCheck` checks actual PCM, deterministic/distinct cues, replacements,
finite completion, real engine scenario ordering, production-board summon wiring,
privacy, interruptions, mute/reduced-motion/zero-volume behavior, persistent/malformed
preferences, and settings open/change/close/reopen flows. It is registered in CI.
See `Reports/DUEL_AUDIO_TEST_RESULTS.md` for measured coverage and limitations.
