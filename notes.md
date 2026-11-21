# RFTools Power — port notes (slice 1: the coal generator; slice 2: the power monitor)

> **Current state (2026-11-21): slice 2, package 0.1.1 at pin
> `0a875da91dbb0fdcb7ba8c42c11341aa229af51a` / mixins `e59da909…`.** Slice 1 (0.1.0) is the coal
> generator; slice 2 adds the **Power Monitor** and the generator's **energy push**
> (`handleSendingEnergy`), from the port's own gap list (gaps 1 and 10). The 0.1.0 package is in
> review upstream; 0.1.1 is the same entry's next version.
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

Status: **ported-partial** — the coal generator (A–M) and the power monitor plus the generator's
energy push (N–T) are implemented and verified in game at the current pin. The gap list below is
the rest of the mod.

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

Slice 2 adds:

| Number | Value | Source |
|---|---:|---|
| monitor observation | every 20 ticks | `PowerMonitorTileEntity.tickServer` (`counter = 20`) |
| monitor levels | 0..=5 | `IntegerProperty.create("level", 0, 5)`; `1 + stored*5/max` clamped to 1..=5 |
| alarm band | percentages 0..100, default 0..0 | `PowerMonitorData(minimum, maximum)` and `stored * 100 / maxEnergy` |
| alarm signal | 15 | `support.setRedstoneState(this, inAlarm ? 15 : 0)` |
| monitor durability | 2.0 / 2.0, pickaxe, iron sound | McJtyLib `BlockBuilder` default (`PowerMonitorTileEntity.createBlock`) |
| monitor recipe | comparator / redstone / machine base / redstone block (`" P "`, `"rAr"`, `" R "`) | `MonitorModule.initDatagen` with McJtyLib's `r`/`R` defaults |
| push budget | 2,000 FE a tick **a neighbour** | `CoalGeneratorConfig.SENDPERTICK`, `EnergyTools.handleSendingEnergy` |

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

## Slice 2 — the power monitor and the generator's energy push (package 0.1.1)

Gap lines it comes from (`## Gaps` below): **gap 1** — *"the generator itself does not push yet"* —
and **gap 10** — *"the power monitor and power level"* (the monitor taken; the power level stays).
Tier: still **machines**; a block entity with a 20-tick server tick, one block state property and a
redstone output. No GUI, no renderer, no linking item, no side modes.

### What it does (upstream `PowerMonitorTileEntity`, 1.21-7.0.6, and `handleSendingEnergy`)

- **Read**: every 20 ticks (`counter = 20`) read the block **behind the monitor's display front**
  through the energy capability. The display front (`facing`) is set facing the placer on
  placement, as a furnace's is; the monitored block is the one the monitor is mounted on, which is
  upstream's logic-slab **input side**. The energy capability is asked with no side (`null`
  upstream).
- **Level**: `ratio = 1 + stored * 5 / capacity` in integer arithmetic, clamped to 1..=5, mirrored
  into the block state's `level` (0..=5). **0** when the block has no energy capability or a
  capacity of 0 — upstream's `if (maxEnergy > 0)` guard, which is why stone reads level 0 and an
  empty generator reads 1.
- **Alarm**: `percentage = stored * 100 / capacity`; the alarm is true when it is inside
  `[minimum, maximum]`. Mirrored into the furnace template's `lit` state. A band of **0..0** is
  upstream's unconfigured default and is read as *unset*: with no GUI in this slice, 0..0 as "alarm
  at exactly 0 %" would silently make every fresh monitor signal on an empty battery. The band is
  read and set by `/rftoolspower monitor` and `/rftoolspower band`, the harness's stand-in for the
  GUI's two sliders.
- **Redstone**: 15 on the **display face** (opposite the monitored block) while the alarm holds,
  0 elsewhere; only `getSignal` (weak), as upstream leaves `getDirectSignal` at 0. The state change
  notifies the neighbours, so a lamp beside it lights on the next observation.
