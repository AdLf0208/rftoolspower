#!/usr/bin/env python3
"""Read the `energy` int out of a `/data get block X Y Z` reply.

    eval "$(python3 tools/parse_data_energy.py "$line")"

The harness receiver's `ModEnergyBuffer` keeps its amount in the block entity's saved compound
under `energy`, so the reply is either `… has the following block data: {energy: 2000}` or, for
the `energy` path itself, `… has the following block data: 2000`. Sets ENERGY and OK; `ok=0`
(exit 1) when neither shape is there.
"""

import re
import sys

ENERGY = re.compile(r"\benergy:\s*(-?\d+)|has the following block data:\s*(-?\d+)")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: parse_data_energy.py '<data get block reply>'", file=sys.stderr)
        return 2
    match = ENERGY.search(sys.argv[1])
    if not match:
        print("ok=0")
        return 1
    print("ok=1")
    print(f"ENERGY={int(match.group(1) or match.group(2))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
