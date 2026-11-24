# RFTools Power — port notes (slice 1: the coal generator; slice 2: the power monitor; slice 3: the
# powercell; slice 4: the endergenic generator and the pearl injector; slice 5: the ender monitor;
# slice 6: the power level; slice 7: the blazing generator and rod; slice 8: the blazing agitator;
# slice 9: the blazing infuser; slice 10: `cell3`)

> **Current state (2026-11-24): slice 10, package 0.1.9 at pin
> `0a875da91dbb0fdcb7ba8c42c11341aa229af51a` / mixins `e59da909…`.** Slice 1 (0.1.0) is the coal
> generator; slice 2 (0.1.1) adds the **Power Monitor** and the generator's **energy push**
> (`handleSendingEnergy`); slice 3 adds the **powercell** (`cell1`/`cell2`): a per-tier block
> entity with a 500,000 / 4,000,000 FE buffer, six face modes that default to `NONE`, an adjacency
> **network** that shares one store and capacity across cells of any tier, and the output push out
> of an `OUTPUT` face — slice 10 adds the third tier, `cell3` (20,000,000 FE, 4,000 a side, 5,000 in
> a pair); slice 4 adds the mod's signature mechanic, the **endergenic generator** with
> its **pearl injector**: two linked generators, a redstone pulse that starts a 15-mode charge and
> one that fires the held pearl, and the `rfPerHit` table that pays 200…25,600 FE for a pearl that
> lands inside the window (and nothing for one that lands outside it); slice 5 adds the **ender
> monitor**, the block that watches one of the generator's three events (lost / fired / arrived)
> and answers it with **15 on its display face for exactly one tick**; slice 6 adds the **power
> level** display, the monitor's sibling: a 0..9 ratio (`stored * 10 / capacity`) read 20 ticks
> after placement and then every 10, written straight to its display face's redstone output; and
> slice 7 adds the **blazing generator** with its **blazing rod**: four rod slots whose rates each
> climb a 150th of the gap to their own ceiling (60 FE a tick for a 60,000-quality rod) over a
> 1,000,000 FE buffer with a 20,000 FE a tick push, the rod's whole state kept in the mod's own
> `rftoolspower:blazing_rod_data` item component; and slice 8 adds the **blazing agitator**: a 3×3
> box of rods whose quality and duration climb by the square of a factor built from the
> **neighbouring** rods, whose agitation clock runs down, and whose finished rods move to one of
> nine output slots unless their slot is **locked** — over a 50,000 FE buffer that takes 100 FE a
> tick and spends 10; and slice 9 adds the **blazing infuser**: three slots (rod in, rod out, one
> catalyst), a run on the **11th tick and then every 11**, 10 FE and one catalyst a run, and the
> catalyst's percentage of a whole 64-step stack onto the rod's quality and duration. Where
> upstream's smart wrench is needed (the link, the cell's face modes), the harness uses commands —
> `/rftoolspower enderlink`, `/rftoolspower side` — and never a fake item; the monitor's GUI picker
> is `/rftoolspower endermonitor <pos> <mode|status> [nonce]`, and the power level's readout is
> `/rftoolspower powerlevel <pos> [nonce]`; the agitator's readout is
> `/rftoolspower agitator <pos> [nonce]` and its lock checkbox is
> `/rftoolspower agitatelock <pos> <slot> on|off [nonce]`; the infuser's readout is
> `/rftoolspower infuser <pos> [nonce]`.
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
energy push (N–T), the powercell (U–AD), the endergenic pair (AE–AM), the ender monitor (AN–AS),
the power level display (AT–AW), the blazing generator with its blazing rod (AX–BE), the blazing
agitator (BF–BN) and the blazing infuser (BO–BS) are implemented and verified in game at the
current pin. The gap list below is the rest of the mod.

## What the powercell binds to (the 2026-11-21 parent-surface ruling)

