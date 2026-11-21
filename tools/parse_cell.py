#!/usr/bin/env python3
"""Parse a `/rftoolspower cell` reply into the shell assignments the e2e evaluates.

The mod prints one line:

    Power Cell at 302,101,48: tier=1 local=12500/500000 network=12500/500000 cells=1 \
        sides=none,none,none,none,input,none t=324 nonce=7

and this script answers:

    ok=1
    X=302 Y=101 Z=48 TIER=1 LOCAL=12500 LCAP=500000 NETWORK=12500 NCAP=500000 CELLS=1
    SIDES=none,none,none,none,input,none T=324 NONCE=7

`ok=0` (and exit 1) when the line is not a cell readout, so a refusal can never be mistaken for a
reading. Usage: parse_cell.py "<reply line>"
"""

from __future__ import annotations

import argparse
import re
import sys

LINE = re.compile(
    r"^Power Cell at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"tier=(?P<tier>\d+) local=(?P<local>-?\d+)/(?P<lcap>\d+) "
    r"network=(?P<network>-?\d+)/(?P<ncap>\d+) cells=(?P<cells>\d+) "
    r"sides=(?P<sides>[a-z]+(?:,[a-z]+){5}) t=(?P<t>-?\d+)"
    r"(?: nonce=(?P<nonce>\S+))?$"
)

NAMES = {
    "x": "X",
    "y": "Y",
    "z": "Z",
    "tier": "TIER",
    "local": "LOCAL",
    "lcap": "LCAP",
    "network": "NETWORK",
    "ncap": "NCAP",
    "cells": "CELLS",
    "sides": "SIDES",
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
        if value is not None:
            print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
