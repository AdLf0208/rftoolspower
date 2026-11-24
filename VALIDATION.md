# RFTools Power — validation record (slice 14, package 0.1.13)

## Slice 14 — the dimensional cell (2026-11-24)

Pin `0a875da91dbb0fdcb7ba8c42c11341aa229af51a` + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.13**, sha
`ca86febbbb54b4642faf9c90185c260532227f5e63c48e36ce5b1a670c11ab1b`, 230,612 B, 194 entries.

The artefact's capacities/rates came from `DimensionalCellConfiguration.java` at `1.21_neo`
@ `e44463ca` — `rfPerTick=5000` (:26), `rfPerNormalCell=1,000,000` (:29), `simpleFactor=4` (:36),
`advancedFactor=4` (:33) — and `getPowerFactor` (:406): simple 250,000/1,250, normal 1,000,000/5,000,
advanced 4,000,000/20,000. The carrier gate passed: `/rftoolspower card` read
`Card: item=rftoolspower:powercell_card net=7 nonce=240` off the live held stack, and the clicked
simple cell read `net=7`; no chat command set a link.

Every compile gate was invoked through `build-slot.sh run --job W1-rftoolspower --port
ports/rftoolspower --step …`, forwarding to `AdLf-PC` (no `BUILD_LOCAL=1`).

| step | result |
|---|---|
| red | `165 passed; 5 failed` — `not yet implemented: dim_tier_capacity / dim_tier_per_side / dim_card_network / dim_pool / dim_receive is not written yet` (`red-dimensionalcell.log`) |
| green test | **171 passed; 0 failed** (`sdk-test.log`, regenerated after the final build, naming the delivered sha) |
| clippy / fmt | 0 warnings / clean (`sdk-clippy.log`, `sdk-fmt.log`) |
| build 1 / 2 | both 230,612 B, sha `ca86feb…`, `cmp`-identical, no packed `Cargo.lock` |
| check | `0.1.13 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, exit 0 |
| fits | `0a875da made for` / `0b14f8a fits`, exit 0 |
| package gate | `verify-sdk-package.py rftoolspower` → **1/1** (`package matches the tree`, R9 clean) |
| game build | `Compiling rftoolspower (1 of 1)`; single `native-0a875da-227fab837d01`, two-mod `native-0a875da-80f83af1b992` (`rftoolspower` 0.1.13) |
| main leg | `e2e-dimensionalcell.log` — **PASS, `EXIT:0`** (A–BS, BT–BW, DA–DE) |
| control | `e2e-dimensionalcell-control.log` — unmodded game cannot place the generator, `EXIT:1` |
| selftest | `e2e-dimensionalcell-selftest.log` — asserts the normal 1,000,000 capacity on the simple pair, observes 250,000, `EXIT:1` |
| strict | `check-e2e-logs.py rftoolspower-e2e --strict` → `logs=41 ok=41 missing-exit=0 bad-exit=0` |

The decisive parsed assertions: DA's gate reply; DB's `tier=simple local=0/250000 network=0/500000
n=2 net=7` at **both** cells four blocks apart against `n=1 net=-1 network=0/250000` at the unlinked
cell; DC's `22500 → 65000` over 34 ticks = `1,250 × 34` at cell B; DD's `75000 → 43750` over 25
ticks = `1,250 × 25` with the receiver gaining FE; DE's crafted-and-consumed card recipe. The
carry-over cell recipes are `blocked(parent-absent)` (no `rftoolsbase:machine_frame` or
`infused_diamond` in this build). Full transcript and coverage: `notes.md` §Slice 14.

---

## Historical — slice 13, package 0.1.12

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.12**.
This slice adds the **endergenic generator's infusable factors** (gap 10): a carrier in the
generator's own slot raises the arrival gain from `rfPerHit[mode] × 2` to
`(long)((long)(rfPerHit[mode] × 2) × (factor + 2) / 2)` — **300 FE** at mode 1 and factor 1 — and
lowers the hold from 500 to `(long)(500 × (3 − factor) / 3)` = **333 FE a tick**, with the artefact's
single-precision products and truncating casts. Every command below ran on 2026-11-24; the logs are
under `ports/_shared/evidence/rftoolspower/` and `ports/_shared/evidence/rftoolspower-e2e/`, and each
package gate prints the `.hmod` sha it ran against.

## The arithmetic, read first from the artefact

`EndergenicTileEntity.java` at `1.21_neo` @ `e44463cacddb85155839373b42d39bc705d618c0` (the exact
ATM10 jar's version), line 353: `rf = (long)(rf * (3.0f - factor) / 3.0f)` with `rf = 500`;
lines 578-579: `rf = (long)(rfPerHit[mode] * powergenFactor (2.0))` then
`rf = (long)(rf * (factor + 2.0f) / 2.0f)`, then the age bonus. `factor = infused / 256.0f`.

**The dispatch prose's `gained == 600` is wrong**: it applies powergenFactor twice. Both the jar
and the formula the same dispatch quotes give **300** at mode 1. The port follows the artefact and
says so in the e2e log and report; the in-game leg additionally observed 450 at mode 2 (3 × 150),
confirming the 3×-table rule at two modes.

## The carrier gate (first in-game check of the slice)

Slice 12 proved the typed component `rftoolspower:infusable_data` on `power_core1` in the coal
generator's slot 2. Phase CC gives the same item with `{infused:256}` to the **endergenic**, clicks it
into its own slot in survival, and reads it back from the reply:
`carrier rftoolspower:power_core1 infused 256 factor 1.000`. The gate passed, so the slice was
implemented rather than `blocked(infusable-carrier)`; no chat command ever sets the factor. The
upstream endergenic container is `empty(...)` (the factor is an implicit `ITEM_INFUSABLE` component
on the block item), so this slot is the port's carrier for the same int.

## The ladder — all compile gates forwarded to `AdLf-PC`

Every SDK gate was invoked as
`ports/tools/build-slot.sh run --job W1-rftoolspower --port ports/rftoolspower --step <step> -- <cmd>`.
The runner printed `build-slot: forwarding <step> for ports/rftoolspower to the remote runner`; the
far box is `AdLf-PC`. No `BUILD_LOCAL=1` was used.

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` | **165 passed; 0 failed** — `sdk-test.log`, `PACKAGE … sha256=b98f7cbc… bytes=208103` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 / 2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | both `208,103 B`, sha256 `b98f7cbc…`; `cmp`-identical — `sdk-build-1.log`, `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0, `0.1.12 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `208103 bytes, SHA-256 b98f7cbc…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** (`package matches the tree`, R9 clean, no local `Block`/`Item` type) |

The red proof is `ports/_shared/evidence/rftoolspower/red-enderfactor.log`:
`test result: FAILED. 160 passed; 2 failed`, verbatim
`not yet implemented: endergenic_hold_cost is not written yet`,
`not yet implemented: endergenic_pearl_gain is not written yet`. The green `sdk-test.log` was
regenerated **after** the 0.1.12 build, so its `PACKAGE` line names `b98f7cbc…` / 208,103 B.

## In game — these legs stayed local

The launcher game build and all three e2e legs were run through `--step e2e` of the slot runner and
stayed on this box: the exported game/instance, the `--offscreen` Vulkan renderer and the unmodded
control game live here. Each leg is logged with its `PACKAGE` line and ends `EXIT:<status>`.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-9ce8dccaf5cc`, exported — `native-build.log` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `native-0a875da-29952fb57a7a`, `rfpowerharness` 0.1.0 and `rftoolspower` **0.1.12** — `native-build-modset.log` |
| main | `tools/e2e.sh` (A–CE) | **PASS**, `EXIT:0`; `PACKAGE … sha256=b98f7cbc… bytes=208103` — `e2e-enderfactor.log` |
| selftest (enderfactor) | `SELFTEST=enderfactor tools/e2e.sh` (CC/CD inverted) | `FAIL: selftest: the enderfactor assertions are alive — gain: the pearl paid 450 FE at mode 2 (artefact: 3 x 150 = 450), so asserting the un-infused 300 fails; hold: a held pearl spent 7659 FE in 23 ticks (333 a tick), so asserting the un-infused 500 a tick fails`, `EXIT:1` — `e2e-enderfactor-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-enderfactor-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=38 ok=38
missing-exit=0 bad-exit=0` (the 35 prior legs stay green). The probes used while designing the leg
live in `ports/rftoolspower/debug/`, outside the evidence tree.

