#!/usr/bin/env python3
"""Parse a `/rftoolspower endergenic` reply into the shell assignments the e2e evaluates.

The mod prints one line:

    Endergenic at 302,101,84: energy=800/5000000 charging=-1 age=0 pearls=0 fired=1 dropped=0 \
        gained=800 spent=0 arrived=4 reason="none" dest=304,101,86 distance=1 \
        carrier rftoolspower:power_core1 infused 256 factor 1.000 t=4242 nonce=9

and this script answers:

    ok=1
    X=302 Y=101 Z=84 ENERGY=800 ECAP=5000000 CHARGING=-1 AGE=0 PEARLS=0 FIRED=1 DROPPED=0
    GAINED=800 SPENT=0 ARRIVED=4 REASON=none DEST=304,101,86 DISTANCE=1
    CARRIER=rftoolspower:power_core1 INFUSED=256 FACTOR=1.000 T=4242 NONCE=9

`ok=0` (and exit 1) when the line is not an endergenic readout, so a refusal can never be mistaken
for a reading. Usage: parse_ender.py "<reply line>"
"""

from __future__ import annotations

import argparse
import re
import sys

LINE = re.compile(
    r"^Endergenic at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"energy=(?P<energy>-?\d+)/(?P<ecap>\d+) charging=(?P<charging>-?\d+) age=(?P<age>-?\d+) "
    r"pearls=(?P<pearls>\d+) fired=(?P<fired>\d+) dropped=(?P<dropped>\d+) "
    r"gained=(?P<gained>-?\d+) spent=(?P<spent>-?\d+) arrived=(?P<arrived>-?\d+) "
    r'reason="(?P<reason>[^"]*)" dest=(?P<dest>[^ ]+) distance=(?P<distance>\d+) '
    r"carrier (?P<carrier>[^ ]+) infused (?P<infused>-?\d+) factor (?P<factor>[\d.]+) "
    r"t=(?P<t>-?\d+)(?: nonce=(?P<nonce>\S+))?$"
)

NAMES = {
    "x": "X",
    "y": "Y",
    "z": "Z",
    "energy": "ENERGY",
    "ecap": "ECAP",
    "charging": "CHARGING",
    "age": "AGE",
    "pearls": "PEARLS",
    "fired": "FIRED",
    "dropped": "DROPPED",
    "gained": "GAINED",
    "spent": "SPENT",
    "arrived": "ARRIVED",
    "reason": "REASON",
    "dest": "DEST",
    "distance": "DISTANCE",
    "carrier": "CARRIER",
    "infused": "INFUSED",
    "factor": "FACTOR",
    "t": "T",
    "nonce": "NONCE",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("line")
    parser.add_argument("--nonce", default=None, help="refuse a reply with another nonce")
    args = parser.parse_args()
    match = LINE.match(args.line.strip())
    if not match:
        print("ok=0")
        return 1
    values = match.groupdict()
    if args.nonce is not None and values["nonce"] != args.nonce:
        print("ok=0")
        print(
            f"# nonce {values['nonce']!r} is not the one asked for ({args.nonce!r})",
            file=sys.stderr,
        )
        return 1
    print("ok=1")
    for key, name in NAMES.items():
        value = values.get(key)
        if value is None:
            continue
        if name == "REASON":
            # The reason is a sentence; single quotes keep it one shell word for `eval`.
            print(f"{name}='{value}'")
        else:
            print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
