#!/usr/bin/env python3
"""Parse `/rftoolspower infuser`'s line into shell assignments, and fold its counter.

    eval "$(python3 tools/parse_infuser.py "$line")"

Sets OK, IN_ENERGY, IN_CAPACITY, IN_COUNTER, IN_STEPS (`-` without a rod), IN_QUALITY,
IN_DURATION (six decimals, `-` without a rod), IN_INPUT, IN_CATALYST, IN_OUTPUT (the item id, or
`empty`), IN_INPUT_COUNT/IN_CATALYST_COUNT/IN_OUTPUT_COUNT (0 for an empty slot), IN_T and
IN_NONCE.

    python3 tools/parse_infuser.py --period COUNTER0 COUNTER1 T0 T1

solves the counter over a window and prints `PERIOD_RUNS` (how many counter wraps, i.e. how many
times the infuser reached a run tick), `PERIOD_TICKS` (`T1 - T0`), `PERIOD_REMAINDER` (`(Δt + c0 −
c1) mod 11`, which must be 0), `PERIOD_FIELD` (`floor((Δt + 10 − c0) / 11)`, the count a 11-tick
period predicts for that phase) and `PERIOD_TEN` (`floor((Δt + 10 − c0) / 10)`, the count a 10-tick
period would predict — the brief's old reading).

The counter decrements once a tick and wraps from -1 back to 10, so over `Δt` ticks
`Δt = 11 × wraps + (c0 − c1)`: a period of 10 would leave a non-zero remainder for every window
that wraps at least once. That is the assertion the leg makes, and `SELFTEST_INFUSER=1` asserts the
10-tick reading instead so the leg fails naming the observed count.

A line that does not match prints `ok=0` and exits 1.
"""

from __future__ import annotations

import re
import sys

LINE = re.compile(
    r"^Blazing Infuser at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"(?P<energy>-?\d+)/(?P<capacity>\d+) FE "
    r"\(counter (?P<counter>-?\d+), "
    r"steps=(?P<steps>-?\d+|-), "
    r"quality=(?P<quality>-?\d+(?:\.\d+)?|-), "
    r"duration=(?P<duration>-?\d+(?:\.\d+)?|-), "
    r"input=(?P<input>[^,]+), "
    r"catalyst=(?P<catalyst>[^,]+), "
    r"output=(?P<output>[^,]+), "
    r"t=(?P<t>-?\d+)(?: nonce=(?P<nonce>\S+))?\)$"
)

# `counter = 10`, then `counter--` and `if (counter < 0) { counter = 10; … }`: 11 ticks a run.
COUNTER_START = 10
PERIOD = COUNTER_START + 1


def period(counter0: int, counter1: int, t0: int, t1: int) -> int:
    """Check the counter's arithmetic over the window and print what the two periods predict."""
    ticks = t1 - t0
    # `Δt = 11 × wraps + (c0 − c1)`; solve it exactly rather than dividing with a truncation.
    wrapped = ticks - (counter0 - counter1)
    print(f"PERIOD_TICKS={ticks}")
    print(f"PERIOD_COUNTER0={counter0}")
    print(f"PERIOD_COUNTER1={counter1}")
    print(f"PERIOD_REMAINDER={wrapped % PERIOD}")
    print(f"PERIOD_RUNS={wrapped // PERIOD if wrapped >= 0 else -1}")
    print(f"PERIOD_FIELD={(ticks + COUNTER_START - counter0) // PERIOD}")
    print(f"PERIOD_TEN={(ticks + COUNTER_START - counter0) // 10}")
    return 0


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "--period":
        if len(sys.argv) != 6:
            print(
                "usage: parse_infuser.py --period COUNTER0 COUNTER1 T0 T1",
                file=sys.stderr,
            )
            return 2
        return period(*(int(value) for value in sys.argv[2:]))

    line = sys.argv[1] if len(sys.argv) > 1 else ""
    match = LINE.match(line)
    if not match:
        print("ok=0")
        return 1
    print("ok=1")
    print(f"IN_ENERGY={match['energy']}")
    print(f"IN_CAPACITY={match['capacity']}")
    print(f"IN_COUNTER={match['counter']}")
    print(f"IN_STEPS={match['steps']}")
    print(f"IN_QUALITY={match['quality']}")
    print(f"IN_DURATION={match['duration']}")
    for name, value in (
        ("IN_INPUT", match["input"]),
        ("IN_CATALYST", match["catalyst"]),
        ("IN_OUTPUT", match["output"]),
    ):
        if value == "empty":
            print(f"{name}=empty")
            print(f"{name}_COUNT=0")
        else:
            item, _, count = value.rpartition(" x")
            print(f"{name}={item}")
            print(f"{name}_COUNT={count}")
    print(f"IN_T={match['t']}")
    print(f"IN_NONCE={match['nonce'] or ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