The slice's new parsed assertions are in `notes.md` (phases CC/CD/CE); the numbers a reader should
check first:

- **the carrier gate**: the endergenic's own reply names `carrier rftoolspower:power_core1 infused
  256 factor 1.000` — the component round-trips on the endergenic, not just the coal generator;
- **the gain**: a pearl landing at mode 1 paid **300** (`t=12763`) against the un-infused 200, and a
  first attempt at mode 2 paid **450** = 3 × 150. Both are the artefact's `(long)(table × 2)` then
  `(long)(rf × (factor+2)/2)`, not the dispatch prose's 600;
- **the hold**: two replies naming `t=12763 → 12785` showed `spent=10323 → 17649`, i.e. **7,326 FE
  over 22 ticks = 333 a tick**, against upstream's 500. A first window was cut by the artefact's own
  0.6 % discard (`reason="Random pearl discard"`) and was retried on a fresh destination — the retry
  is the proof the window can fail;
- **the refusal**: a stone clicked on the endergenic's infusion slot changes nothing, stays in the
  server-side `Inventory`, and is not placed against the machine.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 208,103 B | `b98f7cbc05f4778656c02366ae5f451b4a3848873b3e722a0795c8f7902d95df` | 154 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`), and every packed file is the tree's bytes (`package matches the tree`).
The package was built **after the last packed edit** (`horizon-mod.toml`, `Cargo.toml`, `README.md`
and `src/` — all packed). Only `notes.md`, `VALIDATION.md`, `FINDINGS.md`, `CONTENT.md`,
`tools/e2e.sh`, `tools/parse_ender.py` and the debug probes changed afterwards, and none of them is
packed. The earlier 0.1.11 artifact was 205,875 B / `12edfec1…` / 154 entries.

## Probes that are not evidence, and how they were avoided

- A forwarded `cargo fmt` reformatted only the remote copy (the runner's pull excludes `*.rs`); the
  formatting was applied locally and re-checked through the slot runner. No build ran locally.
- The e2e's focused selftest dispatch had to move to the tail: `enderfactor_phases` calls helpers
  (`give_injector`, `place_held`, `link`) defined much later in the script, and an early dispatch
  exited 127 (`command not found`) before reaching the game. The green leg and the `EXIT:1` selftest
  carry the corrected script.
- The two stale `native-*` tags carrying this mod (`3d288b05a395`, `44fd54c31c1d`) were deleted
  before the build so the launcher could not select a build of the previous source.
- The carrier is consumed into slot 0, so it is **not** in the player's inventory afterwards; the
  "stays server-side" assertion belongs only to the refused stone.
- Two sequential reads of a moving store are not comparable; CC/CD use the replies' own `t=` and
  paired `spent=` deltas, and a window whose `dropped` counter moved is retried rather than asserted.
