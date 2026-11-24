# RFTools Power — validation record (slice 11, package 0.1.10)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.10**.
This slice adds the coal generator's **charge-item slot** (`SLOT_CHARGEITEM`): an energy item in slot 1
is charged at **1,000 FE a tick** out of the generator's own store, read from `CoalGeneratorConfig`'s
`CHARGEITEMPERTICK` in the jar. The pin's `horizon:item_energy` capability answers for a powercell
item's `minecraft:block_entity_data` energy int, so no new item was invented. Every command below ran
on 2026-11-24; the logs are under `ports/_shared/evidence/rftoolspower/` and
`ports/_shared/evidence/rftoolspower-e2e/`, and each package gate prints the `.hmod` sha it ran against.

## The capability gate (first command of the slice)

`ports/_shared/sdk/0a875da/crates/horizon-mod-vocab/src/item/energy_capability.rs` defines
`ITEM_ENERGY: ItemCapabilityKey<dyn EnergyHandler>` with `amount`/`capacity`/`insert`/`extract`, and
`surface.json` lists `capability:horizon:item_energy`. The pin can read and mutate FE on a carried
item, so the gate passed — the slice was implemented, not `blocked(item-energy-capability)`.

## The ladder — all compile gates forwarded to `AdLf-PC`

Every SDK gate was invoked as
`ports/tools/build-slot.sh run --job W1-rftoolspower --port ports/rftoolspower --step <step> -- <cmd>`.
The runner printed `build-slot: forwarding <step> for ports/rftoolspower to the remote runner`; the
far box is `AdLf-PC`. No `BUILD_LOCAL=1` was used.

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` | **156 passed; 0 failed** — `sdk-test.log`, `PACKAGE … sha256=acf020a0… bytes=202754` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 / 2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | both `202,754 B`, sha256 `acf020a0…`; `cmp`-identical — `sdk-build-1.log`, `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0, `0.1.10 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `202754 bytes, SHA-256 acf020a0…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** (`package matches the tree`, R9 clean, no local `Block`/`Item` type) |

The red proof is `ports/_shared/evidence/rftoolspower/red-chargeitem.log`:
`test result: FAILED. 152 passed; 4 failed`, verbatim
`not yet implemented: charge_step is not written yet`. The green `sdk-test.log` was regenerated
**after** the 0.1.10 build, so its `PACKAGE` line names `acf020a0…` / 202,754 B.

## In game — these legs stayed local

The launcher game build and all three e2e legs were run through `--step e2e` of the slot runner and
stayed on this box: the exported game/instance, the `--offscreen` Vulkan renderer and the unmodded
control game live here. Each leg is logged with its `PACKAGE` line and ends `EXIT:<status>`.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-c77791f98fa0`, exported — `native-build.log` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `native-0a875da-4936ffe0d492`, `rfpowerharness` 0.1.0 and `rftoolspower` **0.1.10** — `native-build-modset.log` |
| main | `tools/e2e.sh` (A–BX + BY/BZ) | **PASS**, `EXIT:0`; `PACKAGE … sha256=acf020a0… bytes=202754` — `e2e-chargeitem.log` |
| selftest (charge) | `SELFTEST=charge tools/e2e.sh` (BY inverted) | `FAIL: selftest: the item gained 41000 FE over 41 ticks (1000 a tick), so asserting 2,000 a tick fails — the assertion is alive`, `EXIT:1` — `e2e-charge-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-chargeitem-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=32 ok=32
missing-exit=0 bad-exit=0` (the slice-1…10 logs stay beside the new ones and are still green).

The slice's new parsed assertions are in `notes.md` (phases BY/BZ); the numbers a reader should
check first:

- **the rate and the conservation**: the cell item's component rose `14,000 → 53,000 FE` over two
  replies naming `t=11462 → 11501` (`39,000 = 1,000 × 39`), while the generator's store went
  `86,000 → 47,000` (`−39,000`) — the slot never feeds the generator;
- **the refusal**: a stone clicked on the charge slot leaves it `empty`, stays in the server-side
  `Inventory`, and nothing is placed against the generator;
- **the direction**: the jar's `handleChargingItem` puts FE *into* the item and consumes it from the
  store. The directive's "the item's FE must fall" contradicts the artefact; per the campaign's
  "artefact wins" rule the port implements charging and documents the discrepancy in `notes.md`.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 202,754 B | `acf020a0636fdebc6f799d721a034dcebc75a1b20e4a2c134f191377ad18f2fb` | 154 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`), and every packed file is the tree's bytes (`package matches the tree`).
The package was built **after the last packed edit** (`horizon-mod.toml`, `Cargo.toml`, `README.md`
and `src/` — all packed). Only `notes.md`, `VALIDATION.md`, `FINDINGS.md`, `CONTENT.md`,
`tools/e2e.sh` and the harness `.in` files changed afterwards, and none of them is packed.

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the same export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` 0.1.0 and `rftoolspower` 0.1.10.
- The charge runs at the **level tick's end**, not inside the generator's own tick: an item
  capability answers nothing while its block entity is out of the world. The first in-game probe
  moved 0 FE with `cap=yes` in a command readout; the queue + `level_tick_post` fix made the store
  fall exactly 1,000 a tick. That root cause is recorded in `notes.md`.
- A store still moving is not conserved across two sequential reads; the charge assertion uses the
  two replies' own `t=` and the paired store deltas, never a wall-clock sleep. The tier-3 cell
  windows use a second, roomier harness receiver so a loaded box's reply latency cannot fill the
  100,000 FE buffer and clip the measured rate; phase R keeps the original receiver and its
  exact-full assertions.
- `SELFTEST=charge` is the focused inversion: BY asserts 2,000 FE a tick and the leg fails with its
  `EXIT:1` naming the real 1,000-a-tick rate, so BY can fail. The control leg proves BY's fresh
  generator cannot even be placed without this package.
- Before each build, the stale `native-*` tags carrying this mod were removed so the launcher could
  not select a build of the previous source version.
