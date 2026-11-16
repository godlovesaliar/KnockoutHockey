"""
voicegen.py - batch announcer generator for Knockout Hockey.

Reads the game's script (data/hockey_announcer_lines.csv, via tools/announcer_check.gd),
generates several Chatterbox takes of every Steve (pbp), Bobby (color) and PA announcer (pa)
row, and saves them to takes/. Duets (both/) are made in the Studio's Conversation tab.

Usage:
    python voicegen.py --dry-run          # show the plan, no GPU needed
    python voicegen.py                    # generate everything not already generated
    python voicegen.py --only goal        # rows whose file name or line starts with "goal"
    python voicegen.py --voice color      # just Bobby
    python voicegen.py --redo goal_01 save_02   # wipe + regenerate these rows
    python voicegen.py --redo-list        # redo everything you marked with R in picker.py
    python voicegen.py --retire-old       # move the old announcer clips out of the game

Re-running is safe: takes that already exist are skipped, so you can stop it
anytime (Ctrl+C) and pick up where you left off.
"""

import argparse
import csv
import math
import random
import re
import shutil
import subprocess
import sys
import time

from common import (ANNOUNCER, AUDIO_EXT, CUT_SOUNDS, INTRO_DIR, INTRO_TEXT, INTRO_VOICE,
                    LOG_CSV, OVERRIDES_CSV, REDO_FILE, RETIRED_DIR, SOLO_VOICES, SOUND,
                    TAKES_DIR, VOICE_FILES, VOICES_DIR, ffmpeg, load_intros, load_todo,
                    read_kept, run_godot_check)

# The CSV's intensity column -> Chatterbox settings.
#   intensity = "exaggeration": 0.3 calm, 0.5 normal, 0.8 hyped, 1.2+ screaming
#   pace      = "cfg_weight": lower = looser/slower. Keep it low when intensity is high,
#               or hyped lines come out rushed.
LEVELS = {
    "low":    (0.35, 0.5),
    "medium": (0.5, 0.5),
    "high":   (0.8, 0.35),
}
# ElevenLabs-style tags in the CSV text. Chatterbox would read them aloud, so they're
# stripped; a few nudge the settings instead.
TAGS = {
    "shouting": (1.0, 0.3),
    "excited": None,            # already covered by "high"
    "calm": (0.3, 0.5),
}
VOICE_BOOST = {"pbp": 0.0, "color": 0.1}   # Bobby is the loud one
# A voice can have its own LEVELS/TAGS. The PA announcer's base is its Studio settings
# (voices/pa_announcer.json: intensity 0.9, pace 0.55, variation 0.15), a big steady arena voice.
# (Shouting above the voice's own 0.9 made Chatterbox babble on short lines.)
VOICE_LEVELS = {
    "pa": {"low": (0.6, 0.55), "medium": (0.75, 0.55), "high": (0.9, 0.5),
           "shouting": (0.9, 0.55), "calm": (0.5, 0.55)},
}
VOICE_TEMP = {"pa": 0.4}  # steadier takes than the booth (the Studio's 0.15 gave near-identical takes)
SLOT_TAKES = 2     # takes per row of a team/number line (target 1): pick one
CANDIDATES = 6      # aim for at least this many takes per game line, to pick 3 from
MIN_TAKES = 3       # but never fewer than this per row
INTRO_TAKES = 4     # takes per team intro
DEFAULT_TEMP = 0.8  # randomness between takes; 0.6 steadier, 1.0 wilder


def clean_text(prompt):
    tags = [t.lower() for t in re.findall(r"\[([^\]]*)\]", prompt)]
    text = re.sub(r"\s*\[[^\]]*\]\s*", " ", prompt).strip()
    return text, tags


def num(value, default, cast=float):
    value = (value or "").strip()
    return cast(value) if value else default