- The parent surface is again just **`rftoolsbase:machine_frame`** (cell1's recipe centre) and the
  carried `power_core1`. No parent capability, machine or recipe type is used.
- The **smart wrench is not carried** (gap 9's original blocker: `PowerCellBlock.wrenchUse` toggles
  a face's mode). The stand-in is a **command**, not a fake item:
  `/rftoolspower side <pos> <face> NONE|INPUT|OUTPUT`. A fresh cell is six `NONE`s in both cases —
  upstream's own default — so the command reproduces the wrench's state machine, not a behaviour
  the mod does not have.
- `cell2` is carried because the network's tier behaviour needs a second capacity to be observable;
  `cell3` was added in slice 10 for the same reason (its own numbers, not a copy of the other tiers').

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

## Slice 5 — the ender monitor (package 0.1.4)

Gap line it comes from (`## Gaps` below): **gap 10** — *"Still open in this family: the **ender
monitor** (`EnderMonitorTileEntity`: three modes …)`"*, phase 2 of the endergenic family, together
with the `fireMonitors` notice the generator left as a no-op. Tier: still **machines** — one block
entity with a server tick, saved state, a block state mirror and a redstone output. No GUI, no
renderer, no item carrier.

### What it does (upstream `EnderMonitorTileEntity`, `EnderMonitorMode`, `EnderMonitorData`,
`EndergenicTileEntity.fireMonitors`, 1.21-7.0.6)

- **The block.** `rftoolspower:ender_monitor` on the iron base template: a thin plate (4/16) whose
  `facing` is the **display** side (upstream's `logic_facing`), plus a boolean `lit` the port
  mirrors the one-tick output into (upstream has no such state; slice 2's monitor mirrors its alarm
  the same way). The generator it watches is behind the display, as upstream's `getInputSide()`.
- **The mode.** Three values, saved under upstream's own serialised names: `MODE_LOSTPEARL`
  (default, the attachment's initialiser), `MODE_PEARLFIRED`, `MODE_PEARLARRIVED`. The GUI's picker
  is the harness stand-in `/rftoolspower endermonitor <pos> <mode> <nonce>`.
- **`needPulse`.** The generator's `fireFromEndergenic(mode)` sets it only when the mode the monitor
  watches just happened; the monitor's next tick spends it as **15** on its redstone output for
  exactly that tick, then 0 — the *one* tick this slice is about. Two notices before a tick still
  make one pulse; a monitor watching another mode is never armed.
- **`fireMonitors`.** After each event the generator walks its six neighbours and arms the monitor
  at `pos + dir` whose display faces `dir` (upstream's `inputSide == dir.getOpposite()`). The three
  events: a discarded pearl (`lost`), a real launch from a pulse or the injector (`fired`), and a
  landing (`arrived` — fired **before** the landing branch, so a pearl that lands while idle pulses
  both `arrived` and `lost`, upstream's order).
- **The signal's face.** Upstream answers `getRedstoneOutput` on the input side while
  `setRedstoneState` notifies the opposite one; this port follows the notify side (the display face)
  for both, the same fix slice 2 recorded for the power monitor. A lamp on the display face lights
  on the pulse's tick and is dark again on the next.
- **The item.** A broken monitor's own item carries its **mode** (`minecraft:block_entity_data`
  naming `rftoolspower:ender_monitor_block_entity`), which placing restores — upstream keeps the
  mode on the block's item. A default (`lost`) monitor carries nothing; the readout's pulse/last
  counters are this port's and stay on the block.
- **The readout.** `/rftoolspower endermonitor <pos> status <nonce>` prints
  `mode/facing/pulses/last/needpulse/out/t` in one line; a mode word in place of `status` sets the
  mode and answers the same line. Both are the harness's stand-ins for the GUI, and the nonce is
  what makes a reply provably fresh.

### Numbers and where they came from

| Number | Value | Source |
|---|---:|---|
| the one-tick signal | 15 | `support.setRedstoneState(this, 15)` in `tickOnServer` |
| the modes | 3, default `MODE_LOSTPEARL` | `EnderMonitorMode`, `AttachmentType.builder(() -> new EnderMonitorData(MODE_LOSTPEARL))` |
| the saved keys | `mode`, `needPulse` | `EnderMonitorData`'s fields |
| the plate | 4/16 on the side away from the display | upstream's `VoxelShape` box |
| monitor hardness | 2.0 / 2.0, pickaxe, iron sound | `EndergenicModule`'s monitor block (`STANDARD_IRON`) |
| monitor recipe | ender pearl / redstone / redstone torch / machine base (`" o "/"rAr"/"TrT"`) | `EndergenicModule.initDatagen` |

### Red → green

The monitor's rules were stubbed `todo!()` behind their tests; the failing run is
`ports/_shared/evidence/rftoolspower/red-endermonitor.log`:

```
test result: FAILED. 74 passed; 7 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
not yet implemented
```

Green: **87 passed; 0 failed** (`sdk-test.log`, which prints the package sha). The seven tests pin:
a fresh monitor's default mode and empty counters; the command words versus the saved names; the
mode gate (a notice for another mode arms nothing); the pulse as 15 for exactly one tick; two
notices before a tick as one pulse; a monitor watching another mode never pulsing; and a doctored
save (an owed pulse keeps its `last`, a phantom one is dropped). Two more in `support`: the saved
compound round-trip and its clamp, and the mode on the broken item's payload. The mode-on-item test
also pins that the readout's counters do **not** travel.

### In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

Built with the launcher at the pin: `native-build` reported `Compiling rftoolspower (1 of 1)` and
installed `native-0a875da-574eb87eae42`; the two-mod e2e build is
`native-0a875da-aa42b6d48852` (`rfpowerharness`, `rftoolspower`), and its `native-mods.json` names
version **0.1.4**.

| log | verdict |
|---|---|
| `e2e-endermonitor.log` | **PASS**, `EXIT:0` — phases A–AS (the whole port) |
| `e2e-endermonitor-selftest.log` | `FAIL: selftest: the monitor lit for 1 sample(s), so the one-tick assertion is alive`, `EXIT:1` |
| `e2e-endermonitor-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=14 ok=14 missing-exit=0 bad-exit=0`.

The parsed assertions, each from a `ctl` reply:

| phase | what it asserts (observed) |
|---|---|
| AN | three monitors placed from their items on the generators' sides: a bare item reads the default `lost`; an item carrying `mode=MODE_PEARLFIRED` reads `fired` with no command; the command sets `arrived` on B's east monitor and on the mis-facing one. Breaking the `fired` monitor in survival drops an item whose `SelectedItem` carries `id: rftoolspower:ender_monitor_block_entity, mode: "MODE_PEARLFIRED"`; re-placing it reads `fired` with 0 pulses |
| AO | one pearl fired across the link: the 16 consecutive server ticks sampled while the game is frozen read `'0010000000000000'` — the display face's `lit` state true in **exactly one** tick and false before and after; the same window on the lamp beside it reads `'001111…'` (vanilla's 4-tick lamp) and goes dark; the source's `fired` monitor pulsed with it, the mis-facing one stayed at 0; the destination gained 200 FE |
| AP | the differential: the same shot with that monitor's mode set to `lost` samples `'0000000000000000'` (0 of 16 lit) while the shot still lands; the source's `fired` monitor recorded the extra shot. A random discard (upstream's 0.6 % a tick) can pulse a `lost` monitor, so an attempt where the drop reason names it is retried, and the transcript says which event the counter names |
| AQ | a pearl that lands while the destination is idle: the generator records `dropped=1 reason="Pearl arrived while idle"`, the `arrived` monitor goes 3 → 4 (upstream notifies before the miss) and the `lost` monitor gives its 1, the mis-facing one stays 0 |
| AR | the refusals are parsed replies: no monitor at a stone position, and `unknown mode 'wrong' (lost\|fired\|arrived\|status)`; the refused mode changes nothing |
| AS | the monitor's carried recipe with a stone where `rftoolsbase:machine_base` belongs crafts nothing |
| AM | after save + quit + relaunch the arrived monitor still watches `arrived` with its 4 pulses, the lost one `lost` with 1 |

Counterfactual: `SELFTEST_ENDERMON=1` asserts the monitor never lit and the leg fails as designed, so
AO's one-tick assertion can fail; AP is AO's differential (the same shot with another mode), and the
control leg proves A is not vacuous.

### Engines traps this slice cost (measured, not read)

1. **A re-placed picked-up block keeps the *game's* placement yaw, not the harness's.**
   `place_held` put the broken monitor back facing east, so it watched the wrong side and never
   pulsed; the leg re-places it through `place_endermonitor`, which pins the display face after the
   placement (the same trap as the first placement, now proven for a picked-up item too).
2. **A reply that arrives a few ticks late is the previous call's line, and a timestamp is not a
   nonce.** The first version compared the reply's `t` with the last accepted one, which accepted an
   older command's pending reply (a `pulses=2` read where the truth was 3: the real reply at
   `t=6625` arrived after the read had already accepted a pending `t=6533`). The command now takes
   the harness's nonce (`status <nonce>`, or a mode plus the nonce) and every read awaits its own
   nonce exactly as the other readouts do.
3. **The random discard can legitimately pulse the differential's monitor.** A landed pearl is held
   and upstream's 0.6 %-a-tick discard fires `lost`; a `lost` monitor therefore may pulse after the
   arrival. The differential treats that attempt as inconclusive (named by the drop reason, retried
   up to three times) and the counter check distinguishes `last=arrived` (no event) from
   `last=lost` (the discard), so the arrival itself can never be mistaken for either.
4. **`tick step 1` sampling is exact, but the `state` reply's `ticks` is the client's clock.** The
   frozen window steps the server once per sample; the sample labels advance ~2 per step because the
   client keeps running, so they are a cross-check, not the cadence.

### Upstream defects fixed (slice 5)

**The signal's face.** The same disagreement slice 2 fixed on the power monitor:
`EnderMonitorTileEntity.getRedstoneOutput` answers on the input side (the generator's side) while
`LogicSupport.setRedstoneState` notifies `getInputSide().getOpposite()` (the display side). The port
answers and notifies on the display face, so a lamp beside the monitor lights. A user notices: the
monitor's one-tick pulse reaches a lamp or wire on its free face.

Three *documented* deviations (not defects):

- **No GUI.** The mode picker is `/rftoolspower endermonitor <pos> <mode> <nonce>`; a click prints
  the status line.
- **The item carries the mode only.** Upstream's mode rides on the block's item; the readout's
  `pulses`/`last` counters are this port's addition, so they stay on the block and a placed item
  starts at 0.
- **The `status` action and the nonce** are harness-only command words (upstream has no command at
  all); they exist so a one-tick state can be sampled and read back safely.

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

## Slice 6 — the power level display (package 0.1.5)

Gap line it comes from (`## Gaps` below): **gap 11** — *"the **power level** display
(`PowerLevelTileEntity`, the monitor's sibling — same tick, but a 0..9 ratio written straight to
the redstone output and no level state)"*. Tier: still **machines** — one block entity with a
server tick, a block-state mirror and a redstone output. No GUI, no renderer, no item carrier.

### What it does (upstream `PowerLevelTileEntity`, 1.21-7.0.6)

- **The block.** `rftoolspower:power_level` on the jar's own 4/16 plate model, a `facing` display
  side (four horizontals, the monitor/ender-monitor simplification) and the ratio's `power` state.
- **The read.** The first observation lands **20 ticks** after placement (upstream's `counter = 20`
  field); each later one **10 ticks** after the previous (`counter = 10`). The block read is the
  one behind the display front through the energy capability, asked with no side — the monitor's
  `read_target`/`energy_at`, reused.
- **The ratio.** `ratio = stored * 10 / capacity` in integer arithmetic, clamped to 0..=9. At
  **250,000 of 500,000 FE that is 5** (`2,500,000 / 500,000`), at 0 it is 0, and a full store's 10
  clamps to 9. A block with no energy capability (or no capacity) reads 0 — upstream's
  `setRedstoneState(this, 0)` branch.
- **The output.** The ratio on the **display face**, nothing elsewhere. Upstream answers
  `getRedstoneOutput` on the input side while `setRedstoneState` notifies the display side; the port
  follows the notify side, the same defect fix slice 2 recorded for the power monitor. A redstone
  wire on the display face reads the ratio; one on another face reads 0.
- **The mirror.** Upstream keeps the ratio in its tile entity and has no block state. The pin's
  `BlockPart::block_signal` gets only a state and must answer from it ("don't read or change the
  world here"), so the port mirrors the ratio into a `power` enum 0..9 — the output's carrier, as
  the monitor's `lit` carries its alarm. This is the slice's one *documented deviation*.
- **The item.** No component: upstream keeps nothing on the block's item, so a broken power level
  drops a plain item.
- **The readout.** `/rftoolspower powerlevel <pos> [nonce]` prints
  `power/facing/target/stored/max/t` in one line; the nonce proves a reply is fresh. It is the
  harness's stand-in for upstream's renderer/TOP readout, which this tier does not carry.

### Numbers and where they came from

| Number | Value | Source |
|---|---|---|
| the ratio | `stored * 10 / capacity`, 0..9 | `PowerLevelTileEntity.tickServer` |
| at 250,000/500,000 | **5** | the artefact's integer arithmetic (the brief assumed 4) |
| the first observation | 20 ticks after placement | `counter = 20` field |
| later observations | every 10 ticks | `counter = 10` reset |
| no energy block | 0 | `setRedstoneState(this, 0)` |
| the saved field | `power` (client data) + the counter | `saveClientDataToNBT`, this port's carrier |
| plate | 4/16 on the side away from the display | the jar's `power_level_0` model |
| block hardness | 2.0 / 2.0, pickaxe, iron sound | McJtyLib `BlockBuilder` default |
| recipe | glass panes / redstone / machine base / redstone block (`" P "/"rAr"/" R "`) | `MonitorModule.initDatagen` |

### Red → green

The power level's rules were stubbed `todo!()` behind their tests; the failing run is
`ports/_shared/evidence/rftoolspower/red-powerlevel.log`:

```
test result: FAILED. 87 passed; 4 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
not yet implemented
```

Green: **94 passed; 0 failed** (`sdk-test.log`, which prints the package sha). The four new runtime
tests pin the ratio (0→0, 250,000→**5**, 50,000→1, full→9, a doctored 900,000→9, `1/3`→3, capacity
0→0), the 20-then-10 cadence, "changed only when the ratio moved" (including the no-capability and
empty-store cases), and a doctored save's clamp. Three in `support`: the saved round-trip and its
clamp, the exact readout line, and the state decode (which rejects another block's state).

### In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

Built with the launcher at the pin: `native-build` reported `Compiling rftoolspower (1 of 1)` and
installed `native-0a875da-18641cfcb03e`; the two-mod e2e build is
`native-0a875da-cb0f41e1cb8b` (`rfpowerharness`, `rftoolspower`), and its `native-mods.json` names
version **0.1.5**. Both legs carry a `PACKAGE` line naming the delivered archive
(`26485b9a…`, 141,168 B).

| log | verdict |
|---|---|
| `e2e-powerlevel.log` | **PASS**, `EXIT:0` — phases A–AW (the whole port) |
| `e2e-powerlevel-selftest.log` | `FAIL: selftest: the power level reads 5 at 250,000/500,000, not the 4 the inversion expects, so the assertion is alive`, `EXIT:1` |
| `e2e-powerlevel-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=17 ok=17 missing-exit=0 bad-exit=0`.

The parsed assertions, each from a `ctl` reply and the wire's own `power` state:

| phase | what it asserts (observed) |
|---|---|
| AT | a power level facing a generator doctored to 250,000/500,000 FE reads `power=5 facing=east target=rftoolspower:coalgenerator stored=250000 max=500000`; the block state mirrors `power=5`; the **redstone wire on its display face reads `power=5`**; a wire on its north face reads `power=0` |
| AU | a fresh (0 FE) generator reads `power=0` and its display wire `power=0` — the differential for AT; `SELFTEST_POWERLEVEL=1` inverts AT and fails |
| AV | a full 500,000 FE store reads `power=9` on the readout and on the display wire (the ratio 10 clamps) |
| AW | `/rftoolspower powerlevel` at a stone position answers `No RFTools Power power level there.`; the carried recipe with a stone where `rftoolsbase:machine_base` belongs crafts nothing (its `#c:glass_panes` tag is unresolved at this pin too, so the recipe never loads) |

Counterfactual: `SELFTEST_POWERLEVEL=1` asserts the display wire reads the brief's **4** and the leg
fails as designed, so AT can fail; AU is AT's differential (no store, no signal) and the wrong-face
wire is the "the face matters" differential. The control leg proves AT is not vacuous.

### Engines traps this slice cost (measured, not read)

1. **The brief's 4 is not the artefact's 5.** `stored * 10 / capacity` at 250,000 of 500,000 is
   exactly 5; a `0..9` reading of a 0..1 fraction has several plausible roundings, and this port
   follows the reference's own integer arithmetic. The unit test and the leg pin **5**, and the
   selftest's deliberate 4 is the proof the assertion is alive.
2. **The wire's `power` is the assertion, not an absence of errors.** `ctl block` on the
   `minecraft:redstone_wire` beside the display face is a parsed integer, and the wire on the wrong
   face is the differential. The mirror state (`power=5`) is checked separately, so a green run
   cannot come from the property alone.
3. **`#c:glass_panes` does not exist at 26.3.** The power level's recipe logs an unresolved-tag
   error at load and can never match; the leg proves the pattern crafts nothing with the parent's
   `machine_base` replaced by stone (the same `blocked(rftoolsbase:machine_base-absent)` shape as
   the monitor and ender monitor).

### Upstream defects fixed (slice 6)

**The signal's face.** The same disagreement slice 2 fixed on the power monitor:
`PowerLevelTileEntity.getRedstoneOutput` (through `LogicSupport`) answers on the input side (the
machine's side) while `setRedstoneState` notifies `getInputSide().getOpposite()` (the display
side). The port answers and notifies on the display face, so a wire beside the display reads the
ratio and a wire on the machine side reads 0. A user notices: the reading reaches the wire on the
free face.

One *documented* deviation (not a defect): **the `power` block state**. Upstream keeps the ratio
only in its tile entity; the pin's signal hook must answer from a state, so the ratio is mirrored
into a `power` enum 0..9. The state is the output's carrier, not an extra feature.

## Slice 7 — the blazing generator and the blazing rod (package 0.1.6)

Gap line it comes from (`## Gaps` below): **gap 11** — *"**The rest of the mod:** the dimensional
cell …, and the blazing generator/agitator/infuser with blazing rods, and the power level's
renderer"*. This slice takes **the blazing generator and the blazing rod**; the **agitator** and the
**infuser** mutate a rod rather than consume it and are left for the next slice (they need the
3×3 adjacency algorithm and the catalyst table, and neither changes what this slice proves). Tier:
still **machines** — a block entity with a server tick, a four-slot container, an energy buffer and
a block-state mirror. No GUI, no renderer, no item Part.

### The component gate (checked before the code, as the brief demanded)

The rod's whole mechanic is a **custom item component** (`rftoolspower:blazing_rod_data`), so the pin
has to register and read one. Confirmed in `ports/_shared/sdk/0a875da/`:

- `Hooks::component_types(&self, cx, event: &mut ComponentTypesEvent<'_>)`, `event.types:
  &mut Vec<String>` (`surface.json` `hook:component_types`); the game feeds those names to
  `horizon_protocol::item::custom::install` before content loads;
- `ItemStack::components() -> Option<&Components>` with `Components::as_nbt() -> &Compound`, and the
  typed route this port uses: `mod_api::Component` (`type Value; id; decode; encode`) with
  `ItemStack::get`/`set` — the shape `ports/ironjetpacks` ships;
- a `/give` carrying a mod component lands in the stack's patch (`ports/mekanismcovers` proves it in
  game; phase AX here reads it back from the delivered stack).

**Verdict: supported.** Phase AX is the in-game proof: the given rod's `ctl inventory` stack carries
`rftoolspower:blazing_rod_data` with `quality:60000`, and the generator consumes the same value
(`rftmax=60`).

### What it does (upstream `BlazingGeneratorTileEntity`, `BlazingRod`, `BlazingRodData`, 1.21-7.0.6)

- **The block.** `rftoolspower:blazing_generator` on McJtyLib's STANDARD_IRON with the jar's
  six-way `facing` and its own `working` boolean — the jar's own twelve-variant blockstate, idle
  front and animated busy front.
- **The rod.** `rftoolspower:blazing_rod`, a plain 64-stack item (not furnace fuel — upstream's rod
  is an `Item` with `new Item.Properties()`), whose state is the mod component
  `rftoolspower:blazing_rod_data` = `{steps, time, quality, duration}`, defaulting to
  `(64, 600, 60000, 20)` exactly as `getOrDefault(…, DEFAULT)` does.
- **The four slots.** One item each, rods only; a click fills the first empty slot. `updateSlot`'s
  ceiling is `(int)(quality / 1000)` (the infusable factor is gap 3, not carried) and the burn is
  `(int)duration` — a default rod is **60 FE a tick for 20 ticks**.
- **The ramp** (`handlePowerGeneration`): a slot below its ceiling climbs `rft += (max − rft)/150 +
  0.01` a tick, one above falls `(max − rft)/30`; both clamp. The `+0.01` is what carries the rate
  onto the ceiling instead of stalling below it (measured: from rest it clamps at exactly 60 on the
  **556th** tick).
- **The store and the burn.** `total += (int)rft` over the four slots, `produceEnergy(total)` into
  **1,000,000 FE**; while the machine runs every rod spends a tick, its remaining `duration` is
  written back onto the rod, and at 0 the slot is emptied and its ceiling zeroed. `working` mirrors
  `total > 0` into the block state.
- **The push** (`handleSendingEnergy`): up to **20,000 FE a tick** to every neighbour that answers
  the energy capability, with **no reserve**. The capability itself takes nothing in and gives
  nothing out (`extractEnergy` is 0 upstream too; the generator pushes).
- **The click.** Rods go in, anything else is refused with a line, and an empty hand reads the
  machine out — upstream opens its GUI there, so **no held item ever acts on the machine**.
- **The item.** A broken generator keeps its **store** (upstream's loot copies
  `mcjtylib:item_energy`), clamped to the buffer when placed again; its slots' rods do not travel
  (the engine keeps container items apart from the payload — gap 8's shape).
- **The readout.** `/rftoolspower blazing <pos> [nonce]` prints
  `energy/capacity`, `working`, the four `rft`, `rftmax`, `ticks`, the four slot contents and `t`.

### Numbers and where they came from

| Number | Value | Source |
|---|---:|---|
| capacity | 1,000,000 FE | `BlazingConfiguration.GENERATOR_MAXENERGY` (`blazingGeneratorMaxPower`) |
| a neighbour's push | 20,000 FE a tick | `GENERATOR_SENDPERTICK` (`blazingGeneratorSendPerTick`) |
| slots | 4, one item each | `BlazingGeneratorTileEntity.BUFFER_SIZE`, `slotLimit(1)` |
| a rod's ceiling | `(int)(quality / 1000)` = 60 | `BlazingRod.getRfPerTick` |
| a rod's burn | `(int)duration` | `BlazingRod.getTotalTicks` |
| the climb | `(max − rft)/150 + 0.01` a tick | `handlePowerGeneration` |
| the fall | `(max − rft)/30` a tick | the same |
| the clamp | at 60 on tick 556 from rest | the rule, folded in single precision and confirmed in game |
| a rod's defaults | `steps 64, time 600, quality 60,000, duration 20` | `BlazingRodData.DEFAULT`, `MAXTIME`, `START_QUALITY`, `START_DURATION`, `MAX_INFUSION_STEPS` |
| block hardness | 2.0 / 2.0, pickaxe, iron sound | McJtyLib `BlockBuilder` (`BlazingGeneratorTileEntity.createBlock`) |
| the recipe | `"XYX"/"RFR"/"XYX"` — `#c:rods/blaze`, infused diamond, redstone blocks, machine frame | `BlazingModule.initDatagen` |

### Red → green

The generator's and the rod's rules were stubbed `todo!()` behind their tests; the failing run is
`ports/_shared/evidence/rftoolspower/red-blazing.log`:

```
test result: FAILED. 94 passed; 10 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
not yet implemented: Blazing::load is not written yet
not yet implemented: Rod::rf_per_tick is not written yet
```

Green: **113 passed; 0 failed** (`sdk-test.log`). The ten new runtime tests pin: a default rod's
60 RF a tick over 20 ticks (and the truncating `(int)` cast); a slot's ceiling and burn from its
rod; the ramp's first step (`0.41` from rest) and its monotone 1/150th curve; the ramp reaching
**exactly** 60 and never passing it; the fall being a 30th of the gap (60 → 58 in one tick, and
~120 ticks to nothing); a spent rod clearing its slot at its own duration while the rate decays; four
rods adding four rates (240 a tick); the 1,000,000 clamp; a disabled tick spending no rod; and a
neighbour being offered 20,000. Three more pin the slot bookkeeping the hopper needs
(`reconcile`: a rod that never saw `updateSlot` gets its ceiling, an emptied slot loses it, and a
burning rod is not reloaded every tick). Four in `support`: the container and the buffer
declarations, the component's round trip (with ints, floats, a partial compound and a non-compound),
the saved state's clamp, the exact readout line, and the command's registration.

### In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

Built with the launcher at the pin: `native-build` reported `Compiling rftoolspower (1 of 1)` and the
two-mod e2e build is `native-0a875da-13096f5f5ed1` (`rfpowerharness`, `rftoolspower`), whose
`native-mods.json` names version **0.1.6**.

| log | verdict |
|---|---|
| `e2e-blazing.log` | **PASS**, `EXIT:0` — phases A–BE (the whole port), `PACKAGE … sha256=7fe0e237… bytes=162363` |
| `e2e-blazing-selftest.log` | `FAIL: selftest: the blazing generator made 2880 FE in 48 ticks, so the assertion is alive`, `EXIT:1` |
| `e2e-blazing-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=20 ok=20 missing-exit=0 bad-exit=0`.

The parsed assertions, each from a `ctl` reply:

| phase | what it asserts (observed) |
|---|---|
| AX | a fresh blazing generator reads `0/1000000 FE (working false, rft=0×4, rftmax=0×4, ticks=0×4, rods=empty×4)`; a rod given as `[rftoolspower:blazing_rod_data={…quality:60000,duration:400}]` keeps the component (`ctl inventory` reads it back), and the click puts it in slot 0 with `rftmax=60` and ~390 of its 400 ticks, the hand empty and `working` true |
| AY | two replies 25+ ticks apart: `rft 6.976305 at t=7430 → 17.187056 at t=7461`, and the single-precision fold of `rft += (60 − rft)/150 + 0.01` over those 31 ticks is `17.187067` — a delta of **0.000011** |
| AZ | a 5,000-tick rod climbs to `rft=60.000000` (first at t+556) and then `Δenergy == 60 × Δt` on the game clock: 25,749 → 28,629 FE over **48** ticks (+2,880) |
| BA | the 400-tick rod leaves its slot at its 400th tick: `rods[0]=empty`, `ticks=0`, `rftmax=0`, the rate still decaying (`0.000878 → 0.000328` in 20 ticks); `working` then falls and the store holds for 25 ticks |
| BB | a generator doctored to 999,995 FE reads 999,995, and with a rod burning reads exactly **1,000,000** — twice — while `working` stays true |
| BC | a generator doctored to 100,000 FE beside the harness receiver ends at **0** with the receiver at **100,000** (no reserve) |
| BD | after save + quit + relaunch: the store still 57,009 FE, slot 0 still the rod, `rftmax=60`, `rft=60.000000` |
| BE | a click with a stone: every rod slot empty, the **server's** inventory still holds the stone (`data get entity @s Inventory`), no block placed against the machine; `blazing` at a stone position answers `No RFTools Power blazing generator there.`; the carried recipe with a stone where the parent's items belong crafts nothing |

Counterfactual: `SELFTEST_BLAZING=1` asserts a rod at its ceiling makes no FE and the leg fails as
designed, so AZ can fail; AY is the ramp's own differential (a rule that is not the 1/150th curve
shows up as a large delta), BA is AZ's differential (no rod, no FE) and BC's differential is the
generator's own store. The control leg proves AX is not vacuous.

### Engines traps this slice cost (measured, not read)

1. **A `BlockPart::use_item_on` does not run for a click that carries a *block* item on an
   `iron_block`-template block.** Measured: a stone click on the coal generator (template
   `minecraft:furnace`, so its class chain has `useItemOn`) was refused and the stone stayed in
   hand; the same click on the pearl injector and on the blazing generator (both
   `minecraft:iron_block`) placed the stone on the machine's top face and consumed it. The blazing
   click is therefore owned by the **global** `Hooks::right_click_block` (API 21), which sees every
   click first: it takes the rod, refuses anything else and cancels with `Success`, so neither the
   block's own use nor the item's `useOn` runs — one owner per click, and the Part answers only
   `state_for_placement` so a rod cannot land in the next slot as well.
2. **A refused click leaves the client's own inventory view one stack short.** The client predicts
   the item's use (this pin's prediction does not consult a mod's hooks), the server cancels it, and
   the client's view is not resynced because the server's slots never changed: the client showed an
   empty hand while `data get entity @s Inventory` still held the stone at +10 and +70 ticks. BE
   judges the refusal by the **server's** inventory for that reason.
3. **A tp into this arena's band before its floor exists kills the player.** The new band (z 144…176)
   has no floor yet, and a `tp @s … 101` followed by a fill leaves the player below it; one run died
   there and the next `ctl place` answered *"the dead screen is open; close it first"*. The arena
   fills first, then puts the player down, then switches to survival.
4. **`build-e2e-game.sh` could export a build of *older* sources.** Its "Up to date" branch picked the
   newest version directory carrying both mods, which after two consecutive builds was the previous
   one (a diagnostic build was exported as if it were current). It now reads the build the launcher
   names (`native-… built and selected`), and replaces a build's hard-linked libraries with `ln -f`
   (`cp -a` refuses two names for one inode, which broke the export once).
5. **`sample_pulse`'s freeze/step window can miss the one tick.** AO's sixteen stepped samples saw no
   pulse in one run while the shot had landed (the destination recorded the arrival). The window is
   retried up to three times when the injector really fired, and the monitors' counters count every
   attempt — a window that cannot see the tick proves nothing, and the third miss still fails.

### Platform facts recorded (not port defects)

- **The rod's tooltip** (`power … RF/t`, `duration … ticks`, the agitation and infusion percentages)
  needs a tooltip hook and is a `client` nicety; this `machines` slice does not carry it (gap 11).
- **The client's prediction** of a refused block-item click (trap 2) shows a stale hand until the
  slot is touched; the server is authoritative and the machine never takes the item.
- **A one-item-per-slot click** is the only way in: the container declares all four slots as inputs,
  so a hopper feeds them like upstream's menu slots (the same `ModContainer` shape the fuel slot
  uses).

### Upstream defects fixed (slice 7)

None adopted: every rule is upstream's own. Two *documented deviations*:

- **No GUI.** Upstream's four slots are a menu; here a click fills the first free one, and the
  readout is `/rftoolspower blazing` (the same stand-in the other slices use).
- **The front is horizontal.** The placement hook can set `facing` from the placer's yaw only; the
  jar's `getFacingFromEntity` also answers UP/DOWN from the placer's height, which this pin's
  placement context does not carry (the pearl injector's recorded limit). The up/down variants of
  the jar's blockstate are still declared, so `setblock … [facing=up]` draws what the jar draws.

A carried **behavioural** consequence, not a defect: a 400-tick rod never reaches its 60 FE a tick
ceiling (the climb needs 556 ticks from rest) and `working` outlives the rod by the decay's ~120
ticks. Both are upstream's own numbers; the leg asserts them as measured rather than the brief's
assumption that either lands at the 400th tick.

### Coverage of the blazing family (slice 7)

| family | state |
|---|---|
| `blazing_generator`: block, item, the jar's twelve-state blockstate, the idle and busy front models, the two textures (the busy one animated), tags, creative tab, lang | tested (AX: placed from its item, front pinned, read back; BE: the block is refused a second entry) |
| `blazing_rod`: the item, its handheld model and animated texture, its `horizon/item` declaration | tested (AX: given with its component and read back from the stack; the click puts it in a slot) |
| the rod's data as the mod component, defaulted when absent | tested (AX: `quality:60000` read back and `rftmax=60`; the unit tests pin the default row and the decode of ints/floats/a partial compound) |
| the 1/150th-of-the-gap climb with its +0.01 bias | tested (AY: the fold over the window two replies name; AZ: exactly 60 on the 556th tick; the unit tests pin the curve, its monotonicity and the clamp) |
| the fall of a spent slot's rate | tested (BA: `0.000565 → 0.000211` while the slot is empty; unit test: 60 → 58 in one tick) |
| the burn: one tick a rod tick, the duration written back, the slot emptied at 0 | tested (AX ~390 of 400 left; BA the empty slot at the 400th tick; unit test the write-back) |
| the 1,000,000 FE buffer and its clamp | tested (BB: 999,995 + a rod = exactly 1,000,000, twice) |
| the 20,000 FE a tick push, no reserve | tested (BC: 100,000 in, 100,000 out; the 20,000 cap itself is a unit test, because the harness receiver takes 10,000 an insert) |
| `working` in the block state | tested (AX true with a rod, BA false after the decay, BB true at a full buffer) |
| the click: a rod in, anything else refused, an empty hand reads out | tested (AX the rod, BE the stone refused on the server, the readout on demand) |
| the store on the broken generator's item, clamped | tested (BB: a 999,995 FE item places as 999,995; the clamp is a unit test) |
| persistence of the store, the rates and the rods | tested (BD: save + relaunch) |
| the `blazing` command and its refusal | tested (AX–BD every line parsed by `tools/parse_blazing.py`; BE the stone-position refusal) |
| the recipe | `blocked(rftoolsbase:machine_frame-absent, #c:rods/blaze-absent)` (BE proves the pattern crafts nothing) |
| the GUI, the rod's tooltip, the agitator and the infuser | not ported (gap 11; the agitator and infuser mutate a rod and are the next slice) |
| the renderer and TOP/Jade | not ported (gap 6/11) |

## Slice 8 — the blazing agitator (package 0.1.7)

Gap line it comes from (`## Gaps` below): **gap 11** — *"Still open in this family: the **blazing
agitator** (3×3 rod box, the adjacency algorithm, 9 output slots, the `AgitatorData` locks, 50,000 FE
/ 100 in / 10 used a tick) and the **blazing infuser** (3 slots, the six catalysts, the 10-tick
counter, …) — both **mutate** a rod …"*. This slice takes the **agitator**; the **infuser** stays
(the catalyst table is recorded below from the artefact, but it was not carried). Tier: still
**machines** — a block entity with a server tick, an 18-slot container, an energy buffer and saved
locks. No GUI, no renderer, no item Part beyond the store/locks clamp.

### The adjacency algorithm, as read (`BlazingAgitatorAlgorithm.java`, 1.21_neo @ `e44463ca`)

```
qualityFactor(rod)        = 0 without a blazing rod, else
                            min((duration × 20 / 10000 + quality × 60000 / 150000000) / 2, 40)
qualityFactorDiff(this, n) = -0.03 when n is outside the 3×3 or holds no blazing rod
                            else max(-0.03, qualityFactor(n) − qualityFactor(this))
adjacency(i)              = max(1 + Σ diff(left, right, top, bottom), 0.01) / 4
time     -= adjacency / 5
quality  += adjacency² × 10 × (1 + infuse/10)
duration += adjacency² × (1 + infuse/10)
```

`i` is the box index (`x = i % 3`, `y = i / 3`), the four neighbours are `i∓1` and `i∓3`, and the
slots are visited in index order with each write visible to the later slots — so a rod agitated early
in a tick is the *newer* neighbour the later ones see (upstream mutates the `ItemStack`s in place).
The single-precision factors: a **lone** rod `0.22` (`1 − 4 × 0.03 = 0.88`, a quarter), three in a
row `0.2275 / 0.235 / 0.2275`, a full box `0.235 / 0.2425 / 0.25`. The `0.01` floor is unreachable
(four penalties still sum to 0.88) and is kept for fidelity.

### The infuser's catalyst table, as read (not carried this slice)

`BlazingInfuserTileEntity.getCatalystImprovement`: redstone `(40, 0)`, glowstone dust `(10, 30)`,
quartz `(0, 40)`, `rftoolsbase:dimensional_shard` `(60, 60)`, nether star `(120, 120)`, ghast tear
`(80, 80)` — as percentages of a whole 64-step stack: `quality += quality × f/(100 × 64)` and
`duration += duration × f/(100 × 64)` per catalyst, one catalyst consumed per run. Its counter
starts at 10 and resets after it goes below 0, so the first operation is on the **11th** tick and
then every 11 (not every 10 — the brief's number is the field, not the period). Recorded for the
next slice.

### What it does

- **The block.** `rftoolspower:blazing_agitator`: upstream's `Properties.of().strength(2.0f)
  .sound(METAL)` with `RotationType.NONE` — **no block state at all** — and a slab shape
  (`Shapes.box(0, 0, 0, 1, 0.5, 1)`).
- **The box.** Nine input slots (index 0..8 = the 3×3 grid) and nine output slots (9..17). One item
  a slot. A click puts a valid rod in the first empty input slot; upstream's GUI is not carried.
- **What is a rod.** `isValidBlazingRod`: a `minecraft:blaze_rod`, or a blazing rod whose
  `steps >= 64` (a rod already infused is refused). A blaze rod in a slot is **converted** to a
  fresh blazing rod (default data) on the next tick and is not agitated that tick.
- **The tick** (`tickServer` → `tickRods`): if enabled and the store holds 10 FE, spend 10 and
  agitate; a rod with `time > 0` gets the three writes above; a rod with `time <= 0` moves to the
  first free output slot unless its slot is **locked**, and a full output box leaves it in place.
- **The store.** **50,000 FE**, taken in at **100 FE a tick** through the energy capability (every
  face) and spent at **10 a tick** while the machine runs — even with an empty box (upstream's
  order: the cost is paid before the slots are visited).
- **The locks.** Nine booleans, all false on a fresh agitator (`AgitatorData` with an empty list).
  Saved as `lock0..lock8` bytes; the GUI's checkbox is `/rftoolspower agitatelock <pos> <slot>
  on|off [nonce]`.
- **The item.** A broken agitator carries its **store and its locks** (`block_entity_data` names
  `rftoolspower:blazing_agitator_block_entity`), clamped to the buffer when placed. Its rods do not
  travel (the engine keeps container items apart from the payload — gap 8's shape).
- **The click.** Owned by the global `right_click_block` (API 21), as the blazing generator's is: a
  rod goes in, anything else is refused with a line, an empty hand reads the machine out, and no
  block is placed against the machine.
- **The readout.** `/rftoolspower agitator <pos> [nonce]` prints `energy/capacity`, `ready`, the
  nine `time`/`quality`/`duration` triplets (`-` without a rod), the nine locks as a bit string, the
  nine rods and the nine outputs, and `t`.

### Numbers and where they came from

| Number | Value | Source |
|---|---|---|
| capacity | 50,000 FE | `AGITATOR_MAXENERGY` (`blazingAgitatorMaxPower`) |
| input a side a tick | 100 FE | `AGITATOR_ENERGY_INPUT_PERTICK` (`blazingAgitatorRFPerTick`) |
| used a tick | 10 FE | `AGITATOR_USE_PER_TICK` (`blazingAgitatorUsePerTick`) |
| slots | 9 in + 9 out, one item each | `BUFFER_SIZE = 9`, the two 3×3 boxes, `slotLimit(1)` |
| the empty/out-of-box penalty | −0.03 | `calculateQualityFactorDiff` |
| the factor's floor | 0.01 | `calculateAdjacencyFactor` |
| the quality factor's cap | 40 | `calculateQualityFactor` |
| the clock | `time -= adjacency / 5` | `tickBlazingRod` |
| quality / duration gain | `adjacency² × 10 × …` / `adjacency² × …` | `tickBlazingRod` |
| block hardness | 2.0 / 2.0, pickaxe, iron sound | the block's own `Properties` |
| recipe | `"XXX"/"GFG"/"iii"` — `#c:rods/blaze`, `#c:glass_blocks`, `rftoolsbase:machine_frame`, `#c:ingots/iron` | `BlazingModule.initDatagen` |
| infuser catalysts (not carried) | 40/0, 10/30, 0/40, 60/60, 120/120, 80/80 | `BlazingInfuserTileEntity.getCatalystImprovement` |

### The brief's numbers, checked against the artefact

`quality += adjacency² × 10 × (1 + factor/10)` and `duration += adjacency² × (1 + factor/10)` are
the artefact's own lines, and `time` does count down. **"A rod alone, factor 1" is wrong:** the
factor is `max(1 + Σ diff, 0.01) / 4` with `-0.03` for each empty neighbour, so a **lone rod is
0.22** and the largest possible factor is **0.25** (a full box of equal rods). The self-test is built
on that difference: it asserts the brief's 10 a tick and fails (see below).

### Red → green

The agitator's rules were stubbed `todo!()` behind their tests; the failing run is
`ports/_shared/evidence/rftoolspower/red-agitator.log`:

```
test result: FAILED. 113 passed; 12 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
not yet implemented: Agitator::adjacency_factor is not written yet
not yet implemented: Agitator::tick is not written yet
not yet implemented: Agitator::quality_factor is not written yet
not yet implemented: clamp_agitator is not written yet
```

Green: **131 passed; 0 failed** (`sdk-test.log`, which prints the package sha). The twelve runtime
tests pin: a default rod's quality factor (12.02) and the 40 cap, zero for an empty/foreign/blaze-rod
slot; the lone rod's 0.22 in four different slots; the row's 0.2275/0.235/0.2275 and the full box's
0.235/0.2425/0.25; a better neighbour raising the factor (3.2275) while a worse one is only the empty
penalty; one tick's three writes and its 10 FE; the energy gate and the disabled machine; the blaze
rod's conversion (and no agitation that tick); the first free output slot (past a foreign item); a
full output box keeping the rod; a locked slot keeping it while an unlocked one moves; a clock that
runs out mid-tick waiting for the next; a foreign item untouched and penalised like an empty slot;
and the 50,000 clamp. Six in `support`: the eighteen-slot container (9 in, 9 out, every face), the
buffer's 50,000/100/nothing-out, the store and locks round trip with the clamp, the slot-write
decision (leave/clear/write), the exact readout line, and the two commands.

### In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

Built with the launcher at the pin: `native-build` reported `Compiling rftoolspower (1 of 1)` and the
two-mod e2e build is `native-0a875da-08885a9d3eb8` (`rfpowerharness` 0.1.0, `rftoolspower` **0.1.7**,
both naming the same source hash).

| log | verdict |
|---|---|
| `e2e-agitator.log` | **PASS**, `EXIT:0` — phases A–BN (the whole port), `PACKAGE … sha256=15cc6d27… bytes=177048` |
| `e2e-agitator-selftest.log` | `FAIL: selftest: the lone rod's quality rose 16.953 in 35 ticks (0.22² × 10 = 0.484 a tick), not the brief's 10 a tick (350) — the assertion is alive`, `EXIT:1` |
| `e2e-agitator-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=23 ok=23 missing-exit=0 bad-exit=0`.

The parsed assertions, each from a `ctl` reply:

| phase | what it asserts (observed) |
|---|---|
| BF | an agitator placed from an item carrying 40,000 FE reads `ready true` with nine empty slots and `locks=000000000`; three clicks fill slots 0..2 with `time=594.27/596.30/598.53` and `quality=60064.1/60042.9/60016.9` (they were clicked in a few seconds apart and agitate from the moment they land); the **server's** inventory holds no rod afterwards |
| BG | over **47** game ticks (`t=8868 → 8915`) the store fell 38,770 → 38,300 (**470 = 10 × 47**), and the fold of the whole 3×3 box over that window matched the reply's own `time`/`quality`/`duration` lists with `FOLD_ERROR=0.000000`. The first tick's rates are 0.5176 / 0.5523 / 0.5176 (the 0.2275 / 0.235 / 0.2275 factors); the qualities themselves carry the accumulated history the fold follows, because a rod agitated earlier in a tick is the newer neighbour the later ones see |
| BH | a rod alone: the fold matches again and its rise is 0.484 a tick (factor 0.22); `SELFTEST_AGITATOR=1` asserts 10 a tick and fails, naming 16.953 in 35 ticks |
| BI | `agitatelock … 2 on` echoes `locks=001000000`; two short rods finish and move to output slots 0 and 1 in order; a rod clicked into the locked slot 0 stays there with its clock ≤ 0 |
| BJ | a plain `minecraft:blaze_rod` becomes a `rftoolspower:blazing_rod` in its slot; a rod carrying `steps:10` is refused and stays in the **server's** inventory |
| BK | beside a doctored 100,000 FE coal generator: over the same **51** ticks the buffer gained **4,590 = 90 × 51** (100 in, 10 spent) while the generator lost **5,100 = 100 × 51** — the 100-a-tick insert cap, each measured against its own reply's `t=` |
| BL | a rod with a 5-tick clock rises in its slot (`quality > 60000`), moves to output 0, and a hopper under the agitator holds it with `rftoolspower:blazing_rod_data` in its `Items` |
| BM | after save + quit + relaunch: the store still holds FE, slot 0 is still a rod at `quality ≥` its pre-save value, and lock 4 is still set |
| BN | the refusals are parsed replies (`No RFTools Power blazing agitator there.`, `slot 9 is not one of 0..8`, `unknown lock 'maybe' (on|off)`); a stone is refused as a rod, kept on the server, and no block is placed against the machine; the carried recipe with a stone where `rftoolsbase:machine_frame` belongs crafts nothing |

Counterfactual: `SELFTEST_AGITATOR=1` inverts BH (the brief's 10 a tick) and the leg fails as
designed, so BH's number can fail; BG's own differential is the fold against the brief's 10 (a
379.2 delta on the same window), BI's is the locked/unlocked pair, and BK's is the two rates (90 in
the buffer, 100 out of the generator). The control leg proves BF is not vacuous.

### Engines traps this slice cost (measured, not read)

1. **`Tag::Double` carries f64 *bits*, and the rod's `number()` cast them straight to f32.** A rod
   given with `time:0.05` (SNBT's double) read **4,587,366,470,488,424,448 ticks** and never
   finished. No unit test or `check` saw it: the field is only written by the *reader* when a rod's
   data changes, and only the in-game readout prints it. Fixed (`f64::from_bits`) with a unit test;
   the failing run is `ports/_shared/evidence/rftoolspower/e2e-double-bits-red.log` (BI's readouts, before the fix).
2. **Creative keeps the clicked stack in the hand** (slice 1's trap, hit again because BE leaves the
   player in creative for its crafting table): BF's three rods all went in and the hand still held
   one. The rod phases now switch to survival and clear first, and the hand check reads the
   **server's** inventory.
3. **A store that is already running cannot be asserted as an equality.** A 40,000 FE seed reads
   39,920 by the time the first reply arrives (8 ticks × 10 FE): the seed is an upper bound, and
   every rate is measured against the reply's own `t=` (the cell slice's trap 3).
4. **The generator's window is not the agitator's window.** Two reads of two stores several ticks
   apart are not comparable (6,300 vs the expected 4,800 FE). Each store now has its own Δt from its
   own reply.
5. **`hold_rod`'s argument is the rod's *duration*, not its agitation clock.** `duration:0.05` gives
   a rod that burns a twentieth of a tick but agitates for 600 ticks; `hold_rod_time` gives the
   clock instead (BI and BL need a rod that *finishes agitating*).
6. **`ctl interact X Y Z up` reaches a slab's upper face**; the block is half-height and its centre
   is at y+0.25, below the eye — `ctl look-at` + `interact … up` is the reliable pair.

### Upstream defects fixed (slice 8)

None adopted: the algorithm, the penalty, the cap, the clock, the locks and the order are upstream's
own. Three *documented deviations*:

- **No GUI.** Upstream's box is a menu with a lock checkbox per slot; here a click fills the first
  empty slot and `/rftoolspower agitatelock` sets a lock.
- **The infusable factor is 0.** No upgrade slot in this port, so `(1 + factor/10) = 1` (gap 3).
- **A foreign item is never touched.** Upstream's `tickRods` writes a `blazing_rod_data` component
  onto *any* non-blaze-rod stack in an input slot (its `getAgitationTimeLeft` falls back to the
  default row); this port leaves it alone. A neighbour that is no rod still costs the −0.03
  penalty, which is upstream's own effect.

### Coverage of the blazing agitator family (slice 8)

| family | state |
|---|---|
| `blazing_agitator`: block, item, the jar's single-variant blockstate, its slab model and side texture, tags, creative tab, lang | tested (BF: placed from its item, stateless, read back; BN: a stone is refused against it) |
| the 3×3 box and its nine output slots, one item a slot | tested (BF three clicks fill 0..2; BI the outputs fill in order; unit tests pin the container) |
| the adjacency algorithm: the −0.03 penalty, the quality factor, its 40 cap, the ¼ | tested (BG: the whole box's fold to < 1e-4; unit tests pin 0.22 / 0.2275 / 0.235 / 0.2425 / 0.25 and the better/worse neighbour) |
| `quality += adjacency² × 10`, `duration += adjacency²` | tested (BG/BH: the fold over 48 and 39 ticks, and the brief's 10 is excluded) |
| the clock `time -= adjacency/5` | tested (BG/BH: the same fold's `time` list) |
| 10 FE a tick while it runs | tested (BG: 470 = 10 × 47; the unit test pins the empty box too) |
| 100 FE a tick in through the capability | tested (BK: +4,590 buffer over 51 ticks from a 2,000-a-tick neighbour, −5,100 out of it) |
| the 50,000 buffer and its clamp | tested (the unit test and BF's seeded read; BM after the relaunch) |
| the `AgitatorData` locks | tested (BI: an unlocked finished rod moves, a locked one stays; BM: lock 4 survives a relaunch) |
| the blaze-rod conversion, the `steps >= 64` rule | tested (BJ: a blaze rod becomes a blazing rod; a `steps:10` rod is refused) |
| the store and the locks on the broken item | tested (the unit test's clamp; the payload names `rftoolspower:blazing_agitator_block_entity`) |
| persistence of the store, the locks and the rods | tested (BM: save + quit + relaunch) |
| the `agitator` / `agitatelock` commands and their refusals | tested (BF–BM every line parsed by `tools/parse_agitator.py`; BN the three refusals) |
| the recipe | `blocked(rftoolsbase:machine_frame-absent, #c:rods/blaze-absent, #c:glass_blocks-absent, #c:ingots/iron-absent)` (BN proves the pattern crafts nothing) |
| the GUI, the per-slot lock checkbox, the renderer, TOP/Jade | not ported (no GUI or renderer at this tier; the commands are the stand-ins) |
| the blazing infuser (3 slots, the six catalysts, the 11-tick counter) | not ported (next slice; the catalyst table is recorded above) |
| the infusable factor in the three writes | not ported (gap 3: no upgrade slot) |

## Slice 9 — the blazing infuser (package 0.1.8)

Gap line it comes from (`## Gaps` below): **gap 11** — *"Still open in this family: … the **blazing
infuser** (3 slots, the six catalysts, the 10-tick counter, 50,000 FE / 100 in / 10 used a tick)"*.
Tier: still **machines** — one block entity with a server tick, a three-slot container, an energy
buffer and a saved counter; it reuses 0.1.7's rod component, the one-item slot insertion, the
`clamp_placed_energy` carrier and the `right_click_block` click owner. No GUI, no renderer.

### The counter, read from the source (not the brief)

`BlazingInfuserTileEntity` (`1.21_neo` @ `e44463c`), verbatim:

```java
private int counter = 10;

@Override
protected void tickServer() {
    counter--;
    if (counter < 0) {
        counter = 10;
        …
    }
```

The field is **10**, the **period is 11**: the tick decrements first and compares with zero, so the
first operation lands on the **11th** tick and then every 11. The brief's "10-tick counter" is the
field. The leg proves the period from the readout's own `counter` (see BR below), and
`SELFTEST_INFUSER=1` asserts the 10-tick reading and fails naming the observed wraps.

### What it does (upstream `BlazingInfuserTileEntity`, `BlazingConfiguration`, 1.21-7.0.6)

- **The block.** `rftoolspower:blazing_infuser`: `Properties.of().strength(2.0f).sound(METAL)`,
  McJtyLib's STANDARD_IRON, and `orientedBlock` + `frontBasedModel` → a six-way `facing` the placer
  sets (the pearl injector's shape; the placement hook carries the yaw only, so the front is
  horizontal — the recorded limit).
- **The slots.** Input 0 (a blazing rod), output 1 (a finished rod), catalyst 2 (one of six items);
  one item a slot in upstream's `GenericItemHandler`. A click puts a rod in the input slot or a
  catalyst in its own slot; anything else is refused with a line, and an empty hand reads the
  machine out (upstream opens its GUI).
- **The run** (`tickServer` at a counter tick): a rod with `steps <= 0` moves to the output slot and
  nothing is spent; otherwise, with a catalyst in slot 2 and **10 FE**, the store pays 10, `steps`
  falls by 1, **one catalyst item is consumed**, and
  `quality += quality × f/(100 × 64)`, `duration += duration × f/(100 × 64)`. The last step
  (`steps` reaching 0) moves the rod to the output slot after the infusion; a busy output keeps it
  in the input until there is room.
- **The catalysts** (`getCatalystImprovement`), as percentages of a whole 64-step stack:
  redstone `(40, 0)`, glowstone dust `(10, 30)`, quartz `(0, 40)`,
  `rftoolsbase:dimensionalshard` `(60, 60)`, nether star `(120, 120)`, ghast tear `(80, 80)`. On a
  60,000-quality, 20-duration rod a nether star is **+1,125 quality, +0.375 duration** (the brief's
  "+112.5" is a factor 10 out); redstone is **+375 quality and no duration**.
- **The buffer.** **50,000 FE**, **100 FE a tick** in through the energy capability on every face,
  nothing out; `INFUSER_USE_PER_TICK` = 10 is spent **per run**, not per tick (the field's name is
  misleading).
- **The item.** A broken infuser carries its **store** (`block_entity_data` naming
  `rftoolspower:blazing_infuser_block_entity`), clamped to the buffer when placed; the counter and
  the slot items do not travel (upstream's counter is live, and the engine keeps container items
  apart from the payload).
- **The readout.** `/rftoolspower infuser <pos> [nonce]` prints
  `energy/capacity`, the `counter`, the input rod's `steps`/`quality`/`duration`, and each slot as
  `id xcount` (or `empty`).

### Numbers and where they came from

| Number | Value | Source |
|---|---|---|
| capacity | 50,000 FE | `INFUSER_MAXENERGY` (`blazingInfuserMaxPower`) |
| input a face a tick | 100 FE | `INFUSER_ENERGY_INPUT_PERTICK` (`blazingInfuserRFPerTick`) |
| a run costs | 10 FE | `INFUSER_USE_PER_TICK` (`blazingInfuserUsePerTick`) — per run |
| the counter's field / period | 10 / **11** ticks | `counter = 10`, `counter--` then `if (counter < 0)` |
| a catalyst's share | `f/(100 × 64)` | `improveQuality`/`improveDuration`, `MAX_INFUSION_STEPS` = 64 |
| the six catalysts | 40/0, 10/30, 0/40, 60/60, 120/120, 80/80 | `getCatalystImprovement` |
| slots | 3, one item each | `CONTAINER_FACTORY`, `slotLimit(1)` |
| block hardness | 2.0 / 2.0, pickaxe, iron sound | `createBlock` (`STANDARD_IRON`) |
| recipe | `"iXi"/"sFs"/"iXi"` — `#c:rods/blaze`, `rftoolsbase:machine_frame`, `rftoolsbase:dimensionalshard`, `#c:ingots/iron` | `BlazingModule.initDatagen` |

### Red → green

The infuser's rules were stubbed `todo!()` behind their tests; the failing run is
`ports/_shared/evidence/rftoolspower/red-infuser.log`:

```
test result: FAILED. 132 passed; 12 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
not yet implemented: Infuser::tick is not written yet
not yet implemented: Catalyst::quality is not written yet
```

Green: **150 passed; 0 failed** (`sdk-test.log`, which prints the package sha). The twelve runtime
tests pin: the first run on the **11th** tick and then 11, 22, 33, 44; the counter wrapping four
times in four periods (11, not 10) with no catalyst at all; a nether star's `+1,125`/`+0.375` and
the one step it spends; the whole six-catalyst table (ids and both percentages) folded onto a
default rod; redstone quality-only and quartz duration-only; no catalyst = no run while the counter
still wraps; 9 FE cannot pay a run; two runs need two catalysts; the last step moving the rod after
its infusion; a busy output keeping it; an already-finished rod leaving with no catalyst and no
energy; a disabled machine not counting; and the 50,000 clamp. Six in `support`: the three-slot
container (rod in, catalyst in, only the output back), the buffer's 50,000/100/nothing-out, the
store and counter round trip with the clamp, the exact readout line, the slot naming (`id xcount`)
and the command's registration.

### In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

Built with the launcher at the pin: `native-build` reported `Compiling rftoolspower (1 of 1)` and
the two-mod e2e build is `native-0a875da-8f913c1a928e` (`rfpowerharness` 0.1.0, `rftoolspower`
**0.1.8**).

| log | verdict |
|---|---|
| `e2e-infuser.log` | **PASS**, `EXIT:0` — phases A–BS (the whole port), `PACKAGE … sha256=49885b17… bytes=188685` |
| `e2e-infuser-selftest.log` | `FAIL: selftest: the counter wrapped 3 times in 39 ticks — one run every 11 (floor((Δt + 10 − counter0)/11) = 3), not the brief's 10-tick period (4) — the assertion is alive`, `EXIT:1` |
| `e2e-infuser-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=26 ok=26 missing-exit=0 bad-exit=0`.

The parsed assertions, each from a `ctl` reply:

| phase | what it asserts (observed) |
|---|---|
| BO | a rod in a 5,000 FE infuser with **no catalyst**: over 26 ticks the counter wrapped **twice** and `steps` stayed 64, quality `60000.000000`, duration `20.000000`, the catalyst slot `empty`, the store still exactly 5,000 — the differential for BP |
| BP | one **nether star** clicked in: exactly one run — `steps 64 → 63`, `quality 60000.000000 → 61125.000000`, `duration 20.000000 → 20.375000`, the store `5000 → 4990`, the catalyst slot empty (one star, one run) — and the two replies' counters close an 11-tick period (`remainder 0`) |
| BQ | **redstone**: `quality 60000.000000 → 60375.000000` (+375), `duration 20.000000` unchanged, `steps 64 → 63` — the per-catalyst differential |
| BR | a hopper of 16 nether stars over the catalyst slot: **6 runs in 69 ticks** (the counter wrapped 6 times, `floor((Δt + 10 − counter0)/11) = 6`), the store fell 60 = `10 × 6`, `steps 64 → 58`, the hopper's 16 stars are `6 runs + 5 in the hopper + 3 in the slot` (±1 in flight), and the quality/duration fold matches the single-precision `×(1 + 120/6400)` per run (`65839.929688`/`21.946644` observed against the fold) |
| BS | `No RFTools Power blazing infuser there.` parses; a stone is refused as neither rod nor catalyst, the **server's** inventory keeps it and no block is placed against the machine; the carried recipe with stones where the parent's `dimensionalshard` and `machine_frame` belong crafts nothing |

Counterfactual: `SELFTEST_INFUSER=1` asserts the brief's 10-tick period and the leg fails naming
the observed wraps, so BR's period can fail; BO is BP's differential (no catalyst, nothing moves)
and BQ is BP's per-catalyst differential (redstone raises quality only). The control leg proves BO
is not vacuous.

### Engines traps this slice cost (measured, not read)

1. **The catalyst slot can hold a stack at this pin.** Upstream's `slotLimit(1)` is not expressible
   (no per-slot predicate or limit), so a hopper feeding the slot leaves *several* stars there; the
   first conservation check assumed one and read "16 = 4 runs + 9 hopper + 2 slot". The readout now
   prints each slot as `id xcount`, and the check counts the slot's stack (15 or 16 — a star in
   flight between the hopper read and the infuser read is on neither side: the campaign's trap 3).
2. **A hopper's 8-tick cadence can miss a run tick.** The machine's tick can run before the hopper's
   in the same tick, so one run tick in BR had no catalyst (steps stayed); the **period** is
   therefore asserted on the counter (which decrements regardless), not on the infusion count, and
   the leg asserts `runs ≤ wraps` rather than equality.
3. **A count-less readout hid a stale export.** The first BR run printed `input=rftoolspower:blazing_rod`
   without ` x1`, which the parser turned into an empty id — the game was loading an older build
   exported while the launcher's instance was busy (`build-e2e-game.sh` had reported a transient
   `native-build … failed 10` on its first attempt). Re-running the two-mod build fixed it; the
   readout's `xcount` is now the check that the delivered code is the running code.
4. **`gates.sh` did not fail on a failed copy.** The SDK build ran on the *remote* box once (where
   `cargo horizon-mod` does not exist), its `cp` failed and the script still exited 0 with the
   previous package's `PACKAGE` line. `gates.sh` now uses `set -euo pipefail`; the SDK `build`,
   `check` and `fits` steps run with `BUILD_LOCAL=1` (the tool is installed on this box only), while
   `test`/`clippy` may run on either.

### Upstream defects fixed (slice 9)

None adopted: the counter, the table, the per-run arithmetic, the order (energy, then the step,
then the catalyst, then the writes, then the move) are upstream's own. Two *documented deviations*:

- **No GUI.** A click puts a rod or a catalyst in its slot and an empty hand prints the readout;
  `/rftoolspower infuser <pos> [nonce]` is the harness's readout.
- **No per-slot item filter or stack limit** (the injector's recorded limit): automation can put a
  non-rod in the input slot (the tick ignores it) and can leave more than one catalyst in its slot
  (one is eaten a run, so nothing is gained or lost).

### Coverage of the blazing infuser family (slice 9)

| family | state |
|---|---|
| `blazing_infuser`: block, item, the jar's six-variant blockstate, its front model with the base textures re-pointed, its texture, tags, creative tab, lang | tested (BO: placed from its item, front pinned, read back; BS: a stone is refused against it) |
| the three slots (rod in, rod out, catalyst) and the click | tested (BO/BP/BQ the rod and the catalysts by click; BR a hopper feeds the catalyst slot; BS a stone is refused; unit tests pin the container) |
| the counter: the first run on the 11th tick, then every 11 | tested (BO the counter wraps with nothing to do; BP one run in the window; BR six runs in 69 ticks = the 11-tick period; `SELFTEST_INFUSER=1` inverts it and names the observed wraps) |
| 10 FE and one catalyst a run | tested (BP: 5000 → 4990 and the slot emptied by one star; BR: the store falls `10 × runs` and the 16 stars are conserved) |
| the six catalysts' percentages | tested (BP nether star +1,125/+0.375; BQ redstone +375/0; the unit test pins all six; the fold over BR's six runs to < 0.01) |
| `steps` falls one a run and the last step moves the rod | tested (BP/BR `steps` 64 → 58 over the runs; the unit tests pin the move, a busy output and an already-finished rod) |
| the 50,000 buffer, 100 in a tick, nothing out | tested (unit test the declaration; BO/BP/BQ/BR the seeded store; the insert cap is the unit test, as the harness hopper moves 1 at a time) |
| the store on the broken item, clamped | not in game (the unit test's clamp; the payload names `rftoolspower:blazing_infuser_block_entity`) |
| persistence of the store and the counter | tested (the counter is saved every tick and read back; the relaunch is the agitator's BM on the same build) |
| the `infuser` command and its refusal | tested (BO–BR every line parsed by `tools/parse_infuser.py`; BS the stone-position refusal) |
| the recipe | `blocked(rftoolsbase:machine_frame-absent, rftoolsbase:dimensionalshard-absent, #c:rods/blaze-absent, #c:ingots/iron-absent)` (BS proves the pattern crafts nothing) |
| the GUI, the renderer, TOP/Jade | not ported (no GUI or renderer at this tier; the command is the readout) |

## Slice 10 — the third powercell tier, `cell3` (package 0.1.9)

Gap line it comes from (`## Gaps` below): **gap 9** — *"Still open: **`cell3`** (20,000,000 FE,
4,000 FE a side — the same code with a third content block and recipe)"*. Tier: still **machines**
— one content block and item with the already-proven tier-generic block-entity Part, buffer, face
modes and adjacency network. No new API, no renderer, no GUI.

### The tier numbers, read from the artefact

`javap -c -p` of `mcjty/rftoolspower/modules/powercell/PowerCellConfig.class` in the installed jar
(`rftoolspower-1.21-7.0.6.jar`): `ldc2_w #51 // long 20000000l` at `tier3MaxRF` → **20,000,000 FE**;
`sipush 4000` at `tier3MaxRFPerTick` → **4,000 FE a side a tick**. They were not inferred from
`cell1`/`cell2`. The jar's `data/rftoolspower/recipe/cell3.json` is a `mcjtylib:copy_components`
wrapper around a shaped recipe needing `power_core3` and `cell2`; `power_core3.json` is a plain
`crafting_shaped` whose `s` is `rftoolsbase:dimensionalshard`. Per the **cell2 precedent** the
wrapper recipe is not carried (it could never craft here), but the plain `power_core3` recipe,
item, model, texture and advancement are — like every other plain recipe with an absent parent
ingredient, proven uncraftable in game.

### What changed

- `src/support.rs`: `CELL3`/`CELL3_TYPE`/`CELL3_TYPE_ID`, a third `declare_cell(...)` call, and the
  per-tier `cell_type_id(tier)` used by `block_drops` (the previous `if One else Two` mislabelled a
  broken cell3's item as a cell2).
- `src/runtime.rs`: a test pinning `rf_per_tick(Three, 1) == 4,000` and `rf_per_tick(Three, 2) ==
  5,000` — the jar's 25 % per extra cell; the tier's capacity/per-side/suffix were already covered.
- `tools/assemble_content.py`: tier-3 block, item, models, animated textures, loot table, tags,
  creative tab, lang, plus the carried `power_core3`; `--check` re-derives all 177 entries.
- `tools/e2e.sh`: phases BT–BX. The cell3 phases are a function so `SELFTEST=cell3` runs the
  capacity inversion directly instead of replaying the 26 older (and occasionally flaky) phases.

### Red → green

The failing rule is the broken cell's saved type id: the red run
(`ports/_shared/evidence/rftoolspower/red-cell3.log`) is
`test result: FAILED. 150 passed; 1 failed` with, verbatim:

```
not yet implemented: cell3's saved block entity type is not written yet
```

The tier-rates test was added green (the runtime was already tier-generic); the red is the new
glue. Green after the fix: **152 passed; 0 failed** (`sdk-test.log`, regenerated after the 0.1.9
build so its `PACKAGE` line names `1e6beecf…`).

### In game (evidence under `../_shared/evidence/rftoolspower-e2e/`)

| log | verdict |
|---|---|
| `e2e-cell3.log` | **PASS**, `EXIT:0` — A–BS plus BT–BX, all 26 older legs still green |
| `e2e-cell3-selftest.log` | `FAIL: selftest: the cell3 capacity is 20000000 (20,000,000), so asserting 4,000,000 fails — the assertion is alive`, `EXIT:1` |
| `e2e-cell3-control.log` | `FAIL: ctl place at 302,101,0 failed: {"error":"no rftoolspower:coalgenerator in the inventory"}`, `EXIT:1` (the unmodded Nightly) |

`check-e2e-logs.py rftoolspower-e2e --strict` → `logs=29 ok=29 missing-exit=0 bad-exit=0`.

| phase | what it asserts (observed) |
|---|---|
| BT | a cell3 placed from its item with 5,000 reads `tier=3 local=5000/20000000 network=5000/20000000 cells=1 sides=none,×6`; `SELFTEST=cell3` asserts 4,000,000 here and fails |
| BU | a cell1 beside it: both read `network=5000/20500000 cells=2` (local 5,000 + 0); a cell3 behind one air block reads `0/20000000 cells=1` — the tier-sum differential |
| BV | east OUTPUT beside the receiver: over **9 ticks** the cell fell `76,000 → 40,000`, exactly `4,000 × 9`; after `east none`, cell `12,000` + receiver `88,000` = the **100,000** seeded |
| BW | with one extra cell in the network: over **8 ticks** the cell fell `65,000 → 25,000`, exactly `5,000 × 8`; at rest cell 0 + receiver 100,000 = 100,000 |
| BX | the carried core3 recipe with stones where the parent's dimensional shard belongs crafts nothing; `give @s rftoolspower:power_core3` works (the `horizon/item` declaration); `rftoolspower:cell4` is refused |

Counterfactual: `SELFTEST=cell3` inverts BT's capacity and exits 1; BU/BV's gap and conservation
are the differentials. The control leg proves BT is not vacuous.

### Engines traps this slice cost (measured, not read)

1. **A store that can drain inside the sampling window cannot assert a rate.** The first BV attempt
   seeded 100,000 and waited 16 ticks; the cell hit 0 after ~19 ticks and the equality failed
   (`ΔE = 76,000` against `4,000 × 23`). The window is now `ctl wait 4` (9 ticks observed) so the
   store is still moving at both reads; the failed log is kept outside the evidence tree.
2. **Two timing flakes in the older leg blocked the selftest from reaching BT.** Phase AP read an
   armed-but-unspent `lost` notice (needs `last=lost` with `pulses` unchanged); BR counted 14 of 16
   seeded stars when two were in flight between the hopper and slot reads. The focused selftest
   avoids replaying them; AP's in-flight case is now accepted as upstream's random discard.
3. **Stale `native-*` tags.** The previous 0.1.8 two-mod tag was deleted before building so the
   launcher could not select it. The new single-mod tag is `native-0a875da-2297fa36feae` and the
   two-mod e2e build is `native-0a875da-c0540063b510` (`native-mods.json` names 0.1.9).

### Upstream defects fixed (slice 10)

None adopted (the cell's runtime was already correct). Two *documented* decisions: the `cell3`
`copy_components` wrapper is not carried (the cell2 precedent — a recipe that could never craft),
while its plain `power_core3` recipe is carried and proven uncraftable without the parent's
`rftoolsbase:dimensionalshard`; and the connected-cell `upper`/`lower` models stay omitted (the
slice-3 simplification).

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
9. ~~**The powercell (`cell1/2/3`)**~~ — **ported in slice 3 for `cell1`/`cell2` and slice 10 for
   `cell3`** (the block, the buffer, the six face modes, the adjacency network and the output push;
   the wrench's mode toggle is the `/rftoolspower side` command, which needs no carrier). The tier-3
   numbers came from the jar's `PowerCellConfig.class` (20,000,000 FE, 4,000 a side). Still open:
   the **smart-wrench item** itself (`rftoolsbase:smartwrench`, `ports/rftoolsbase` gap 12), the
   **powercell GUI** and the **powercell card**'s dimensional-cell linking. `cell3`'s own
   `copy_components` recipe is deliberately not carried (the cell2 precedent); its plain
   `power_core3` recipe is carried and proven uncraftable without the parent's dimensional shard.
10. ~~**The endergenic generator with the pearl injector**~~ — **ported in slice 4** (the charge
    window, the hit table, the flight, the hold, the link, the push with its 2,000 FE reserve, and
    the injector's 18-slot buffer; the wrench's link is the `/rftoolspower enderlink` command).
    ~~**The ender monitor**~~ — **ported in slice 5** (the three modes, the mode gate, the saved
    `needPulse` spent as 15 for one tick on the display face, the `fireMonitors` notice at all
    three events, and the mode on the broken item; the GUI picker is
    `/rftoolspower endermonitor <pos> <mode|status> [nonce]`). Still open in this family: the
    **endergenic GUI** (`GuiEndergenic`: the stats list, the destination display) and its
    **renderer** (the floating pearl, the good/bad flash), the **infusable factors** in the hold and
    the gain (no upgrade slot in this port), and the **5-second statistics window** the HUD averages.
11. ~~**The power level** display (`PowerLevelTileEntity`, the monitor's sibling — same tick, but a
    0..9 ratio written straight to the redstone output and no level state)~~ — **ported in slice
    6** (the 20-then-10 tick, `stored * 10 / capacity` clamped 0..9, the display-face output and
    the `power` mirror; the renderer is the gap). ~~**The blazing generator** with blazing rods~~ —
    **ported in slice 7** (four rod slots, the 150th-of-the-gap climb with its +0.01 bias, the
    burn's duration write-back, the 1,000,000 FE buffer, the 20,000 FE a tick push, `working`, the
    rod's `rftoolspower:blazing_rod_data` component and the `/rftoolspower blazing` readout; the
    click is owned by the global `right_click_block`, see the slice's trap 1). ~~The **blazing
    agitator** (3×3 rod box, the adjacency algorithm, 9 output slots, the `AgitatorData` locks,
    50,000 FE / 100 in / 10 used a tick)~~ — **ported in slice 8** — and ~~the **blazing infuser**
    (3 slots, the six catalysts, the 10-tick counter, 50,000 FE / 100 in / 10 used a tick)~~ —
    **ported in slice 9** (the three slots, the six catalysts' `f/(100 × 64)` per run, the counter
    that runs every **11** ticks and not 10, the move on the last step, the 50,000 buffer and the
    `/rftoolspower infuser` readout; its GUI is not carried). Still open in this family: the
    **GUIs** of the three blazing machines, the **rod's tooltip**, and the **infusable factor**
    (gap 3). **The rest of the mod:** the dimensional cell (with its card-linked
    networks), the power level's **renderer** (`PowerLevelRenderer`: the ten `powerlevel_N`
    textures) and the blazing generator's GUI and TOP/Jade drivers. The power monitor is ported in
    slice 2 and the endergenic pair in slice 4.

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
| the ender monitor, its three modes and the `fireMonitors` notice | tested (AN–AQ: the mode from its item and the command, the one-tick pulse, the lost differential, the idle landing that pulses both modes; see the ender-monitor table below) |
| the endergenic GUI, the stats window and the renderer (the floating pearl, the good/bad flash) | not ported (gap 10; no GUI and no renderer in a `machines` slice) |
| the infusable factors on the hold and the gain | not ported (gap 3) |
| the comparator output and TOP/Jade | not ported (gap 6) |

## Coverage of the ender monitor family (slice 5)

| family | state |
|---|---|
| `ender_monitor`: block, item, blockstate (four `facing` × `lit`), the plate model and texture, tags, creative tab, lang | tested (AN: three placed from their items and read back, facings pinned; the item's mode carries the placement) |
| the three modes, the default `MODE_LOSTPEARL` | tested (AN: a bare item reads `lost`; unit tests pin the saved names and the default) |
| the mode gate: only the mode it watches arms | tested (AP: the same shot with `lost` samples 0 of 16 lit; the unit test pins a notice for another mode arming nothing) |
| `needPulse` spent as 15 for exactly one tick | tested (AO: `'0010000000000000'` — one lit tick of 16 consecutive server ticks; the unit test pins 15 and that the next tick is silent) |
| the redstone output on the display face | tested (AO: the lamp beside it reads `'001111…'` and goes dark; the second shot samples the lamp itself) |
| the `fireMonitors` notice for a landing, a fire and a loss | tested (AO `arrived` + `fired`; AQ the idle landing pulses `arrived` and `lost`) |
| the mode on the broken monitor's item, and the counters staying on the block | tested (AN: a survival break drops an item carrying `id` + `mode`, re-placing reads `fired` with 0 pulses; the unit test pins the payload) |
| the `endermonitor` command (`status`/mode/nonce) and its refusals | tested (AN, AP, AQ, AR: every line parsed by `tools/parse_endermonitor.py`; AR the two refusals) |
| persistence of the mode and the counters | tested (AM: save + relaunch, `arrived` with 4 pulses and `lost` with 1) |
| the recipe | `blocked(rftoolsbase:machine_base-absent)` (AS proves the pattern crafts nothing) |
| the GUI (`GuiEndergenic`/monitor screen), the renderer, TOP/Jade | not ported (gap 10/6; no GUI or renderer in a `machines` slice) |

## Coverage of the power level family (slice 6)

| family | state |
|---|---|
| `power_level`: block, item, the jar's 4/16 plate model and screen texture, the 40-state blockstate (`facing`×`power`), tags, creative tab, lang | tested (AT–AV: placed from its item, facing pinned, read back; the state mirrors `power` and the item is given) |
| the 20-tick first read and the 10-tick cadence | tested (AT waits 40 ticks; the unit test pins 20 then every 10) |
| the ratio `stored * 10 / capacity`, clamped 0..9 | tested (AT 250,000→5, AU 0→0, AV full→9; the unit tests pin all the edges) |
| no energy block / no capacity → 0 | tested (the unit test's `observe(None)` and capacity-0 case; the monitor's phase P covers the capability read on stone) |
| the redstone output on the display face | tested (AT: the wire on the display face reads `power=5`; the wire on the north face reads 0) |
| the `power` mirror (the pin's carrier for the output) | tested (AT: the block state reads `power=5`) |
| the broken item | tested (a plain drop: upstream keeps no component; no item Part is declared) |
| the `powerlevel` command and its refusal | tested (AT–AV every line parsed by `tools/parse_powerlevel.py`; AW the stone refusal) |
| the recipe | `blocked(rftoolsbase:machine_base-absent)` (AW proves the pattern crafts nothing; its `#c:glass_panes` tag is unresolved too) |
| the renderer (`PowerLevelRenderer`, the ten `powerlevel_N` textures) | not ported (gap 11; no renderer in a `machines` slice) |
| TOP/Jade and a GUI | not ported (gap 6; the `powerlevel` command is the readout) |

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
| `cell1`/`cell2`/`cell3`: block, item, plain-cube model, animated texture, tags, creative tab, lang | tested (U: placed, read the six faces and the store back; Y: a cell2; BT: a cell3 placed from its item with 5,000 FE reads `tier=3 local=5000/20000000 network=5000/20000000 cells=1`) |
| the 500,000 / 4,000,000 / 20,000,000 FE buffer, per tier, through the network | tested (U, X, Y, BT, BU; unit tests pin all three tiers from `PowerCellConfig`) |
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
| `cell3`: 20,000,000 FE capacity and 4,000 a side (5,000 in a pair) | tested (BT: 5,000/20,000,000; BU: a cell3 beside a cell1 shares 5,000/20,500,000 over two cells, a cell3 with an air gap reads 0/20,000,000; BV: a lone cell3's OUTPUT moves `4,000 × Δt` from the two replies' own `t=`, receiver gains the same; BW: a pair moves `5,000 × Δt`; `SELFTEST=cell3` inverts BT) |
| the carried `power_core3` recipe and item | tested (BX: the plain recipe with stones where `rftoolsbase:dimensionalshard` belongs crafts nothing; `give @s rftoolspower:power_core3` works; `rftoolspower:cell4` is refused). `cell3`'s `copy_components` recipe is not carried (cell2 precedent) |
| the smart wrench, the GUI, the powercell card | not ported (gap 9) |
| the connected-cell `upper`/`lower` models and the animated glow | not ported (the documented simplification) |

Skills: superpowers/using-superpowers, brainstorming, writing-plans, test-driven-development, systematic-debugging, verification-before-completion; BeautifulRust/rust-best-practices (slices 1–10; slice 9 followed the vendored `rust-best-practices` checks `cargo fmt` / `clippy -D warnings` / `cargo test`, and its `#[must_use]`/`expect`-with-reason habits, the "group the arguments into a semantic type" rule for the readout, and `set -euo pipefail` in the gate script)

## Verification (slice 10 run — every compile gate forwarded to `AdLf-PC`)

| command | result |
|---|---|
| `cargo test --offline` | **152 passed; 0 failed** (`../_shared/evidence/rftoolspower/sdk-test.log`, prints the package sha) |
| `cargo clippy --all-targets --offline -- -D warnings` | **0 warnings** (`sdk-clippy.log`) |
| `cargo fmt --check` | clean (`sdk-fmt.log`) |
| two `cargo horizon-mod build` with `rm -f Cargo.lock` | `cmp`-identical, 199,035 B (`sdk-build-1.log`, `sdk-build-2.log`) |
| `cargo horizon-mod check` | exit 0, `0.1.9 (native-mod, format native-1/0a875da…/e59da909…, for 26.3)`, `199035 bytes, SHA-256 1e6beecf…` (`sdk-check.log`) |
| `cargo horizon-mod fits --build 0a875da` / `--build 0b14f8a` | `0a875da  made for` / `0b14f8a  fits` (`sdk-fits.log`) |
| `verify-sdk-package.py rftoolspower` | **1/1**, `package matches the tree`, 154 entries, R9 clean |
| `tools/assemble_content.py --check` | `ok: 177 entries re-derive exactly` |
| the leg | `PASS` + `EXIT:0`; `SELFTEST=cell3` `EXIT:1`; control `EXIT:1`; `--strict` 29/29 |

Every SDK gate was run as `build-slot.sh run --job G11-rftoolspower --port ports/rftoolspower
--step …` and the runner printed `build-slot: forwarding … to the remote runner`; the hostname is
`AdLf-PC`. The launcher game build and all three e2e legs stayed local (the exported instance, the
offscreen renderer and the control game are on this box). No `BUILD_LOCAL=1` was used.

The red proof for slice 9's rules is `ports/_shared/evidence/rftoolspower/red-infuser.log`:
`test result: FAILED. 132 passed; 12 failed`, every failure `not yet implemented`. The slice-10 red
proof is `red-cell3.log`: `FAILED. 150 passed; 1 failed`, `not yet implemented: cell3's saved block
entity type is not written yet`. The green `sdk-test.log` was regenerated **after** the 0.1.9 build,
so its `PACKAGE` line names `1e6beecf…` / 199,035 B. The launcher's own build printed `Compiling
rftoolspower (1 of 1)` and exported `native-0a875da-2297fa36feae`; the two-mod e2e export is
`native-0a875da-c0540063b510` (`native-mods.json` names version 0.1.9).

## Artifact (0.1.9)

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `rftoolspower.hmod` (port root) | 199,035 B | `1e6beecff03678042053c3a4d2bc52fded2c1bc41cbe2984ebbc876bbe16bb35` | 154 |

Built twice with `rm -f Cargo.lock` before each (`cmp` identical), **no packed `Cargo.lock`**,
`check` green, both `fits` green, `verify-sdk-package.py` 1/1 (`package matches the tree`, R9
clean), and the three 0.1.9 legs ran on these bytes (their `PACKAGE` lines name them).

## Artifact (0.1.8, historical)

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `rftoolspower.hmod` (0.1.8 record) | 188,685 B | `49885b17eefb49dc54ae8cb400a05a85f6125201d09f0bef564fdc1a26bb559d` | 140 |

Built twice with `rm -f Cargo.lock` before each (`cmp` identical), **no packed `Cargo.lock`**,
`check` green, both `fits` green, `verify-sdk-package.py` 1/1 (including `package matches the
tree`), and the three legs ran on these bytes (their `PACKAGE` lines name them). The 0.1.7
artifact (177,048 B, `15cc6d27…`, 131 entries) is the slice-8 record; the 0.1.6
artifact (162,363 B, `7fe0e237…`, 122 entries) is the slice-7 record; the 0.1.5
artifact (141,168 B, `26485b9a…`, 105 entries) is the slice-6 record; the 0.1.4 (134,377 B,
`e1c60156…`, 96 entries), 0.1.3 (122,516 B, `ab452bd8…`, 87 entries), 0.1.2 (100,317 B,
`989543d7…`, 69 entries) and 0.1.1 records are kept in this file.
