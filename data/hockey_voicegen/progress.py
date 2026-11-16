"""
progress.py - live progress bars for a voicegen.py run, in its own terminal.

It counts the takes already in takes/ against what voicegen plans (the last todo.json),
so it works for any run, started before or after it, and never touches the GPU.

    python progress.py                 # every voice with work left
    python progress.py --voice pa      # just one
    python progress.py --once          # print once and exit

Ctrl+C to close. It exits by itself when everything is generated.
"""

import argparse
import os
import sys
import time

from voicegen import build_jobs, take_path
from common import TAKES_DIR, load_todo

NAMES = {"pbp": "Steve", "color": "Bobby", "pa": "PA"}
RATE_WINDOW = 300.0     # seconds of recent takes used for the speed and ETA
WIDTH = 40


def bar(done, total):
    frac = done / total if total else 1.0
    fill = int(frac * WIDTH)
    return "[" + "#" * fill + "-" * (WIDTH - fill) + f"] {frac * 100:5.1f}%  {done}/{total}"


def eta_text(seconds):
    if seconds is None:
        return "--"
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h}h {m:02d}m" if h else f"{m}m {s:02d}s"


def snapshot(voice, only):
    rows = build_jobs(load_todo(), only, voice)
    per = {}
    for r in rows:
        d = per.setdefault(r["voice"], [0, 0])
        for n in range(1, r["takes"] + 1):
            d[1] += 1
            d[0] += take_path(r["id"], n).exists()
    return per


def recent_rate():
    """Takes per second over the last few minutes (from the files' times), and the newest."""
    now = time.time()
    times = sorted(f.stat().st_mtime for f in TAKES_DIR.glob("*_take*.wav")
                   if now - f.stat().st_mtime < RATE_WINDOW)
    if len(times) < 2:
        return None, (times[-1] if times else None)
    return (len(times) - 1) / max(times[-1] - times[0], 1.0), times[-1]


def draw(per):
    rate, newest = recent_rate()
    lines = ["Knockout Hockey - voicegen progress", ""]
    left = 0
    for v, (done, total) in per.items():
        if done < total or len(per) == 1:
            lines.append(f"  {NAMES.get(v, v):6s} {bar(done, total)}")
        left += total - done
    if left == 0:
        lines.append("  Everything is generated.")
    lines.append("")
    if rate and newest and time.time() - newest < 120:
        lines.append(f"  {rate * 60:.1f} takes/min   about {eta_text(left / rate)} left")
    elif left:
        lines.append("  (no new takes in the last 2 minutes - is voicegen running?)")
    lines.append("")
    lines.append("  Ctrl+C to close")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--voice")
    ap.add_argument("--only", nargs="+")
    ap.add_argument("--once", action="store_true")
    args = ap.parse_args()
    os.system("")   # turns on ANSI escapes in the Windows console
    try:
        while True:
            per = snapshot(args.voice, args.only)
            text = draw(per)
            if args.once:
                print(text)
                return
            sys.stdout.write("\x1b[2J\x1b[H" + text + "\n")
            sys.stdout.flush()
            if all(d >= t for d, t in per.values()):
                return
            time.sleep(3)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
