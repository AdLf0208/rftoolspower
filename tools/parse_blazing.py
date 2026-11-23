#!/usr/bin/env python3
"""Parse `/rftoolspower blazing`'s line into shell assignments, and fold the ramp for the e2e.

    eval "$(python3 tools/parse_blazing.py "$line")"

Sets OK, BZ_ENERGY, BZ_CAPACITY, BZ_WORKING (1/0), BZ_RFT0..3, BZ_RFTMAX0..3, BZ_TICKS0..3,
BZ_ROD0..3 (`empty` for a slot with no rod), BZ_T and BZ_NONCE.

    python3 tools/parse_blazing.py --ramp RFT T0 RFT1 T1 CEILING

prints `RAMP_EXPECTED=<rft folded T1-T0 ticks>`, `RAMP_DELTA=<|expected-observed|>` and
`RAMP_RISING=1|0`, with the fold done in IEEE single precision step by step — the artefact's own
`rft += (ceiling - rft)/150 + 0.01`, one rounding per operation — so a rule that is not that rule
shows up as a large delta.
A line that does not match prints `ok=0` and exits 1.
"""

from __future__ import annotations

import re
import struct
import sys

LINE = re.compile(
    r"^Blazing Generator at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"(?P<energy>-?\d+)/(?P<capacity>\d+) FE "
    r"\(working (?P<working>true|false), "
    r"rft=(?P<rft>[-0-9.,]+), rftmax=(?P<rftmax>[-0-9,]+), "
    r"ticks=(?P<ticks>[-0-9,]+), rods=(?P<rods>[^,]+(,[^,]+)*), "
    r"t=(?P<t>-?\d+)(?: nonce=(?P<nonce>\S+))?\)$"
)


def f32(value: float) -> float:
    """`value` rounded to IEEE single precision, as one Rust f32 operation does."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


def ramp(rft: float, ticks: int, ceiling: float) -> float:
    """The generator's climb, one f32 operation at a time (`handlePowerGeneration`)."""
    value = f32(rft)
    for _ in range(ticks):
        value = f32(
            f32(value + f32(f32(ceiling - value) / f32(150.0))) + f32(0.01)
        )
        if value > ceiling:
            value = ceiling
    return value


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "--ramp":
        if len(sys.argv) != 7:
            print("usage: parse_blazing.py --ramp RFT T0 RFT1 T1 CEILING", file=sys.stderr)
            return 2
        rft0, t0, rft1, t1, ceiling = (float(arg) for arg in sys.argv[2:7])
        expected = ramp(rft0, max(0, int(round(t1 - t0))), ceiling)
        print(f"RAMP_EXPECTED={expected:.6f}")
        print(f"RAMP_DELTA={abs(expected - rft1):.6f}")
        print(f"RAMP_RISING={1 if expected > rft0 else 0}")
        return 0

    line = sys.argv[1] if len(sys.argv) > 1 else ""
    match = LINE.match(line)
    if not match:
        print("ok=0")
        return 1
    print("ok=1")
    print(f"BZ_ENERGY={match['energy']}")
    print(f"BZ_CAPACITY={match['capacity']}")
    print(f"BZ_WORKING={1 if match['working'] == 'true' else 0}")
    rates = match["rft"].split(",")
    ceilings = match["rftmax"].split(",")
    ticks = match["ticks"].split(",")
    rods = match["rods"].split(",")
    if not (len(rates) == len(ceilings) == len(ticks) == len(rods) == 4):
        print("ok=0")
        return 1
    for index in range(4):
        print(f"BZ_RFT{index}={rates[index]}")
        print(f"BZ_RFTMAX{index}={ceilings[index]}")
        print(f"BZ_TICKS{index}={ticks[index]}")
        print(f"BZ_ROD{index}={rods[index]}")
    print(f"BZ_T={match['t']}")
    print(f"BZ_NONCE={match['nonce'] or ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