def load_overrides():
    """lines.csv: optional per-row tweaks (blank cells keep the default)."""
    out = {}
    if not OVERRIDES_CSV.exists():
        return out
    with open(OVERRIDES_CSV, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rid = (row.get("id") or "").strip()
            if rid and not rid.startswith("#"):
                out[rid] = row
    return out


def build_jobs(todo, only=None, voice=None):
    rows = [r for r in todo["rows"] if r["voice"] in SOLO_VOICES]
    per_line = {}
    for r in rows:
        per_line[r["line"]] = per_line.get(r["line"], 0) + 1
    over = load_overrides()
    plan = []
    for r in rows:
        if only and not any(r["file"].startswith(o) or r["line"].startswith(o) for o in only):
            continue
        if voice and r["voice"] != voice:
            continue
        text, tags = clean_text(r["prompt"])
        vl = VOICE_LEVELS.get(r["voice"], {})
        intensity, pace = vl.get(r["intensity"].lower()) or LEVELS.get(r["intensity"].lower(), LEVELS["medium"])
        for t in tags:
            if vl.get(t) or TAGS.get(t):
                intensity, pace = vl.get(t) or TAGS[t]
        intensity = round(intensity + VOICE_BOOST.get(r["voice"], 0.0), 2)
        takes = max(MIN_TAKES, math.ceil(CANDIDATES / per_line[r["line"]]))
        if todo["lines"].get(r["line"], {}).get("target", 3) == 1:
            takes = SLOT_TAKES
        o = over.get(r["file"], {})
        plan.append({
            "id": r["file"], "line": r["line"], "voice": r["voice"],
            "text": (o.get("text") or "").strip() or text,
            "intensity": num(o.get("intensity"), intensity),
            "pace": num(o.get("pace"), pace),
            "takes": num(o.get("takes"), takes, int),
        })
    # Team intros (intros.csv): one Bobby line per team.
    for call, spoken in load_intros():
        rid = f"intro_{call}"
        if only and not any(rid.startswith(o) for o in only):
            continue
        if voice and voice != INTRO_VOICE:
            continue
        o = over.get(rid, {})
        plan.append({
            "id": rid, "line": f"team_intro_{call}", "voice": INTRO_VOICE,
            "text": (o.get("text") or "").strip() or INTRO_TEXT.format(team=spoken),
            "intensity": num(o.get("intensity"), LEVELS["medium"][0] + VOICE_BOOST[INTRO_VOICE]),
            "pace": num(o.get("pace"), LEVELS["medium"][1]),
            "takes": num(o.get("takes"), INTRO_TAKES, int),
        })
    return plan


def voice_ref(voice):
    """voices/<voice>.wav, or an .mp3 converted to wav once (cached in voices/.cache)."""
    voice = VOICE_FILES.get(voice, voice)
    wav = VOICES_DIR / f"{voice}.wav"
    if wav.exists():
        return wav
    mp3 = VOICES_DIR / f"{voice}.mp3"
    if not mp3.exists():
        return None
    if not ffmpeg():
        return mp3          # Chatterbox can usually read mp3 itself
    cached = VOICES_DIR / ".cache" / f"{voice}.wav"
    if not cached.exists() or cached.stat().st_mtime < mp3.stat().st_mtime:
        cached.parent.mkdir(exist_ok=True)
        subprocess.run([ffmpeg(), "-v", "error", "-y", "-i", str(mp3), "-ac", "1",
                        "-ar", "24000", str(cached)], check=True)
    return cached


def take_text(text, n):
    """A row's text can hold variants separated by " | " (in lines.csv): take n uses
    variant n, wrapping around, so one row can try several spellings or deliveries."""
    variants = [v.strip() for v in text.split("|") if v.strip()]
    return variants[(n - 1) % len(variants)] if variants else text


def take_path(line_id, n):
    return TAKES_DIR / f"{line_id}_take{n}.wav"


def retire_old():
    """Move every clip in announcer/, its pbp/, color/ and both/, and intro/ that
    picker.py or studio.py didn't export into retired/ (outside Godot's view), then
    re-cut the intro halves."""
    kept = {k["game_file"].replace("\\", "/").lower() for k in read_kept()}
    moved = 0
    for d in (ANNOUNCER, ANNOUNCER / "pbp", ANNOUNCER / "color", ANNOUNCER / "both", INTRO_DIR):
        if not d.exists():
            continue
        for f in sorted(d.iterdir()):
            if f.suffix.lower() not in AUDIO_EXT:
                continue
            rel = f.relative_to(SOUND).as_posix()
            if rel.lower() in kept:
                continue
            dest = RETIRED_DIR / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(f), str(dest))
            imp = f.with_name(f.name + ".import")
            if imp.exists():
                imp.unlink()    # Godot's import record for the moved clip
            moved += 1
    print(f"Moved {moved} old clips to {RETIRED_DIR}.")
    print("Re-cutting the intro halves (tools/cut_sounds.py)...")
    subprocess.run([sys.executable, str(CUT_SOUNDS)], check=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="+", help="only rows whose file name or line starts with one of these")
    ap.add_argument("--voice", choices=SOLO_VOICES, help="only this voice")
    ap.add_argument("--redo", nargs="+", help="delete and regenerate takes for these rows")
    ap.add_argument("--redo-list", action="store_true", help="redo rows listed in redo_list.txt")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--temp", type=float, default=None,
                    help=f"randomness between takes (default {DEFAULT_TEMP}; the PA {VOICE_TEMP['pa']})")
    ap.add_argument("--threads", type=int, default=2,
                    help="PyTorch CPU threads (default 2: more crashed this PC; 0 = all)")
    ap.add_argument("--pause", type=float, default=0.0,
                    help="seconds to rest the GPU between takes (eases sustained load)")
    ap.add_argument("--retire-old", action="store_true", help="move the old clips out of the game")
    args = ap.parse_args()

    if args.retire_old:
        return retire_old()

    err = run_godot_check()
    if err:
        print(f"Couldn't refresh the line list from Godot, using the last todo.json:\n  {err}")
    rows = build_jobs(load_todo(), args.only, args.voice)

    redo = list(args.redo or [])
    if args.redo_list and REDO_FILE.exists():
        redo += REDO_FILE.read_text().split()
    if args.redo or args.redo_list:
        rows = [r for r in rows if r["id"] in redo]
        if not rows:
            sys.exit("None of those rows are in the script")
        if not args.dry_run:
            for line_id in redo:
                for old in TAKES_DIR.glob(f"{line_id}_take*.wav"):
                    old.unlink()
            if args.redo_list and REDO_FILE.exists():
                REDO_FILE.unlink()

    refs = {v: voice_ref(v) for v in {r["voice"] for r in rows}}
    missing = [v for v, p in refs.items() if p is None]
    if missing:
        sys.exit("Missing voice reference clips: " + ", ".join(f"voices/{VOICE_FILES.get(v, v)}.mp3" for v in missing))
    TAKES_DIR.mkdir(exist_ok=True)

    jobs = [(r, n) for r in rows for n in range(1, r["takes"] + 1)
            if not take_path(r["id"], n).exists()]
    jobs.sort(key=lambda j: j[0]["voice"])     # one voice at a time
    total = sum(r["takes"] for r in rows)
    print(f"{len(rows)} rows, {len(jobs)} takes to generate ({total - len(jobs)} already done)")
    for v in SOLO_VOICES:
        n = sum(1 for r, _ in jobs if r["voice"] == v)
        if n:
            print(f"  {v}: {n} takes")
    if args.dry_run:
        for r, n in jobs:
            print(f"  {take_path(r['id'], n).name:36s} [{r['voice']} "
                  f"int={r['intensity']} pace={r['pace']}]  {take_text(r['text'], n)}")
        return
    if not jobs:
        return

    # Heavy imports only when actually generating
    import torch
    import torchaudio as ta
    from chatterbox.tts import ChatterboxTTS

    if args.threads > 0:
        torch.set_num_threads(args.threads)
    if not torch.cuda.is_available():
        print("WARNING: CUDA not available - running on CPU will be very slow.")
        print("         See README step 3 to install the CUDA build of PyTorch.")
    device = "cuda" if torch.cuda.is_available() else "cpu"

    print("Loading Chatterbox (first run downloads ~2 GB)...")
    model = ChatterboxTTS.from_pretrained(device=device)
    conds = {}      # voice -> prepared reference, so each clip is analysed once

    new_log = not LOG_CSV.exists()
    log = open(LOG_CSV, "a", newline="", encoding="utf-8")
    logw = csv.writer(log)
    if new_log:
        logw.writerow(["file", "id", "line", "voice", "intensity", "pace", "temp", "seed", "text"])

    start = time.time()
    try:
        for i, (r, n) in enumerate(jobs, start=1):
            v = r["voice"]
            if v not in conds:
                model.prepare_conditionals(str(refs[v]), exaggeration=r["intensity"])
                conds[v] = model.conds
            model.conds = conds[v]
            seed = random.randint(0, 2**31 - 1)
            torch.manual_seed(seed)
            text = take_text(r["text"], n)
            temp = args.temp if args.temp is not None else VOICE_TEMP.get(v, DEFAULT_TEMP)
            wav = model.generate(text, exaggeration=r["intensity"],
                                 cfg_weight=r["pace"], temperature=temp)
            out = take_path(r["id"], n)
            ta.save(str(out), wav, model.sr)
            logw.writerow([out.name, r["id"], r["line"], v, r["intensity"],
                           r["pace"], temp, seed, text])
            log.flush()

            elapsed = time.time() - start
            eta = elapsed / i * (len(jobs) - i)
            print(f"[{i}/{len(jobs)}] {out.name}  (ETA {eta/60:.1f} min)")
            if args.pause:
                time.sleep(args.pause)
    except KeyboardInterrupt:
        print("\nStopped. Re-run to continue where you left off.")
    finally:
        log.close()


if __name__ == "__main__":
    main()
