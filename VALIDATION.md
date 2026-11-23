# RFTools Power — validation record (slice 8, package 0.1.7)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.7**.
Every command below ran on 2026-11-23; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against. Slice 7's 0.1.6 record (and the
earlier slices') is kept in `notes.md`; this file supersedes its numbers.

## The ladder

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` in a build slot (`CARGO_INCREMENTAL=0`, `--offline`) | **131 passed; 0 failed** — `sdk-test.log` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 | `rm -f Cargo.lock && cargo horizon-mod build` | 177,048 B, sha256 `15cc6d27…` — `sdk-build-1.log` |
| build 2 | the same, again | `cmp` identical to build 1 — `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0: `0.1.7 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `177048 bytes, SHA-256 15cc6d27…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** (131 entries, no packed `Cargo.lock`, `package matches the tree`) |
| content | `python3 tools/assemble_content.py --check` | `ok: 154 entries re-derive exactly` |

The red proof for slice 8's rules is `ports/_shared/evidence/rftoolspower/red-agitator.log`:
`test result: FAILED. 113 passed; 12 failed`, every failure `not yet implemented`. The green
`sdk-test.log` was regenerated **after** the 0.1.7 build, so its `PACKAGE` line names
`15cc6d27…` / 177,048 B.

One defect the ladder could not see was found **in game** and fixed with a unit test: the rod
component's reader handed a `Tag::Double`'s raw f64 *bits* to the f32 clock, so a rod given with
`time:0.05` read 4,587,366,470,488,424,448 ticks (`e2e` BI before the fix). The package was then
rebuilt: both builds above are the fixed tree.

`cargo horizon-mod` is installed only on this box, so the packing steps ran locally under a local
lease (`BUILD_LOCAL=1`); the launcher build and the game legs are local by design. The packer was
run twice with `rm -f Cargo.lock` before each and the two archives are `cmp`-identical.

## In game

The delivered package is built into the game by the launcher; the same game also carries the
e2e-only receiver (`tools/harness-receiver/`, never in the `.hmod`) so the energy pushes have
something to push into. The launcher's version store carried no `native-*` build of this mod before
the run (`grep -l rftoolspower */native-mods.json` → none), so nothing stale could be reused.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-b39f8e5ff85d` — `rftoolspower-e2e/native-build.log`, `native-build-record-rftoolspower.json` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `native-0a875da-08885a9d3eb8` (`rfpowerharness` 0.1.0, `rftoolspower` **0.1.7** f63639cc) — `native-build-modset.log`, `native-build-record-modset.json` |
| main | `tools/e2e.sh` (A–BN) | **PASS**, `EXIT:0`; log line `PACKAGE rftoolspower.hmod sha256=15cc6d27… bytes=177048` — `rftoolspower-e2e/e2e-agitator.log` |
| selftest (agitator) | `SELFTEST_AGITATOR=1 tools/e2e.sh` (BH inverted) | `FAIL: selftest: the lone rod's quality rose 16.953 in 35 ticks (0.22² × 10 = 0.484 a tick), not the brief's 10 a tick (390) — the assertion is alive`, `EXIT:1` — `e2e-agitator-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (the unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-agitator-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=23 ok=23
missing-exit=0 bad-exit=0` (the slice-1…7 logs stay beside the new ones and are still green).

The slice's parsed assertions are in `notes.md` (phases BF–BN); the numbers a reader should check
first:

- **three rods in a row fold exactly**: over 47 game ticks (`t=8868 → 8915`) the whole 3×3 box's
  `time`, `quality` and `duration` matched the single-precision fold of `adjacency² × 10` /
  `adjacency²` / `adjacency/5` with `FOLD_ERROR=0.000000`; the first tick's rates are 0.5176 /
  0.5523 / 0.5176 (0.2275 / 0.235 / 0.2275 factors);
- **the brief's factor 1 is wrong**: the artefact's null neighbour penalty makes a lone rod's factor
  0.22 (rise 0.484 a tick); the self-test asserts 10 a tick and fails with `18.891 in 39 ticks`;
- **10 FE a tick spent**: 38,770 → 38,300 over 47 ticks (470 = 10 × 47), and an idle box spends too;
- **100 FE a tick taken in**: beside a doctored 100,000 FE coal generator the buffer netted
  **+4,590 over 51 ticks** (90 = 100 in − 10 spent) while the generator lost **5,100 over the same
  51 ticks** (100 a tick);
- **the locks**: a finished rod moves to the first free output slot unless its slot is locked
  (`locks=001000000`), and lock 4 survives save + quit + relaunch;
- **the rod's data is real**: an agitated rod left the agitator for a hopper and its
  `Items` carry `rftoolspower:blazing_rod_data`;
- a plain blaze rod converts, an already-infused one (`steps:10`) and a stone are refused, the three
  refusals parse as replies, and the carried recipe crafts nothing without the parent.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 177,048 B | `15cc6d27279638fb67003d7a9492eb8dd21f87b1273025a433c4712121212bbd` | 131 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`), and every packed file is the tree's bytes (`package matches the tree`).
The package was built **after the last packed edit**: the first build of this slice differed from
the tree in `horizon-mod.toml` and `README.md` (both packed), which the package gate caught
(`differs: horizon-mod.toml, README.md`) — the table above is the rebuild of the final tree. Only
`notes.md`, `VALIDATION.md`, `CONTENT.md`, `tools/e2e.sh` and `tools/parse_agitator.py` changed
afterwards, and none of them is packed.

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the **same** export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` 0.1.0 and `rftoolspower` 0.1.7.
- The new values were read from `ctl` replies and from the game's own tick counter in the same reply
  (`t=`), never from a sleep: the adjacency fold is an independent implementation in
  `tools/parse_agitator.py` (IEEE single precision, one rounding per operation), and each store's
  rate is measured against its **own** reply's `t`.
- Two stores several ticks apart are not compared (that produced a 6,300-vs-4,800 FE false alarm);
  every rate is per-store and per-reply.
- The refused items are judged by the **server's** inventory: the client's own view predicts a
  click this pin does not consult a mod's hooks for.
