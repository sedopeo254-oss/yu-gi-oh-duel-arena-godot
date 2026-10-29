# Optional OCG-core diagnostic — local verification

Date: 2026-10-29. Scope: the optional synthetic-Normal-Monster diagnostic, not a
new playable backend. Existing game engine and board code are unchanged.

Environment: Linux x86_64; GCC/G++ 14.2; Python 3.12.14; available Godot
**4.6.3.stable.official.7d41c59c4**. CI's configured **4.7.1** is a separate
verification target; the new native-core CI steps have not been run remotely as
part of this local report.

| Check | Result |
| --- | --- |
| Baseline SmokeCheck | PASS, clean exit |
| Baseline full Godot regression | 10,653 / 10,653 assertions, 101 suites, clean exit |
| `python3 Tools/build_ocg_probe.py --fetch` | PASS: exact core revision fetched, Lua checksum verified, native executable compiled and smoke-tested |
| Cached/explicit core-source rebuild | PASS |
| `python3 Tools/ocg/test_probe.py` | 3 test methods PASS, including nine invalid argument cases, 14 seed/lifecycle cases, repeatability and different-seed RNG |
| `RunOcgCoreTests` | 26 / 26 Godot-to-native and report-validation assertions, clean exit |
| Final SmokeCheck | PASS, clean exit |
| Final full Godot regression | 10,653 / 10,653 assertions, 101 suites, clean exit |
| Python helper suite, including bootstrap recovery/provenance | 33 tests PASS (26 existing + 7 new) |
| Probe C++ strict syntax check (`-Wall -Wextra -Werror`) | PASS |
| Python byte-compilation; manifest JSON and doc links; `git diff --check` | PASS |
| Missing cache without `--fetch` | Explicit failure; no implicit download |
| Wrong/dirty source revision | Explicit failure |
| Interrupted initial Git fetch | Resumes only with explicit `--fetch`; tested offline against a local Git fixture |
| Ignored source file / assume-unchanged modified tracked file | Excluded from compilation snapshot; original pinned Git content verified |
| Missing native binary in Godot | Explicit failure; no fallback to a pretend core |

The real native run for seed 42 emitted 33 decoded messages and transcript FNV-1a
fingerprint `374a2c7c8549d21e`. The fingerprint is a regression aid, **not a
cryptographic authenticity check**. Actual verified checkpoints:

- Opening hands `[5, 5]`, player 0 has five Normal Summon candidates.
- Invalid command is rejected by the core with `MSG_RETRY`.
- Core-driven hand shuffle; same seed repeats exactly, another seed differs.
- Normal Summon yields hands `[4, 5]`, monster-zone counts `[1, 0]`, and no second
  Normal Summon allowance.
- Turn passes to player 1, hands `[4, 6]`, decks `[35, 34]`.

The full suite still intentionally logs errors for fail-loudly test cases. There
were no script errors, native crashes, leaks-at-exit warnings, or nonzero test
runner exits in the passing runs. Writable XDG cache/config/data locations under
`/tmp` were used because this sandbox's home directory is read-only.

Not tested or claimed: real effect-card Lua, complete duel/battle/card coverage,
native-vs-GDScript rules equivalence, production session wiring, non-Linux
platforms, exports, or either GPL/AGPL reference project's runtime compatibility.
See [scope and prerequisites](../docs/OCG_CORE_DIAGNOSTIC.md).
