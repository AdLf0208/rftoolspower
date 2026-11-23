# RFTools Power — validation record (slice 7, package 0.1.6)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.6**.
Every command below ran on 2026-11-23; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against. Slice 6's 0.1.5 record (and the
earlier slices') is kept in `notes.md`; this file supersedes its numbers.

## The ladder

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` in a build slot (`CARGO_INCREMENTAL=0`, `--offline`) | **113 passed; 0 failed** — `sdk-test.log` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | 162,363 B, sha256 `7fe0e237…` — `sdk-build-1.log` |
| build 2 | the same, again | `cmp` identical to build 1 — `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0: `0.1.6 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `162363 bytes, SHA-256 7fe0e237…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** (122 entries, no packed `Cargo.lock`, `package matches the tree`) |
| content | `python3 tools/assemble_content.py --check` | `ok: 145 entries re-derive exactly` |

The red proof for slice 7's rules is `ports/_shared/evidence/rftoolspower/red-blazing.log`:
`test result: FAILED. 94 passed; 10 failed`, every failure `not yet implemented`. The green
`sdk-test.log` was regenerated **after** the 0.1.6 build, so its `PACKAGE` line names
`7fe0e237…` / 162,363 B.

`cargo horizon-mod` is installed only on this box, so the packing steps ran locally under a local
lease (`BUILD_LOCAL=1`); the launcher build and the game legs are local by design. The packer was
run twice with `rm -f Cargo.lock` before each and the two archives are `cmp`-identical.

## In game

The delivered package is built into the game by the launcher; the same game also carries the
e2e-only receiver (`tools/harness-receiver/`, never in the `.hmod`) so the energy push has
something to push into.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-db53fcfacf1b` — `rftoolspower-e2e/native-build.log`, `native-build-record-rftoolspower.json` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `native-0a875da-eb1690a1e69a` (`rfpowerharness` 0.1.0, `rftoolspower` **0.1.6**, both naming the same source hash) — `native-build-modset.log`, `native-build-record-modset.json` |
| main | `tools/e2e.sh` (A–BE) | **PASS**, `EXIT:0`; log line `PACKAGE rftoolspower.hmod sha256=7fe0e237… bytes=162363` — `rftoolspower-e2e/e2e-blazing.log` |
| selftest (blazing) | `SELFTEST_BLAZING=1 tools/e2e.sh` (AZ inverted) | `FAIL: selftest: the blazing generator made 2880 FE in 48 ticks, so the assertion is alive`, `EXIT:1`; same `PACKAGE` line — `e2e-blazing-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (the unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-blazing-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=20 ok=20
missing-exit=0 bad-exit=0` (the slice-1/2/3/4/5/6 logs stay beside the new ones and are still
green).

The slice's parsed assertions are in `notes.md` (phases AX–BE); the numbers a reader should check
first:

- **the rate's climb is the artefact's own curve**: `rft 6.976305 at t=7430 → 17.187056 at
  t=7461`, and the single-precision fold of `rft += (60 − rft)/150 + 0.01` over those 31 ticks is
  `17.187067` — a delta of **0.000011**, i.e. the rule to six decimals;
- **at the ceiling `Δenergy == 60 × Δt`**: 25,749 → 28,629 FE over **48** ticks (+2,880 = 60 × 48),
  after the rod's climb clamps at `rft=60.000000` (first seen at t+556 from rest);
- the **400-tick rod** leaves slot 0 at its 400th tick (`ticks=0`, `rftmax=0`) and its rate decays
  (`0.000878 → 0.000328` in 20 ticks) until `working` falls and the store holds;
- a generator doctored to **999,995 FE** reads 999,995 and, with a rod burning, exactly
  **1,000,000** (twice), `working` true;
- a **100,000 FE** store beside the harness receiver ends at **0** with the receiver at
  **100,000** (no reserve);
- **after save + relaunch**: 57,009 FE, slot 0 still the rod, `rftmax=60`, `rft=60.000000`;
- a click with a **stone** is refused: every rod slot empty, the *server's* inventory
  (`data get entity @s Inventory`) still holds the stone, and no block was placed against the
  machine; the recipe with a stone where the parent's items belong crafts nothing.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 162,363 B | `7fe0e23708d8473564c53494f983c01bb9373fafdb8d551f7b8db5df0ae59a7c` | 122 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`), and every packed file is the tree's bytes (`package matches the tree`).

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the **same** export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` and `rftoolspower` 0.1.6.
- The export's build is now read from the launcher's own answer (`native-… built and selected`)
  instead of the newest version directory: after two consecutive builds the old rule exported the
  **previous** build (a diagnostic build was tested as if it were current, and the refusal of a
  stone with a block item looked broken). The record above is the build the launcher named.
- The new values were read from `ctl` replies and from the game's own tick counter in the same
  reply (`t=`), never from a sleep; the ramp's fold is an independent implementation in
  `tools/parse_blazing.py` (IEEE single precision, one rounding per operation), so a rule that is
  not the artefact's shows up as a large delta.
- The stone refusal is judged by the **server's** inventory: the client's own view loses the stack
  to its prediction (measured at +10 and +70 ticks), which is an engine quirk, not the port's state.
