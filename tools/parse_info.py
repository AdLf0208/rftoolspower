#!/usr/bin/env python3
"""Parse `/rftoolspower info`'s line into shell assignments.

    Coal Generator at 300,101,0: 1940/500000 FE (burning 503/600 ticks, lit true, fuel
    minecraft:coal x4, t=324 nonce=1)

Prints `ok=1` plus `ENERGY=… CAPACITY=… BURN=… BURN_MAX=… LIT=… FUEL_ITEM=…
FUEL_COUNT=… T=… NONCE=…` (or `ok=0`) for the e2e to `eval`. A reply the readout never
prints — no generator there — is `ok=0`.
"""

from __future__ import annotations

import re
import sys

LINE = re.compile(
    r"^Coal Generator at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"(?P<energy>-?\d+)/(?P<capacity>\d+) FE "
    r"\(burning (?P<burn>\d+)/(?P<burn_max>\d+) ticks, lit (?P<lit>true|false), "
    r"fuel (?P<fuel>.*?), t=(?P<t>\d+)(?: nonce=(?P<nonce>\S+))?\)$"
)
STACK = re.compile(r"^(?P<item>\S+) x(?P<count>\d+)$")


def main() -> None:
    line = sys.argv[1] if len(sys.argv) > 1 else ""
    match = LINE.match(line)
    if not match:
        print("ok=0")
        return
    print("ok=1")
    for key in ("energy", "capacity", "burn", "burn_max", "lit", "t"):
        print(f"{key.upper()}={match[key]}")
    print(f"NONCE={match['nonce'] or ''}")
    fuel = STACK.match(match["fuel"])
    print(f"FUEL_ITEM={fuel['item'] if fuel else 'empty'}")
    print(f"FUEL_COUNT={fuel['count'] if fuel else 0}")


if __name__ == "__main__":
    main()
