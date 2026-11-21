# RFTools Power slice 1 — the carried content

`assets/` and `data/` at the package root are generated from two jars by
[`tools/assemble_content.py`](tools/assemble_content.py); rerun it to rebuild, or `--check` to
re-derive into a temporary tree and compare (`ok: 63 entries re-derive exactly`). They ship inside
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
| `data/minecraft/tags/block/{mineable/pickaxe,needs_iron_tool}.json` | both blocks (upstream's `ironPickaxeTags()`) |

## Patched, because 1.21.1 → 26.3 differs

| File | Patch |
|---|---|
| the recipe | `{"item": X}` → 26.3's bare id, `{"tag": T}` → `#T` (the 1.21.1 object form is an unknown ingredient) |
| the loot table | the `copy_components` function is removed (it names mcjtylib's `item_energy`, `item_inventory` and `infusable` components, which this port does not register); `copy_name` stays. The store travels through `minecraft:block_entity_data`, written by `Hooks::block_drops` |
| the block model | `rftoolsbase:block/base/…` → `rftoolspower:block/base/…` (the base textures travel in this package) |
| `coalgenerator_on.json` | the jar's parent is `rftoolsbase:block/rftoolsblock_glow`, a custom glow-overlay model with an animated `coalgenerator_glow.png`; the pin cannot run it, so the lit variant is the same cube. The `lit` state is real; the overlay is a recorded gap |
| the advancement | the predicate rewritten to 26.3's `{"items": […]}` shape under `conditions` |
| the lang | only the three keys this slice can show (block name, tab, shift line); upstream's GUI and tooltip strings are not carried because nothing reads them |

## What the content cannot do alone

- **The monitor's recipe needs `rftoolsbase:machine_base`** (the parent port declares it), so with
  only this package the pattern crafts nothing (`phase T` proves the negative).
- **The recipe needs `rftoolsbase:machine_frame`**, an item the `rftoolsbase` port's content
  declares (`data/rftoolsbase/horizon/item/machine_frame.json`). A game with only this port has the
  recipe loaded but uncraftable, so the e2e proves the pattern crafts nothing without it (`phase M`).
  With both ports installed the recipe works as upstream's does.
- **The `lit` overlay** (see above): the block is dark or lit by its state, not by a glow layer.
- **The GUI textures** (`assets/rftoolspower/textures/gui/coalgenerator.png`) are not carried: there
  is no menu in this slice.
