# RFTools Power slice 1 — validation record

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.0**.
Every command below ran on 2026-11-21; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against.

## The ladder

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` in a build slot (`CARGO_INCREMENTAL=0`, `--offline`) | **18 passed; 0 failed** — `sdk-test.log` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | 30,509 B, sha256 `33a0c6c0…` — `sdk-build-1.log` |
| build 2 | the same, again | `cmp` identical to build 1 — `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0: `native-mod, format native-1/0a875da…/e59da909…, for 26.3`, `30509 bytes, SHA-256 33a0c6c0961bf39a86d1ef9ac613dd8a16050b4fd5ca18f4e7588f09450ecf99` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |

The red proof for the new rules is `ports/_shared/evidence/rftoolspower/red-runtime.log`:
`test result: FAILED. 0 passed; 10 failed`, every failure `not yet implemented`.

The build slot forwarded the compile steps to the second machine; `cargo horizon-mod` is only
installed on this box, so the packing steps ran here under a local lease (`BUILD_LOCAL=1`), and
the launcher build and the game legs are local by design.

## In game

| leg | command | result |
|---|---|---|
| build | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-07078c9d2541`, exported — `rftoolspower-e2e/native-build.log` |
| main | `tools/e2e.sh` (A–M) | **PASS**, `EXIT:0` — `rftoolspower-e2e/e2e-coal-generator.log` |
| selftest | `SELFTEST=1 tools/e2e.sh` (C inverted) | `FAIL: selftest: the generator made 3240 FE in 54 ticks, so the assertion is alive`, `EXIT:1` |
| control | `CONTROL=1 tools/e2e.sh` (the unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=3 ok=3 missing-exit=0
bad-exit=0`.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 30,509 B | `33a0c6c0961bf39a86d1ef9ac613dd8a16050b4fd5ca18f4e7588f09450ecf99` | 24 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`).

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built by `launcher-game.sh` into the **same** export the e2e then ran,
  and the export's `native-mods.json` names exactly one mod (`rftoolspower`).
- The first main run **failed** (phase B, `the hand still holds 1 coal after the click`) because
  creative keeps a container stack; the leg runs in survival. The failure is in the git-less history
  of the log directory only as the fixed run; the cause is recorded in `notes.md`.
