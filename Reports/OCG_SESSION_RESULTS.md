# Native reference session — local verification (2026-10-29)

Environment: Linux x86_64, G++ 14.2, Python 3.12.14, Godot 4.6.3. This record
covers the stateful synthetic-Normal-Monster session, not real effects or the
production board. Remote CI for this local milestone has not run.

- **659 Godot assertions pass**, clean exit and no script/child-process warnings:
  real Normal Summon and zone response, native wrong-player/stale/invalid-choice
  rejection, independently numbered player channels, duplicated submissions,
  copied output, simultaneous native duels, child crash, idempotent stop and
  owner-reference destruction.
- A complete **139-response native duel** through the Godot adapter ends by
  actual core deck-out at turn 72: 68 hand-limit discard decisions, player 0 wins,
  both viewers receive consistent final counts, and the child exits cleanly.
- Ten controlled broken-worker cases fail closed: extra private top-level
  data, extra offer data, unknown mode, success followed by exit 7, success
  followed by a hang, only one terminal report, mismatched terminal views,
  mismatched winners, duplicate terminal reports, and prompts after terminal
  processing began. No success/private data
  escapes; each child is terminated/reaped.
- **Eight native Python test groups pass**: original diagnostic/seed/input
  checks plus stateful authorization, complete deck-out, parent EOF, malformed
  and oversized requests, and a player idle interval longer than the 10-second
  processing watchdog.
- Independent review additionally exercised full native sessions at seeds
  `0`, `1`, `42`, `4294967295`, including hand shuffle, **10 Normal Summons**,
  zones and 58 discards: **220 accepted responses**, correct deck-out winner at
  turn 72, exit 0 for each.

The original diagnostic seed-42 fingerprint remains `374a2c7c8549d21e`.
All source changes are additive to the experimental adapter; no existing game
engine, production session, board or card implementation was changed.

Final aggregate regression: **10,653 / 10,653 existing assertions** across 101
suites, clean exit; **26 / 26 original diagnostic assertions**; **33 Python
helper tests**. Strict C++ warnings-as-errors syntax check, Python compilation,
YAML parsing, documentation link checks and `git diff --check` also pass.
Do not infer Godot 4.7.1 CI or cross-platform results from these local checks.
