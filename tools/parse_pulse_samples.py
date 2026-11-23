#!/usr/bin/env python3
"""Read the per-tick `ctl script` samples of one ender-monitor pulse window.

Usage: parse_pulse_samples.py SAMPLES BLOCK_ID

`sample_pulse` runs the game frozen and writes, for each step, `state` (the client clock, printed as
`ticks`) followed by `block` (the witness). This script pairs each block reading with the tick that
preceded it and answers the shell assignments the e2e evaluates:

    ok=1
    PULSE_SAMPLES=16 PULSE_LIT=1 PULSE_SEQUENCE=0010000000000000
    PULSE_TICKS=...,... PULSE_TICK_LIT=1

`PULSE_LIT` counts readings and `PULSE_TICK_LIT` counts *distinct* ticks, so two readings that carry
the same label (the label is the client's clock, not the server's step) cannot turn one pulse into
two. Lines that are not block or state replies are skipped.
"""

from __future__ import annotations

import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("samples")
    parser.add_argument("block")
    args = parser.parse_args()
    with open(args.samples, encoding="utf-8", errors="replace") as handle:
        lines = handle.readlines()
    readings: list[tuple[object, str]] = []
    tick: object = None
    for line in lines:
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            reply = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(reply.get("ticks"), int):
            tick = reply["ticks"]
        elif reply.get("block") == args.block:
            state = reply.get("state") or ""
            readings.append((tick, "1" if "lit=true" in state else "0"))
    sequence = "".join(value for _tick, value in readings)
    per_tick: dict[object, str] = {}
    for at, value in readings:
        # The last reading of a tick wins: it is the one taken after the step that produced it.
        per_tick[at] = "1" if value == "1" or per_tick.get(at) == "1" else "0"
    lit_ticks = sum(1 for value in per_tick.values() if value == "1")
    ticks = ",".join("?" if at is None else str(at) for at in per_tick)
    print("ok=1")
    print(f"PULSE_SAMPLES={len(readings)}")
    print(f"PULSE_LIT={sequence.count('1')}")
    print(f"PULSE_SEQUENCE={sequence}")
    print(f"PULSE_TICKS={ticks}")
    print(f"PULSE_TICK_LIT={lit_ticks}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
