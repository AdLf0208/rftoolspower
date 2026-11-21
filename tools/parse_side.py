#!/usr/bin/env python3
"""Parse a `/rftoolspower side` reply into the shell assignments the e2e evaluates.

A set answers:

    Power Cell side at 302,101,48: west input (sides=none,none,none,none,input,none)

and a refusal one of:

    Power Cell at 302,101,48: unknown face 'nowhere' (down|up|north|south|west|east)
    Power Cell at 302,101,48: unknown mode 'in' (none|input|output)
    No RFTools Power power cell there.

The command's exit status is 0 even for a refusal (the chat path), so the e2e asserts this parsed
reply, never the status. Prints:

    ok=1 REFUSAL=none FACE=west MODE=input SIDES=none,none,none,none,input,none
    ok=1 REFUSAL=face WORD=nowhere
    ok=1 REFUSAL=mode WORD=in
    ok=1 REFUSAL=target

`ok=0` (exit 1) only when the line is none of the four shapes. Usage: parse_side.py "<reply>"
"""

from __future__ import annotations

import argparse
import re
import sys

SET = re.compile(
    r"^Power Cell side at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"(?P<face>[a-z]+) (?P<mode>[a-z]+) \(sides=(?P<sides>[a-z]+(?:,[a-z]+){5})\)$"
)
UNKNOWN_FACE = re.compile(
    r"^Power Cell at -?\d+,-?\d+,-?\d+: unknown face '(?P<word>[^']*)' "
    r"\(down\|up\|north\|south\|west\|east\)$"
)
UNKNOWN_MODE = re.compile(
    r"^Power Cell at -?\d+,-?\d+,-?\d+: unknown mode '(?P<word>[^']*)' "
    r"\(none\|input\|output\)$"
)
NO_CELL = re.compile(r"^No RFTools Power power cell there\.$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("line")
    args = parser.parse_args()
    line = args.line.strip()
    if match := SET.match(line):
        values = match.groupdict()
        print("ok=1")
        print("REFUSAL=none")
        print(f"FACE={values['face']}")
        print(f"MODE={values['mode']}")
        print(f"SIDES={values['sides']}")
        return 0
    if match := UNKNOWN_FACE.match(line):
        print("ok=1")
        print("REFUSAL=face")
        print(f"WORD={match.group('word')}")
        return 0
    if match := UNKNOWN_MODE.match(line):
        print("ok=1")
        print("REFUSAL=mode")
        print(f"WORD={match.group('word')}")
        return 0
    if NO_CELL.match(line):
        print("ok=1")
        print("REFUSAL=target")
        return 0
    print("ok=0")
    return 1


if __name__ == "__main__":
    sys.exit(main())
