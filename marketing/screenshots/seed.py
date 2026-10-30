#!/usr/bin/env python3
"""Seeds the simulator's App Group with demo data. Never touches a real battery: the host is 127.0.0.1.

Usage: seed.py <udid> lasts|short|empty
"""
import json
import plistlib
import random
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

GROUP = "group.com.mlapin.marstek.battery"
BUNDLE = "com.mlapin.marstek.battery"
EPOCH = datetime(2001, 1, 1, tzinfo=ZoneInfo("UTC"))
KYIV = ZoneInfo("Europe/Kyiv")
RATED_WH = 5120
SCENES = {"lasts": (58, 620, 130), "short": (30, 900, 95)}


def ref(moment):
    return (moment - EPOCH).total_seconds()


def encode(value):
    return json.dumps(value, ensure_ascii=False).encode()


def container(udid):
    out = subprocess.check_output(["xcrun", "simctl", "get_app_container", udid, BUNDLE, GROUP], text=True)
    return Path(out.strip())


def simulate(now, outage_start, soc_now, load):
    """Five-minute samples for 7 days: the grid charges, each outage drains, and today ends at soc_now."""
    rng = random.Random(7)
    start = (now - timedelta(days=6)).replace(hour=0, minute=0, second=0, microsecond=0)
    outages = [(outage_start, now)]
    day = start
    while day < now:
        for hour in (2 + rng.randint(0, 2), 10 + rng.randint(0, 2)):
            begin = day.replace(hour=hour)
            end = begin + timedelta(hours=3 + rng.randint(0, 1))
            if end < outage_start - timedelta(hours=2):
                outages.append((begin, end))
        day += timedelta(days=1)

    samples, soc, t = [], 100.0, start
    soc_start = soc
    swing = {}
    while t < now:
        off = next((o for o in outages if o[0] <= t < o[1]), None)
        if off:
            base = swing.setdefault(off, rng.randint(420, 760))
            watts = base + rng.randint(-40, 40)
            if off[0] == outage_start:
                share = (t - outage_start) / (now - outage_start)
                soc = soc_start + (soc_now - soc_start) * share
                watts = load + rng.randint(-20, 20)
            else:
                soc -= watts * 5 / 60 / RATED_WH * 100 * 1.09
            offgrid = watts
        elif soc < 100:
            watts = -rng.randint(1300, 1600)
            soc = min(100.0, soc + 1450 * 5 / 60 / RATED_WH * 100 * 0.88)
            offgrid = 0
        else:
            watts, offgrid = 0, 0
        if t < outage_start:
            soc_start = soc
        samples.append({"t": ref(t), "s": round(soc), "w": watts, "o": offgrid})
        t += timedelta(minutes=5)
    return samples


def slot(minute_start, minute_end):
    return {"start": minute_start, "end": minute_end, "type": "Definite"}


def main():
    udid, scene = sys.argv[1], sys.argv[2]
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
    root = container(udid)
    prefs = root / "Library" / "Preferences" / f"{GROUP}.plist"
    history = root / "history.json"
    prefs.parent.mkdir(parents=True, exist_ok=True)
    prefs.unlink(missing_ok=True)
    history.unlink(missing_ok=True)

    if scene != "empty":
        soc, load, back_in = SCENES[scene]
        now = datetime.now(KYIV).replace(second=0, microsecond=0)
        hour = now.replace(minute=0)
        outage_start = hour - timedelta(hours=3)
        back = now + timedelta(minutes=back_in)
        back = back.replace(minute=0) + timedelta(hours=1 if back.minute >= 30 else 0)
        midnight = now.replace(hour=0, minute=0)
        start_minute = int((outage_start - midnight).total_seconds() // 60)
        end_minute = int((back - midnight).total_seconds() // 60)
        day = {"date": ref(midnight), "status": "ScheduleApplies", "slots": [slot(start_minute, end_minute)]}
        tomorrow = dict(day, date=ref(midnight + timedelta(days=1)), status="WaitingForSchedule", slots=[])
        values = {
            "settings": {"host": "127.0.0.1", "port": 30000, "floorPct": 12},
            "powerBack": ref(back),
            "powerBackFromSchedule": True,
            "outageGroup": {"group": 3, "subgroup": 1, "address": "вул. Хрещатик, 1"},
            "schedule": {"key": "3.1", "checkedAt": ref(now), "days": {"today": day, "tomorrow": tomorrow}, "failed": False},
            "snapshot": {
                "reading": {
                    "time": ref(now), "socPct": soc, "acW": load, "offgridW": load,
                    "capacityWh": soc / 100 * RATED_WH, "ratedWh": RATED_WH,
                },
                "checkedAt": ref(now),
            },
        }
        with prefs.open("wb") as f:
            plistlib.dump({k: encode(v) for k, v in values.items()}, f, fmt=plistlib.FMT_BINARY)
        history.write_text(json.dumps({"samples": simulate(now, outage_start, soc, load)}))
    subprocess.run(["xcrun", "simctl", "spawn", udid, "killall", "-9", "cfprefsd"], capture_output=True)
    print(f"seeded {scene}")


if __name__ == "__main__":
    main()
