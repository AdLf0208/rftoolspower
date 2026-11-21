# RFTools Power — upstream behaviour extracted (slice 1)

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

## Family inventory (the rest of the mod)

From `unzip -l` of the jar plus the module classes: coal generator; powercell `cell1/2/3` with the
side-mode network and the powercell card; power monitor and power level; dimensional cell
(simple/normal/advanced/creative) with card-linked networks; endergenic generator, pearl injector and
ender monitor; blazing generator, agitator and infuser with blazing rods.
