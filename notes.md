# RFTools Power — port notes (slice 1: the coal generator)

> **Current state (2026-11-21): slice 1, package 0.1.0 at pin
> `0a875da91dbb0fdcb7ba8c42c11341aa229af51a` / mixins `e59da909…`.** This is the port's
> **first** slice, not a continuation: `ports/rftoolspower/` did not exist when the wave-1121 brief
> was written, so the brief's "next slice after `pending`" had no gap list to read. The slice is
> therefore chosen from the jar's own inventory and the upstream repository, the way
> `refinedtypes` (§0ak) and `rftoolsbuilder` (wave 5) were dispatched — and it is one family, not
> the whole mod.
>
> **Format:** one flat SDK `.hmod` — `horizon-mod.toml` (`api = "0.2"`, `[native]` pin) +
> `Cargo.toml` + `src/lib.rs` (`impl mod_api::Hooks`) + `src/runtime.rs` (pure) + `src/support.rs`
> (glue) + `assets/` + `data/`. No `mixins/`, no `horizon-mixin.toml`, no `.hnmod`.

Ported from **RFTools Power 1.21-7.0.6** (`McJtyMods/RFToolsPower`, **MIT**), the exact ATM10
NeoForge 1.21.1 jar `ports/_shared/licence-cache/rftoolspower-1.21-7.0.6.jar` (SHA-256
`259ebd617cc48e82bf0f1384ab661584829c6bcf0296273e338ceaa38a11f5d8`, 464 entries, 579,975 B).
Upstream behaviour was read from branch `1.21_neo`, commit
`e44463cacddb85155839373b42d39bc705d618c0` (`version=1.21-7.0.6`, 2026-06-16) and McJtyLib
`1.21_neo` commit `ef393e608eebc188a6e1decbf110506a55cc0725` — analysis only, this is a
clean-room rewrite. What was read and the numbers extracted: [`FINDINGS.md`](FINDINGS.md).

**Licence: MIT → rank 0 (permissive).** The jar's `neoforge.mods.toml` declares
`license="MIT License https://github.com/McJtyMods/RFToolsPower/blob/1.21_neo/LICENCE"`, read with
`python3 ports/tools/audit_licences.py --mod rftoolspower --fetch` → `AUDITED`. The text is kept in
[`LICENSE`](LICENSE); the base textures this package carries are from the **rftoolsbase** jar, also
MIT (`5195ba53…4b00`), and the provenance is in [`LICENSE-NOTICE.md`](LICENSE-NOTICE.md) and
[`CONTENT.md`](CONTENT.md). Publishable as a first publication under MIT with this source, subject
to the campaign's maintainer approval (ARCHITECTURE.md §8).

Status: **ported-partial** — the coal generator family is implemented and verified in game at the
current pin; A–M of the e2e are green. The gap list below is the rest of the mod.

## Class + tier and the approach

- **Class:** `content`; **tier:** `machines` (`ports/ledger.csv` row 405,
  `ports/_shared/source-map/atm10-sources.csv` row 405). `precheck-mod.py` also calls it an
  **add-on** (it declares `rftoolsbase` and `mcjtylib` required); the parent this slice binds to is
  this campaign's own `rftoolsbase` port, `ported-partial`.
- **Approach** (`horizon/docs/modpacks.md` §Tiers, §6 machines row): a block entity with a server
  tick, a container and an energy capability, plus the carried content. Not a data-only block and no
  renderer (a renderer would be `client`).
- **Carry-over vs agent port:** the blockstate (twelve `facing`×`lit` variants), the two block
  models, the item model, the front texture, the recipe, the loot table, the advancement and the
  lang are carried from the jar; the three machine base textures are carried from the rftoolsbase
  jar (see `CONTENT.md`); the block entity, the tick, the buffer, the click, the drop and the
  command are the agent port.
- **Parent surface this add-on binds to** (the 2026-11-21 ruling): the *only* parent id used is
  **`rftoolsbase:machine_frame`**, the centre cell of the carried recipe. It exists in the parent
  port (`ports/rftoolsbase/data/rftoolsbase/horizon/item/machine_frame.json`, template
  `minecraft:stick`, plus its own recipe and creative tab). No parent capability, machine or recipe
  type is used. The three base textures are **copied into this namespace** rather than referenced,
  so the package stands alone.

## What the slice does

- **The block.** `rftoolspower:coalgenerator` on the **`minecraft:furnace`** template: a full cube
  with `facing` and `lit`, hardness 2.0 / blast 2.0, correct tool, metal sound (McJtyLib's
  `STANDARD_IRON`).
