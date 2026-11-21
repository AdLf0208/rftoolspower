#!/usr/bin/env python3
"""Parse the `/data get entity @s SelectedItem` reply for a broken generator's store.

The engine answers vanilla's line:

    <player> has the following entity data: {count:1,id:"rftoolspower:coalgenerator",
    components:{"minecraft:block_entity_data":{id:"rftoolspower:coalgenerator_block_entity",
    burn:503,burn_max:600,energy:3000}}}

Prints the shell assignments the e2e evaluates, and exits 1 when the reply is not what was
asked for:

    ok=1 component=present carried=3000 burn=503

Usage: parse_drop.py "<reply line>" none|<FE> [type_id]

`type_id` is the block entity type the payload must name — the generator's by default; a
powercell passes its own (`rftoolspower:cell1_block_entity`).
"""

from __future__ import annotations

import re
import sys

COMPONENT = "minecraft:block_entity_data"
TYPE = "rftoolspower:coalgenerator_block_entity"


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print(
            "usage: parse_drop.py '<data get reply>' none|<FE> [type_id]",
            file=sys.stderr,
        )
        return 2
    line, expect = argv[1], argv[2].strip()
    type_id = argv[3].strip() if len(argv) == 4 else TYPE
    present = COMPONENT in line
    carried = None
    burn = None
    if present:
        after = line.split(COMPONENT, 1)[1]
        energy = re.search(r"energy:\s*(-?\d+)", after)
        carried = int(energy.group(1)) if energy else None
        burning = re.search(r"burn:\s*(-?\d+)", after)
        burn = int(burning.group(1)) if burning else None
    if expect == "none":
        ok = not present
    else:
        try:
            wanted = int(expect)
        except ValueError:
            print(f"bad expectation {expect!r}", file=sys.stderr)
            return 2
        ok = present and carried == wanted and type_id in line
    print(f"ok={1 if ok else 0}")
    print(f"component={'present' if present else 'absent'}")
    print(f"carried={carried if carried is not None else 'none'}")
    print(f"burn={burn if burn is not None else 'none'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
