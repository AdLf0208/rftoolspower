#!/usr/bin/env python3
"""Parse the `/data get entity @s SelectedItem` reply for a broken generator's store.

The engine answers vanilla's line:

    <player> has the following entity data: {count:1,id:"rftoolspower:coalgenerator",
    components:{"minecraft:block_entity_data":{id:"rftoolspower:coalgenerator_block_entity",
    burn:503,burn_max:600,energy:3000}}}

Prints the shell assignments the e2e evaluates, and exits 1 when the reply is not what was
asked for:

    ok=1 component=present carried=3000 burn=503

Usage: parse_drop.py "<reply line>" none|<FE>
"""

from __future__ import annotations

import re
import sys

COMPONENT = "minecraft:block_entity_data"
TYPE = "rftoolspower:coalgenerator_block_entity"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: parse_drop.py '<data get reply>' none|<FE>", file=sys.stderr)
        return 2
    line, expect = argv[1], argv[2].strip()
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
        ok = present and carried == wanted and TYPE in line
    print(f"ok={1 if ok else 0}")
    print(f"component={'present' if present else 'absent'}")
    print(f"carried={carried if carried is not None else 'none'}")
    print(f"burn={burn if burn is not None else 'none'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
