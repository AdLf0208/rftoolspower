# RFTools Power — validation record (slice 12, package 0.1.11)

Pin **`0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`, game 26.3. Package **0.1.11**.
This slice adds the coal generator's **infusable upgrade factor** (gap 3): an int 0–256 component on
an existing carried item in a third slot raises the rate to `60 + (long)(60 × factor)` FE a tick and
the burn to `600 + (int)(600 × factor / 2)` ticks, exactly upstream's float rules. The pin has no
infusable component, so this port's own `rftoolspower:infusable_data` carries the int (McJtyLib's
scale and field name `infused`; the block-NBT key stays `infusable`). Every command below ran on
2026-11-24; the logs are under `ports/_shared/evidence/rftoolspower/` and
`ports/_shared/evidence/rftoolspower-e2e/`, and each package gate prints the `.hmod` sha it ran against.

## The component gate (first command of the slice)

`grep -ri infus ports/_shared/sdk/0a875da/` → no matches: the pin has no infusable component or
capability, so the gate passed on the directive's own terms — carry the factor as this port's own int
component (`rftoolspower:infusable_data`), the way the blazing rod's `blazing_rod_data` is carried.
No upstream item was invented and no chat command sets the factor. The artefact was read first at
`1.21_neo` @ `e44463ca`: `handlePowerGeneration`'s `burning += (int)(burning * factor / 2.0f)` and
`getRfPerTick`'s `rf += (long)(rf * factor)`, with McJtyLib `IInfusable.getInfusedFactor() =
(float) infused / maxInfuse`, `maxInfuse = 256`.

## The ladder — all compile gates forwarded to `AdLf-PC`

Every SDK gate was invoked as
`ports/tools/build-slot.sh run --job W1-rftoolspower --port ports/rftoolspower --step <step> -- <cmd>`.
The runner printed `build-slot: forwarding <step> for ports/rftoolspower to the remote runner`; the
far box is `AdLf-PC`. No `BUILD_LOCAL=1` was used.

| step | command | result |
|---|---|---|
| unit tests | `tools/gates.sh test` | **160 passed; 0 failed** — `sdk-test.log`, `PACKAGE … sha256=12edfec1… bytes=205875` |
| clippy | `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings**, exit 0 — `sdk-clippy.log` |
| fmt | `cargo fmt --check` | clean, exit 0 — `sdk-fmt.log` |
| build 1 / 2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | both `205,875 B`, sha256 `12edfec1…`; `cmp`-identical — `sdk-build-1.log`, `sdk-build-2.log` |
| check | `cargo horizon-mod check rftoolspower.hmod` | exit 0, `0.1.11 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `205875 bytes, SHA-256 12edfec1…` — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for` — `sdk-fits.log` |
| fits (another) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits` — `sdk-fits.log` |
| package gate | `python3 ports/tools/verify-sdk-package.py rftoolspower` | **1/1** (`package matches the tree`, R9 clean, no local `Block`/`Item` type) |

The red proof is `ports/_shared/evidence/rftoolspower/red-factor.log`:
`test result: FAILED. 156 passed; 3 failed`, verbatim
`not yet implemented: infused_burn_ticks is not written yet`,
`not yet implemented: infused_factor is not written yet`,
`not yet implemented: generator_rf_per_tick is not written yet`. The green `sdk-test.log` was
regenerated **after** the 0.1.11 build, so its `PACKAGE` line names `12edfec1…` / 205,875 B.

## In game — these legs stayed local

The launcher game build and all three e2e legs were run through `--step e2e` of the slot runner and
stayed on this box: the exported game/instance, the `--offscreen` Vulkan renderer and the unmodded
control game live here. Each leg is logged with its `PACKAGE` line and ends `EXIT:<status>`.

| leg | command | result |
|---|---|---|
| build (package) | `launcher-game.sh build rftoolspower` | `Compiling rftoolspower (1 of 1)`, `native-0a875da-3d288b05a395`, exported — `native-build.log` |
| build (package + receiver) | `tools/build-e2e-game.sh` | `native-0a875da-44fd54c31c1d`, `rfpowerharness` 0.1.0 and `rftoolspower` **0.1.11** — `native-build-modset.log` |
| main | `tools/e2e.sh` (A–BX + BY/BZ + CA/CB) | **PASS**, `EXIT:0`; `PACKAGE … sha256=12edfec1… bytes=205875` — `e2e-factor.log` |
| selftest (factor) | `SELFTEST=factor tools/e2e.sh` (CA inverted) | `FAIL: selftest: the infused generator made 3330 FE over 37 ticks (90 a tick), so asserting the un-infused 60 a tick fails — the assertion is alive`, `EXIT:1` — `e2e-factor-selftest.log` |
| control | `CONTROL=1 tools/e2e.sh` (unmodded Nightly) | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` — `e2e-factor-control.log` |

