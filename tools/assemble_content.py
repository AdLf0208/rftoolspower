#!/usr/bin/env python3
"""Build the coal generator's carried content from the two jars, reproducibly.

    python3 tools/assemble_content.py [--check]

`assets/` and `data/` at the package root are this script's output. `--check` rebuilds into a
temporary tree and compares it byte for byte with what is on disk, exiting 1 on any drift — the
same rule the campaign's other carries use.

Two jars are read, both MIT and both already in this campaign's licence cache:

* `rftoolspower-1.21-7.0.6.jar` — the mod itself: the blockstate, the two block models, the item
  model, the front texture, the recipe, the loot table, the advancement and the lang lines.
* `rftoolsbase-1.21-6.0.11.jar` — the three machine base textures the generator's own model names
  (`rftoolsbase:block/base/…`). A package must stand alone (one `.hmod`, no second content package),
  so they are copied into this namespace and the model re-pointed, exactly as `rftoolsutility` did
  for its tank.

Nothing is invented. The only edits are the ones 26.3 forces, each listed in CONTENT.md:

* the base-texture namespace in the model, and the recipe's 1.21.1 ingredient objects (`{"item": X}`)
  → 26.3's bare id / `#tag`;
* the loot table's `copy_components` function, which names mcjtylib components this port does not
  register (the store moves through `minecraft:block_entity_data` instead, in `src/support.rs`);
* the `lit=true` model: the jar's `coalgenerator_on` inherits `rftoolsbase:block/rftoolsblock_glow`,
  a custom glow layer the pin cannot run, so it is the same cube (the `lit` state is real; the glow
  overlay is a recorded gap);
* the advancement's predicate shape, 26.3's `{"items": […]}` under `conditions`.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JARS = ROOT.parent / "_shared" / "licence-cache"
POWER = JARS / "rftoolspower-1.21-7.0.6.jar"
BASE = JARS / "rftoolsbase-1.21-6.0.11.jar"

BLOCK = "coalgenerator"
MONITOR = "power_monitor"
PLAIN_CUBE = {
    "parent": "minecraft:block/cube",
    "textures": {
        "particle": "rftoolspower:block/base/machineside",
        "down": "rftoolspower:block/base/machinebottom",
        "up": "rftoolspower:block/base/machinetop",
        "east": "rftoolspower:block/base/machineside",
        "west": "rftoolspower:block/base/machineside",
        "north": "rftoolspower:block/coalgenerator",
        "south": "rftoolspower:block/base/machineside",
    },
}


def monitor_cube(level: int) -> dict:
    """The monitor's cube for one level: the screen is the model's `north` face."""
    return {
        "parent": "minecraft:block/cube",
        "textures": {
            "particle": "rftoolspower:block/base/machineside",
            "down": "rftoolspower:block/base/machinebottom",
            "up": "rftoolspower:block/base/machinetop",
            "east": "rftoolspower:block/base/machineside",
            "west": "rftoolspower:block/base/machineside",
            "north": f"rftoolspower:block/monitor/{MONITOR}{level}",
            "south": "rftoolspower:block/base/machineside",
        },
    }


# `facing` is the monitor's **read side** (the block it monitors, set from the placer's look);
# the model's `north` face is the screen, so it is rotated onto the opposite side. `y=90` turns
# the model's north face east, as vanilla's furnace blockstate does.
MONITOR_ROTATION = {"south": 0, "west": 90, "north": 180, "east": 270}

MONITOR_DECL = {
    "template": "minecraft:furnace",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "state_properties": {
        "level": {"type": "enum", "values": ["0", "1", "2", "3", "4", "5"]},
    },
    "default_state": {"level": "0"},
    "item": True,
}

# `MonitorModule.initDatagen`: " P " / "rAr" / " R " — comparator, machine base, redstone and a
# redstone block (McJtyLib's recipe builder defines `r` as redstone and `R` as a redstone block).
MONITOR_RECIPE = {
    "type": "minecraft:crafting_shaped",
    "category": "misc",
    "key": {
        "P": "minecraft:comparator",
        "A": "rftoolsbase:machine_base",
        "r": "minecraft:redstone",
        "R": "minecraft:redstone_block",
    },
    "pattern": [" P ", "rAr", " R "],
    "result": {"count": 1, "id": "rftoolspower:power_monitor"},
}

MONITOR_LOOT = {
    "type": "minecraft:block",
    "pools": [
        {
            "bonus_rolls": 0.0,
            "entries": [
                {
                    "type": "minecraft:item",
                    "functions": [
                        {"function": "minecraft:copy_name", "source": "block_entity"}
                    ],
                    "name": "rftoolspower:power_monitor",
                }
            ],
            "name": "power_monitor",
            "rolls": 1.0,
        }
    ],
    "random_sequence": "rftoolspower:blocks/power_monitor",
}

MONITOR_ADVANCEMENT = {
    "parent": "minecraft:recipes/root",
    "criteria": {
        "base": {
            "conditions": {"items": [{"items": "rftoolsbase:machine_base"}]},
            "trigger": "minecraft:inventory_changed",
        },
        "has_the_recipe": {
            "conditions": {"recipe": "rftoolspower:power_monitor"},
            "trigger": "minecraft:recipe_unlocked",
        },
    },
    "requirements": [["has_the_recipe", "base"]],
    "rewards": {"recipes": ["rftoolspower:power_monitor"]},
}

# The block, as `mcjty.lib.builder.BlockBuilder` + McJtyLib's STANDARD_IRON describe it: a full cube
# with the furnace template's `facing` and `lit`, hardness 2.0, blast 2.0, correct tool, metal sound.
BLOCK_DECL = {
    "template": "minecraft:furnace",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "item": True,
}

# `CoalGeneratorModule.initDatagen`: shaped "cTc"/"cFc"/"cTc" with a machine frame in the centre, a
# redstone torch above and below it, and the `minecraft:coals` tag elsewhere.
RECIPE = {
    "type": "minecraft:crafting_shaped",
    "category": "misc",
    "key": {
        "F": "rftoolsbase:machine_frame",
        "T": "minecraft:redstone_torch",
        "c": "#minecraft:coals",
    },
    "pattern": ["cTc", "cFc", "cTc"],
    "result": {"count": 1, "id": "rftoolspower:coalgenerator"},
}

LOOT = {
    "type": "minecraft:block",
    "pools": [
        {
            "bonus_rolls": 0.0,
            "entries": [
                {
                    "type": "minecraft:item",
                    "functions": [
                        {"function": "minecraft:copy_name", "source": "block_entity"}
                    ],
                    "name": "rftoolspower:coalgenerator",
                }
            ],
            "name": "coalgenerator",
            "rolls": 1.0,
        }
    ],
    "random_sequence": "rftoolspower:blocks/coalgenerator",
}

ADVANCEMENT = {
    "parent": "minecraft:recipes/root",
    "criteria": {
        "frame": {
            "conditions": {"items": [{"items": "rftoolsbase:machine_frame"}]},
            "trigger": "minecraft:inventory_changed",
        },
        "has_the_recipe": {
            "conditions": {"recipe": "rftoolspower:coalgenerator"},
            "trigger": "minecraft:recipe_unlocked",
        },
    },
    "requirements": [["has_the_recipe", "frame"]],
    "rewards": {"recipes": ["rftoolspower:coalgenerator"]},
}

LANG = {
    "block.rftoolspower.coalgenerator": "Coal Generator",
    "block.rftoolspower.power_monitor": "Power Monitor",
    "block.rftoolspower.power_level": "Power Level",
    "block.rftoolspower.cell1": "Powercell (Low)",
    "block.rftoolspower.cell2": "Powercell (Medium)",
    "block.rftoolspower.cell3": "Powercell (High)",
    "block.rftoolspower.endergenic": "Endergenic",
    "block.rftoolspower.ender_monitor": "Ender Monitor",
    "block.rftoolspower.pearl_injector": "Pearl Injector",
    "block.rftoolspower.blazing_generator": "Blazing Generator",
    "block.rftoolspower.blazing_agitator": "Blazing Agitator",
    "block.rftoolspower.blazing_infuser": "Blazing Infuser",
    "item.rftoolspower.power_core1": "Power Core (Low)",
    "item.rftoolspower.power_core3": "Power Core (High)",
    "item.rftoolspower.blazing_rod": "Blazing Rod",
    "itemGroup.rftoolspower": "RFTools Power",
    "message.rftoolspower.shiftmessage": "<Press Shift>",
}

CREATIVE_TAB = {
    "icon": "rftoolspower:coalgenerator",
    "items": [
        "rftoolspower:coalgenerator",
        "rftoolspower:power_monitor",
        "rftoolspower:power_level",
        "rftoolspower:cell1",
        "rftoolspower:cell2",
        "rftoolspower:cell3",
        "rftoolspower:endergenic",
        "rftoolspower:ender_monitor",
        "rftoolspower:pearl_injector",
        "rftoolspower:blazing_generator",
        "rftoolspower:blazing_agitator",
        "rftoolspower:blazing_infuser",
        "rftoolspower:blazing_rod",
        "rftoolspower:power_core1",
        "rftoolspower:power_core3",
    ],
    "title": "itemGroup.rftoolspower",
}

TAGS = {
    "data/minecraft/tags/block/mineable/pickaxe.json": [
        "rftoolspower:coalgenerator",
        "rftoolspower:power_monitor",
        "rftoolspower:power_level",
        "rftoolspower:cell1",
        "rftoolspower:cell2",
        "rftoolspower:cell3",
        "rftoolspower:endergenic",
        "rftoolspower:ender_monitor",
        "rftoolspower:pearl_injector",
        "rftoolspower:blazing_generator",
        "rftoolspower:blazing_agitator",
        "rftoolspower:blazing_infuser",
    ],
    "data/minecraft/tags/block/needs_iron_tool.json": [
        "rftoolspower:coalgenerator",
        "rftoolspower:power_monitor",
        "rftoolspower:power_level",
        "rftoolspower:cell1",
        "rftoolspower:cell2",
        "rftoolspower:cell3",
        "rftoolspower:endergenic",
        "rftoolspower:ender_monitor",
        "rftoolspower:pearl_injector",
        "rftoolspower:blazing_generator",
        "rftoolspower:blazing_agitator",
        "rftoolspower:blazing_infuser",
    ],
}

# A powercell is a plain full cube (`PowerCellBlock` has only `upper`/`lower` for its model's
# connection shapes; this slice draws one cell, so the states are not declared) and it is
# McJtyLib's STANDARD_IRON: hardness 2.0, blast 2.0, iron sound, an iron pickaxe's tool.
CELL_DECL = {
    "template": "minecraft:iron_block",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "item": True,
}

# `EndergenicModule.ENDERGENIC`: `Properties.of().strength(2.0f).sound(METAL).noOcclusion()` with
# `RotationType.NONE` — a full cube, no facing. `PEARL_INJECTOR` takes BlockBuilder's default
# STANDARD_IRON and `RotationType.ROTATION`, so it has a six-way `facing` the placer sets.
ENDERGENIC_DECL = {
    "template": "minecraft:iron_block",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "item": True,
}

INJECTOR_DECL = {
    "template": "minecraft:iron_block",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "state_properties": {
        "facing": {
            "type": "enum",
            "values": ["north", "south", "east", "west", "up", "down"],
        },
    },
    "default_state": {"facing": "north"},
    "item": True,
}

ENDERGENIC_CUBE = {
    "parent": "minecraft:block/cube_all",
    # The jar's model asks for `render_type: translucent`; 26.3's models have no such field (checked
    # against the prepared vanilla models), so the cube is opaque — recorded in notes.md.
    "textures": {"all": "rftoolspower:block/endergenic/endergenic"},
}

INJECTOR_CUBE = {
    "parent": "minecraft:block/cube",
    "textures": {
        "down": "rftoolspower:block/base/machinebottom",
        "east": "rftoolspower:block/base/machineside",
        "north": "rftoolspower:block/endergenic/pearl_injector",
        "particle": "rftoolspower:block/endergenic/pearl_injector",
        "south": "rftoolspower:block/base/machineside",
        "up": "rftoolspower:block/base/machinetop",
        "west": "rftoolspower:block/base/machineside",
    },
}

# `EnderMonitorTileEntity` is a `LogicSlabBlock`: a 4/16 plate mounted on the face it was clicked
# against, with the display on its outward face. Its `logic_facing` state has 24 values (six mount
# faces × four display directions); this slice mounts it on a horizontal face only, so its `facing`
# is the **display** direction and the plate sits on the opposite side. The jar's own bottom-plate
# model is rotated by the same x/y pair the jar's blockstate uses for that display direction
# (`facing=east` is the jar's `east_*` geometry), so the plate really is against the generator.
ENDER_MONITOR = "ender_monitor"
ENDER_MONITOR_ROTATION = {
    "north": {"x": -90},
    "south": {"x": 90},
    "east": {"x": 90, "y": 270},
    "west": {"x": 90, "y": 90},
}
# A 4/16 plate on the side the display faces away from.
ENDER_MONITOR_SHAPES = {
    "north": [[0.0, 0.0, 0.75, 1.0, 1.0, 1.0]],
    "south": [[0.0, 0.0, 0.0, 1.0, 1.0, 0.25]],
    "east": [[0.0, 0.0, 0.0, 0.25, 1.0, 1.0]],
    "west": [[0.75, 0.0, 0.0, 1.0, 1.0, 1.0]],
}

ENDER_MONITOR_DECL = {
    "template": "minecraft:iron_block",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "state_properties": {
        "facing": {"type": "enum", "values": ["north", "south", "east", "west"]},
        "lit": {"type": "boolean"},
    },
    "default_state": {"facing": "north", "lit": "false"},
    # `shapes` is the outline *and* the collision box at this pin (`BlockShapes`: "per-state
    # outline and collision boxes"); there is no separate collision key in the loader.
    "shapes": {"property": "facing", "values": ENDER_MONITOR_SHAPES},
    "item": True,
}

POWER_LEVEL = "power_level"
# The same 4/16 plate: the jar's `power_level_0` model carries the screen on its `up` face, so
# that face is the display and the plate lies behind it. Models 1–3 differ only in the `up`
# texture's UV rotation, which a four-way horizontal `facing` never needs.
POWER_LEVEL_ROTATION = ENDER_MONITOR_ROTATION
POWER_LEVEL_SHAPES = ENDER_MONITOR_SHAPES

# Upstream's `PowerLevelTileEntity` has no block state: the ratio lives in its tile entity and is
# written straight to the redstone output. The pin's `block_signal` gets only a state and must
# answer from it, so the ratio is mirrored into a `power` enum (0..9) — the output's carrier, as
# the power monitor's `lit` carries its alarm.
POWER_LEVEL_DECL = {
    "template": "minecraft:iron_block",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "state_properties": {
        "facing": {"type": "enum", "values": ["north", "south", "east", "west"]},
        "power": {
            "type": "enum",
            "values": [str(power) for power in range(10)],
        },
    },
    "default_state": {"facing": "north", "power": "0"},
    "shapes": {"property": "facing", "values": POWER_LEVEL_SHAPES},
    "item": True,
}

# --- the blazing generator and its rod (`BlazingGeneratorTileEntity`, `BlazingRod`).
BLAZING = "blazing_generator"
ROD = "blazing_rod"

# `BlazingGeneratorTileEntity.createBlock` is McJtyLib's STANDARD_IRON with `BlockStateProperties.FACING`
# (the ROTATION default: the front faces the placer) plus its own `WORKING` boolean. The jar's own
# blockstate carries all twelve variants (six faces × working), including the two `x` rotations for
# up/down, which this pin's variant reader supports (`horizon-assets` `Variant::rotations`).
BLAZING_DECL = {
    "template": "minecraft:iron_block",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "state_properties": {
        "facing": {
            "type": "enum",
            "values": ["north", "south", "east", "west", "up", "down"],
        },
        "working": {"type": "boolean"},
    },
    "default_state": {"facing": "north", "working": "false"},
    "item": True,
}

# `BlazingRod extends Item` with McJtyLib's `defaultProperties()` (`new Item.Properties()`): a plain
# 64-stack item with no components of its own. The blaze-rod template is the close vanilla item, and
# the one component it would bring is removed: upstream's rod is not furnace fuel.
ROD_DECL = {
    "template": "minecraft:blaze_rod",
    "components": {"!minecraft:cooking_fuel": {}},
}

# --- the blazing agitator (`BlazingAgitatorTileEntity`): a slab, `RotationType.NONE`, so it has no
# state at all. Its model is vanilla's slab with McJty's two base textures and its own side.
AGITATOR = "blazing_agitator"
AGITATOR_DECL = {
    "template": "minecraft:iron_block",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "shapes": {"default": [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0]]},
    "collision_shapes": {"default": [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0]]},
    "item": True,
}

# --- the blazing infuser (`BlazingInfuserTileEntity`): BlockBuilder's STANDARD_IRON with
# `orientedBlock` + `frontBasedModel` — a full cube with a six-way `facing` the placer sets (the
# same `RotationType.ROTATION` the pearl injector takes), and no other state.
INFUSER = "blazing_infuser"
INFUSER_DECL = {
    "template": "minecraft:iron_block",
    "properties": {
        "hardness": 2.0,
        "explosion_resistance": 2.0,
        "sounds": "minecraft:iron_block",
        "requires_tool": True,
    },
    "state_properties": {
        "facing": {
            "type": "enum",
            "values": ["north", "south", "east", "west", "up", "down"],
        },
    },
    "default_state": {"facing": "north"},
    "item": True,
}


def plain_loot(name: str) -> dict:
    """McJtyLib's standard loot with only `copy_name`: the `copy_components` function names
    mcjtylib's own components, which this port does not register (the store travels through
    `minecraft:block_entity_data`, written by `Hooks::block_drops`)."""
    return {
        "type": "minecraft:block",
        "pools": [
            {
                "bonus_rolls": 0.0,
                "entries": [
                    {
                        "type": "minecraft:item",
                        "functions": [
                            {"function": "minecraft:copy_name", "source": "block_entity"}
                        ],
                        "name": f"rftoolspower:{name}",
                    }
                ],
                "name": name,
                "rolls": 1.0,
            }
        ],
        "random_sequence": f"rftoolspower:blocks/{name}",
    }

# `McJtyLib`'s standard loot with the `copy_components` function dropped (it names mcjtylib's
# `item_energy`, which this port does not register); the store travels through
# `minecraft:block_entity_data`, written by `Hooks::block_drops`.
def cell_loot(name: str) -> dict:
    return {
        "type": "minecraft:block",
        "pools": [
            {
                "bonus_rolls": 0.0,
                "entries": [
                    {
                        "type": "minecraft:item",
                        "functions": [
                            {"function": "minecraft:copy_name", "source": "block_entity"}
                        ],
                        "name": f"rftoolspower:{name}",
                    }
                ],
                "name": name,
                "rolls": 1.0,
            }
        ],
        "random_sequence": f"rftoolspower:blocks/{name}",
    }


def read_jar(jar: Path, name: str) -> bytes:
    with zipfile.ZipFile(jar) as archive:
        return archive.read(name)


def build(out: Path) -> None:
    """Write the whole content tree under `out`."""
    # --- assets: the two block models, the item model, the item definition, the textures, lang
    blockstate = json.loads(read_jar(POWER, f"assets/rftoolspower/blockstates/{BLOCK}.json"))

    write(out / f"assets/rftoolspower/blockstates/{BLOCK}.json", blockstate)
    write(out / f"assets/rftoolspower/models/block/{BLOCK}.json", PLAIN_CUBE)
    write(out / f"assets/rftoolspower/models/block/{BLOCK}_on.json", PLAIN_CUBE)
    write(
        out / f"assets/rftoolspower/models/item/{BLOCK}.json",
        {"parent": f"rftoolspower:block/{BLOCK}"},
    )
    write(
        out / f"assets/rftoolspower/items/{BLOCK}.json",
        {"model": {"model": f"rftoolspower:item/{BLOCK}", "type": "minecraft:model"}},
    )
    write(out / "assets/rftoolspower/lang/en_us.json", LANG)

    binary(
        out / f"assets/rftoolspower/textures/block/{BLOCK}.png",
        read_jar(POWER, f"assets/rftoolspower/textures/block/{BLOCK}.png"),
    )
    for texture in ("machineside", "machinebottom", "machinetop"):
        binary(
            out / f"assets/rftoolspower/textures/block/base/{texture}.png",
            read_jar(BASE, f"assets/rftoolsbase/textures/block/base/{texture}.png"),
        )

    # --- data: the block declaration, the tab, the loot table, the recipe, the advancement, tags
    write(out / f"data/rftoolspower/horizon/block/{BLOCK}.json", BLOCK_DECL)
    write(out / "data/rftoolspower/horizon/creative_tab/rftoolspower.json", CREATIVE_TAB)
    write(out / f"data/rftoolspower/loot_table/blocks/{BLOCK}.json", LOOT)
    write(out / f"data/rftoolspower/recipe/{BLOCK}.json", RECIPE)
    write(out / f"data/rftoolspower/advancement/recipes/misc/{BLOCK}.json", ADVANCEMENT)
    for path, values in TAGS.items():
        write(out / path, {"values": values})

    # --- the power monitor: one cube per level, a facing/level/lit blockstate, its item
    variants = {}
    for facing, rotation in MONITOR_ROTATION.items():
        for level in range(6):
            for lit in ("false", "true"):
                variants[f"facing={facing},level={level},lit={lit}"] = {
                    "model": f"rftoolspower:block/{MONITOR}{level}",
                    "y": rotation,
                }
    write(out / f"assets/rftoolspower/blockstates/{MONITOR}.json", {"variants": variants})
    for level in range(6):
        write(out / f"assets/rftoolspower/models/block/{MONITOR}{level}.json", monitor_cube(level))
    write(
        out / f"assets/rftoolspower/models/item/{MONITOR}.json",
        {"parent": f"rftoolspower:block/{MONITOR}5"},
    )
    write(
        out / f"assets/rftoolspower/items/{MONITOR}.json",
        {"model": {"model": f"rftoolspower:item/{MONITOR}", "type": "minecraft:model"}},
    )
    for level in range(6):
        binary(
            out / f"assets/rftoolspower/textures/block/monitor/{MONITOR}{level}.png",
            read_jar(POWER, f"assets/rftoolspower/textures/block/monitor/{MONITOR}{level}.png"),
        )

    write(out / f"data/rftoolspower/horizon/block/{MONITOR}.json", MONITOR_DECL)
    write(out / f"data/rftoolspower/loot_table/blocks/{MONITOR}.json", MONITOR_LOOT)
    write(out / f"data/rftoolspower/recipe/{MONITOR}.json", MONITOR_RECIPE)
    write(out / f"data/rftoolspower/advancement/recipes/misc/{MONITOR}.json", MONITOR_ADVANCEMENT)

    # --- the powercells: tier 1, 2 and 3, one plain cube each, and the power cores that `cell1`
    # and `power_core3` are built from. `cell2`/`cell3`'s own recipes are *not* carried: they are
    # McJtyLib's `copy_components` wrappers around shaped recipes needing `power_core2`/`core3`,
    # whose ingredients include `rftoolsbase:dimensional_shard` — a parent item this build does not
    # carry, so those wrappers could never craft (the cell2 precedent, recorded in notes.md). The
    # plain `crafting_shaped` recipe for `power_core3` *is* carried, exactly like the other items'
    # plain recipes: the leg proves it crafts nothing here without that parent item.
    for tier, name in ((1, "cell1"), (2, "cell2"), (3, "cell3")):
        write(
            out / f"assets/rftoolspower/blockstates/{name}.json",
            {"variants": {"": {"model": f"rftoolspower:block/{name}"}}},
        )
        write(
            out / f"assets/rftoolspower/models/block/{name}.json",
            {
                "parent": "minecraft:block/cube_all",
                "textures": {"all": f"rftoolspower:block/powercell/cellboth_t{tier}"},
            },
        )
        write(
            out / f"assets/rftoolspower/models/item/{name}.json",
            {"parent": f"rftoolspower:block/{name}"},
        )
        write(
            out / f"assets/rftoolspower/items/{name}.json",
            {"model": {"model": f"rftoolspower:item/{name}", "type": "minecraft:model"}},
        )
        for suffix in ("", ".mcmeta"):
            texture = f"assets/rftoolspower/textures/block/powercell/cellboth_t{tier}.png{suffix}"
            binary(out / texture, read_jar(POWER, texture))
        write(out / f"data/rftoolspower/horizon/block/{name}.json", CELL_DECL)
        write(out / f"data/rftoolspower/loot_table/blocks/{name}.json", cell_loot(name))

    write(out / "data/rftoolspower/recipe/cell1.json", patched_recipe("cell1"))
    write(
        out / "data/rftoolspower/advancement/recipes/misc/cell1.json",
        json.loads(read_jar(POWER, "data/rftoolspower/advancement/recipes/misc/cell1.json")),
    )
    write(out / "data/rftoolspower/recipe/power_core1.json", patched_recipe("power_core1"))
    write(
        out / "data/rftoolspower/advancement/recipes/misc/power_core1.json",
        json.loads(
            read_jar(POWER, "data/rftoolspower/advancement/recipes/misc/power_core1.json")
        ),
    )
    write(
        out / "assets/rftoolspower/models/item/power_core1.json",
        {
            "parent": "minecraft:item/handheld",
            "textures": {"layer0": "rftoolspower:item/power_core1"},
        },
    )
    write(
        out / "assets/rftoolspower/items/power_core1.json",
        {"model": {"model": "rftoolspower:item/power_core1", "type": "minecraft:model"}},
    )
    # A pure item is registered by its own horizon/item declaration, not by a block: `give` and a
    # recipe's result both resolve the item registry, and without this file the id exists only as
    # a stack the recipe produced (the e2e caught exactly that: "Unknown item
    # 'rftoolspower:power_core1'"). A stick's template is a plain 64-stack item.
    write(out / "data/rftoolspower/horizon/item/power_core1.json", {"template": "minecraft:stick"})
    binary(
        out / "assets/rftoolspower/textures/item/power_core1.png",
        read_jar(POWER, "assets/rftoolspower/textures/item/power_core1.png"),
    )

    # `power_core3` is the third tier's core: a plain shaped recipe from the jar (its
    # `"sds"/"rRr"/"ses"` needs the parent's dimensional shard, so it crafts nothing in this build
    # — proven in game like every other carried recipe with an absent parent ingredient). Its
    # `copy_components` cell recipe is deliberately not carried.
    write(out / "data/rftoolspower/recipe/power_core3.json", patched_recipe("power_core3"))
    write(
        out / "data/rftoolspower/advancement/recipes/misc/power_core3.json",
        json.loads(
            read_jar(POWER, "data/rftoolspower/advancement/recipes/misc/power_core3.json")
        ),
    )
    write(
        out / "assets/rftoolspower/models/item/power_core3.json",
        {
            "parent": "minecraft:item/handheld",
            "textures": {"layer0": "rftoolspower:item/power_core3"},
        },
    )
    write(
        out / "assets/rftoolspower/items/power_core3.json",
        {"model": {"model": "rftoolspower:item/power_core3", "type": "minecraft:model"}},
    )
    write(out / "data/rftoolspower/horizon/item/power_core3.json", {"template": "minecraft:stick"})
    binary(
        out / "assets/rftoolspower/textures/item/power_core3.png",
        read_jar(POWER, "assets/rftoolspower/textures/item/power_core3.png"),
    )

    # --- the endergenic generator and the pearl injector: the two blocks of the endergenic
    # mechanic. `endergenic` is a plain cube with its own translucent texture (drawn opaque at this
    # pin); the injector is a front-based cube with a six-way `facing`, carried unchanged from the
    # jar. Their recipes need the parent's `machine_frame` (and, for the generator, its
    # `infused_enderpearl`), so both craft nothing in a build without RFToolsBase — recorded in
    # notes.md with the phase that proves it.
    for name, decl, model, texture in (
        (
            "endergenic",
            ENDERGENIC_DECL,
            ENDERGENIC_CUBE,
            "assets/rftoolspower/textures/block/endergenic/endergenic.png",
        ),
        (
            "pearl_injector",
            INJECTOR_DECL,
            INJECTOR_CUBE,
            "assets/rftoolspower/textures/block/endergenic/pearl_injector.png",
        ),
    ):
        write(
            out / f"assets/rftoolspower/blockstates/{name}.json",
            json.loads(read_jar(POWER, f"assets/rftoolspower/blockstates/{name}.json")),
        )
        write(out / f"assets/rftoolspower/models/block/{name}.json", model)
        write(
            out / f"assets/rftoolspower/models/item/{name}.json",
            {"parent": f"rftoolspower:block/{name}"},
        )
        write(
            out / f"assets/rftoolspower/items/{name}.json",
            {"model": {"model": f"rftoolspower:item/{name}", "type": "minecraft:model"}},
        )
        binary(out / texture, read_jar(POWER, texture))
        write(out / f"data/rftoolspower/horizon/block/{name}.json", decl)
        write(out / f"data/rftoolspower/loot_table/blocks/{name}.json", plain_loot(name))
        write(out / f"data/rftoolspower/recipe/{name}.json", patched_recipe(name))
        write(
            out / f"data/rftoolspower/advancement/recipes/misc/{name}.json",
            json.loads(read_jar(POWER, f"data/rftoolspower/advancement/recipes/misc/{name}.json")),
        )

    # --- the ender monitor: the jar's plate model and texture, a facing/lit blockstate (the plate
    # rotated onto the display side), its declaration, loot, recipe and advancement. Models 1–3 of
    # the jar differ only in the display texture's UV rotation, which a horizontal-only `facing`
    # never needs; model 0 carries it.
    variants = {}
    for facing, rotation in ENDER_MONITOR_ROTATION.items():
        for lit in ("false", "true"):
            variant = {"model": f"rftoolspower:block/{ENDER_MONITOR}_0", **rotation}
            variants[f"facing={facing},lit={lit}"] = variant
    write(out / f"assets/rftoolspower/blockstates/{ENDER_MONITOR}.json", {"variants": variants})
    model = json.loads(
        read_jar(POWER, f"assets/rftoolspower/models/block/{ENDER_MONITOR}_0.json")
    )
    model["textures"] = {
        key: value.replace("rftoolsbase:block/base/", "rftoolspower:block/base/")
        for key, value in model["textures"].items()
    }
    write(out / f"assets/rftoolspower/models/block/{ENDER_MONITOR}_0.json", model)
    write(
        out / f"assets/rftoolspower/models/item/{ENDER_MONITOR}.json",
        {"parent": f"rftoolspower:block/{ENDER_MONITOR}_0"},
    )
    write(
        out / f"assets/rftoolspower/items/{ENDER_MONITOR}.json",
        {"model": {"model": f"rftoolspower:item/{ENDER_MONITOR}", "type": "minecraft:model"}},
    )
    binary(
        out / "assets/rftoolspower/textures/block/endergenic/ender_monitor.png",
        read_jar(POWER, "assets/rftoolspower/textures/block/endergenic/ender_monitor.png"),
    )
    write(out / f"data/rftoolspower/horizon/block/{ENDER_MONITOR}.json", ENDER_MONITOR_DECL)
    write(out / f"data/rftoolspower/loot_table/blocks/{ENDER_MONITOR}.json", plain_loot(ENDER_MONITOR))
    write(out / f"data/rftoolspower/recipe/{ENDER_MONITOR}.json", patched_recipe(ENDER_MONITOR))
    write(
        out / f"data/rftoolspower/advancement/recipes/misc/{ENDER_MONITOR}.json",
        json.loads(
            read_jar(POWER, f"data/rftoolspower/advancement/recipes/misc/{ENDER_MONITOR}.json")
        ),
    )

    # --- the power level: the jar's 4/16 plate rotated onto a four-way display side, with the
    # `power` enum the ratio is mirrored into (the output's carrier at this pin). The ten
    # `powerlevel_N` textures belong to upstream's renderer, which this machines slice does not
    # carry; the plate's own `power_level` screen texture is the one the model names.
    variants = {}
    for facing, rotation in POWER_LEVEL_ROTATION.items():
        for power in range(10):
            variants[f"facing={facing},power={power}"] = {
                "model": f"rftoolspower:block/{POWER_LEVEL}_0",
                **rotation,
            }
    write(out / f"assets/rftoolspower/blockstates/{POWER_LEVEL}.json", {"variants": variants})
    model = json.loads(
        read_jar(POWER, f"assets/rftoolspower/models/block/{POWER_LEVEL}_0.json")
    )
    model["textures"] = {
        key: value.replace("rftoolsbase:block/base/", "rftoolspower:block/base/")
        for key, value in model["textures"].items()
    }
    write(out / f"assets/rftoolspower/models/block/{POWER_LEVEL}_0.json", model)
    write(
        out / f"assets/rftoolspower/models/item/{POWER_LEVEL}.json",
        {"parent": f"rftoolspower:block/{POWER_LEVEL}_0"},
    )
    write(
        out / f"assets/rftoolspower/items/{POWER_LEVEL}.json",
        {"model": {"model": f"rftoolspower:item/{POWER_LEVEL}", "type": "minecraft:model"}},
    )
    binary(
        out / "assets/rftoolspower/textures/block/monitor/power_level.png",
        read_jar(POWER, "assets/rftoolspower/textures/block/monitor/power_level.png"),
    )
    write(out / f"data/rftoolspower/horizon/block/{POWER_LEVEL}.json", POWER_LEVEL_DECL)
    write(out / f"data/rftoolspower/loot_table/blocks/{POWER_LEVEL}.json", plain_loot(POWER_LEVEL))
    write(out / f"data/rftoolspower/recipe/{POWER_LEVEL}.json", patched_recipe(POWER_LEVEL))
    write(
        out / f"data/rftoolspower/advancement/recipes/misc/{POWER_LEVEL}.json",
        json.loads(
            read_jar(POWER, f"data/rftoolspower/advancement/recipes/misc/{POWER_LEVEL}.json")
        ),
    )

    # --- the blazing generator: the jar's twelve-variant blockstate (facing × working), its two
    # front models with the base textures re-pointed into this namespace, and the rod item a plain
    # item of its own (its data is the mod component `rftoolspower:blazing_rod_data`).
    write(
        out / f"assets/rftoolspower/blockstates/{BLAZING}.json",
        json.loads(read_jar(POWER, f"assets/rftoolspower/blockstates/{BLAZING}.json")),
    )
    for state in ("idle", "busy"):
        model = json.loads(
            read_jar(POWER, f"assets/rftoolspower/models/block/{BLAZING}_{state}.json")
        )
        model["textures"] = {
            key: value.replace("rftoolsbase:block/base/", "rftoolspower:block/base/")
            for key, value in model["textures"].items()
        }
        write(out / f"assets/rftoolspower/models/block/{BLAZING}_{state}.json", model)
    write(
        out / f"assets/rftoolspower/models/item/{BLAZING}.json",
        {"parent": f"rftoolspower:block/{BLAZING}_busy"},
    )
    write(
        out / f"assets/rftoolspower/items/{BLAZING}.json",
        {"model": {"model": f"rftoolspower:item/{BLAZING}", "type": "minecraft:model"}},
    )
    for texture in (f"{BLAZING}_idle.png", f"{BLAZING}_busy.png", f"{BLAZING}_busy.png.mcmeta"):
        binary(
            out / f"assets/rftoolspower/textures/block/blazing/{texture}",
            read_jar(POWER, f"assets/rftoolspower/textures/block/blazing/{texture}"),
        )
    write(out / f"data/rftoolspower/horizon/block/{BLAZING}.json", BLAZING_DECL)
    write(out / f"data/rftoolspower/loot_table/blocks/{BLAZING}.json", plain_loot(BLAZING))
    write(out / f"data/rftoolspower/recipe/{BLAZING}.json", patched_recipe(BLAZING))
    write(
        out / f"data/rftoolspower/advancement/recipes/misc/{BLAZING}.json",
        json.loads(read_jar(POWER, f"data/rftoolspower/advancement/recipes/misc/{BLAZING}.json")),
    )

    write(
        out / f"assets/rftoolspower/models/item/{ROD}.json",
        json.loads(read_jar(POWER, f"assets/rftoolspower/models/item/{ROD}.json")),
    )
    write(
        out / f"assets/rftoolspower/items/{ROD}.json",
        {"model": {"model": f"rftoolspower:item/{ROD}", "type": "minecraft:model"}},
    )
    for texture in (f"{ROD}.png", f"{ROD}.png.mcmeta"):
        binary(
            out / f"assets/rftoolspower/textures/item/{texture}",
            read_jar(POWER, f"assets/rftoolspower/textures/item/{texture}"),
        )
    write(out / f"data/rftoolspower/horizon/item/{ROD}.json", ROD_DECL)

    # --- the blazing agitator: the jar's single-variant blockstate, its slab model with the base
    # textures re-pointed into this namespace (a package stands alone), and its own item.
    write(
        out / f"assets/rftoolspower/blockstates/{AGITATOR}.json",
        json.loads(read_jar(POWER, f"assets/rftoolspower/blockstates/{AGITATOR}.json")),
    )
    model = json.loads(read_jar(POWER, f"assets/rftoolspower/models/block/{AGITATOR}.json"))
    model["textures"] = {
        key: value.replace("rftoolsbase:block/base/", "rftoolspower:block/base/")
        for key, value in model["textures"].items()
    }
    write(out / f"assets/rftoolspower/models/block/{AGITATOR}.json", model)
    write(
        out / f"assets/rftoolspower/models/item/{AGITATOR}.json",
        {"parent": f"rftoolspower:block/{AGITATOR}"},
    )
    write(
        out / f"assets/rftoolspower/items/{AGITATOR}.json",
        {"model": {"model": f"rftoolspower:item/{AGITATOR}", "type": "minecraft:model"}},
    )
    binary(
        out / f"assets/rftoolspower/textures/block/blazing/{AGITATOR}_side.png",
        read_jar(POWER, f"assets/rftoolspower/textures/block/blazing/{AGITATOR}_side.png"),
    )
    write(out / f"data/rftoolspower/horizon/block/{AGITATOR}.json", AGITATOR_DECL)
    write(out / f"data/rftoolspower/loot_table/blocks/{AGITATOR}.json", plain_loot(AGITATOR))
    write(out / f"data/rftoolspower/recipe/{AGITATOR}.json", patched_recipe(AGITATOR))
    write(
        out / f"data/rftoolspower/advancement/recipes/misc/{AGITATOR}.json",
        json.loads(read_jar(POWER, f"data/rftoolspower/advancement/recipes/misc/{AGITATOR}.json")),
    )

    # --- the blazing infuser: the jar's six-variant blockstate (facing), its front model with the
    # base textures re-pointed into this namespace, and its own item.
    write(
        out / f"assets/rftoolspower/blockstates/{INFUSER}.json",
        json.loads(read_jar(POWER, f"assets/rftoolspower/blockstates/{INFUSER}.json")),
    )
    model = json.loads(read_jar(POWER, f"assets/rftoolspower/models/block/{INFUSER}.json"))
    model["textures"] = {
        key: value.replace("rftoolsbase:block/base/", "rftoolspower:block/base/")
        for key, value in model["textures"].items()
    }
    write(out / f"assets/rftoolspower/models/block/{INFUSER}.json", model)
    write(
        out / f"assets/rftoolspower/models/item/{INFUSER}.json",
        {"parent": f"rftoolspower:block/{INFUSER}"},
    )
    write(
        out / f"assets/rftoolspower/items/{INFUSER}.json",
        {"model": {"model": f"rftoolspower:item/{INFUSER}", "type": "minecraft:model"}},
    )
    binary(
        out / f"assets/rftoolspower/textures/block/blazing/{INFUSER}.png",
        read_jar(POWER, f"assets/rftoolspower/textures/block/blazing/{INFUSER}.png"),
    )
    write(out / f"data/rftoolspower/horizon/block/{INFUSER}.json", INFUSER_DECL)
    write(out / f"data/rftoolspower/loot_table/blocks/{INFUSER}.json", plain_loot(INFUSER))
    write(out / f"data/rftoolspower/recipe/{INFUSER}.json", patched_recipe(INFUSER))
    write(
        out / f"data/rftoolspower/advancement/recipes/misc/{INFUSER}.json",
        json.loads(read_jar(POWER, f"data/rftoolspower/advancement/recipes/misc/{INFUSER}.json")),
    )


def ingredient(value: object) -> object:
    """A 1.21.1 recipe ingredient as 26.3 spells it: `{"item": X}` → X, `{"tag": T}` → `#T`."""
    if isinstance(value, dict) and len(value) == 1:
        if "item" in value:
            return value["item"]
        if "tag" in value:
            return f"#{value['tag']}"
    return value


def patched_recipe(name: str) -> dict:
    """A shaped recipe from the jar with only its ingredient spellings changed for 26.3."""
    recipe = json.loads(read_jar(POWER, f"data/rftoolspower/recipe/{name}.json"))
    if recipe.get("type") != "minecraft:crafting_shaped":
        raise SystemExit(f"{name}: unexpected recipe type {recipe.get('type')!r}")
    recipe["key"] = {key: ingredient(value) for key, value in recipe["key"].items()}
    return recipe


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def binary(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def check() -> int:
    """Rebuild into a temporary tree and compare with what is on disk."""
    with tempfile.TemporaryDirectory() as tmp:
        fresh = Path(tmp)
        build(fresh)
        drift = []
        for path in sorted(fresh.rglob("*")):
            if path.is_dir():
                continue
            relative = path.relative_to(fresh)
            on_disk = ROOT / relative
            if not on_disk.is_file():
                drift.append(f"missing: {relative}")
            elif on_disk.read_bytes() != path.read_bytes():
                drift.append(f"differs: {relative}")
        for path in sorted((ROOT / "assets").rglob("*")) + sorted(
            (ROOT / "data").rglob("*")
        ):
            if path.is_dir():
                continue
            relative = path.relative_to(ROOT)
            if not (fresh / relative).is_file():
                drift.append(f"stray: {relative}")
        if drift:
            print("drift:")
            for line in drift:
                print(f"  {line}")
            return 1
        print(f"ok: {len(list(fresh.rglob('*')))} entries re-derive exactly")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        return check()
    for tree in (ROOT / "assets", ROOT / "data"):
        if tree.is_dir():
            shutil.rmtree(tree)
    build(ROOT)
    print("wrote assets/ and data/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
