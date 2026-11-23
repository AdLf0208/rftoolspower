# RFTools Power slice 1 — the carried content

`assets/` and `data/` at the package root are generated from two jars by
[`tools/assemble_content.py`](tools/assemble_content.py); rerun it to rebuild, or `--check` to
re-derive into a temporary tree and compare (`ok: 127 entries re-derive exactly`). They ship inside
the SDK package `rftoolspower.hmod`, beside `src/` and `horizon-mod.toml`.

The two jars, both MIT, both already in this campaign's licence cache:

- `ports/_shared/licence-cache/rftoolspower-1.21-7.0.6.jar`, SHA-256 `259ebd61…f5d8` — the mod
  itself (the blockstate, the two block models, the item model, the front texture, the recipe, the
  loot table, the advancement, the lang);
- `ports/_shared/licence-cache/rftoolsbase-1.21-6.0.11.jar`, SHA-256 `5195ba53…4b00` — the three
  machine base textures the generator's own model names (`rftoolsbase:block/base/…`). A package
  must stand alone (one `.hmod`, no second content package), so they are copied into this namespace
  and the model re-pointed, exactly as `rftoolsutility` did for its tank.

Nothing is invented. Everything below that is not a straight copy is a change 26.3 forces.

## Carried from the jar

| File | Why |
|---|---|
| `assets/rftoolspower/blockstates/coalgenerator.json` | the jar's twelve `facing`×`lit` variants, byte for byte |
| `assets/rftoolspower/textures/block/coalgenerator.png` | the generator's front (`north`) |
| `data/rftoolspower/recipe/coalgenerator.json` | 4 coals + 2 redstone torches around a machine frame |
| `data/rftoolspower/advancement/recipes/misc/coalgenerator.json` | the recipe unlock |
| `data/rftoolspower/loot_table/blocks/coalgenerator.json` | the block's drop |
| `assets/rftoolspower/lang/en_us.json` (4 keys) | both block names, the tab title, upstream's shift line |
| `assets/rftoolspower/textures/block/monitor/power_monitor0..5.png` | the monitor's six display faces (level 0–5) |

## Carried from the rftoolsbase jar (the parent's art, into this namespace)

| File | Why |
|---|---|
| `assets/rftoolspower/textures/block/base/machineside.png` | the model's four sides |
| `…/machinebottom.png`, `…/machinetop.png` | down / up |

## Written by the assembler

