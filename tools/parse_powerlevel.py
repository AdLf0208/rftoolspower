#!/usr/bin/env python3
"""Parse the one line `/rftoolspower powerlevel X Y Z <nonce>` prints into shell assignments.

    eval "$(python3 tools/parse_powerlevel.py "$line")"

Sets POWER, FACING, TARGET, IS_ENERGY, STORED, MAXE, T and OK. A line that does not match prints
`ok=0` and exits 1.
"""

import re
import sys

LINE = re.compile(
    r"^Power Level at (-?\d+),(-?\d+),(-?\d+): power=(\d+) facing=(\S+)"
    r" target=(\S+)( \(not an energy block\))? stored=(-|\d+) max=(-|\d+)"
    r" t=(-?\d+)(?: nonce=(\S+))?$"
)


def quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: parse_powerlevel.py '<Power Level line>'", file=sys.stderr)
        return 2
    match = LINE.match(sys.argv[1].strip())
    if not match:
        print("ok=0")
        print(f"error={quote('the power level line did not match: ' + sys.argv[1])}")
        return 1
    (
        _x,
        _y,
        _z,
        power,
        facing,
        target,
        not_energy,
        stored,
        capacity,
        t,
        nonce,
    ) = match.groups()
    values = {
        "ok": 1,
        "POWER": int(power),
        "FACING": facing,
        "TARGET": target,
        "IS_ENERGY": 0 if not_energy else 1,
        "STORED": -1 if stored == "-" else int(stored),
        "MAXE": -1 if capacity == "-" else int(capacity),
        "T": int(t),
    }
    for name, value in values.items():
        print(f"{name}={value}" if isinstance(value, int) else f"{name}={quote(value)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
