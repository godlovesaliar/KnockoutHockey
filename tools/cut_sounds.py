"""Cuts the recordings in assets/sound/ into the clips the game plays (assets/sound/cut/).

    python tools/cut_sounds.py            (needs ffmpeg on PATH or FFMPEG set)

Each entry below takes a stretch of a source file, fades its ends, normalizes its peak
and writes <name>_<n>.ogg; the Sfx autoload loads every clip in assets/sound/cut/ and
plays a random variant per name, in place of its synthesized stand-in. Loops ("loop")
are made seamless by crossfading their end into their start.

Game intros (assets/sound/intro/intro_<team>.mp3, each "Tonight: a matchup between the
<team> and the <team>.") are split at the quietest moment between the two halves into
intro_home_<team> ("...between the <team>") and intro_away_<team> ("and the <team>."),
so any home team's opening can lead into any away team's close.

To retune: listen, change the times here, rerun.
"""
import os
import re
import math
import shutil
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "sound")
OUT = os.path.join(SRC, "cut")
INTRO_DIR = os.path.join(SRC, "intro")
INTRO_SPLIT_FROM = 1.9     # the split is searched between here...
INTRO_SPLIT_TO_END = 1.2   # ...and this long before the end (seconds)

# name: [(source, start s, length s, peak dB), ...]
CLIPS = {
    # Effects
    "shot_slap": [("shots", 0.15, 1.6, -1), ("shots", 2.35, 1.5, -1)],
    "shot_wrist": [("shots2", 0.15, 1.2, -3), ("shots2", 3.45, 1.4, -3)],
    "board_hit": [("boardcheck", 0.7, 2.3, -1), ("boardcheck2", 2.15, 2.0, -1)],
    "ice_hit": [("icecheck", 1.2, 1.5, -1)],
    "carve": [("hockeystop", 2.2, 2.4, -4), ("hockeystop2", 4.15, 2.6, -4), ("hockeystop2", 9.85, 1.6, -4)],
    "stride": [("skating", 0.95, 0.6, -8), ("skating2", 6.4, 0.8, -8), ("skating2", 8.1, 0.8, -8), ("skating2", 9.85, 0.8, -8)],
    "horn": [("goalhorn", 0.0, 2.9, -1)],
    # Crowd one-shots
    "goal_cheer": [("bigcheer", 0.0, 9.2, -1)],
    "cheer": [("crowdcheer", 0.0, 9.0, -2), ("crowdcheer2", 0.0, 9.4, -2)],
    "short_cheer": [("shortcheer", 0.0, 8.4, -3)],
    "boo": [("crowdboo", 0.0, 9.4, -2)],
    "big_boo": [("crowdbigboo", 0.0, 9.7, -2)],
    "rising": [("crowdgeneraltointerested", 0.0, 20.0, -2)],
    "chant_defense": [("chantdefense", 0.0, 10.0, -2)],
    "disappointed": [("crowddisappointed", 0.0, 8.4, -2)],
    "outrage": [("crowdoutragethenboo", 0.0, 12.0, -2)],
    # Organ
    "organ_charge": [("organcharge", 0.0, 3.5, -2)],
    "organ_upbeat": [("organupbeat", 0.55, 27.6, -2)],
    "chant_geese": [("chant_teamgeese", 0.0, 8.9, -2)],
    "chant_lobsters": [("chant_teamlobsters", 0.0, 10.0, -2)],
    "chant_quahogs": [("chant_teamquahogs", 0.5, 9.5, -2)],
    "chant_whalers": [("chant_teamwhalers", 0.0, 11.2, -2)],
}
# Recordings of several hits in a row, split automatically into one clip per hit:
# name: (source, quiet gap that separates hits in s, peak dB)
SPLITS = {
    "punch": ("punch", 0.06, -1),
    "punch_male": ("punch_male", 0.08, -2),
    "punch_female": ("punch_female", 0.08, -2),
}
LOOPS = {
    # name: (source, start, length, crossfade, peak dB)
    "crowd": ("crowdbaseline", 0.0, 20.0, 1.5, -3),
}


def ffmpeg_bin():
    exe = os.environ.get("FFMPEG") or shutil.which("ffmpeg")
    if not exe:
        sys.exit("ffmpeg not found: put it on PATH or set FFMPEG")
    return exe


