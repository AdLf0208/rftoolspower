#!/usr/bin/env python3
"""Parse `/rftoolspower info`'s line into shell assignments.

    Coal Generator at 300,101,0: 1940/500000 FE (burning 503/600 ticks, lit true, fuel
    minecraft:coal x4, charge empty, infused 128 factor 0.500 rf 90, t=324 nonce=1)

Prints `ok=1` plus `ENERGY=… CAPACITY=… BURN=… BURN_MAX=… LIT=… FUEL_ITEM=…
FUEL_COUNT=… T=… INFUSED=… FACTOR=… RF=… NONCE=…` (or `ok=0`) for the e2e to `eval`. A reply the readout never
prints — no generator there — is `ok=0`.
"""

from __future__ import annotations

import re
import sys

LINE = re.compile(
    r"^Coal Generator at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"(?P<energy>-?\d+)/(?P<capacity>\d+) FE "
    r"\(burning (?P<burn>\d+)/(?P<burn_max>\d+) ticks, lit (?P<lit>true|false), "
    r"fuel (?P<fuel>.*?), charge (?P<charge>.*?), carrier (?P<carrier>.*?), "
    r"infused (?P<infused>\d+) factor (?P<factor>\d+\.\d+) rf (?P<rf>\d+), t=(?P<t>\d+)"
    r"(?: nonce=(?P<nonce>\S+))?\)$"
)
STACK = re.compile(r"^(?P<item>\S+) x(?P<count>\d+)$")
CHARGE = re.compile(
    r"^(?P<item>\S+) x(?P<count>\d+) \((?P<fe>-?\d+) FE, cap=(?P<cap>yes|no)\)$"
)


def main() -> None:
    line = sys.argv[1] if len(sys.argv) > 1 else ""
    match = LINE.match(line)
    if not match:
        print("ok=0")
        return
    print("ok=1")
    for key in ("energy", "capacity", "burn", "burn_max", "lit", "t", "infused", "rf", "carrier"):
        print(f"{key.upper()}={match[key]}")
    print(f"FACTOR={match['factor']}")
    print(f"NONCE={match['nonce'] or ''}")
    fuel = STACK.match(match["fuel"])
    print(f"FUEL_ITEM={fuel['item'] if fuel else 'empty'}")
    print(f"FUEL_COUNT={fuel['count'] if fuel else 0}")
    charge = CHARGE.match(match["charge"])
    print(f"CHARGE_ITEM={charge['item'] if charge else 'empty'}")
    print(f"CHARGE_COUNT={charge['count'] if charge else 0}")
    print(f"CHARGE_FE={charge['fe'] if charge else 0}")
    print(f"CHARGE_CAP={charge['cap'] if charge else 'no'}")


if __name__ == "__main__":
    main()