`python3 ports/tools/check-e2e-logs.py rftoolspower-e2e --strict` → `logs=35 ok=35
missing-exit=0 bad-exit=0` (the slice-1…11 logs stay beside the new ones and are still green; the two
component-field probes are in `ports/rftoolspower/debug/`, outside the evidence tree).

The slice's new parsed assertions are in `notes.md` (phases CA/CB); the numbers a reader should
check first:

- **the burn and the rate**: the carrier reads `infused 128 factor 0.500 rf 90`, and one coal starts
  `burning 744/750` (`750 = 600 + (int)(600 × 0.5 / 2)`); over two replies naming `t=242 → 279` the
  store rises `540 → 3,870` — **+3,330 = 90 × 37**;
- **the differential**: a generator with no carrier starts a 600-tick burn and makes exactly
  **60 × Δburn**;
- **the refusal**: a stone clicked on the infusion slot changes nothing, stays in the server-side
  `Inventory`, and is not placed against the machine;
- **the artefact's float casts**: `60 × (1 + factor)` is exact at factor 0.5, but `infused=1` gives
  no extra FE and one extra tick — the unit tests pin the truncation the in-game window cannot see.

## The delivered package

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `ports/rftoolspower/rftoolspower.hmod` | 205,875 B | `12edfec12d1537c8d72e4ff3dafbb789addbf684dce4d1667173cbcf3a2a65a9` | 154 |

No packed `Cargo.lock`; `src/runtime.rs` inside the archive is byte-identical to the tree file
(`verify-sdk-package.py`), and every packed file is the tree's bytes (`package matches the tree`).
The package was built **after the last packed edit** (`horizon-mod.toml`, `Cargo.toml`, `README.md`
and `src/` — all packed). Only `notes.md`, `VALIDATION.md`, `FINDINGS.md`, `CONTENT.md`,
`tools/e2e.sh`, `tools/parse_info.py` and the harness `.in` files changed afterwards, and none of them
is packed. The earlier 0.1.10 artifact was 202,754 B / `acf020a0…` / 154 entries.

## Probes that are not evidence, and how they were avoided

- A `horizon-ctl` run outside a lease can execute another port's `horizon-client` from the shared
  target; every leg here was built into the same export the e2e then ran, and the export's
  `native-mods.json` names exactly `rfpowerharness` 0.1.0 and `rftoolspower` 0.1.11.
- The first in-game attempt put the carrier in slot 2 but read `infused 0`: the component's *field*
  was `infusable` in code while the `/give` (and McJtyLib's `ItemInfusable`) uses `infused`. Two
  probes (`debug/probe-component-field.log`, `debug/probe-saved-nbt.log`) named the stack and block
  NBT; the fix separated the component field `infused` from the block-NBT key `infusable`.
- A local shell variable named `CARRIER` was clobbered by `info`'s `eval` (the readout now prints a
  `CARRIER=` field). The e2e uses `UPGRADE_ITEM`, and the parsed `CARRIER` is an assertion.
- A store still moving is not conserved across two sequential reads; CA/CB use the two replies'
  own `t=` and paired burn deltas, never a wall-clock sleep, as the earlier slices do.
- `SELFTEST=factor` is the focused inversion: CA asserts the un-infused 60 FE a tick and the leg
  fails with its `EXIT:1` naming the real 90, so the rate assertion can fail. The control leg proves
  a fresh generator cannot even be placed without this package.
- Before each build, the stale `native-*` tags carrying this mod were removed so the launcher could
  not select a build of the previous source version; one retry was needed when another port's
  launcher build held the shared native-build lock.
