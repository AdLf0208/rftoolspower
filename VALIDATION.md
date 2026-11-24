# RFTools Power — validation record (slice 10, package 0.1.9)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.9**.
This slice adds the third powercell tier, `cell3`: 20,000,000 FE and 4,000 FE a side (5,000 in a
two-cell network), with the jar's `PowerCellConfig.class` as the source of both numbers.
Every command below ran on 2026-11-24; the logs are under
`ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha256 and size it ran against. The slice-9 (0.1.8) record is kept
in `notes.md`; this file supersedes its numbers.

## The ladder — all compile gates forwarded to `AdLf-PC`

Every SDK gate was invoked as
`ports/tools/build-slot.sh run --job G11-rftoolspower --port ports/rftoolspower --step <step> -- <cmd>`.
The runner printed `build-slot: forwarding <step> for ports/rftoolspower to the remote runner`; the
far box's hostname is `AdLf-PC` (checked with `ssh … hostname`). No `BUILD_LOCAL=1` was used.

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` | **152 passed; 0 failed** — `sdk-test.log`, `PACKAGE … sha256=1e6beecf… bytes=199035` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 / 2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | both `199035 B`, sha256 `1e6beecf…`; `cmp`-identical — `sdk-build-1.log`, `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0, `0.1.9 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `199035 bytes, SHA-256 1e6beecf…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** (154 entries, no packed `Cargo.lock`, `package matches the tree`, R9 clean, no local `Block`/`Item` type) |
| content | `python3 tools/assemble_content.py --check` | `ok: 177 entries re-derive exactly` |

The red proof is `ports/_shared/evidence/rftoolspower/red-cell3.log`:
`test result: FAILED. 150 passed; 1 failed`, verbatim
`not yet implemented: cell3's saved block entity type is not written yet`. The green `sdk-test.log`
was regenerated **after** the 0.1.9 build, so its `PACKAGE` line names `1e6beecf…` / 199,035 B.
`cargo horizon-mod` is present on `AdLf-PC` (repaired CLI and wasm target), so no step needed a
local fallback.

## In game — these legs stayed local

The launcher game build and all three e2e legs were run through `--step e2e` of the slot runner and
stayed on this box: the exported game/instance, the `--offscreen` Vulkan renderer and the unmodded
control game live here. Each leg is logged with its `PACKAGE` line and ends `EXIT:<status>`.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-2297fa36feae`, exported — `native-build.log`, `native-build-record-rftoolspower.json` (0.1.9) |
| build (package + receiver) | `tools/build-e2e-game.sh` | `native-0a875da-c0540063b510`, `rfpowerharness` 0.1.0 (`31ae6dd7…`), `rftoolspower` **0.1.9** (source hash `f37bc66d…`) — `native-build-modset.log`, `native-build-record-modset.json` |
| main | `tools/e2e.sh` (A–BS + BT–BX) | **PASS**, `EXIT:0`; `PACKAGE … sha256=1e6beecf… bytes=199035` — `e2e-cell3.log` |
| selftest (cell3) | `SELFTEST=cell3 tools/e2e.sh` (BT inverted) | `FAIL: selftest: the cell3 capacity is 20000000 (20,000,000), so asserting 4,000,000 fails — the assertion is alive`, `EXIT:1` — `e2e-cell3-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-cell3-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=29 ok=29
missing-exit=0 bad-exit=0` (the slice-1…9 logs stay beside the new ones and are still green).

The slice's new parsed assertions are in `notes.md` (phases BT–BX); the numbers a reader should
check first:

- **the capacity and the tier sum**: `tier=3 local=5000/20000000` alone and
  `network=5000/20500000 cells=2` beside a cell1, while a cell3 behind one air block reads
  `0/20000000 cells=1`;
- **4,000 a side, not 5,000**: over 9 ticks a lone cell3 fell 76,000 → 40,000 (`4,000 × 9`) and at
  rest cell 12,000 + receiver 88,000 = the 100,000 seeded; with one extra cell the same window
  gives 65,000 → 25,000 over 8 ticks (`5,000 × 8`, the 25 % growth) and cell 0 + receiver 100,000;
- **the recipe's parent**: the carried plain `power_core3` recipe with stones where
  `rftoolsbase:dimensionalshard` belongs crafts nothing, while the core3 item is carried and a
  `cell4` id is refused.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 199,035 B | `1e6beecff03678042053c3a4d2bc52fded2c1bc41cbe2984ebbc876bbe16bb35` | 154 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`), and every packed file is the tree's bytes (`package matches the tree`).
The package was built **after the last packed edit** (`horizon-mod.toml`, `Cargo.toml`, `README.md`
and `src/` — all packed). Only `notes.md`, `VALIDATION.md`, `FINDINGS.md`, `CONTENT.md`,
`PLAN-slice10.md`, `tools/e2e.sh` and `tools/assemble_content.py` changed afterwards, and none of
them is packed.

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the **same** export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` 0.1.0 and `rftoolspower` 0.1.9.
- The rate assertions use the two replies' own `t=` and `local=` (`ΔE = rate × Δt`), never a sleep.
  The first BV attempt waited too long and let the cell drain to 0 mid-window; that false failure
  was fixed by shortening the window, not by weakening the equality.
- A store still moving is not conserved across two reads: the face was set back to `NONE` before
  the receiver was read, so BV/BW's conservation is checked at rest.
- `SELFTEST=cell3` is a focused leg: the cell3 phases are a function called directly after phase T,
  so a timing flake in a phase after T cannot stop the inversion from being reached. Its `EXIT:1`
  names the 20,000,000-vs-4,000,000 mismatch.
- Before building, the stale 0.1.8 `native-*` tag carrying this mod was removed so the launcher
  could not select it.
