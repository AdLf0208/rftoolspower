#!/usr/bin/env python3
"""Parse a `/rftoolspower injector` reply into the shell assignments the e2e evaluates.

The mod prints one line:

    Pearl Injector at 302,102,84: pearls=1 generator=302,101,84 t=4242 nonce=9

and this script answers:

    ok=1
    X=302 Y=102 Z=84 PEARLS=1 GENERATOR=302,101,84 T=4242 NONCE=9

`ok=0` (and exit 1) when the line is not an injector readout, so a refusal can never be mistaken
for a reading. Usage: parse_injector.py "<reply line>"
"""

from __future__ import annotations

import argparse
import re
import sys

LINE = re.compile(
    r"^Pearl Injector at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"pearls=(?P<pearls>\d+) generator=(?P<generator>[^ ]+) "
    r"t=(?P<t>-?\d+)(?: nonce=(?P<nonce>\S+))?$"
)

NAMES = {
    "x": "X",
    "y": "Y",
    "z": "Z",
    "pearls": "PEARLS",
    "generator": "GENERATOR",
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
