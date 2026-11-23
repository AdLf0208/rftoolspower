# RFTools Power — validation record (slice 5, package 0.1.4)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.4**.
Every command below ran on 2026-11-23; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against. Slice 1's 0.1.0, slice 2's 0.1.1,
slice 3's 0.1.2 and slice 4's 0.1.3 records are kept in `notes.md`; this file supersedes their
numbers.

## The ladder

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` in a build slot (`CARGO_INCREMENTAL=0`, `--offline`) | **87 passed; 0 failed** — `sdk-test.log` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | 134,377 B, sha256 `e1c60156…` — `sdk-build-1.log` |
| build 2 | the same, again | `cmp` identical to build 1 — `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0: `0.1.4 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `134377 bytes, SHA-256 e1c60156…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** |

The red proof for slice 5's rules is `ports/_shared/evidence/rftoolspower/red-endermonitor.log`:
`test result: FAILED. 74 passed; 7 failed`, every failure `not yet implemented`.

The build slot forwarded the compile steps to the second machine; `cargo horizon-mod` is only
installed on this box, so the packing steps ran here under a local lease (`BUILD_LOCAL=1`), and the
launcher build and the game legs are local by design. One `fits` run can hit a GitHub 403 (the
release list it resolves a build tag from); the retry is the log that is kept.

## In game

The delivered package is built into the game by the launcher; the same game also carries the
e2e-only receiver (`tools/harness-receiver/`, never in the `.hmod`) so the endergenic push has
something to push into.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-574eb87eae42` — `rftoolspower-e2e/native-build.log` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `Compiling rfpowerharness (1 of 2)`, `Compiling rftoolspower (2 of 2)`, `native-0a875da-aa42b6d48852` (`rfpowerharness` 0.1.0, `rftoolspower` **0.1.4**) — `rftoolspower-e2e/native-build-modset.log` |
| main | `tools/e2e.sh` (A–AS) | **PASS**, `EXIT:0` — `rftoolspower-e2e/e2e-endermonitor.log` |
| selftest (ender monitor) | `SELFTEST_ENDERMON=1 tools/e2e.sh` (AO inverted) | `FAIL: selftest: the monitor lit for 1 sample(s), so the one-tick assertion is alive`, `EXIT:1` — `e2e-endermonitor-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (the unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-endermonitor-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=14 ok=14 missing-exit=0
bad-exit=0` (the slice-1/2/3/4 logs stay beside the new ones and are still green).

The slice's parsed assertions are in `notes.md` (phases AN–AS); the numbers a reader should check
first:

- the `arrived` monitor's `lit` state is true in **exactly one** of 16 consecutive server ticks
  around a landing (`'0010000000000000'`), and false before and after;
- the same shot with its mode set to `lost` samples **0 of 16** lit (the differential), while the
  destination still records the arrival and pays 200 FE;
- the lamp on its display face lights (`'001111…'`, vanilla's 4 ticks) and goes dark — the 15 is a
  real redstone output, not only a block state;
- a landing at an idle destination pulses **both** monitors (the `arrived` one first) and records
  `Pearl arrived while idle`; the mis-facing monitor (display pointing at the generator) never pulses;
- a broken monitor's item carries `id: rftoolspower:ender_monitor_block_entity` and
  `mode: "MODE_PEARLFIRED"`, and placing it restores `fired` with 0 pulses;
- after save + relaunch the modes and counters survive (`arrived` 4, `lost` 1).

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 134,377 B | `e1c6015697ba7825e07e6b58f0ca25daa89c7617c6880a90af4fec6968b1c9b2` | 96 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`).

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the **same** export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` and `rftoolspower` 0.1.4.
- The e2e attempts before the passing run were harness faults, not port faults, and both kinds are
  recorded in `notes.md` as traps: a re-placed picked-up monitor kept the game's placement yaw
  (wrong display face), and a reply read by its timestamp accepted a *previous* command's pending
  line. The command gained the harness's nonce (`endermonitor <pos> <action> [nonce:word]`), and the
  re-placement goes through the helper that pins the face. The failed logs are not kept; the
  passing log is the evidence.
- The one-tick `lit` state is sampled per **server** tick with the game frozen; the `state` reply's
  `ticks` field is the client's clock and is used only as a cross-check (the samples' labels are
  ~2 apart while the server steps once each).
