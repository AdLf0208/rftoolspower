# RFTools Power — validation record (slice 6, package 0.1.5)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.5**.
Every command below ran on 2026-11-23; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against. Slice 1's 0.1.0, slice 2's 0.1.1,
slice 3's 0.1.2, slice 4's 0.1.3 and slice 5's 0.1.4 records are kept in `notes.md`; this file
supersedes their numbers.

## The ladder

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` in a build slot (`CARGO_INCREMENTAL=0`, `--offline`) | **94 passed; 0 failed** — `sdk-test.log` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | 141,168 B, sha256 `26485b9a…` — `sdk-build-1.log` |
| build 2 | the same, again | `cmp` identical to build 1 — `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0: `0.1.5 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `141168 bytes, SHA-256 26485b9a…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** (105 entries, no packed `Cargo.lock`, `package matches the tree`) |

The red proof for slice 6's rules is `ports/_shared/evidence/rftoolspower/red-powerlevel.log`:
`test result: FAILED. 87 passed; 4 failed`, every failure `not yet implemented`. The green
`sdk-test.log` was regenerated after the 0.1.5 build, so its `PACKAGE` line names
`26485b9a…` / 141,168 B.

The first 0.1.5 build (`fc6a1706…`, 140,994 B) packed a `README.md` that predated the slice's
README update (the tree's README changed after that build). The drift was one document; the package
was rebuilt from the final tree, both builds are `cmp`-identical at `26485b9a…`, every packed file
is the tree's bytes (`verify-sdk-package` prints `package matches the tree`), and the main leg and
the power-level selftest were re-run on those bytes. The version stayed 0.1.5.

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
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-18641cfcb03e` — `rftoolspower-e2e/native-build.log` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `Compiling rfpowerharness (1 of 2)`, `Compiling rftoolspower (2 of 2)`, `native-0a875da-cb0f41e1cb8b` (`rfpowerharness` 0.1.0, `rftoolspower` **0.1.5**) — `rftoolspower-e2e/native-build-modset.log` |
| main | `tools/e2e.sh` (A–AW) | **PASS**, `EXIT:0`; log line `PACKAGE rftoolspower.hmod sha256=26485b9a… bytes=141168` — `rftoolspower-e2e/e2e-powerlevel.log` |
| selftest (power level) | `SELFTEST_POWERLEVEL=1 tools/e2e.sh` (AT inverted) | `FAIL: selftest: the power level reads 5 at 250,000/500,000, not the 4 the inversion expects, so the assertion is alive`, `EXIT:1`; same `PACKAGE` line — `e2e-powerlevel-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (the unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-powerlevel-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=17 ok=17 missing-exit=0
bad-exit=0` (the slice-1/2/3/4/5 logs stay beside the new ones and are still green).

The slice's parsed assertions are in `notes.md` (phases AT–AW); the numbers a reader should check
first:

- **at 250,000 of 500,000 FE the display face's redstone wire reads `power=5`** — the artefact's
  `stored * 10 / capacity` (integer), **not the brief's assumed 4**; the block's own state mirrors
  `power=5` and the readout says `power=5 facing=east target=rftoolspower:coalgenerator
  stored=250000 max=500000`;
- a wire on the power level's **north face** (not the display) reads `power=0` at the same moment;
- a **fresh generator reads `power=0`** on the readout and on its display wire (the differential);
- a **full 500,000 FE store reads `power=9`** (the ratio 10 clamps), on both the readout and the
  wire;
- the `powerlevel` refusal at a stone position is a parsed line (`No RFTools Power power level
  there.`), and the carried recipe with a stone where `rftoolsbase:machine_base` belongs crafts
  nothing (its `#c:glass_panes` tag is unresolved at this pin, logged by the game at load).

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 141,168 B | `26485b9a8e5277bc248ad4a476e17b98cdcd3a1632e4718bb44d0b8909b614d6` | 105 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`), and every packed file is the tree's bytes (`package matches the tree`).

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the **same** export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` and `rftoolspower` 0.1.5.
- The new values were read from the **wire's own `power` state** (`ctl block` on the
  `minecraft:redstone_wire`), not from the block's mirror alone, and the wrong-face wire is the
  differential; `SELFTEST_POWERLEVEL=1` inverts the display wire's 5, so a run where the assertion
  could not fail is visible as `EXIT:0` in the selftest log.
- The first e2e attempt failed at AW with `no minecraft:stone in the inventory for the recipe`
  because the give loop omitted the stone; that is a harness fault, not a port fault, and the
  passing log is the evidence. The failed log was not kept.
