# RFTools Power — validation record (slice 4, package 0.1.3)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.3**.
Every command below ran on 2026-11-22; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against. Slice 1's 0.1.0, slice 2's 0.1.1 and
slice 3's 0.1.2 records are kept in `notes.md`; this file supersedes their numbers.

## The ladder

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` in a build slot (`CARGO_INCREMENTAL=0`, `--offline`) | **74 passed; 0 failed** — `sdk-test.log` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | 122,516 B, sha256 `ab452bd8…` — `sdk-build-1.log` |
| build 2 | the same, again | `cmp` identical to build 1 — `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0: `0.1.3 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `122516 bytes, SHA-256 ab452bd8…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** |

The red proof for slice 4's rules is `ports/_shared/evidence/rftoolspower/red-endergenic.log`:
`test result: FAILED. 50 passed; 14 failed`, every failure `not yet implemented`.

The build slot forwarded the compile steps to the second machine; `cargo horizon-mod` is only
installed on this box, so the packing steps ran here under a local lease (`BUILD_LOCAL=1`), and the
launcher build and the game legs are local by design. One `fits` run hit a GitHub 403 (the release
list it resolves a build tag from); the retry is the log that is kept.

## In game

The delivered package is built into the game by the launcher; the same game also carries the
e2e-only receiver (`tools/harness-receiver/`, never in the `.hmod`) so the endergenic push has
something to push into.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-88daa563f37b` — `rftoolspower-e2e/native-build.log` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `Compiling rfpowerharness (1 of 2)`, `Compiling rftoolspower (2 of 2)`, `native-0a875da-26adda5b2fc9` (`rfpowerharness` 0.1.0, `rftoolspower` **0.1.3**) — `rftoolspower-e2e/native-build-modset.log` |
| main | `tools/e2e.sh` (A–AM) | **PASS**, `EXIT:0` — `rftoolspower-e2e/e2e-endergenic.log` |
| selftest (endergenic) | `SELFTEST_ENDER=1 tools/e2e.sh` (AF inverted) | `FAIL: selftest: the pearl paid 200 FE at mode 1, so the assertion is alive`, `EXIT:1` — `e2e-endergenic-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (the unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-endergenic-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=11 ok=11 missing-exit=0
bad-exit=0` (the slice-1/2/3 logs stay beside the new ones and are still green).

The slice's parsed assertions are in `notes.md` (phases AE–AM); the numbers a reader should check
first:

- a pearl fired at a destination charged to mode 1 pays **200 FE** (`rfPerHit[1] × 2`) and the
  store equals `gained − spent`;
- the same shot with the destination **idle** pays **0** and is recorded as
  `Pearl arrived while idle`;
- a charge with **no injector** goes 1…15 and makes no FE;
- a 100,000 FE generator beside the harness receiver ends at exactly **2,000 FE** (the
  `endergenicKeepRf` reserve) with the receiver at **98,000**;
- a broken generator carries `energy: 3000` on its item and restores it, with no link.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 122,516 B | `ab452bd8913d68820359293365a983d30d8c47bfa729bb2053c1039276c45af0` | 87 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`).

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the **same** export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` and `rftoolspower` 0.1.3.
- The injector's placement was probed in a throwaway session first (the probe is not kept): the
  reason `ctl place` refused a block on top of another — `no face … is visible from here` for a top
  face above the eye — is recorded in `notes.md` as the trap it is, and the leg now places the
  injector beside its generator.
