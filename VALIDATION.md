# RFTools Power — validation record (slice 2, package 0.1.1)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.1**.
Every command below ran on 2026-11-21; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against. Slice 1's 0.1.0 record is kept in
`notes.md`; this file supersedes its numbers.

## The ladder

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` in a build slot (`CARGO_INCREMENTAL=0`, `--offline`) | **33 passed; 0 failed** — `sdk-test.log` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | 73,339 B, sha256 `6df52b74…` — `sdk-build-1.log` |
| build 2 | the same, again | `cmp` identical to build 1 — `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0: `0.1.1 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `73339 bytes, SHA-256 6df52b7421749bc7fea622dd3359e84ce3ff847ea2454d2ce9ef3ef79c2d15f5` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** |

The red proof for slice 2's rules is `ports/_shared/evidence/rftoolspower/red-monitor.log`:
`test result: FAILED. 18 passed; 9 failed`, every failure `not yet implemented`.

The build slot forwarded the compile steps to the second machine; `cargo horizon-mod` is only
installed on this box, so the packing steps ran here under a local lease (`BUILD_LOCAL=1`), and the
launcher build and the game legs are local by design.

## In game

The delivered package is built into the game by the launcher; the same game also carries the
e2e-only receiver (`tools/harness-receiver/`, never in the `.hmod`) so the generator's push has
something to push into.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-79921933a1fd` — `rftoolspower-e2e/native-build.log` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `Compiling rfpowerharness (1 of 2)`, `Compiling rftoolspower (2 of 2)`, `native-0a875da-f3302f74a768` (`rfpowerharness, rftoolspower`) — `rftoolspower-e2e/native-build-modset.log` |
| main | `tools/e2e.sh` (A–T) | **PASS**, `EXIT:0` — `rftoolspower-e2e/e2e-power-monitor.log` |
| selftest | `SELFTEST=1 tools/e2e.sh` (O inverted) | `FAIL: selftest: the empty generator reads level 1, not the charged 3, so the assertion is alive`, `EXIT:1` |
| control | `CONTROL=1 tools/e2e.sh` (the unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=4 ok=4 missing-exit=0
bad-exit=0` (the two slice-1 logs stay beside the new ones and are still green).

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 73,339 B | `6df52b7421749bc7fea622dd3359e84ce3ff847ea2454d2ce9ef3ef79c2d15f5` | 45 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`).

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the **same** export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` and `rftoolspower`.
- The first monitor runs found two real harness facts (recorded in `notes.md`): the placement
  context's yaw is not the player's look, and a mob in the target blocks a placement. The leg now
  sets the display face explicitly after placing and clears non-player entities before a place.
