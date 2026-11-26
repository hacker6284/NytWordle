#!/usr/bin/env python3
"""Verify America/New_York Wordle-day math against zoneinfo.

Mirrors source/nytDate.lua: post-2007 US Eastern DST
(2nd Sunday March 07:00 UTC through 1st Sunday November 06:00 UTC).
"""

from __future__ import annotations

import datetime as dt
from zoneinfo import ZoneInfo


NY = ZoneInfo("America/New_York")
UTC = dt.timezone.utc


def nth_sunday(year: int, month: int, n: int) -> int:
    first = dt.date(year, month, 1)
    # Monday=0 ... Sunday=6
    first_sunday = 1 + ((6 - first.weekday()) % 7)
    return first_sunday + (n - 1) * 7


def lua_style_ny_date(instant: dt.datetime) -> str:
    year = instant.year
    dst_start = dt.datetime(year, 3, nth_sunday(year, 3, 2), 7, 0, tzinfo=UTC)
    dst_end = dt.datetime(year, 11, nth_sunday(year, 11, 1), 6, 0, tzinfo=UTC)
    offset = dt.timedelta(hours=-4 if dst_start <= instant < dst_end else -5)
    ny = instant + offset
    return f"{ny.year:04d}-{ny.month:02d}-{ny.day:02d}"


def true_ny_date(instant: dt.datetime) -> str:
    local = instant.astimezone(NY)
    return f"{local.year:04d}-{local.month:02d}-{local.day:02d}"


def main() -> int:
    mismatches = 0
    checked = 0

    for year in range(2024, 2028):
        start = dt.datetime(year, 1, 1, 0, 0, tzinfo=UTC)
        end = dt.datetime(year + 1, 1, 1, 0, 0, tzinfo=UTC)
        instant = start
        while instant < end:
            checked += 1
            got = lua_style_ny_date(instant)
            want = true_ny_date(instant)
            if got != want:
                mismatches += 1
                if mismatches <= 20:
                    print(f"MISMATCH {instant.isoformat()} got={got} want={want}")
            instant += dt.timedelta(hours=1)

        # Transition edges
        for month, n, hour in ((3, 2, 7), (11, 1, 6)):
            edge = dt.datetime(year, month, nth_sunday(year, month, n), hour, 0, tzinfo=UTC)
            for delta in (-1, 0, 1):
                instant = edge + dt.timedelta(seconds=delta)
                checked += 1
                got = lua_style_ny_date(instant)
                want = true_ny_date(instant)
                if got != want:
                    mismatches += 1
                    print(f"MISMATCH edge {instant.isoformat()} got={got} want={want}")

    print(f"checked={checked} mismatches={mismatches}")
    return 0 if mismatches == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
