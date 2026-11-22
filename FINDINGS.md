# RFTools Power — upstream behaviour extracted (slices 1–3)

Analysis only. Repository `https://github.com/McJtyMods/RFToolsPower`, branch `1.21_neo`, commit
**`e44463cacddb85155839373b42d39bc705d618c0`** (2026-06-16, `version=1.21-7.0.6`) — the exact
version of the ATM10 jar `rftoolspower-1.21-7.0.6.jar`. McJtyLib (the library the machine's base
class and redstone mode live in): branch `1.21_neo`, commit
**`ef393e608eebc188a6e1decbf110506a55cc0725`**. Both shallow clones were deleted after this file
was written. No Java was copied or translated; no jar was decompiled.

## Files read

| File | What it gave |
|---|---|
| `modules/generator/blocks/CoalGeneratorTileEntity.java` | the tick order, the fuels, the burn, the buffer, the slot layout, the `LIT` state, the loot components |
| `modules/generator/CoalGeneratorConfig.java` | 60 FE/t, 600 ticks/coal, 500,000 FE, 2,000 FE/t out, 1,000 FE/t into a charge item |
| `modules/generator/CoalGeneratorModule.java` | the recipe (`"cTc"/"cFc"/"cTc"`), the advancement, the block item properties |
| `modules/generator/data/CoalGeneratorData.java` | the saved state is one int (`burning`) |
| `modules/powercell/blocks/PowerCellTileEntity.java`, `PowerCellBlock.java`, `PowerCellConfig.java`, `data/{Tier,SideType,PowerCellNetwork}.java` | the next family: 500,000 / 4,000,000 / 20,000,000 FE by tier, 250 / 1,000 / 4,000 FE a tick a side, `rfPerTickScale` 0.25, six side modes defaulting to `NONE`, the wrench toggle, the same-tier adjacency network |
| `modules/monitor/…`, `modules/dimensionalcell/…`, `modules/endergenic/…`, `modules/blazing/…` | the remaining families, checked only to rank them |
| `mcjtylib/tileentity/GenericTileEntity.java`, `TickingTileEntity.java`, `varia/RedstoneMode.java`, `setup/Registration.java` | `isMachineEnabled()`, the `REDSTONE_IGNORED` default, `needsRedstoneMode()` |

## Behaviour, in the order the tick runs it

1. `markDirtyQuick()`; charge the item in slot 1; push energy to neighbours (`handleSendingEnergy`);
   return early when `!isMachineEnabled()`.
2. `handlePowerGeneration()`:
   - `burning > 0` → `burning--`, `energyStorage.produceEnergy(rfPerTick)`;
   - else, fuel in slot 0 → take one item, `burning = TICKSPERCOAL` (`×9` for a coal block), then
     `+= burning * infusedFactor / 2`.
   - `LIT` = `isWorking()` = `burning > 0 && isMachineEnabled()`.
3. `rfPerTick` = `RFPERTICK * (1 + infusedFactor)`; the store clamps at `MAXENERGY` (`produceEnergy`
   is a `GenericEnergyStorage` with `maxReceive = 0`).

Facts this slice reuses verbatim: the fuels are the three **items** (`Items.COAL`,
`Items.CHARCOAL`, `Items.COAL_BLOCK`), not the `minecraft:coals` tag; fuel is taken only when
nothing is burning, and the buffer's fullness is not consulted (a full generator still eats coal);
the store survives a break through the loot table's `copy_components` (`mcjtylib:item_energy`,
`mcjtylib:item_inventory`, `mcjtylib:infusable`), which this port expresses as the vanilla
`minecraft:block_entity_data` component.

## Slice 2: the power monitor and `handleSendingEnergy` (read for the same commits)

