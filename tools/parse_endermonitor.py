#!/usr/bin/env python3
"""Parse a `/rftoolspower endermonitor` reply into the shell assignments the e2e evaluates.

The mod prints one line:

    Ender Monitor at 304,101,97: mode=arrived facing=east pulses=1 last=arrived \
        needpulse=false out=0 t=4242 nonce=3

and this script answers:

    ok=1
    X=304 Y=101 Z=97 MODE=arrived FACING=east PULSES=1 LAST=arrived NEEDPULSE=false OUT=0
    T=4242 NONCE=3

`ok=0` (and exit 1) when the line is not an ender-monitor readout, so a refusal can never be
mistaken for a reading. Usage: parse_endermonitor.py "<reply line>"
"""

from __future__ import annotations

import argparse
import re
import sys

LINE = re.compile(
    r"^Ender Monitor at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"mode=(?P<mode>lost|fired|arrived) facing=(?P<facing>north|south|east|west|none) "
    r"pulses=(?P<pulses>\d+) last=(?P<last>lost|fired|arrived|none) "
    r"needpulse=(?P<needpulse>true|false) out=(?P<out>\d+) "
    r"t=(?P<t>-?\d+)(?: nonce=(?P<nonce>\S+))?$"
)

NAMES = {
    "x": "X",
    "y": "Y",
    "z": "Z",
    "mode": "MODE",
    "facing": "FACING",
    "pulses": "PULSES",
    "last": "LAST",
    "needpulse": "NEEDPULSE",
    "out": "OUT",
    "t": "T",
    "nonce": "NONCE",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("line")
    args = parser.parse_args()
    match = LINE.match(args.line.strip())
    if not match:
        print("ok=0")
        return 1
    print("ok=1")
    for key, name in NAMES.items():
        value = match.groupdict().get(key)
        if value is None:
            continue
        print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
