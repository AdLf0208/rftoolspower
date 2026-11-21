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
    "itemGroup.rftoolspower": "RFTools Power",
    "message.rftoolspower.shiftmessage": "<Press Shift>",
}

CREATIVE_TAB = {
    "icon": "rftoolspower:coalgenerator",
    "items": ["rftoolspower:coalgenerator"],
    "title": "itemGroup.rftoolspower",
}

TAGS = {
    "data/minecraft/tags/block/mineable/pickaxe.json": ["rftoolspower:coalgenerator"],
    "data/minecraft/tags/block/needs_iron_tool.json": ["rftoolspower:coalgenerator"],
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
