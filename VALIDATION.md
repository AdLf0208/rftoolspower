# RFTools Power — validation record (slice 9, package 0.1.8)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.8**.
Every command below ran on 2026-11-23; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against. Slice 8's 0.1.7 record (and the
earlier slices') is kept in `notes.md`; this file supersedes its numbers.

## The ladder

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` in a build slot (`CARGO_INCREMENTAL=0`, `--offline`) | **150 passed; 0 failed** — `sdk-test.log` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | 188,685 B, sha256 `49885b17…` — `sdk-build-1.log` |
| build 2 | the same, again | `cmp` identical to build 1 — `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0: `0.1.8 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `188685 bytes, SHA-256 49885b17…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** (140 entries, no packed `Cargo.lock`, `package matches the tree`, R9 clean) |
| content | `python3 tools/assemble_content.py --check` | `ok: 163 entries re-derive exactly` |

The red proof for slice 9's rules is `ports/_shared/evidence/rftoolspower/red-infuser.log`:
`test result: FAILED. 132 passed; 12 failed`, every failure `not yet implemented`. The green
`sdk-test.log` was regenerated **after** the 0.1.8 build, so its `PACKAGE` line names `49885b17…` /
188,685 B.

`cargo horizon-mod` is installed only on this box, so the SDK `build`, `check` and `fits` steps ran
locally under a local lease (`BUILD_LOCAL=1`); `test`/`clippy`/`fmt` may run on either box. The
packer was run twice with `rm -f Cargo.lock` before each and the two archives are `cmp`-identical.
(The first attempt of this slice ran the SDK build on the remote box, where the subcommand does not
exist; its `cp` failed and the old `PACKAGE` line was printed because `tools/gates.sh` did not stop
on errors. The script now uses `set -euo pipefail`, and the failed run is why the build is local.)

## In game

The delivered package is built into the game by the launcher; the same game also carries the
e2e-only receiver (`tools/harness-receiver/`, never in the `.hmod`) so the energy pushes of the
earlier phases have something to push into.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-8dc1a703caa7`; a repeat run answers `Up to date (no build needed)` — `rftoolspower-e2e/native-build.log`, `native-build-record-rftoolspower.json` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `native-0a875da-8f913c1a928e` — `rfpowerharness` 0.1.0 (`31ae6dd7…`), `rftoolspower` **0.1.8** (`dd308d58…` source hash) — `native-build-modset.log`, `native-build-record-modset.json` |
| main | `tools/e2e.sh` (A–BS) | **PASS**, `EXIT:0`; log line `PACKAGE rftoolspower.hmod sha256=49885b17… bytes=188685` — `rftoolspower-e2e/e2e-infuser.log` |
| selftest (infuser) | `SELFTEST_INFUSER=1 tools/e2e.sh` (BR inverted) | `FAIL: selftest: the counter wrapped 3 times in 39 ticks — one run every 11 (floor((Δt + 10 − counter0)/11) = 3), not the brief's 10-tick period (4) — the assertion is alive`, `EXIT:1` — `e2e-infuser-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (the unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-infuser-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=26 ok=26
missing-exit=0 bad-exit=0` (the slice-1…8 logs stay beside the new ones and are still green).

The slice's parsed assertions are in `notes.md` (phases BO–BS); the numbers a reader should check
first:

- **the period is 11, not 10**: a rod with no catalyst sat in a 5,000 FE infuser while the counter
  wrapped **twice in 26 ticks** and `steps`/`quality`/`duration`/the store did not move;
- **one star, one run**: `steps 64 → 63`, `quality 60000.000000 → 61125.000000` (+1,125),
  `duration 20.000000 → 20.375000` (+0.375), the store `5000 → 4990`, the catalyst slot emptied;
- **redstone is quality-only**: `quality 60000.000000 → 60375.000000` (+375), `duration` unchanged;
- **six runs in 69 ticks**: a hopper of 16 nether stars produced `steps 64 → 58`, the store fell
  exactly 60 (10 a run), the counter wrapped 6 times (`floor((Δt + 10 − counter0)/11) = 6`), and
  the quality/duration rose to `65839.929688`/`21.946644`, which the single-precision per-run
  `×(1 + 120/6,400)` fold matches;
- **one catalyst a run**: the 16 seeded stars are `6 runs + 5 in the hopper + 3 in the slot` (15 or
  16 — a star in flight between the two reads is on neither side);
- a stone is refused as neither rod nor catalyst, the **server** keeps it, no block is placed
  against the machine, the stone-position readout parses, and the carried recipe crafts nothing
  without the parent's `dimensionalshard` and `machine_frame`.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 188,685 B | `49885b17eefb49dc54ae8cb400a05a85f6125201d09f0bef564fdc1a26bb559d` | 140 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`), and every packed file is the tree's bytes (`package matches the tree`).
The package was built **after the last packed edit** (`horizon-mod.toml`, `Cargo.toml`, `README.md`
and `src/` — all packed). Only `notes.md`, `VALIDATION.md`, `CONTENT.md`, `FINDINGS.md`, `PLAN-slice9.md`,
`tools/e2e.sh`, `tools/parse_infuser.py`, `tools/gates.sh` and `tools/assemble_content.py` changed
afterwards, and none of them is packed.

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the **same** export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` 0.1.0 and `rftoolspower` 0.1.8.
- The readout prints each slot as `id xcount`, which is how the leg proves the running binary is the
  delivered one: a stale export printed no count, and that was caught and rebuilt.
- The counter's period is computed from the **reply's own** `counter` and `t=` (`parse_infuser.py
  --period`), never from a sleep: `Δt = 11 × wraps + (c0 − c1)` must close exactly, and the
  brief's 10-tick reading leaves a non-zero remainder on any window that wraps.
- A hopper and the block entity are two reads a few ticks apart, so the catalyst conservation is
  stated as "15 or 16 of the 16 seeded stars", not an equality (the campaign's trap 3).
- The refused items are judged by the **server's** inventory: the client's own view predicts a
  click this pin does not consult a mod's hooks for.
