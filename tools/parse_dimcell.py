#!/usr/bin/env python3
"""Parse a `/rftoolspower dimcell` reply into shell assignments.

    Dimensional Cell at 302,101,80: tier=simple local=0/250000 network=0/500000 n=2 \
        net=7 sides=none,none,none,none,none,none t=324 nonce=9

Prints `ok=1` with `DX DY DZ DTILE DLOCAL DLCAP DNETWORK DNCAP DN DNET DSIDES DT DNONCE`.
`ok=0` (exit 1) for anything else, so a refusal is never mistaken for a reading.
"""

from __future__ import annotations

import argparse
import re
import sys

LINE = re.compile(
    r"^Dimensional Cell at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"tier=(?P<tier>[a-z]+) local=(?P<local>-?\d+)/(?P<lcap>\d+) "
    r"network=(?P<network>-?\d+)/(?P<ncap>\d+) n=(?P<n>\d+) net=(?P<net>-?\d+) "
    r"sides=(?P<sides>[a-z]+(?:,[a-z]+){5}) t=(?P<t>-?\d+)"
    r"(?: nonce=(?P<nonce>\S+))?$"
)

NAMES = {
    "x": "DX",
    "y": "DY",
    "z": "DZ",
    "tier": "DTILE",
    "local": "DLOCAL",
    "lcap": "DLCAP",
    "network": "DNETWORK",
    "ncap": "DNCAP",
    "n": "DN",
    "net": "DNET",
    "sides": "DSIDES",
    "t": "DT",
    "nonce": "DNONCE",
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
        if value is not None:
            print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
