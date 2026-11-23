#!/usr/bin/env python3
"""Parse `/rftoolspower agitator`'s line into shell assignments, and fold the adjacency algorithm.

    eval "$(python3 tools/parse_agitator.py "$line")"

Sets OK, AG_ENERGY, AG_CAPACITY, AG_READY (1/0), AG_TIME0..8, AG_QUALITY0..8, AG_DURATION0..8
(`-` for a slot with no rod), AG_LOCK0..8 (1/0), AG_ROD0..8 and AG_OUT0..8 (`empty` for a slot with
no item), AG_T and AG_NONCE.

    python3 tools/parse_agitator.py --fold T0 T1 TIME QUALITY DURATION TIME1 QUALITY1 DURATION1

folds the whole 3×3 box from the first reply over `T1 - T0` game ticks and prints the expected
`time=…,quality=…,duration=…` slot lists (one slot per argument), `FOLD_ERROR=<largest |expected −
observed|>` and `FOLD_RISE=<quality gain>`/`FOLD_T0_RISE=<the brief's 10-a-tick gain>`, in IEEE
single precision, one rounding per operation — the artefact's own
`BlazingAgitatorAlgorithm.tickBlazingRod`, so a rule that is not that rule shows up as a large
delta.

A line that does not match prints `ok=0` and exits 1.
"""

from __future__ import annotations

import re
import struct
import sys

LINE = re.compile(
    r"^Blazing Agitator at (?P<x>-?\d+),(?P<y>-?\d+),(?P<z>-?\d+): "
    r"(?P<energy>-?\d+)/(?P<capacity>\d+) FE "
    r"\(ready (?P<ready>true|false), "
    r"time=(?P<time>[^,]+(?:,[^,]+){8}), "
    r"quality=(?P<quality>[^,]+(?:,[^,]+){8}), "
    r"duration=(?P<duration>[^,]+(?:,[^,]+){8}), "
    r"locks=(?P<locks>[01]{9}), "
    r"rods=(?P<rods>[^,]+(?:,[^,]+){8}), "
    r"out=(?P<out>[^,]+(?:,[^,]+){8}), "
    r"t=(?P<t>-?\d+)(?: nonce=(?P<nonce>\S+))?\)$"
)

SLOTS = 9
COLUMNS = 3
START_QUALITY = 60000.0
START_DURATION = 20.0
PENALTY = -0.03
FLOOR = 0.01
CAP = 40.0


def f32(value: float) -> float:
    """`value` rounded to IEEE single precision, as one Rust f32 operation does."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


def quality_factor(rod: tuple[float, float, float] | None) -> float:
    """`calculateQualityFactor`: `min((duration*20/10000 + quality*60000/1.5e8)/2, 40)`."""
    if rod is None:
        return 0.0
    duration, quality, _ = rod
    duration_term = f32(f32(f32(duration) * f32(START_DURATION)) / f32(10000.0))
    quality_term = f32(f32(f32(quality) * f32(START_QUALITY)) / f32(150000000.0))
    return min(f32(f32(duration_term + quality_term) / f32(2.0)), f32(CAP))


def neighbour_difference(box: list, this: float, index: int, x: int, y: int) -> float:
    """`calculateQualityFactorDiff`: the empty/out-of-box penalty, else the capped difference."""
    if x < 0 or y < 0 or x >= COLUMNS or y >= COLUMNS:
        return f32(PENALTY)
    if not 0 <= index < SLOTS or box[index] is None:
        return f32(PENALTY)
    return max(f32(PENALTY), f32(quality_factor(box[index]) - this))


def adjacency_factor(box: list, index: int) -> float:
    """`calculateAdjacencyFactor`: a quarter of one plus the four neighbours' differences."""
    this = quality_factor(box[index])
    x = index % COLUMNS
    y = index // COLUMNS
    factor = f32(1.0)
    for neighbour, nx, ny in (
        (index - 1, x - 1, y),
        (index + 1, x + 1, y),
        (index - COLUMNS, x, y - 1),
        (index + COLUMNS, x, y + 1),
    ):
        factor = f32(factor + neighbour_difference(box, this, neighbour, nx, ny))
    if factor < f32(FLOOR):
        factor = f32(FLOOR)
    return f32(factor / f32(4.0))