def peak_db(ff, path, start, length):
    r = subprocess.run([ff, "-hide_banner", "-nostats", "-ss", str(start), "-t", str(length), "-i", path,
                        "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"max_volume: (-?[\d.]+) dB", r.stderr)
    return float(m.group(1)) if m else 0.0


def pcm(ff, path, rate=8000):
    r = subprocess.run([ff, "-v", "error", "-i", path, "-ac", "1", "-ar", str(rate), "-f", "s16le", "-"],
                       capture_output=True, check=True)
    b = r.stdout
    return struct.unpack("<%dh" % (len(b) // 2), b), rate


def intro_split(ff, path):
    """Seconds into the intro of the quietest 60 ms between its two halves."""
    s, rate = pcm(ff, path)
    w = rate // 50   # 20 ms frames
    env = [math.sqrt(sum(x * x for x in s[i:i + w]) / w) for i in range(0, len(s) - w, w)]
    dur = len(s) / rate
    lo, hi = int(INTRO_SPLIT_FROM * 50), int((dur - INTRO_SPLIT_TO_END) * 50)
    best, at = None, lo
    for i in range(lo, max(lo + 1, hi - 3)):
        m = sum(env[i:i + 3]) / 3
        if best is None or m < best:
            best, at = m, i
    return (at + 1.5) / 50.0, dur


def split_hits(ff, path, gap):
    """(start, length) of each loud stretch, split where it goes quiet for `gap` s."""
    s, rate = pcm(ff, path)
    w = rate // 100   # 10 ms frames
    env = [math.sqrt(sum(x * x for x in s[i:i + w]) / w) for i in range(0, len(s) - w, w)]
    peak = max(env) or 1.0
    loud = [e > peak * 0.08 for e in env]   # about -22 dB under the loudest moment
    hits, start, quiet = [], None, 0
    for i, on in enumerate(loud):
        if on:
            if start is None:
                start = i
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet * 0.01 >= gap:
                hits.append((start, i - quiet + 1))
                start = None
    if start is not None:
        hits.append((start, len(loud)))
    out = []
    for a, b in hits:
        if (b - a) * 0.01 < 0.05:
            continue   # a click, not a hit
        t0 = max(0.0, a * 0.01 - 0.01)
        out.append((t0, min(0.9, (b - a) * 0.01 + 0.12)))
    return out


def cut_splits(ff):
    for name, (src, gap, peak) in SPLITS.items():
        path = os.path.join(SRC, src + ".mp3")
        if not os.path.exists(path):
            continue
        for i, (start, length) in enumerate(split_hits(ff, path, gap)):
            gain = peak - peak_db(ff, path, start, length)
            fade = min(0.08, length * 0.3)
            af = "afade=t=in:d=0.003,afade=t=out:st=%.3f:d=%.3f,volume=%.2fdB" % (length - fade, fade, gain)
            out = os.path.join(OUT, "%s_%d.ogg" % (name, i))
            subprocess.run([ff, "-v", "error", "-y", "-ss", "%.3f" % start, "-t", "%.3f" % length, "-i", path,
                            "-af", af, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
            print("%-18s %s %.2f+%.2f" % (os.path.basename(out), src, start, length))


def cut_intros(ff):
    if not os.path.isdir(INTRO_DIR):
        return
    for f in sorted(os.listdir(INTRO_DIR)):
        m = re.match(r"intro_(\w+)\.(mp3|wav|ogg)$", f)
        if not m:
            continue
        team = m.group(1)
        path = os.path.join(INTRO_DIR, f)
        split, dur = intro_split(ff, path)
        gain = -1 - peak_db(ff, path, 0, dur)
        for part, start, length in (("home", 0.0, split), ("away", split, dur - split)):
            out = os.path.join(OUT, "intro_%s_%s_0.ogg" % (part, team))
            af = "afade=t=in:d=0.01,afade=t=out:st=%.3f:d=0.04,volume=%.2fdB" % (max(0.0, length - 0.04), gain)
            subprocess.run([ff, "-v", "error", "-y", "-ss", str(start), "-t", str(length), "-i", path,
                            "-af", af, "-c:a", "libvorbis", "-q:a", "6", out], check=True)
        print("intro %-14s split at %.2fs of %.2fs" % (team, split, dur))


def main():
    ff = ffmpeg_bin()
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    for name, parts in CLIPS.items():
        for i, (src, start, length, peak) in enumerate(parts):
            path = os.path.join(SRC, src + ".mp3")
            gain = peak - peak_db(ff, path, start, length)
            fade = min(0.25, length * 0.2)
            af = "afade=t=in:d=0.008,afade=t=out:st=%.3f:d=%.3f,volume=%.2fdB" % (length - fade, fade, gain)
            out = os.path.join(OUT, "%s_%d.ogg" % (name, i))
            subprocess.run([ff, "-v", "error", "-y", "-ss", str(start), "-t", str(length), "-i", path,
                            "-af", af, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
            print("%-16s %s %.2f+%.2f  gain %+.1f dB" % (os.path.basename(out), src, start, length, gain))
    for name, (src, start, length, xf, peak) in LOOPS.items():
        path = os.path.join(SRC, src + ".mp3")
        gain = peak - peak_db(ff, path, start, length)
        out = os.path.join(OUT, "%s_0.ogg" % name)
        # body = [start+xf, start+length]; its last xf seconds crossfade into [start, start+xf],
        # so the loop's end flows into its beginning.
        fc = ("[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS[body];"
              "[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS[head];"
              "[body][head]acrossfade=d=%.3f:c1=tri:c2=tri,volume=%.2fdB[out]"
              % (start + xf, start + length, start, start + xf, xf, gain))
        subprocess.run([ff, "-v", "error", "-y", "-i", path, "-filter_complex", fc, "-map", "[out]",
                        "-c:a", "libvorbis", "-q:a", "5", out], check=True)
        print("%-16s %s loop %.1fs (xfade %.1fs)  gain %+.1f dB" % (os.path.basename(out), src, length - xf, xf, gain))
    cut_intros(ff)
    cut_splits(ff)


if __name__ == "__main__":
    main()
