# RFTools Power — port notes (slice 1: the coal generator; slice 2: the power monitor; slice 3: the
# powercell; slice 4: the endergenic generator and the pearl injector)

> **Current state (2026-11-22): slice 4, package 0.1.3 at pin
> `0a875da91dbb0fdcb7ba8c42c11341aa229af51a` / mixins `e59da909…`.** Slice 1 (0.1.0) is the coal
> generator; slice 2 (0.1.1) adds the **Power Monitor** and the generator's **energy push**
> (`handleSendingEnergy`); slice 3 adds the **powercell** (`cell1`/`cell2`): a per-tier block
> entity with a 500,000 / 4,000,000 FE buffer, six face modes that default to `NONE`, an adjacency
> **network** that shares one store and capacity across cells of any tier, and the output push out
> of an `OUTPUT` face; slice 4 adds the mod's signature mechanic, the **endergenic generator** with
> its **pearl injector**: two linked generators, a redstone pulse that starts a 15-mode charge and
> one that fires the held pearl, and the `rfPerHit` table that pays 200…25,600 FE for a pearl that
> lands inside the window (and nothing for one that lands outside it). Where upstream's smart
> wrench is needed (the link, the cell's face modes), the harness uses commands —
> `/rftoolspower enderlink`, `/rftoolspower side` — and never a fake item.
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

Status: **ported-partial** — the coal generator (A–M), the power monitor plus the generator's
energy push (N–T), the powercell (U–AD) and the endergenic pair (AE–AM) are implemented and
verified in game at the current pin. The gap list below is the rest of the mod.

## What the powercell binds to (the 2026-11-21 parent-surface ruling)

- The parent surface is again just **`rftoolsbase:machine_frame`** (cell1's recipe centre) and the
  carried `power_core1`. No parent capability, machine or recipe type is used.
- The **smart wrench is not carried** (gap 9's original blocker: `PowerCellBlock.wrenchUse` toggles
  a face's mode). The stand-in is a **command**, not a fake item:
  `/rftoolspower side <pos> <face> NONE|INPUT|OUTPUT`. A fresh cell is six `NONE`s in both cases —
  upstream's own default — so the command reproduces the wrench's state machine, not a behaviour
  the mod does not have.
- `cell2` is carried because the network's tier behaviour needs a second capacity to be observable;
  `cell3` is not (gap 9).

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

## Engines traps this slice cost (measured, not read)

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

## Slice 3 — the powercell, tier 1 and tier 2 (package 0.1.2)

Gap line it comes from (`## Gaps` below): **gap 9** — *"the powercell (`cell1/2/3`) — the mod's
storage and its multiblock network — is `blocked(smartwrench-not-carried)`"*. Tier: still
**machines**; block entities with a server tick, a capability and saved state. No GUI, no renderer,
no linking item.

### What it does (upstream `PowerCellTileEntity`, `PowerCellBlock`, `PowerCellConfig`,
`data/{Tier,SideType,PowerCellNetwork}.java`, 1.21-7.0.6)

- **The block.** `rftoolspower:cell1`/`cell2` on a plain full cube (`minecraft:iron_block`
  template): hardness 2.0, blast 2.0, iron sound, an iron pickaxe's tool.
- **The buffer.** One cell stores `tierNMaxRF` — **500,000** (tier 1) / **4,000,000** (tier 2); its
  own store is the int `energy` in its saved compound (`saveAdditional`'s `tag.putLong("energy")`,
  read back through the capability as the network's total).
- **The six faces.** `SideType` `NONE`/`INPUT`/`OUTPUT`, **all `NONE` on a fresh cell**, saved as
  upstream's own six-digit `mode` string in `Direction` order (`saveClientDataToNBT`). A face takes
  FE in only through `INPUT` (`receiveEnergyFacing`'s mode check); a face gives FE out only through
  `OUTPUT` (`sendOutEnergy`); the capability itself **never** lets a neighbour pull
  (`extractEnergy` answers 0), so the cell pushes on its own tick, as upstream's does.
- **The per-side cap.** One side moves `tierNMaxRFPerTick` — **250** (tier 1) / **1,000** (tier 2)
  — plus `rfPerTickScale` (**0.25**) of that per extra cell in the network, truncated by upstream's
  `(long)` cast: one cell 250, a pair **312**, nine 750. This is why a 2,000-a-tick generator fills
  a lone tier-1 cell at 250 a tick and keeps the rest.
- **The network.** Every powercell reachable through a shared face is one network
  (`buildNetwork` walks from one `PowerCellTileEntity` to the next): the capability answers the
  **sum** of the cells' stores and the **sum** of their capacities, and an insert fills the cell
  asked first and then the rest (`receiveEnergyFacing`). A network larger than `networkMax`
  (**729**) is `!isValid()` and moves nothing.
- **The output push.** Each tick (`tickServer` → `sendOutEnergy`) a cell with any `OUTPUT` face
  offers up to the network's per-side budget to the block on that face, **skipping another
  powercell** (cells share through the network, never by pushing into each other), and drains what
  was accepted from the network, its own store first (`extractEnergyFromNetwork`).
- **The item.** A broken cell keeps its own store (upstream's `copy_components` of `item_energy`)
  through `minecraft:block_entity_data`; the face modes are client data and do not travel. A
  doctored item's amount is clamped to the block's tier when placed.
- **The readouts.** `/rftoolspower cell <pos> [nonce]` prints tier/local/network/cells/sides in one
  line; `/rftoolspower side <pos> <face> <mode>` sets a face and echoes the six modes. Both are the
  harness's stand-ins for upstream's GUI and wrench.

### Numbers and where they came from

| Number | Value | Source |
|---|---:|---|
| tier-1 capacity | 500,000 FE | `PowerCellConfig.TIER1_MAXRF` (`tier1MaxRF`) |
| tier-2 capacity | 4,000,000 FE | `TIER2_MAXRF` |
| (tier 3, not carried) | 20,000,000 FE | `TIER3_MAXRF` |
| tier-1 a side a tick | 250 FE | `TIER1_RFPERTICK` (`tier1MaxRFPerTick`) |
| tier-2 a side a tick | 1,000 FE | `TIER2_RFPERTICK` |
| per extra cell | +25 % of the per-side number | `RFPERTICK_SCALE` (`rfPerTickScale`, `0.25`) |
| a network | at most 729 cells | `NETWORK_MAX` (`networkMax`, `9*9*9`) |
| face modes | NONE 0 / OUTPUT 1 / INPUT 2, fresh all NONE | `SideType` ordinals, `modes` initialiser |
| cell hardness | 2.0 / 2.0, pickaxe, iron sound | McJtyLib `BlockBuilder` default |
| cell1 recipe | redstone / power core / machine frame (`"rKr"/"KFK"/"rKr"`) | `PowerCellModule.initDatagen` |
| power core recipe | diamond / redstone / redstone block (`" d "/"rRr"/" r "`) | `PowerCellModule.initDatagen` |

### Two brief assertions corrected from the artefact (rulings: the artefact wins)

The dispatch brief asked for **a cell whose `energy` rises by exactly 2,000 a tick** from a
2,000-a-tick generator, and for **a `cell2` beside a `cell1` not to join the network**. Both
contradict 1.21-7.0.6:

1. **The receive rate is 250 a tick, not 2,000.** `receiveEnergyFacing` begins
   `maxReceive = Math.min(maxReceive, getRfPerTickReal())`, and `getRfPerTickReal` is
   `per_side + (size-1)*per_side*0.25` — 250 for a lone tier-1 cell. The port implements the cap and
   the leg asserts **exactly 250 × Δticks** on the cell *and* the matching loss on the generator
   (phase W). A 2,000-a-tick acceptance would have been an invented mechanic (and a cheat: eight
   times upstream's throughput).
2. **A `cell2` beside a `cell1` does join the network.** `buildNetwork` recurses over every
   adjacent `PowerCellTileEntity` with **no tier test**, and `redistributeNetwork` loops the three
   tiers *inside one network* — a per-tier loop that would be dead code if networks were
   single-tier. The network's capacity is therefore the sum of the tiers' capacities (a cell1 beside
   a cell2 = 4,500,000). The port implements that and the leg proves both directions (phase Y):
   adjacent cell1+cell2 share `5,000/4,500,000`; a cell2 one block away is its own
   `0/4,000,000`. What the brief meant to exclude — membership by tier rather than adjacency — is
   exactly what the differential shows is absent.

Both corrections are in the e2e transcript, so a reader can check them against the jar's source.

### Red → green

The cell's rules were stubbed `todo!()` behind their tests; the failing run is
`ports/_shared/evidence/rftoolspower/red-cell.log`:

```
test result: FAILED. 33 passed; 12 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
not yet implemented
```

Green: **50 passed; 0 failed** (`sdk-test.log`, which prints the package sha). The twelve new tests
pin: the six `NONE`s of a fresh cell and upstream's six-digit saved string; one face at a time and
the wrench's NONE→INPUT→OUTPUT cycle; the three tiers' capacities and per-side numbers; the 250 take
from a 2,000 push; the 312 budget of a pair and the asking cell's tier setting it; the rest of a
budget passing to the next cell; the network as the sum of mixed tiers; the 729-cell limit; the
asked cell draining first; and the per-tier clamp of a doctored store.

### In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

Built with the launcher at the pin: `native-build` reported
`Compiling rftoolspower (1 of 1)` and installed `native-0a875da-ad5b2631abc2`; the two-mod e2e build
is `native-0a875da-18dcc70fffdb` (`rfpowerharness`, `rftoolspower`), and its `native-mods.json`
names version **0.1.2**.

| log | verdict |
|---|---|
| `e2e-powercell.log` | **PASS**, `EXIT:0` — phases A–AD (the whole port, not just the cell) |
| `e2e-powercell-selftest.log` | `FAIL: selftest: the cell's NONE face took nothing in 40 ticks, so the assertion is alive`, `EXIT:1` |
| `e2e-powercell-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |
| `e2e-powercell-selftest-monitor.log` | slice 2's inversion, `EXIT:1` (regression: still alive) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=8 ok=8 missing-exit=0 bad-exit=0`.

The parsed assertions, each from a `ctl` reply:

| phase | what it asserts (observed) |
|---|---|
| U | a placed `cell1` reads `tier=1 local=0/500000 network=0/500000 cells=1 sides=none,none,none,none,none,none`, and `/data get … energy` is 0 |
| V | 40 ticks against a 100,000 FE generator whose face is still `NONE`: the cell stays **0** and the generator stays **100,000** (the differential for W) |
| W | `side … west input` echoes `west input (sides=none,none,none,none,input,none)`; over **38 ticks** the cell rises `2000 → 11500` (**+9,500 = 250 × 38**) and the generator falls `95750 → 86250` (**−9,500**); after the drain: cell `100000`, generator `0` |
| X | two adjacent `cell1`s read the same `network=3000/1000000 cells=2` (locals 1,000 + 2,000); a third with one air block of gap reads `4000/500000 cells=1` |
| Y | a `cell2` beside a `cell1`: both read `network=5000/4500000 cells=2`; a `cell2` with a gap reads `0/4000000 cells=1` |
| Z | `east output`, 100,000 in the cell: over 29 ticks `98000 → 90750` (**−7,250 = 250 × 29**); after `east none`, cell 88,500 + receiver 11,500 = **100,000** (nothing created or lost) |
| AA | `7000/500000 FE` and `west input` before and after save + quit + relaunch |
| AB | a survival break of a 3,000 FE cell drops one whose `SelectedItem` carries `block_entity_data {id: "rftoolspower:cell1_block_entity", energy: 3000}`; placing it restores `3000 FE` |
| AC | the power core's recipe crafts once (`rftoolspower:power_core1`) and consumes its diamond, redstone block and three redstones; cell1's recipe with a stone where `rftoolsbase:machine_frame` belongs crafts nothing |
| AD | `side … nowhere input` → `unknown face 'nowhere' (down\|up\|north\|south\|west\|east)`; `side … west inputt` → `unknown mode 'inputt' (none\|input\|output)`; a stone position → `No RFTools Power power cell there.` — all **parsed replies**, never the command's (always 0) exit status |

Counterfactual: `SELFTEST=1` inverts V and the leg fails as designed, so V can fail; W's differential
is V itself (no mode, no transfer). The control leg proves U is not vacuous.

### Engines traps this slice cost (measured, not read)

1. **A pure item needs its own `data/<mod>/horizon/item/<name>.json`.** The 26.3
   `assets/<mod>/items/<name>.json` is only the client model definition: without the `horizon/item`
   declaration, a recipe's result still *crafts* and the screen still shows
   `rftoolspower:power_core1`, but `give @s rftoolspower:power_core1` answers `Unknown item` — the
   in-game leg caught exactly that, and no `check`/`fits`/clippy run could.
2. **`setblock` of the same block keeps its block entity data.** A re-run left the harness receiver
   standing with a full store, so phase R's first sample read `100000` and the assertion was
   vacuous. The leg now sets the spot to air, waits, and places the receiver again (`SX,101,36` and
   `SX+1,101,68`).
3. **Two `data get` reads are several ticks apart, and a store still moving is not conserved across
   them** (`A(t1) + B(t2) = total − the change between the reads`). The leg asserts per-store rates
   against each reply's own `t` (`ΔE == 250 × Δt`) and does its conservation check **at rest**
   (after setting the face back to `NONE`, or after the generator is empty).
4. **`ctl click-slot 200` puts a crafting result on the cursor**, not in the inventory; a second
   click on a free hotbar slot stores it (`click-slot 8`), which is also how the leg proves the
   ingredients were consumed.
5. **A fill that spans unloaded End chunks answers "That position is not loaded" and lands
   nothing.** The cell rows reach z=90, so the leg stands in them and retries the floor fill, then
   asserts the floor and the air are really there before placing anything.
6. **`/tmp` tmpfs**: the leg honours `E2E_TMP` (the launcher wrapper exports
   `~/.cache/horizon-e2e/scratch`), so no scratch tree goes near the 7.5 GB tmpfs.

### Upstream defects fixed (slice 3)

None adopted. Two *documented simplifications*:

- **The model's `upper`/`lower` states are not declared.** Upstream's `PowerCellBlock` declares two
  boolean states for its connected-cell models, but its own `blockstates/cell1.json` carries only a
  single `""` variant — a state/model mismatch that would render an invisible block in vanilla. This
  slice draws one cell (a plain cube) and declares no extra states, so the block always renders.
- **No GUI.** Upstream opens a powercell screen; this slice's right click reads the status line, and
  the face modes are set by `/rftoolspower side` (the wrench stand-in).

Also recorded: the network is rebuilt from the loaded cells on every read rather than cached as
upstream's `PowerCellNetwork` object. A cell in an unloaded chunk is therefore not counted until its
chunk loads; nothing is lost (each cell saves its own store), but a network straddling an unloaded
chunk reads a smaller total for that moment.

### Slice 4 — the endergenic generator and the pearl injector (package 0.1.3)

Gap line it comes from (`## Gaps` below): **gap 10** — *"the endergenic generator with the pearl
injector and ender monitor"* (the generator and injector taken; the **ender monitor is phase 2**,
together with the `fireMonitors` notifications the two now leave as a no-op). Tier: still
**machines** — block entities with a server tick, a capability, saved state and a flight model. No
GUI, no renderer, no linking item.

### What it does (upstream `EndergenicTileEntity`, `PearlInjectorTileEntity`,
`EndergenicConfiguration`, `data/EndergenicPearl.java`, 1.21-7.0.6)

- **The blocks.** `rftoolspower:endergenic` on a plain full cube (upstream's
  `Properties.of().strength(2.0f).sound(METAL).noOcclusion()`, `RotationType.NONE`) and
  `rftoolspower:pearl_injector` on McJtyLib's STANDARD_IRON with a six-way `facing`
  (`RotationType.ROTATION`; the front faces the placer, so the generator it feeds is behind it).
- **The charge.** A **rising** redstone edge (`getBestNeighborSignal > 0 && !prevIn`) while idle
  starts a charge at mode **1**; each tick then adds a mode, and past **15** the generator is idle
  again. A rising edge while **holding** fires the held pearl.
- **The hit table.** A pearl that arrives at mode *N* while charging pays
  `rfPerHit[N] × powergenFactor` (2.0), plus up to **100 %** more for the pearl's age
  (`age × 5 %`, capped at 100 — a pearl that has already powered five generators is worth double).
  The table is `{0, 100, 150, 200, 400, 800, 1600, 3200, 6400, 8000, 12800, 8000, 6400, 2500,
  1000, 100}`: **200 FE** at mode 1, **25,600 FE** at mode 10, 200 again at mode 15.
- **The misses.** A pearl that arrives while idle is **lost** (`"Pearl arrived while idle"`); one
  that arrives while already holding loses **both** (`"Pearl arrived while holding"`). Nothing is
  paid — the differential this slice is proven against.
- **The hold.** A landed pearl starts a hold that costs **500 FE a tick**; when the store cannot
  pay it the pearl is dropped (`"Not enough energy to hold pearl"`). While holding there is also
  upstream's **0.6 %** chance a tick that the pearl is simply lost (`nextInt(1000) <= 5`).
- **The flight.** A fired pearl travels `(int)(3-D distance / 3) + 1` ticks (a three-block link is
  2 ticks) to its **destination**, the generator a wrench link named; a link of **5 ticks or more**
  is refused ("maximum 4"). A generator with no destination loses the pearl it fires
  (`"Missing destination"`).
- **The buffer.** **5,000,000 FE** (`endergenicMaxPower`), stored as the int `energy` in the saved
  compound and declared through `Registrar::block_energy`: readable (a monitor facing it shows the
  store) and **not** insertable/extractable — the generator pushes on its own tick, as upstream's
  `handleSendingEnergy` does: up to **20,000 FE a tick** to every neighbour that answers the
  capability, and it **keeps 2,000 FE** (`endergenicKeepRf`) as the reserve a held pearl needs.
- **The injector.** **18 pearl slots** (a 9×2 buffer), insert-only through every face; a rising
  redstone edge takes **one ender pearl** and fires it from the generator it is mounted on
  (`findEndergenicTileEntity`: behind its front, else above). A pearl injected into a generator
  that is already holding is consumed and dropped — upstream's own comment says "this one is lost".
- **The item.** A broken endergenic carries its **store** (upstream's loot copies
  `mcjtylib:item_energy` only), clamped to the capacity when placed; the charge, the link and the
  pearls do not travel. The injector's pearls do not travel either (upstream's `item_inventory`
  component is not registered here — gap 8's shape).
- **The readouts.** `/rftoolspower endergenic <pos>` prints energy/charging/age/pearls/fired/
  dropped/gained/spent/arrived/reason/dest/distance in one line; `/rftoolspower injector <pos>`
  prints its pearl count and the generator it feeds; `/rftoolspower enderlink <pos> <dest>` is the
  smart wrench's link. All three are the harness's stand-ins for upstream's GUI and wrench.

### Numbers and where they came from

| Number | Value | Source |
|---|---:|---|
| capacity | 5,000,000 FE | `EndergenicConfiguration.MAXENERGY` (`endergenicMaxPower`) |
| a held pearl costs | 500 FE a tick | `rfToHoldPearl` (`endergenicRfHolding`) |
| the reserve | 2,000 FE | `ENDERGENIC_KEEPRF` (`endergenicKeepRf`) |
| the push | 20,000 FE a tick a neighbour | `ENDERGENIC_SENDPERTICK` |
| the powergen factor | ×2 | `powergenFactor` (default 2.0) |
| the loss chance | 5 in 1,000 (0.6 %) | `chanceLost` (`nextInt(1000) <= 5`) |
| the hit table | 0…12,800 by mode | `EndergenicTileEntity.rfPerHit` |
| the window | modes 1…15 | `chargingMode >= 16` → idle |
| the age bonus | +5 % an age, capped +100 % | `age * 5`, `a > 100` → 100 |
| a link's flight | `(int)(d/3)+1` ticks, ≤ 4 | `calculateDistance`, `distance >= 5` refused |
| the injector's buffer | 18 pearls | `PearlInjectorTileEntity.BUFFER_SIZE` (9×2) |
| endergenic hardness | 2.0 / 2.0, pickaxe, iron sound | the block's own `Properties` / STANDARD_IRON |
| endergenic recipe | diamond, obsidian-tag, infused pearl, machine frame (`"dod"/"ZFZ"/"dod"`) | `EndergenicModule.initDatagen` |
| pearl injector recipe | chest tag / redstone / machine frame / hopper (`" C "/"rFr"/" H "`) | `EndergenicModule.initDatagen` |

### Red → green

The generator's and the injector's rules were stubbed `todo!()` behind their tests; the failing run
is `ports/_shared/evidence/rftoolspower/red-endergenic.log`:

```
test result: FAILED. 50 passed; 14 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
not yet implemented: Endergenic::gain is not written yet
not yet implemented: chance_roll is not written yet
```

Green: **74 passed; 0 failed** (`sdk-test.log`, which prints the package sha). The fourteen tests
pin: the hit table and the window's edges; a mode-5 arrival paying 1,600 and starting the hold; the
age bonus's cap at a doubling; an idle and a holding arrival paying nothing; the fifteen charging
modes; rising-edge-only pulses; the 500-a-tick hold and an empty buffer dropping the pearl; the
flight time and its arrival; a fired pearl with no destination; the held-versus-injected age; the
loss chance (6 in 1,000, deterministic); the 5,000,000 clamp and the 2,000 reserve; a doctored save
read back clamped; and one whole pulse → charge → hit → hold cycle.

### In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

Built with the launcher at the pin: `native-build` reported `Compiling rftoolspower (1 of 1)` and
installed `native-0a875da-88daa563f37b`; the two-mod e2e build is `native-0a875da-26adda5b2fc9`
(`rfpowerharness`, `rftoolspower`), and its `native-mods.json` names version **0.1.3**.

| log | verdict |
|---|---|
| `e2e-endergenic.log` | **PASS**, `EXIT:0` — phases A–AM (the whole port) |
| `e2e-endergenic-selftest.log` | `FAIL: selftest: the pearl paid 200 FE at mode 1, so the assertion is alive`, `EXIT:1` |
| `e2e-endergenic-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=11 ok=11 missing-exit=0 bad-exit=0`.

The parsed assertions, each from a `ctl` reply:

| phase | what it asserts (observed) |
|---|---|
| AE | an injector placed from its item at `303,101,94` reads `pearls=0 generator=302,101,94`, faces `east`; the source's link reads `dest=302,101,97 distance=2`; both generators are `0/5000000` and idle |
| AF | a pearl clicked into the injector (`pearls=1`, hand empty) and fired by one `fill` that pulses the injector and the destination **on the same tick**: the source reads `fired=1`, the destination `arrived=1 gained=200` = `rfPerHit[1] × 2`, `energy == gained − spent`; the monitor beside it reads `stored=200 max=5000000 level=1` |
| AG | the same shot with the destination left idle: `energy=0 gained=0 dropped=1 arrived=-2 reason="Pearl arrived while idle"` — the differential for AF, and `SELFTEST_ENDER=1` inverts AF and fails |
| AH | a generator with no injector: the pulse leaves `charging=5` (inside 1…15), 30 ticks later `charging=0`, `energy=0`, `fired=0` |
| AI | a doctored 100,000 FE generator beside the harness receiver ends at **2,000 FE** with the receiver at **98,000** — the push and the `endergenicKeepRf` reserve |
| AJ | a survival break of a 3,000 FE generator drops one whose `SelectedItem` carries `block_entity_data {id: "rftoolspower:endergenic_block_entity", energy: 3000}`; placing it restores `3000 FE` and **no link** |
| AK | the endergenic's and the injector's carried recipes with a stone where the parent's items belong craft nothing |
| AL | `/rftoolspower enderlink` refusals are parsed replies: "destination … is not an endergenic generator", "distance 5 is too far (maximum 4)", "No RFTools Power endergenic generator there." |
| AM | after save + quit + relaunch: the destination still holds `200 FE` with `arrived=1`, and the source still links to it |

Counterfactual: `SELFTEST_ENDER=1` asserts AF's `gained == 0` and the leg fails as designed, so AF
can fail; AG is AF's differential (the same shot outside the window pays nothing) and AH is the
"no injector at all" case. The control leg proves AE is not vacuous.

### Engines traps this slice cost (measured, not read)

1. **`ctl look-at-block … up` cannot see a face above the eye.** Aiming at a block's top face from
   the floor answers *"no face of block … is visible from here"*, and the placement then refuses
   with *"no visible face to place … against; it needs a solid neighbour in reach"*. The injector
   therefore stands **beside** its generator on the floor (where `place_held`'s floor-level
   placement works) and its front is pinned to the side the generator is not on.
2. **The placement's yaw is the game's, not the player's** (the monitor's trap again): the injector
   placed with `state_for_placement` running reported `facing=east` in this run, but the leg pins
   the state anyway, so a change in the placement context cannot silently repoint the injector.
3. **One `fill` is the only atomic multi-block pulse.** Two `setblock`s land on different ticks, so
   the destination and the injector must be pulsed by **one** fill (through their top faces) or the
   arrival mode drifts with the command latency.
4. **A generator whose store cannot pay the 500-a-tick hold drops the pearl on the next tick**, so
   a 200 FE hit ends at `charging=0 dropped=1 reason="Not enough energy to hold pearl"` — the leg
   reads `arrived`/`gained` for the payment, not the hold.
5. **The drop reason is saved state here.** Upstream keeps `lastPearlsLostReason` as a live field;
   this port prints the readout from the saved compound, so the reason is written with the rest of
   the state (otherwise a reply a tick later says `none`).

### Upstream defects fixed (slice 4)

None adopted. Three *documented* deviations:

- **The loss chance is a position-and-tick hash** (splitmix64, `chance_roll`) instead of
  `java.util.Random`: the same 6-in-1,000 rate, but reproducible, so a lost pearl in a run can be
  replayed instead of appearing once.
- **The statistics window is not ported**: upstream averages `rfGained`/`rfLost` over 100 ticks for
  its HUD; this port prints the totals since placement and the last arrival mode, which is the same
  data without the average.
- **The injector has no per-slot item filter** (a `ModContainer` declaration has no slot predicate
  at this pin): automation can insert any item into its 18 slots, but the injector only ever
  consumes ender pearls (upstream refuses non-pearls at the face). A hand click refuses them with a
  line.
- Also not expressible: upstream's `getFacingFromEntity` vertical branches (placer above → UP,
  block above the eye → DOWN) — the placement event carries the view angles, not the placer's
  height, so the injector's front is horizontal; the `findEndergenicTileEntity` UP fallback still
  works for a generator above it.

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
9. ~~**The powercell (`cell1/2/3`)**~~ — **ported in slice 3 for `cell1` and `cell2`** (the block,
   the buffer, the six face modes, the adjacency network and the output push; the wrench's mode
   toggle is the `/rftoolspower side` command, which needs no carrier). Still open: **`cell3`**
   (20,000,000 FE, 4,000 FE a side — the same code with a third content block and recipe), the
   **smart-wrench item** itself (`rftoolsbase:smartwrench`, `ports/rftoolsbase` gap 12), the
   **powercell GUI** and the **powercell card**'s dimensional-cell linking.
10. ~~**The endergenic generator with the pearl injector**~~ — **ported in slice 4** (the charge
    window, the hit table, the flight, the hold, the link, the push with its 2,000 FE reserve, and
    the injector's 18-slot buffer; the wrench's link is the `/rftoolspower enderlink` command).
    Still open in this family: the **ender monitor** (`EnderMonitorTileEntity`: three modes —
    `MODE_LOSTPEARL`/`MODE_PEARLFIRED`/`MODE_PEARLARRIVED` — where `fireFromEndergenic` sets
    `needpulse` when the mode it watches just happened and the tick puts **15** on its redstone
    output for that one tick, plus the `fireMonitors` notice the generator owes its neighbours), the
    **endergenic GUI** (`GuiEndergenic`: the stats list, the destination display) and its
    **renderer** (the floating pearl, the good/bad flash), the **infusable factors** in the hold and
    the gain (no upgrade slot in this port), and the **5-second statistics window** the HUD averages.
11. **The rest of the mod:** the **power level** display (`PowerLevelTileEntity`, the monitor's
    sibling — same tick, but a 0..9 ratio written straight to the redstone output and no level
    state), the dimensional cell (with its card-linked networks), and the blazing
    generator/agitator/infuser with blazing rods. The power monitor is ported in slice 2 and the
    endergenic pair in slice 4.

## Coverage of the endergenic family (slice 4)

| family | state |
|---|---|
| `endergenic` and `pearl_injector`: block, item, blockstates (the injector's six `facing` variants), models, textures, tags, creative tab, lang | tested (AE: the injector placed from its item and read back facing east; the two generators placed, drawn from the tab) |
| the charge: a rising edge starts mode 1, fifteen modes, idle again | tested (AH: `charging=5` right after a pulse, `0` thirty ticks later; unit test pins 1…15) |
| the hit table: `rfPerHit[mode] × 2` (plus the age bonus) | tested (AF: the arrival mode is read from the reply and `gained` must equal `rfPerHit[mode] × 2` — 200 at mode 1; unit tests pin the table and the age cap) |
| the miss: a pearl arriving at idle is lost and pays nothing | tested (AG: `energy=0 gained=0 dropped=1 arrived=-2 reason="Pearl arrived while idle"`; `SELFTEST_ENDER=1` inverts AF) |
| the hold: 500 FE a tick, dropped when the store cannot pay | tested (AF: `energy == gained − spent`, `spent` a multiple of 500; unit test pins the drop) |
| the flight: `(int)(d/3)+1` ticks, the link's 5-tick refusal | tested (AE: a three-block link is 2 ticks; AL: a twelve-block link is refused) |
| the push: 20,000 a tick, keeping the 2,000 FE reserve | tested (AI: 100,000 FE seeded, the generator ends at exactly 2,000 and the receiver at 98,000; the 20,000 cap is a unit test because the harness receiver takes 10,000 an insert) |
| the buffer through the energy capability | tested (AF: a monitor facing the generator reads `stored=200 max=5000000`) |
| the injector: 18 pearls, a rising edge injects one | tested (AF/AG: `pearls=1` before the pulse, `0` after; the hand gave its pearl; unit test pins the container) |
| a generator with no injector makes no FE | tested (AH) |
| the store on the broken generator's item, and the clamp | tested (AJ: 3,000 carried and restored; the clamp is a unit test) |
| persistence of the store, the arrival mode and the link | tested (AM: save + quit + relaunch) |
| the `endergenic`, `injector` and `enderlink` commands and their refusals | tested (AE–AM every line parsed by `tools/parse_ender.py`/`parse_injector.py`; AL the three refusals) |
| the two recipes | `blocked(rftoolsbase:machine_frame-absent)`: the endergenic's also needs `rftoolsbase:infused_enderpearl` and an empty `#c:ender_pearls`, the injector's an empty `#c:chests` — AK proves both patterns craft nothing here |
| the ender monitor, its three modes and the `fireMonitors` notice | not ported (gap 10, phase 2 of this family) |
| the endergenic GUI, the stats window and the renderer (the floating pearl, the good/bad flash) | not ported (gap 10; no GUI and no renderer in a `machines` slice) |
| the infusable factors on the hold and the gain | not ported (gap 3) |
| the comparator output and TOP/Jade | not ported (gap 6) |

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

## Coverage of the powercell family (slice 3)

| family | state |
|---|---|
| `cell1`/`cell2`: block, item, plain-cube model, animated texture, tags, creative tab, lang | tested (U: placed, read the six faces and the store back; Y: a cell2 placed) |
| the 500,000 / 4,000,000 FE buffer, per tier, through the network | tested (U, X, Y; unit tests pin all three tiers) |
| the six face modes, all `NONE` on a fresh cell | tested (U: `sides=none,×6`; V: a `NONE` face refuses 100,000 FE over 40 ticks) |
| INPUT: exactly 250 a tick for a lone tier-1 cell, 312 for a pair | tested (W: `ΔE == 250 × Δt` on both stores; unit tests pin 250 and 312) |
| OUTPUT: 250 a tick out of one face, from the network's store | tested (Z: `−7,250` over 29 ticks; at rest the two stores still add to 100,000) |
| the adjacency network: shared store and capacity, adjacent cells only | tested (X: 3,000/1,000,000 in both, a gap is alone; Y: cell1+cell2 = 5,000/4,500,000) |
| a mixed-tier network (the artefact's behaviour, not the brief's) | tested (Y; the correction is documented above) |
| the network's 729-cell limit | not in game (a 729-cell build is not worth the leg); unit test `a_network_past_upstreams_limit_takes_nothing` |
| the store on the broken cell's item, and the per-tier clamp | tested (AB: 3,000 carried and restored; the clamp is a unit test) |
| persistence of the store and the face modes | tested (AA) |
| the `side` command and its refusals | tested (W, Y, Z, AA, AD) |
| the `cell` readout | tested (U–AB, every line parsed by `tools/parse_cell.py`) |
| `cell1`'s recipe | `blocked(rftoolsbase:machine_frame-absent)` (AC proves the pattern crafts nothing) |
| the power core's recipe | tested (AC: crafts once, consumes its diamond, redstone block and three redstones) |
| `cell2`'s recipe | not ported: McJtyLib's `copy_components` wrapper needs `power_core2`, whose recipe needs `rftoolsbase:dimensional_shard` (the parent) — it could never craft here, so it is not carried |
| the smart wrench, the GUI, the powercell card, `cell3` | not ported (gap 9) |
| the connected-cell `upper`/`lower` models and the animated glow | not ported (the documented simplification) |

Skills: superpowers/using-superpowers, brainstorming, writing-plans, test-driven-development, systematic-debugging, verification-before-completion; BeautifulRust/rust-best-practices

## Verification (slice 4 run)

| command | result |
|---|---|
| `cargo test --offline` | **74 passed; 0 failed** (`../_shared/evidence/rftoolspower/sdk-test.log`, prints the package sha) |
| `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings** (`sdk-clippy.log`) |
| `cargo fmt --check` | clean (`sdk-fmt.log`) |
| two `cargo horizon-mod build` with `rm -f Cargo.lock` | `cmp`-identical, 122,516 B (`sdk-build-1.log`, `sdk-build-2.log`) |
| `cargo horizon-mod check` | exit 0, `0.1.3 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)` (`sdk-check.log`) |
| `cargo horizon-mod fits --build 0a875da` / `--build 0b14f8a` | `made for` / `fits` (`sdk-fits.log`) |
| `verify-sdk-package.py rftoolspower` | **1/1** |
| the leg | `PASS` + `EXIT:0`; `SELFTEST_ENDER=1` `EXIT:1`; control `EXIT:1`; `--strict` 11/11 |

## Artifact (0.1.3)

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `rftoolspower.hmod` (port root) | 122,516 B | `ab452bd8913d68820359293365a983d30d8c47bfa729bb2053c1039276c45af0` | 87 |

Built twice with `rm -f Cargo.lock` before each (`cmp` identical), **no packed `Cargo.lock`**,
`check` green, both `fits` green, `verify-sdk-package.py` 1/1, `src/runtime.rs` byte-identical in
the archive. The 0.1.2 artifact (100,317 B, `989543d7…`, 69 entries) is the slice-3 record; its
gates are kept as `sdk-*-0.1.1.log` beside this run's.
