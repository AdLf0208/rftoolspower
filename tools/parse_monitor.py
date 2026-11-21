#!/usr/bin/env python3
"""Parse the one line `/rftoolspower monitor X Y Z <nonce>` prints into shell assignments.

    eval "$(python3 tools/parse_monitor.py "$line")"

Sets LEVEL, MIN, MAX, UNSET (1 when the band is 0..0), TARGET, IS_ENERGY, STORED, MAXE,
ALARM and OK. A line that does not match prints `ok=0` and exits 1.
"""

import re
import sys

LINE = re.compile(
    r"^Power Monitor at (-?\d+),(-?\d+),(-?\d+): level=(\d+) band=(-?\d+)\.\.(-?\d+)"
    r"( \(unset\))? target=(\S+)( \(not an energy block\))? stored=(-|\d+) max=(-|\d+)"
    r" alarm=(true|false) t=(-?\d+)(?: nonce=(\S+))?$"
)


def quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: parse_monitor.py '<Power Monitor line>'", file=sys.stderr)
        return 2
    match = LINE.match(sys.argv[1].strip())
    if not match:
        print("ok=0")
        print(f"error={quote('the monitor line did not match: ' + sys.argv[1])}")
        return 1
    (
        _x,
        _y,
        _z,
        level,
        minimum,
        maximum,
        unset,
        target,
        not_energy,
        stored,
        capacity,
        alarm,
        t,
        nonce,
    ) = match.groups()
    values = {
        "ok": 1,
        "LEVEL": int(level),
        "MIN": int(minimum),
        "MAX": int(maximum),
        "UNSET": 1 if unset else 0,
        "TARGET": target,
        "IS_ENERGY": 0 if not_energy else 1,
        "STORED": -1 if stored == "-" else int(stored),
        "MAXE": -1 if capacity == "-" else int(capacity),
        "ALARM": 1 if alarm == "true" else 0,
        "T": int(t),
    }
    for name, value in values.items():
        print(f"{name}={value}" if isinstance(value, int) else f"{name}={quote(value)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