def tick(box: list) -> None:
    """One `tickRods`: every rod with time left is agitated, in slot order (in place)."""
    for index in range(SLOTS):
        rod = box[index]
        if rod is None:
            continue
        duration, quality, time = rod
        if time <= 0.0:
            # A finished rod leaves the box; the fold's window never crosses that.
            box[index] = None
            continue
        factor = adjacency_factor(box, index)
        time = f32(time - f32(factor / f32(5.0)))
        quality = f32(quality + f32(f32(f32(factor * factor) * f32(10.0)) * f32(1.0)))
        duration = f32(duration + f32(f32(factor * factor) * f32(1.0)))
        box[index] = (duration, quality, time)


def parse_slot_list(text: str) -> list[float | None]:
    values = text.split(",")
    if len(values) != SLOTS:
        raise SystemExit(f"a slot list has {len(values)} entries, expected {SLOTS}: {text!r}")
    return [None if value == "-" else float(value) for value in values]


def fold(
    t0: float,
    t1: float,
    times: str,
    qualities: str,
    durations: str,
    times_later: str,
    qualities_later: str,
    durations_later: str,
) -> int:
    ticks = max(0, int(round(t1 - t0)))
    times_ = parse_slot_list(times)
    qualities_ = parse_slot_list(qualities)
    durations_ = parse_slot_list(durations)
    box: list = [
        (durations_[slot], qualities_[slot], times_[slot])
        if times_[slot] is not None
        else None
        for slot in range(SLOTS)
    ]
    first = [rod[1] if rod else None for rod in box]
    for _ in range(ticks):
        tick(box)
    expected = [
        (rod[0], rod[1], rod[2]) if rod else (None, None, None) for rod in box
    ]
    worst = 0.0
    later_durations = parse_slot_list(durations_later)
    later_qualities = parse_slot_list(qualities_later)
    later_times = parse_slot_list(times_later)
    observed = [
        (later_durations[slot], later_qualities[slot], later_times[slot])
        for slot in range(SLOTS)
    ]
    for slot in range(SLOTS):
        for want, have in zip(expected[slot], observed[slot]):
            if want is None or have is None:
                continue
            worst = max(worst, abs(want - have))
    print(
        "FOLD_TIME=" + ",".join("-" if rod[2] is None else f"{rod[2]:.6f}" for rod in expected)
    )
    print(
        "FOLD_QUALITY="
        + ",".join("-" if rod[1] is None else f"{rod[1]:.6f}" for rod in expected)
    )
    print(
        "FOLD_DURATION="
        + ",".join("-" if rod[0] is None else f"{rod[0]:.6f}" for rod in expected)
    )
    print(f"FOLD_ERROR={worst:.6f}")
    rise = 0.0
    for slot in range(SLOTS):
        if first[slot] is None or expected[slot][1] is None:
            continue
        rise = max(rise, expected[slot][1] - first[slot])
    print(f"FOLD_RISE={rise:.6f}")
    print(f"FOLD_BRIEF_RISE={f32(10.0 * ticks):.6f}")
    print(f"FOLD_TICKS={ticks}")
    return 0


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "--fold":
        if len(sys.argv) != 10:
            print(
                "usage: parse_agitator.py --fold T0 T1 TIME QUALITY DURATION "
                "TIME1 QUALITY1 DURATION1",
                file=sys.stderr,
            )
            return 2
        return fold(
            float(sys.argv[2]),
            float(sys.argv[3]),
            sys.argv[4],
            sys.argv[5],
            sys.argv[6],
            sys.argv[7],
            sys.argv[8],
            sys.argv[9],
        )

    line = sys.argv[1] if len(sys.argv) > 1 else ""
    match = LINE.match(line)
    if not match:
        print("ok=0")
        return 1
    print("ok=1")
    print(f"AG_ENERGY={match['energy']}")
    print(f"AG_CAPACITY={match['capacity']}")
    print(f"AG_READY={1 if match['ready'] == 'true' else 0}")
    for name, tag in (
        ("AG_TIME", match["time"]),
        ("AG_QUALITY", match["quality"]),
        ("AG_DURATION", match["duration"]),
    ):
        for slot, value in enumerate(tag.split(",")):
            print(f"{name}{slot}={value}")
    for slot, locked in enumerate(match["locks"]):
        print(f"AG_LOCK{slot}={locked}")
    for name, tag in (("AG_ROD", match["rods"]), ("AG_OUT", match["out"])):
        for slot, value in enumerate(tag.split(",")):
            print(f"{name}{slot}={value}")
    print(f"AG_T={match['t']}")
    print(f"AG_NONCE={match['nonce'] or ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