| File | What it gave |
|---|---|
| `modules/monitor/blocks/PowerMonitorTileEntity.java` | the 20-tick counter; the `LEVEL` property (0–5); `getFacing(...).getInputSide()`; the energy read through `EnergyTools`; `ratio = 1 + stored * 5 / maxEnergy` clamped 1..5; `percentage = stored * 100 / maxEnergy` and the alarm inside `[minimum, maximum]`; `setInvalid()` (level 0, redstone 0); `support.setRedstoneState(this, 15/0)`; the item component `ITEM_POWER_MONITOR_DATA` |
| `modules/monitor/data/PowerMonitorData.java` | the saved trio `rflevel`, `minimum`, `maximum` (minimum/maximum are bytes; the module's default is `0, 0`) |
| `modules/monitor/MonitorModule.java` | the recipe (`" P "`, `"rAr"`, `" R "` with McJtyLib's default `r` = redstone, `R` = redstone block) and the six level textures |
| `mcjtylib/.../LogicSupport.java` | `getRedstoneOutput` answers only on `getInputSide()`, while `setRedstoneState` notifies `getInputSide().getOpposite()` — the disagreement the port resolves towards the display face (see `notes.md`, "Upstream defect fixed") |
| `mcjtylib/.../LogicSlabBlock.java`, `varia/LogicFacing.java` | the logic slab's 24-way placement and the input side; the port uses a full cube with a four-way display front (a recorded simplification) |
| `modules/generator/blocks/CoalGeneratorTileEntity.java` (`tickServer`, `handleSendingEnergy`) + `mcjtylib/.../EnergyTools.java` | the push: for each of six directions, `min(SENDPERTICK, stored)` into the neighbour's energy handler on the face toward the generator, the store consumed by what was received; per neighbour, not shared; before generation |
| `modules/monitor/blocks/PowerLevelTileEntity.java` | the sibling display (ratio 0..9 straight to redstone); **not** ported, left in gap 10 |

## Family inventory (the rest of the mod)

From `unzip -l` of the jar plus the module classes: coal generator; powercell `cell1/2/3` with the
side-mode network and the powercell card; power monitor and power level; dimensional cell
(simple/normal/advanced/creative) with card-linked networks; endergenic generator, pearl injector and
ender monitor; blazing generator, agitator and infuser with blazing rods.

## Slice 3: the powercell (read for the same commits)

Files read (`1.21_neo`, `e44463c`):

| File | What it gave |
|---|---|
| `modules/powercell/blocks/PowerCellTileEntity.java` | the tier's capacity/per-side numbers, the six `modes` (fresh all `NONE`), `toggleMode`'s NONE→INPUT→OUTPUT cycle, `saveClientDataToNBT`'s six-digit `mode` string, `receiveEnergyFacing`'s mode test and `Math.min(maxReceive, getRfPerTickReal())` cap, `receiveEnergyLocal`, `sendOutEnergy`/`extractEnergyFromNetwork` (local first, skip other powercells), `SidedHandler` (extract 0), `NullHandler` (no side, takes nothing), the network walk `buildNetwork`, `redistributeNetwork` (per tier *within* one network) and `isValid`'s `networkMax` |
| `modules/powercell/blocks/PowerCellBlock.java` | `wrenchUse → toggleMode(side)`; `getStateForPlacement`/`updateShape`'s `UPPER`/`LOWER` (model connection); `getComponentsToPreserve` = `ITEM_ENERGY`; `setPlacedBy` restores the item's energy and forces a network rebuild |
| `modules/powercell/PowerCellConfig.java` | 500,000 / 4,000,000 / 20,000,000 FE; 250 / 1,000 / 4,000 a side a tick; `rfPerTickScale` 0.25; `networkMax` 729 |
| `modules/powercell/data/{Tier,SideType,PowerCellNetwork}.java` | the tier order and block ids; `SideType` ordinals (NONE 0, OUTPUT 1, INPUT 2); the network's cached energy/capacity and its positions set |
| `modules/powercell/PowerCellModule.java` | cell1/2/3 registration; the cell1 recipe (`"rKr"/"KFK"/"rKr"` with a machine frame and `power_core1`); cell2/3's `copy_components` recipes; the three power-core recipes; `ironPickaxeTags()` |

**The load-bearing finding, against the brief:** the network is **not** same-tier.
`buildNetwork` recurses into every adjacent `PowerCellTileEntity` with no tier test, and
`redistributeNetwork` iterates all three tiers inside one network — so a cell1 and a cell2 side by
side share one store and one summed capacity (4,500,000), and only the *rates* are per cell. The
port implements the artefact; the leg proves adjacency, not tier, decides membership.

The other finding: **the per-side cap is the receive limit**. A 2,000-a-tick neighbour fills a lone
tier-1 cell at 250 a tick, not 2,000; a tier-2 cell at 1,000. The port's leg asserts exactly
`ΔE == 250 × Δt` and the matching loss on the generator.

Recorded simplification: upstream's `PowerCellBlock` declares `upper`/`lower` states for connected
models, but its own `blockstates/cell1.json` has only the `""` variant (a state/model mismatch); the
port draws one plain cube and declares no extra states.

## Slice 4: the endergenic generator and the pearl injector (read for the same commits)

Files read (`1.21_neo`, `e44463c`), plus McJtyLib `1.21_neo` `ef393e6`:

| File | What it gave |
|---|---|
| `modules/endergenic/blocks/EndergenicTileEntity.java` | the tick order (`handlePearls` → `handleSendingEnergy` → the loss chance → the pulse → idle/holding/charging); the charging modes (1…15, idle at 16); the `CHARGE_IDLE`/`CHARGE_HOLDING` sentinels; the `rfPerHit` table; `receivePearl`'s three branches and the age bonus; `firePearl`/`firePearlFromInjector`; `discardPearl` and its four reasons; the 500-a-tick hold with the infusable factor; `handleSendingEnergy` over `energy - ENDERGENIC_KEEPRF`; `calculateDistance`; the saved fields (`charging`, `age`, `dest`, `distance`, `prevIn`, `pearls`, `energy`); the loot's `item_energy` copy; the wrench's link and the "maximum 4" refusal |
| `modules/endergenic/blocks/PearlInjectorTileEntity.java` | the 9×2 pearl buffer (`BUFFER_SIZE`), `itemValid(match(ENDER_PEARL))`, the rising-edge `injectPearl` (take the pearl, then fire unless the generator is holding), `findEndergenicTileEntity` (behind the front, else UP) |
| `modules/endergenic/data/EndergenicPearl.java` | the flight: `ticksLeft--`, arrive at `<= 0`, deliver to the destination's `receivePearl(age)` |
| `modules/endergenic/EndergenicConfiguration.java` | 5,000,000 FE; `chanceLost` 5; 500 a tick to hold; `endergenicKeepRf` 2,000; 20,000 a tick out; `powergenFactor` 2.0 |
| `modules/endergenic/EndergenicModule.java` | the two recipes (`"dod"/"ZFZ"/"dod"` and `" C "/"rFr"/" H "`), the block properties, the ender monitor and its `EnderMonitorData`/`EnderMonitorMode` (phase 2) |
| `mcjtylib/.../GenericTileEntity.java`, `blocks/BaseBlock.java` | `checkRedstone` = `world.getBestNeighborSignal(pos)` on a neighbour change and on placement; `powerLevel` saved as a byte; `RotationType.ROTATION`'s `getStateForPlacement` uses `OrientationTools.getFacingFromEntity` |
| `modules/endergenic/blocks/EnderMonitorTileEntity.java`, `data/EnderMonitorMode.java` | the phase-2 family: three modes (`MODE_LOSTPEARL`, `MODE_PEARLFIRED`, `MODE_PEARLARRIVED`); `fireFromEndergenic` sets `needpulse` only when the mode it watches matches; the tick puts **15** on the redstone output for that one tick (`support.setRedstoneState`); rank 2; saved `rs`/`needPulse`; the mode rides on the item's own component |
| `modules/endergenic/client/GuiEndergenic.java`, `EndergenicRenderer.java` | what the GUI and the renderer show (a gap: no GUI, no renderer in this slice) |

**The load-bearing finding:** the *power* of a pearl is not a constant — it is the arrival **mode**
looked up in a 16-entry table, so the mechanic is the timing window. A pearl that arrives at mode 1
pays 200 FE and one at mode 10 pays 25,600; the window closes at mode 16, and an arrival while idle
loses the pearl. The port therefore asserts `gained == rfPerHit[arrived] × 2` against the mode the
readout reports, instead of a fixed amount.

Second finding: the endergenic's buffer **answers** the energy capability but refuses insert and
extract — it gives FE out only through its own tick's push, `energy - 2,000` a tick, capped at
20,000. The 2,000 reserve is what a held pearl lives on, and the leg proves exactly it (100,000 in,
2,000 left, 98,000 in the receiver).