| File | What |
|---|---|
| `assets/rftoolspower/models/block/coalgenerator.json` | the jar's cube model with its base textures re-pointed into this namespace |
| `assets/rftoolspower/models/block/coalgenerator_on.json` | the same cube (see the patch list) |
| `assets/rftoolspower/models/item/coalgenerator.json` | the item model (`parent: rftoolspower:block/coalgenerator`, the jar's own) |
| `assets/rftoolspower/items/coalgenerator.json` | the 26.3 item definition (`minecraft:model` → `rftoolspower:item/coalgenerator`) |
| `data/rftoolspower/horizon/block/coalgenerator.json` | the block: `minecraft:furnace` template (its `facing` and `lit`), hardness 2.0 / blast 2.0, correct tool, metal sound |
| `data/rftoolspower/horizon/creative_tab/rftoolspower.json` | `itemGroup.rftoolspower`, the generator and the monitor |
| `assets/rftoolspower/blockstates/power_monitor.json` | the 48 `facing`×`level`×`lit` variants, one cube model per level with the display on the model's `north` face |
| `assets/rftoolspower/models/block/power_monitor0..5.json` | one cube per level (the display texture on `north`, the base textures elsewhere) |
| `assets/rftoolspower/models/item/power_monitor.json`, `assets/rftoolspower/items/power_monitor.json` | the item model and the 26.3 item definition |
| `data/rftoolspower/horizon/block/power_monitor.json` | the monitor: `minecraft:furnace` template (its `facing` and `lit`), a declared `level` enum 0–5, hardness 2.0 / blast 2.0, pickaxe, iron sound |
| `data/rftoolspower/recipe/power_monitor.json` | comparator / redstone / machine base / redstone block (`" P "`, `"rAr"`, `" R "`) |
| `data/rftoolspower/advancement/recipes/misc/power_monitor.json` | the recipe unlock (machine base) |
| `data/rftoolspower/loot_table/blocks/power_monitor.json` | the monitor's drop |
| `data/minecraft/tags/block/{mineable/pickaxe,needs_iron_tool}.json` | every block (upstream's `ironPickaxeTags()`) |

Slice 3 adds:

| File | What |
|---|---|
| `assets/rftoolspower/blockstates/cell1.json`, `cell2.json` | the jar's own single-variant blockstates |
| `assets/rftoolspower/models/block/cell1.json`, `cell2.json` | a plain `cube_all` with `cellboth_t1`/`_t2` (the jar's model, parent qualified as `minecraft:block/cube_all`) |
| `assets/rftoolspower/textures/block/powercell/cellboth_t1.png`, `_t2.png` (+ `.mcmeta`) | the cells' animated faces, byte for byte |
| `assets/rftoolspower/models/item/cell1.json`, `cell2.json`, `power_core1.json` | the item models (`item/handheld` qualified to `minecraft:item/handheld` for the core) |
| `assets/rftoolspower/items/cell1.json`, `cell2.json`, `power_core1.json` | the 26.3 item definitions |
| `assets/rftoolspower/textures/item/power_core1.png` | the core's texture, byte for byte |
| `data/rftoolspower/horizon/block/cell1.json`, `cell2.json` | a plain full cube (`minecraft:iron_block` template), hardness 2.0 / blast 2.0, pickaxe, iron sound |
| `data/rftoolspower/horizon/item/power_core1.json` | the core is a **pure item**, so it needs its own declaration (`minecraft:stick` template) — without it a recipe still crafts but `give` refuses the id |
| `data/rftoolspower/recipe/cell1.json` | redstone / power core / machine frame (`"rKr"/"KFK"/"rKr"`), the jar's own |
| `data/rftoolspower/recipe/power_core1.json` | diamond / redstone / redstone block (`" d "/"rRr"/" r "`), the jar's own |
| `data/rftoolspower/advancement/recipes/misc/{cell1,power_core1}.json` | the two recipe unlocks, in the jar's own (26.3-shaped) predicate form |
| `data/rftoolspower/loot_table/blocks/cell1.json`, `cell2.json` | the block drop (`copy_name` kept; `copy_components` dropped — the store rides on `block_entity_data`) |
| `assets/rftoolspower/lang/en_us.json` | + `block.rftoolspower.cell1`/`cell2`, `item.rftoolspower.power_core1` (upstream's names) |
| `data/rftoolspower/horizon/creative_tab/rftoolspower.json` | + the two cells and the core |

Slice 4 adds:

| File | What |
|---|---|
| `assets/rftoolspower/blockstates/endergenic.json` | the jar's own single-variant blockstate |
| `assets/rftoolspower/blockstates/pearl_injector.json` | the jar's six `facing` variants, byte for byte (the model rotated by `x`/`y`) |
| `assets/rftoolspower/models/block/endergenic.json` | `cube_all` with `endergenic/endergenic` (the jar's model, minus its `render_type`) |
| `assets/rftoolspower/models/block/pearl_injector.json` | the jar's front-based cube with the base textures re-pointed into this namespace |
| `assets/rftoolspower/models/item/{endergenic,pearl_injector}.json`, `assets/rftoolspower/items/{…}.json` | the item models and the 26.3 item definitions |
| `assets/rftoolspower/textures/block/endergenic/{endergenic,pearl_injector}.png` | the two textures, byte for byte |
| `data/rftoolspower/horizon/block/endergenic.json` | a plain full cube (`minecraft:iron_block` template), hardness 2.0 / blast 2.0, pickaxe, iron sound |
| `data/rftoolspower/horizon/block/pearl_injector.json` | the same cube plus a declared six-way `facing` enum (the injector's `RotationType.ROTATION`) |
| `data/rftoolspower/recipe/endergenic.json` | `"dod"/"ZFZ"/"dod"` — diamonds, the `#c:ender_pearls` tag, `rftoolsbase:infused_enderpearl`, `rftoolsbase:machine_frame` |
| `data/rftoolspower/recipe/pearl_injector.json` | `" C "/"rFr"/" H "` — the `#c:chests` tag, redstone, `rftoolsbase:machine_frame`, a hopper |
| `data/rftoolspower/advancement/recipes/misc/{endergenic,pearl_injector}.json` | the two recipe unlocks, in the jar's own shape |
| `data/rftoolspower/loot_table/blocks/{endergenic,pearl_injector}.json` | the block drops (`copy_name` kept, `copy_components` dropped — see below) |
| `assets/rftoolspower/lang/en_us.json` | + `block.rftoolspower.endergenic`/`pearl_injector` |
| `data/minecraft/tags/block/…`, `data/rftoolspower/horizon/creative_tab/rftoolspower.json` | both blocks in the tags and the tab |

Two of the new recipes' ingredients — `rftoolsbase:infused_enderpearl` and the `#c:chests` /
`#c:ender_pearls` tags — do not exist in a build without the parent (and 26.3 ships no `c:` tags at
all), so the recipes load but cannot match; `notes.md`'s phase AK proves both patterns craft
nothing here.

Slice 5 adds the ender monitor:

| File | What |
|---|---|
| `assets/rftoolspower/blockstates/ender_monitor.json` | the jar's `ender_monitor_0` model in four `facing` rotations (upstream's `logic_facing` display side) and both `lit` values (one model, as upstream's) |
| `assets/rftoolspower/models/block/ender_monitor_0.json` | the jar's thin plate (`0..4/16`), its `ender_monitor` texture on the display face and the base textures on the rest |
| `assets/rftoolspower/models/item/ender_monitor.json`, `assets/rftoolspower/items/ender_monitor.json` | the item model and the 26.3 item definition |
| `assets/rftoolspower/textures/block/endergenic/ender_monitor.png` | the jar's own texture, byte for byte |
| `data/rftoolspower/horizon/block/ender_monitor.json` | an iron base cube with a `facing` enum (north/south/east/west) and a boolean `lit`; hardness 2.0 / blast 2.0, pickaxe, iron sound; the plate's collision shape follows `facing` |
| `data/rftoolspower/recipe/ender_monitor.json` | `" o "/"rAr"/"TrT"` — an ender pearl, redstone, redstone torches and `rftoolsbase:machine_base` |
| `data/rftoolspower/advancement/recipes/misc/ender_monitor.json` | the recipe unlock, in the 26.3 predicate shape |
| `data/rftoolspower/loot_table/blocks/ender_monitor.json` | the block drop (`copy_name` kept; the mode travels through `block_entity_data`, written by `Hooks::block_drops`) |
| `assets/rftoolspower/lang/en_us.json` | + `block.rftoolspower.ender_monitor` |
| `data/minecraft/tags/block/…`, `data/rftoolspower/horizon/creative_tab/rftoolspower.json` | the block in the tags and the tab |

Slice 6 adds the power level display:

| File | What |
|---|---|
| `assets/rftoolspower/blockstates/power_level.json` | 40 variants (`facing` four ways × `power` 0–9), all the jar's `power_level_0` plate rotated onto the display side |
| `assets/rftoolspower/models/block/power_level_0.json` | the jar's 4/16 plate (its screen on the `up` face), the base textures re-pointed into this namespace; models 1–3 differ only in the `up` texture's UV rotation, which a four-way `facing` never needs |
| `assets/rftoolspower/models/item/power_level.json`, `assets/rftoolspower/items/power_level.json` | the item model and the 26.3 item definition |
| `assets/rftoolspower/textures/block/monitor/power_level.png` | the plate's screen texture, byte for byte |
| `data/rftoolspower/horizon/block/power_level.json` | an iron base plate with a `facing` enum and a `power` enum 0–9 (the ratio's carrier, the redstone output's state at this pin); hardness 2.0 / blast 2.0, pickaxe, iron sound; the plate's shape follows `facing` |
| `data/rftoolspower/recipe/power_level.json` | `" P "/"rAr"/" R "` — a glass-pane tag, redstone, `rftoolsbase:machine_base` and a redstone block |
| `data/rftoolspower/advancement/recipes/misc/power_level.json` | the recipe unlock, in the 26.3 predicate shape |
| `data/rftoolspower/loot_table/blocks/power_level.json` | the block drop (plain: upstream keeps no component on its item) |
| `assets/rftoolspower/lang/en_us.json` | + `block.rftoolspower.power_level` |
| `data/minecraft/tags/block/…`, `data/rftoolspower/horizon/creative_tab/rftoolspower.json` | the block in the tags and the tab |

The ten `powerlevel_0..9` textures belong to upstream's `PowerLevelRenderer` (the visual reading),
which this `machines` slice does not carry; the block model only names the base `power_level.png`.

## Patched, because 1.21.1 → 26.3 differs

| File | Patch |
|---|---|
| the recipe | `{"item": X}` → 26.3's bare id, `{"tag": T}` → `#T` (the 1.21.1 object form is an unknown ingredient) |
| the loot table | the `copy_components` function is removed (it names mcjtylib's `item_energy`, `item_inventory` and `infusable` components, which this port does not register); `copy_name` stays. The store travels through `minecraft:block_entity_data`, written by `Hooks::block_drops` |
| the block model | `rftoolsbase:block/base/…` → `rftoolspower:block/base/…` (the base textures travel in this package) |
| `coalgenerator_on.json` | the jar's parent is `rftoolsbase:block/rftoolsblock_glow`, a custom glow-overlay model with an animated `coalgenerator_glow.png`; the pin cannot run it, so the lit variant is the same cube. The `lit` state is real; the overlay is a recorded gap |
| the advancement | the predicate rewritten to 26.3's `{"items": […]}` shape under `conditions` (the cell/core files already ship that shape) |
| the cell recipes | the 1.21.1 `{"item": X}` ingredient objects become bare ids (`{"tag": T}` → `#T`) |
| `cell2`'s recipe | **not carried**: McJtyLib's `copy_components` wrapper around a shaped recipe needing `power_core2`, whose recipe needs `rftoolsbase:dimensional_shard` — a parent item this build does not carry, so it could never craft |
| the lang | only the three keys this slice can show (block name, tab, shift line); upstream's GUI and tooltip strings are not carried because nothing reads them |

## Slice 7 — the blazing generator and the blazing rod

| File | What |
|---|---|
| `assets/rftoolspower/blockstates/blazing_generator.json` | the jar's own twelve variants (`facing` × `working`, with the `x` rotations for up/down), byte for byte |
| `assets/rftoolspower/models/block/blazing_generator_idle.json`, `…_busy.json` | the jar's two front models, with `rftoolsbase:block/base/…` re-pointed at this package's copies |
| `assets/rftoolspower/models/item/blazing_generator.json` | the jar's (parent: the busy model) |
| `assets/rftoolspower/textures/block/blazing/blazing_generator_idle.png`, `…_busy.png` (+`.mcmeta`) | the idle front and the animated busy front, byte for byte |
| `data/rftoolspower/horizon/block/blazing_generator.json` | an iron machine cube with a six-way `facing` (the jar's `BlockStateProperties.FACING`) and the `working` boolean; hardness 2.0 / blast 2.0, pickaxe, iron sound |
| `data/rftoolspower/loot_table/blocks/blazing_generator.json` | `copy_name` only; the store travels through `minecraft:block_entity_data` (the `copy_components` function names mcjtylib's components, which this port does not register) |
| `data/rftoolspower/recipe/blazing_generator.json` | `"XYX"/"RFR"/"XYX"` — `#c:rods/blaze`, `rftoolsbase:infused_diamond`, redstone blocks and `rftoolsbase:machine_frame` |
| `data/rftoolspower/advancement/recipes/misc/blazing_generator.json` | the recipe unlock, in the 26.3 predicate shape |
| `assets/rftoolspower/models/item/blazing_rod.json`, `assets/rftoolspower/items/blazing_rod.json`, `assets/rftoolspower/textures/item/blazing_rod.png` (+`.mcmeta`) | the rod's handheld model, its item definition and its animated texture, byte for byte |
| `data/rftoolspower/horizon/item/blazing_rod.json` | the rod as a plain item: `minecraft:blaze_rod`'s 64-stack template **minus `minecraft:cooking_fuel`** — upstream's `BlazingRod extends Item` with `new Item.Properties()` is not furnace fuel, and the template would make it one |
| `assets/rftoolspower/lang/en_us.json` | + `block.rftoolspower.blazing_generator`, `item.rftoolspower.blazing_rod` |
| `data/minecraft/tags/block/…`, `data/rftoolspower/horizon/creative_tab/rftoolspower.json` | the block in the pickaxe and needs-iron-tool tags, both entries in the tab |

The rod's own data is **not** content: it is the mod component `rftoolspower:blazing_rod_data`
(`{steps, time, quality, duration}`), registered by `Hooks::component_types` and read and written
through [`mod_api::Component`] on the stack (`src/support.rs`). A rod crafted or given without the
component reads upstream's default row `(64, 1200, 60000, 20)`, exactly as upstream's
`getOrDefault(…, BlazingRodData.DEFAULT)` answers.

The `blazing` blockstate's `up`/`down` variants are the jar's: the placement hook can only set a
horizontal front (the pin's placement context carries the placer's view angles, not its height), the
same limit the pearl injector records; `setblock … [facing=up]` still draws what the jar draws.

## Slice 8 — the blazing agitator

| File | What |
|---|---|
| `assets/rftoolspower/blockstates/blazing_agitator.json` | the jar's own single-variant blockstate, byte for byte |
| `assets/rftoolspower/models/block/blazing_agitator.json` | the jar's `minecraft:block/slab` model, with `rftoolsbase:block/base/…` re-pointed at this package's copies |
| `assets/rftoolspower/models/item/blazing_agitator.json`, `assets/rftoolspower/items/blazing_agitator.json` | the item model (parent: the block) and its item definition |
| `assets/rftoolspower/textures/block/blazing/blazing_agitator_side.png` | the jar's own side texture, byte for byte |
| `data/rftoolspower/horizon/block/blazing_agitator.json` | an iron machine with **no state at all** (`RotationType.NONE`), a slab shape and collision box (`Shapes.box(0, 0, 0, 1, 0.5, 1)`), hardness 2.0 / blast 2.0, pickaxe, iron sound |
| `data/rftoolspower/loot_table/blocks/blazing_agitator.json` | `copy_name` only; the store and the nine locks travel through `minecraft:block_entity_data` |
| `data/rftoolspower/recipe/blazing_agitator.json` | `"XXX"/"GFG"/"iii"` — `#c:rods/blaze`, `#c:glass_blocks`, `rftoolsbase:machine_frame` and `#c:ingots/iron` |
| `data/rftoolspower/advancement/recipes/misc/blazing_agitator.json` | the recipe unlock, in the 26.3 predicate shape |
| `assets/rftoolspower/lang/en_us.json` | + `block.rftoolspower.blazing_agitator` |
| `data/minecraft/tags/block/…`, `data/rftoolspower/horizon/creative_tab/rftoolspower.json` | the block in the pickaxe and needs-iron-tool tags, in the tab |

The agitator's GUI texture (`blazing_agitator.png`) and its `.gui` file are **not** carried: no menu
in this tier. Its `rftoolspower:agitator_data` component is upstream's **block** attachment (the nine
locks); here the locks are the saved `lock0..lock8` bytes of the block entity's compound, which is
what `minecraft:block_entity_data` carries on a broken agitator's item.

## Slice 9 — the blazing infuser

| File | What |
|---|---|
| `assets/rftoolspower/blockstates/blazing_infuser.json` | the jar's own six `facing` variants, byte for byte |
| `assets/rftoolspower/models/block/blazing_infuser.json` | the jar's front model, with `rftoolsbase:block/base/…` re-pointed at this package's copies |
| `assets/rftoolspower/models/item/blazing_infuser.json`, `assets/rftoolspower/items/blazing_infuser.json` | the item model (parent: the block) and its item definition |
| `assets/rftoolspower/textures/block/blazing/blazing_infuser.png` | the jar's own front texture, byte for byte |
| `data/rftoolspower/horizon/block/blazing_infuser.json` | an iron machine cube with a six-way `facing` (the jar's `orientedBlock`/`frontBasedModel`), hardness 2.0 / blast 2.0, pickaxe, iron sound |
| `data/rftoolspower/loot_table/blocks/blazing_infuser.json` | `copy_name` only; the store travels through `minecraft:block_entity_data` |
| `data/rftoolspower/recipe/blazing_infuser.json` | `"iXi"/"sFs"/"iXi"` — `#c:rods/blaze`, `#c:ingots/iron`, `rftoolsbase:dimensionalshard` and `rftoolsbase:machine_frame` |
| `data/rftoolspower/advancement/recipes/misc/blazing_infuser.json` | the recipe unlock, in the 26.3 predicate shape |
| `assets/rftoolspower/lang/en_us.json` | + `block.rftoolspower.blazing_infuser` |
| `data/minecraft/tags/block/…`, `data/rftoolspower/horizon/creative_tab/rftoolspower.json` | the block in the pickaxe and needs-iron-tool tags, in the tab |

The infuser's GUI texture (`assets/rftoolspower/textures/gui/blazing_infuser.png`) and its `.gui`
file are **not** carried: no menu at this tier. The catalyst's item filter is upstream's
`slotDefinition` predicate, which this pin has no per-slot form of; the click refuses a non-catalyst
and the tick ignores one.

## Patched, because 1.21.1 → 26.3 differs (slice 9)

| File | Patch |
|---|---|
| the infuser's model | `rftoolsbase:block/base/…` → `rftoolspower:block/base/…` (the base textures travel in this package) |
| the loot table | `copy_components` removed as above; the store rides on `minecraft:block_entity_data` |
| the recipe | `{"item": X}` → bare ids, `{"tag": T}` → `#T`; `#c:rods/blaze` and `#c:ingots/iron` are **not** 26.3 tags and `rftoolsbase:dimensionalshard`/`machine_frame` are the parent's, so it loads with unresolved-tag errors and can never match here (`phase BS` proves the pattern crafts nothing) |

## Patched, because 1.21.1 → 26.3 differs (slice 7)

| File | Patch |
|---|---|
| the two block models | `rftoolsbase:block/base/…` → `rftoolspower:block/base/…` (the base textures travel in this package) |
| the loot table | `copy_components` removed as above; the store rides on `minecraft:block_entity_data` |
| `blazing_rod`'s item | `!minecraft:cooking_fuel` — the blaze-rod template is fuel, upstream's rod is not |
| the recipe | `{"item": X}` → bare ids, `{"tag": T}` → `#T`; `#c:rods/blaze` is **not** a 26.3 tag, so the recipe loads with an unresolved-tag error and can never match here (`phase BE` proves the pattern crafts nothing) |
| the lang | only the two names; upstream's tooltip (`power … RF/t`, `duration … ticks`) and GUI strings are not carried, because nothing reads them at this tier |

## Patched, because 1.21.1 → 26.3 differs (slice 8)

| File | Patch |
|---|---|
| the agitator's model | `rftoolsbase:block/base/…` → `rftoolspower:block/base/…` (the base textures travel in this package) |
| the loot table | `copy_components` removed as above; the store and the locks ride on `minecraft:block_entity_data` |
| the recipe | `{"item": X}` → bare ids, `{"tag": T}` → `#T`; `#c:rods/blaze`, `#c:glass_blocks` and `#c:ingots/iron` are **not** 26.3 tags, so it loads with unresolved-tag errors and can never match here (`phase BN` proves the pattern crafts nothing) |
| the lang | only the block's name; upstream's header/gold tooltip lines are not carried, because nothing reads them at this tier |

## What the content cannot do alone

- **The monitor's recipe needs `rftoolsbase:machine_base`** (the parent port declares it), so with
  only this package the pattern crafts nothing (`phase T` proves the negative). The ender monitor's
  and the power level's recipes need the same parent item, and both also name a `c:` tag 26.3 does
  not ship (`#c:chests`/`#c:ender_pearls`, `#c:glass_panes`), so they load with an unresolved-tag
  error and can never match here (`phase AS`, `phase AW`).
- **The recipes need `rftoolsbase:machine_frame`** (the generator's and cell1's), an item the
  `rftoolsbase` port's content declares (`data/rftoolsbase/horizon/item/machine_frame.json`). A game
  with only this port has the recipes loaded but uncraftable, so the e2e proves the patterns craft
  nothing without it (`phase M`, `phase AC`). With both ports installed the recipes work as
  upstream's do. The power core's recipe needs only vanilla items, so it is proven to craft in this
  build (`phase AC`).
- **The `lit` overlay** (see above): the block is dark or lit by its state, not by a glow layer.
- **The GUI textures** (`assets/rftoolspower/textures/gui/coalgenerator.png`) are not carried: there
  is no menu in this slice.
- **The blazing agitator's recipe needs `rftoolsbase:machine_frame`** and the absent
  `#c:rods/blaze`/`#c:glass_blocks`/`#c:ingots/iron` tags: with only this package the pattern crafts
  nothing (`phase BN`).
- **The blazing infuser's recipe needs the parent twice** — `rftoolsbase:machine_frame` and
  `rftoolsbase:dimensionalshard` — and its rods name the `#c:rods/blaze` tag: with only this package
  the pattern crafts nothing (`phase BS`).
- **The blazing generator's recipe needs the parent twice** — `rftoolsbase:machine_frame` and
  `rftoolsbase:infused_diamond` — and its rods name the `#c:rods/blaze` tag, which 26.3 does not
  ship: with only this package the pattern crafts nothing (`phase BE`). Its loot keeps the store
  (upstream copies `mcjtylib:item_energy`) but not the rods in its slots, which the engine keeps
  apart from the payload (gap 8's shape).