- **The burn.** Each server tick (upstream `handlePowerGeneration`): if nothing is burning and the
  one fuel slot holds a fuel, one item is taken and the burn is set to 600 ticks (5,400 for a coal
  block); then one tick of burn is spent and 60 FE are stored. `lit` mirrors the burn into the block
  state, so the block is dark the moment the burn ends.
- **The fuels.** `minecraft:coal`, `minecraft:charcoal`, `minecraft:coal_block` — upstream tests the
  *item*, not the `minecraft:coals` tag. A non-fuel is refused with an action-bar line and nothing
  moves.
- **The buffer.** 500,000 FE, stored as the int `energy` in the block entity's saved compound and
  declared through `Registrar::block_energy` (capacity 500,000, takes nothing in, gives 2,000 FE an
  extract on every face — upstream's `generatorRFPerTick`). A full buffer keeps burning: the fuel is
  spent anyway (upstream's own order).
- **The slot.** One insert-only slot every face reaches, so a hopper feeds it; a right click puts
  the held fuel in it (there is no GUI in this slice, so the click is how a player fuels it).
- **The store on the item.** A broken generator's own item carries `minecraft:block_entity_data`
  with `energy`/`burn`/`burn_max` (upstream's loot table copies its energy component; this is the
  vanilla carrier), and placing that item restores the store, clamped to the capacity and to the
  longest burn.
- **The readout.** `/rftoolspower info <pos> [nonce]` (operator level): the line the e2e parses.

## Numbers and where they came from

| Number | Value | Source |
|---|---:|---|
| capacity | 500,000 FE | `CoalGeneratorConfig.MAXENERGY` (`defineInRange("generatorMaxRF", 500000, …)`) |
| FE a tick | 60 | `CoalGeneratorConfig.RFPERTICK` (`generatePerTick`) |
| ticks a coal | 600 | `CoalGeneratorConfig.TICKSPERCOAL` (`ticksPerCoal`) |
| a coal block | 5,400 ticks | `handlePowerGeneration`'s `if (extracted.getItem() == Blocks.COAL_BLOCK.asItem()) burning *= 9` |
| FE out a tick | 2,000 | `CoalGeneratorConfig.SENDPERTICK` (`generatorRFPerTick`); upstream's `handleSendingEnergy` |
| a charge item | 1,000 FE a tick | `CoalGeneratorConfig.CHARGEITEMPERTICK` — **not ported**, see the gaps |
| fuels | coal, charcoal, coal block | `CoalGeneratorTileEntity.isValidFuel` |
| redstone | ignored by default | `RedstoneMode.REDSTONE_IGNORED` is McJtyLib's `BaseBEData` default; `isMachineEnabled()` returns true |
| block properties | 2.0 / 2.0, pickaxe, iron sound | McJtyLib `BlockBuilder.STANDARD_IRON` (`CoalGeneratorTileEntity.createBlock`) |
| recipe | 4 coals / 2 redstone torches / a machine frame | `CoalGeneratorModule.initDatagen` `"cTc"/"cFc"/"cTc"` |

## Red → green (unit, verbatim)

The six rules were stubbed `todo!()` behind their tests first; the failing run is
`ports/_shared/evidence/rftoolspower/red-runtime.log`:

```
test result: FAILED. 0 passed; 10 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
not yet implemented: Generator::tick is not written yet
not yet implemented: Fuel::of is not written yet: minecraft:charcoal passed
not yet implemented: Generator::load is not written yet
not yet implemented: restored is not written yet: 999999 0 0
```

Green: **18 passed; 0 failed** (`cargo test`, log `sdk-test.log`). Two fixture mistakes were the
tests' faults, not the rules': a burn of 1,503 ticks with a 600-tick denominator (fixed to 503/600)
and a stale denominator left over an empty bar (`restored` now zeroes it — a repaired bar over no
burn is not upstream state, it is a doctored item).

## In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

Built with the launcher at the pin: `native-build` reported
`Compiling rftoolspower (1 of 1)` and installed `native-0a875da-07078c9d2541` — a **new** tag, so no
stale build was reused (the trap the brief names).

| log | verdict |
|---|---|
| `e2e-coal-generator.log` | **PASS**, `EXIT:0` — phases A–M |
| `e2e-selftest.log` | `FAIL: selftest: the generator made 3240 FE in 54 ticks, so the assertion is alive`, `EXIT:1` |
| `e2e-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=3 ok=3 missing-exit=0 bad-exit=0`.

The parsed assertions, each from a `ctl` reply:

| phase | what it asserts (observed) |
|---|---|
| A | a placed generator reads `0/500000 FE (burning 0/0 ticks, lit false, fuel empty)` and the block state is `lit=false` |
| B | one coal in the hand moves into the slot, is loaded on the next tick and lights the block: `780/500000 FE (burning 587/600 ticks, lit true)`, the hand empty, block `lit=true` |
| C | over 53 burn ticks the store rose `1620 → 4800`, i.e. **exactly 60 a tick** (`dE == 60*dB`) |
| D | after the burn ends: `36000/500000 FE (burning 0/0 ticks, lit false)`, block `lit=false`, and the store is unchanged 20 ticks later |
| E | a stone click leaves the slot empty and the stone in the hand |
| F | charcoal starts a 600-tick burn |
| G | a coal block starts a 5,386/5,400-tick burn (one item) |
| H | an item doctored to 499,950 FE + a 600-tick burn clamps to `500000/500000` and keeps burning (`burning 556`) |
| I | a hopper over a fresh generator feeds it with no click: `0 FE` → `4200 FE`, fuel `minecraft:coal x1` |
| J | the store survives save + quit + relaunch: `500000/500000 FE` before and after |
| K | a survival break of a 3,000 FE generator drops one whose `SelectedItem` carries `minecraft:block_entity_data {energy: 3000, …}`; placing it restores `3000 FE`; a 999,999 FE item places `500000 FE` |
| L | `rftoolspower:coal_generatore` is refused and never reaches the inventory |
| M | the carried recipe with a stone where `rftoolsbase:machine_frame` belongs crafts nothing |

Counterfactual: `SELFTEST=1` inverts C and the leg fails as designed, so C can fail. D is the
differential for C (no fuel → no FE), and the control leg proves A is not vacuous.

## Engines traps this slice cost (measured, not read)

1. **Creative keeps the container stack.** `ItemPlace::PlayerHand.extract` follows vanilla's
   creative rule, so the first e2e run's click left the coal in the hand and B failed at
   `the hand still holds 1 coal after the click`. The leg now runs in survival from the arena on —
   the mechanic the mod has is the survival one.
2. **A tick's edits are discarded unless the Part answers `Changed`.** `BlockEntityTickReply::
   Unchanged` restores the payload snapshot (`ModBlockEntityView::__finish_tick_listener`), so the
   tick reports `changed` from the rule's own comparison instead of assuming the write stuck.
3. **A block entity type whose id equals its block's id makes the host skip the entity**
   (`actuallyadditions` measured it): the type here is `rftoolspower:coalgenerator_block_entity`
   while the block is `rftoolspower:coalgenerator`.
4. **The item's `block_entity_data` payload must name the type id**, not the block id
   (`TypedEntityData.loadInto`), which is why K's drop reads
   `id: "rftoolspower:coalgenerator_block_entity"`.

## Upstream defects fixed

None adopted: every rule in this slice is upstream's own. Two *documented* deviations instead:

- **No GUI, so a click fuels the machine.** Upstream inserts through its menu slot or automation;
  this slice has no menu, so a right click puts one held stack in the slot. A user notices: fuel goes
  in without opening a screen. The container is declared, so a hopper feeds it exactly as upstream.
- **The `lit=true` model draws the same cube as `lit=false`.** Upstream's `coalgenerator_on` inherits
  `rftoolsbase:block/rftoolsblock_glow`, a custom glow-layer model with an animated overlay
  (`coalgenerator_glow.png` + `.mcmeta`); the pin cannot run that model, so the state is real and the
  overlay is a gap.

## Gaps (the rest of the mod)

1. **The FE push into a neighbour** (`handleSendingEnergy`, 2,000 FE a tick into adjacent energy
   handlers). The buffer is declared and every face extracts, so a neighbour that pulls works; the
   generator itself does not push yet, because **no receiver family ships in this slice** and an
   unproven push would be a claim. Next slice: the powercell.
2. **The charge-item slot** (`SLOT_CHARGEITEM`, 1,000 FE a tick into an energy item). Needs the item
   energy capability and an item that carries FE; not carried here.
3. **The infusable upgrade factor** (`getRfPerTick`'s `factor`, and the burn's `+burning*factor/2`).
   Upstream's upgrade slot is McJtyLib's `DefaultInfusable`; the upgrade item family is not ported.
4. **The GUI and its redstone mode** (`GuiCoalGenerator`, `RedstoneMode` Ignored/Off/On). The port
   keeps upstream's default `IGNORED` (the machine always runs) and has no toggle.
5. **The `lit=true` glow layer and the animated `coalgenerator_glow.png`** (see the deviations).
6. **The comparator output** (`ComparatorBlockEntity` on the buffer) and the TOP/Jade integration.
7. **The recipe's crafting in this build** — `blocked(rftoolsbase:machine_frame-absent)`: the parent
   package is a second `.hmod` the launcher cannot load beside this one in the e2e instance, so the
   leg proves the pattern crafts nothing without it (the `rftoolsstorage` precedent). With both
   packages installed the recipe crafts as upstream's.
8. **The fuel slot's items do not ride on a broken generator's item.** The `block_entity_data`
   payload is the saved compound (the store); the engine keeps container items apart from it, and
   upstream copies them through its own `item_inventory` component. A user notices: a broken
   fuelled generator keeps its FE but not its coal.
9. **The powercell (`cell1/2/3`)** — the mod's storage and its multiblock network — is
   `blocked(smartwrench-not-carried)`: `PowerCellBlock.wrenchUse` toggles a side's NONE/INPUT/OUTPUT
   mode, and a fresh cell's six faces are all `NONE`, so a cell cannot be filled without
   `rftoolsbase:smartwrench`, which the parent port does not carry (`ports/rftoolsbase/notes.md`
   gap 12).
10. **The rest of the mod:** the power monitor and power level, the dimensional cell (with its
    card-linked networks), the endergenic generator with the pearl injector and ender monitor, and
    the blazing generator/agitator/infuser with blazing rods.

## Coverage of the coal generator family

| family | state |
|---|---|
| block, item, blockstate (12 variants), models, textures, tags, creative tab, lang | tested (A: place, read the block back, invent the item) |
| the fuel slot: click insert, hopper insert, non-fuel refusal | tested (B, E, I) |
| the burn: 600 ticks a coal, 5,400 a coal block, charcoal | tested (B, F, G) |
| generation at 60 FE a tick | tested (C, `dE == 60*dB`; selftest inverts it) |
| the differential: no fuel, no FE; the block dark | tested (D) |
| the 500,000 FE clamp while burning | tested (H) |
| persistence across save + relaunch | tested (J) |
| the store on the block's item, and the clamp of a doctored item | tested (K) |
| unknown id refused | tested (L) |
| comparator output, TOP/Jade | not ported (gaps 4, 6) |
| the GUI, the redstone toggle, the glow layer | not ported (gaps 4, 5) |
| the charge-item slot, the infusable factor | not ported (gaps 2, 3) |
| the FE push into a neighbour, the charge item | blocked (gap 1: next slice, the powercell) |
| the recipe's craft | `blocked(rftoolsbase:machine_frame-absent)` (gap 7) |
| the other nine blocks | not ported (gaps 9, 10) |

Skills: superpowers/using-superpowers, brainstorming, writing-plans, test-driven-development, systematic-debugging, verification-before-completion; BeautifulRust/rust-best-practices

## Verification (this run)

| command | result |
|---|---|
| `cargo test --offline` | **18 passed; 0 failed** (`../_shared/evidence/rftoolspower/sdk-test.log`, prints the package sha) |
| `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings** (`sdk-clippy.log`) |
| `cargo fmt --check` | clean (`sdk-fmt.log`) |
| two `cargo horizon-mod build` with `rm -f Cargo.lock` | `cmp`-identical (`sdk-build-1.log`, `sdk-build-2.log`) |
| `cargo horizon-mod check` | exit 0, `native-mod, format native-1/0a875da…/e59da909…, for 26.3` (`sdk-check.log`) |
| `cargo horizon-mod fits --build 0a875da` / `--build 0b14f8a` | `made for` / `fits` (`sdk-fits.log`) |
| `verify-sdk-package.py rftoolspower` | see `VALIDATION.md` |
| the leg | `PASS` + `EXIT:0`; selftest `EXIT:1`; control `EXIT:1`; `--strict` 3/3 |

## Artifact

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `rftoolspower.hmod` (port root) | 30,509 B | `33a0c6c0961bf39a86d1ef9ac613dd8a16050b4fd5ca18f4e7588f09450ecf99` | 24 |

Built twice with `rm -f Cargo.lock` before each (`cmp` identical), **no packed `Cargo.lock`**,
`check` green, both `fits` green.