- **The item**: a broken monitor carries its configured band in its own item's
  `minecraft:block_entity_data` (upstream's `ITEM_POWER_MONITOR_DATA`), clamped when placed.
- **The push** (`CoalGeneratorTileEntity.tickServer` → `handleSendingEnergy`, gap 1): each tick,
  **before** generation and from the store the tick started with, offer `min(2,000, stored)` to
  each of the six neighbours that answers the energy capability and take out what it accepted.
  Upstream's budget is **per neighbour**, not shared between faces.

### Red → green

The monitor's rules and the send clamp were stubbed `todo!()` behind their tests; the failing run
is `ports/_shared/evidence/rftoolspower/red-monitor.log`:

```
test result: FAILED. 18 passed; 9 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
not yet implemented
```

Green: **33 passed; 0 failed** (`sdk-test.log`). The nine new tests pin the ratio (`250,000 of
500,000 → 3`, full → 5, no capacity → 0), the percentage, the unset band, a configured band's
inclusive edges, the 20-tick window, "changed only when the state moved", a doctored restore, and
the send clamp.

### In game (same evidence directory)

| log | verdict |
|---|---|
| `e2e-power-monitor.log` | **PASS**, `EXIT:0` — phases A–T |
| `e2e-selftest.log` | `FAIL: selftest: the empty generator reads level 1, not the charged 3, so the assertion is alive`, `EXIT:1` |
| `e2e-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=4 ok=4 missing-exit=0 bad-exit=0`
(the slice-1 logs stay beside the new ones).

The parsed assertions, each from a `ctl` reply:

| phase | what it asserts (observed) |
|---|---|
| N | a monitor mounted against a 250,000/500,000 generator reads **level 3** (the ratio the unit test pins), band `0..0 (unset)`, alarm false, and a redstone lamp on its display face stays dark |
| O | an empty generator reads **level 1**, alarm false, lamp dark — the differential for N; `SELFTEST=1` inverts it and fails |
| P | a monitor mounted on `minecraft:stone` reads **level 0** and `target=minecraft:stone (not an energy block)` |
| Q | band `40..60` at 50 %: alarm true, monitor `lit=true`, lamp `lit=true`; band `90..100`: alarm false, both dark |
| R | the generator pushes its 100,000 FE into an adjacent energy block: the receiver ends full (100,000), the generator empty (0), the receiver's gain a multiple of the 2,000 a push moves, and the monitor facing the receiver reads **level 5** |
| S | a monitor item carrying band `80..90` is placed and the monitor reads `80..90` |
| T | the monitor's carried recipe with a stone where `rftoolsbase:machine_base` belongs crafts nothing |

Counterfactual: phase C's slice-1 inversion stays available as `SELFTEST_GENERATOR=1`; this
slice's `SELFTEST=1` is phase O. Phase R's differential is the generator's own store: it falls from
100,000 to 0 only because a receiver with room stands beside it.

### The receiver the push is proven against

The mod's own receiver, the powercell, is `blocked(smartwrench-not-carried)` (gap 9), and a monitor
is a display with **no buffer** (upstream has no energy capability on it), so the leg cannot push
into the monitor. The push is proven against `tools/harness-receiver/`, a **harness-only** native
mod: one block, `rfpowerharness:receiver`, with a 100,000 FE buffer (10,000 in a face an insert,
nothing out). It is built beside the package by `tools/build-e2e-game.sh`, lives outside the
`.hmod` (the launcher refuses nested package paths, so its source is stored as `.in` files), and is
listed in `native-mods.json` in `native-build-modset.log`.

### Engines traps this slice cost (measured, not read)

1. **The placement context's yaw is not the player's look.** `ctl place` reported the opposite of
   the player's yaw, and changed between runs, so the direction-sensitive phases let the monitor
   place and then set its display face with `/setblock … [facing=east,…]` (`aim_monitor`). The
   `state_for_placement` hook is still exercised (the block places); the read side the assertions
   use is then explicit.
2. **A mob in the target blocks a placement** ("the block did not change (blocked by an entity)").
   The End spawns endermen while the slice-1 phases run; every placement now clears non-player
   entities first and retries once.
3. **`/data get block X Y Z energy` answers a bare number**, not `{energy: N}` — the parser takes
   both shapes.
4. **Sequential `/data get` reads are several ticks apart**, so a conservation check across the
   generator and the receiver read earlier/later values (110,000 of a seeded 100,000). The leg
   asserts what is skew-free instead: the receiver ends full, the generator empty, and the gain is
   a multiple of the push size.
5. **`ctl messages` is newest-first and a new command's chat reply can arrive a few ticks late**;
   `await_line` waits up to ~3 s for the exact nonce.

### Upstream defect fixed (slice 2)

**The monitor's redstone face.** `PowerMonitorTileEntity.getRedstoneOutput` answers only when
`side == getFacing(state).getInputSide()` (the side attached to the machine), while
`LogicSupport.setRedstoneState` notifies `pos.relative(getInputSide().getOpposite())` — the display
side. The two disagree, so a lamp or wire on the output face is never told to re-read and the
signal never leaves the free face. The port follows the notify side (the display face, opposite the
monitored block) for both the answer and the update; a user notices: the alarm reaches a lamp beside
the monitor. The band's unset default is documented as the port's reading, not a defect.

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

1. ~~**The FE push into a neighbour**~~ — **ported in slice 2**: `handleSendingEnergy` offers
   2,000 FE a tick to every adjacent energy handler and is proven in game (phase R, against the
   harness receiver). The powercell, the mod's own receiver, is still gap 9.
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
10. **The rest of the mod:** the **power level** display (`PowerLevelTileEntity`, the monitor's
    sibling — same tick, but a 0..9 ratio written straight to the redstone output and no level
    state), the dimensional cell (with its card-linked networks), the endergenic generator with the
    pearl injector and ender monitor, and the blazing generator/agitator/infuser with blazing rods.
    The power monitor itself is ported in slice 2.

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
| the FE push into an adjacent energy handler, 2,000 a tick a neighbour | tested (R, against the harness receiver) |
| the charge item | not ported (gap 2) |
| the recipe's craft | `blocked(rftoolsbase:machine_frame-absent)` (gap 7) |
| the other nine blocks | not ported (gaps 9, 10) |

## Coverage of the power monitor family (slice 2)

| family | state |
|---|---|
| block, item, blockstate (facing×level×lit), six level models, textures, tags, creative tab, lang | tested (N: placed, read the state back; S: a monitor item placed) |
| the 20-tick read of the block behind the display front through the energy capability | tested (N, O, P, R) |
| the level ratio `1 + stored*5/capacity`, 0 for no energy block | tested (N=3, O=1, P=0, R=5; unit tests pin the numbers) |
| the band and its alarm, mirrored into `lit` | tested (Q: 40..60 lit at 50 %, 90..100 dark) |
| the redstone output on the display face | tested (Q: a redstone lamp lights and goes out) |
| the band on the broken monitor's item | tested (S) |
| the recipe's craft | `blocked(rftoolsbase:machine_base-absent)` (phase T proves the pattern crafts nothing) |
| the GUI, its two sliders and the redstone input mode | not ported (gap 4; `/rftoolspower band` is the harness stand-in) |
| TOP/Jade and the comparator output | not ported (gap 6) |

Skills: superpowers/using-superpowers, brainstorming, writing-plans, test-driven-development, systematic-debugging, verification-before-completion; BeautifulRust/rust-best-practices

## Verification (this run)

| command | result |
|---|---|
| `cargo test --offline` | **33 passed; 0 failed** (`../_shared/evidence/rftoolspower/sdk-test.log`, prints the package sha) |
| `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings** (`sdk-clippy.log`) |
| `cargo fmt --check` | clean (`sdk-fmt.log`) |
| two `cargo horizon-mod build` with `rm -f Cargo.lock` | `cmp`-identical (`sdk-build-1.log`, `sdk-build-2.log`) |
| `cargo horizon-mod check` | exit 0, `0.1.1 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)` (`sdk-check.log`) |
| `cargo horizon-mod fits --build 0a875da` / `--build 0b14f8a` | `made for` / `fits` (`sdk-fits.log`) |
| `verify-sdk-package.py rftoolspower` | **1/1** |
| the leg | `PASS` + `EXIT:0`; selftest `EXIT:1`; control `EXIT:1`; `--strict` 4/4 |

## Artifact (0.1.1)

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `rftoolspower.hmod` (port root) | 73,339 B | `6df52b7421749bc7fea622dd3359e84ce3ff847ea2454d2ce9ef3ef79c2d15f5` | 45 |

Built twice with `rm -f Cargo.lock` before each (`cmp` identical), **no packed `Cargo.lock`**,
`check` green, both `fits` green, `verify-sdk-package.py` 1/1, `src/runtime.rs` byte-identical in
the archive.
