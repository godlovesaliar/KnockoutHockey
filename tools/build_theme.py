"""Bakes the broadcast theme and the TV package's sounds into assets/sound/tv/.

    "E:\\Program Files\\Blender\\5.2\\python\\bin\\python.exe" tools/build_theme.py
    ... build_theme.py only=theme        (just the music)
    ... build_theme.py only=sfx          (just the whoosh / slam / clash / sting)
    ... build_theme.py theme=minor       (that theme becomes the game's: THEMES below lists them)
    ... build_theme.py options           (every theme into assets/sound/tv/options/theme_<name>.ogg,
                                          to compare; `-- theme=<name>` plays one in the game)

Needs numpy (Blender's bundled Python has it) and ffmpeg on PATH (or FFMPEG set).
Everything here is synthesized: no samples, no outside recordings.

The theme (theme.ogg) is written to the broadcast open's clock (BroadcastOpen in the game
reads the same numbers, keep them in step):

    130 BPM, 4/4.  A two-beat pickup, then eight bars of fanfare in four two-bar phrases,
    one per beat of the open (league title, home team, away team, the lockup), each
    starting on a big hit; then an eight-bar bed that loops for as long as it's needed
    (it plays on quietly under the booth's welcome). The loop point is the bed's first bar.

        0.000 s   pickup (snare roll, swell)
        0.923 s   bar 1   league title lands
        4.615 s   bar 3   home team
        8.308 s   bar 5   away team
       12.000 s   bar 7   the lockup (the clash)
       15.692 s   bar 9   bed, loops to here

Every theme in THEMES keeps that form (and its hits), so any of them fits the open as cut.

The sounds (tv_<name>.ogg; Sfx plays them by that name):
    tv_whoosh   a panel sweeping across the screen
    tv_slam     a logo landing
    tv_clash    the two crests meeting at the lockup
    tv_sting    the league stinger's sweep (in, the logo's thump, out)

To retune: change the notes or levels here, rerun, then let Godot reimport.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sound", "tv")

SR = 44100
BPM = 130.0
BEAT = 60.0 / BPM
BAR = 4.0 * BEAT
PICKUP = 2.0 * BEAT
FANFARE_BARS = 8
BED_BARS = 8
TAIL = 3.0

rng = np.random.default_rng(7)


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# --- Building blocks -------------------------------------------------------------------

def shaped_noise(n, lo, hi, edge=0.35):
    """White noise kept between lo and hi Hz (soft edges, `edge` octaves wide)."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = 1e-6
    up = 1.0 / (1.0 + (lo / f) ** (2.0 / edge))
    down = 1.0 / (1.0 + (f / hi) ** (2.0 / edge))
    out = np.fft.irfft(spec * up * down, n)
    return out / (np.max(np.abs(out)) + 1e-9)


def adsr(n, attack, decay, sustain, hold, release):
    """An envelope `n` samples long: up in `attack`, down to `sustain` over `decay`,
    held until `hold` seconds, then out over `release`."""
    t = np.arange(n) / SR
    env = np.where(t < attack, t / max(attack, 1e-5),
                   sustain + (1.0 - sustain) * np.exp(-(t - attack) / max(decay, 1e-5)))
    rel = np.clip((t - hold) / max(release, 1e-5), 0.0, 1.0)
    return env * (1.0 - rel) ** 2


def horn(freq, dur, bright=1.0, voices=(-7.0, 0.0, 6.0), attack=0.03, vib=0.0035, cutoff=2900.0):
    """A brass section note: detuned saws built harmonic by harmonic, each harmonic's
    level following a filter that opens hard on the attack (the 'blat') and settles."""
    n = int((dur + 0.16) * SR)
    t = np.arange(n) / SR
    amp = adsr(n, attack, 0.12, 0.82, dur, 0.13)
    # The filter: wide open just after the attack, then down to the sustain's color.
    fc = cutoff * bright * (1.0 + 1.5 * np.exp(-t / 0.09)) * (0.35 + 0.65 * np.minimum(t / attack, 1.0))
    # A little vibrato that comes in on held notes.
    wob = 1.0 + vib * np.sin(2.0 * np.pi * 5.6 * t) * np.clip((t - 0.25) / 0.3, 0.0, 1.0)
    out = np.zeros(n)
    top = int(min(40, (0.45 * SR) // freq))
    for cents in voices:
        f0 = freq * 2.0 ** (cents / 1200.0)
        phase = 2.0 * np.pi * np.cumsum(f0 * wob) / SR + rng.uniform(0, 2.0 * np.pi)
        for h in range(1, top + 1):
            level = (1.0 / h) / np.sqrt(1.0 + (h * f0 / fc) ** 4)
            out += level * np.sin(h * phase)
    return out * amp / len(voices)


def string_pluck(freq, dur, bright=1.0):
    """A short bowed-string stab for the running sixteenths."""
    n = int((dur + 0.08) * SR)
    t = np.arange(n) / SR
    amp = adsr(n, 0.006, 0.07, 0.35, dur, 0.07)
    out = np.zeros(n)
    top = int(min(14, (0.45 * SR) // freq))
    for cents in (-9.0, 8.0):
        f0 = freq * 2.0 ** (cents / 1200.0)
        phase = 2.0 * np.pi * f0 * t + rng.uniform(0, 2.0 * np.pi)
        for h in range(1, top + 1):
            out += (1.0 / h) / (1.0 + (h * f0 / (2600.0 * bright)) ** 2) * np.sin(h * phase)
    return out * amp * 0.5


def pad(freq, dur):
    """A soft held section note under everything."""
    n = int((dur + 0.4) * SR)
    t = np.arange(n) / SR
    amp = adsr(n, 0.12, 0.3, 0.8, dur, 0.38)
    out = np.zeros(n)
    top = int(min(8, (0.45 * SR) // freq))
    for cents in (-11.0, -3.0, 4.0, 12.0):
        f0 = freq * 2.0 ** (cents / 1200.0)
        phase = 2.0 * np.pi * f0 * t + rng.uniform(0, 2.0 * np.pi)
        for h in range(1, top + 1):
            out += (1.0 / h) / (1.0 + (h * f0 / 1400.0) ** 2) * np.sin(h * phase)
    return out * amp * 0.25


def bass(freq, dur):
    n = int((dur + 0.05) * SR)
    t = np.arange(n) / SR
    amp = adsr(n, 0.004, 0.09, 0.6, dur, 0.04)
    fc = 500.0 + 1400.0 * np.exp(-t / 0.05)
    phase = 2.0 * np.pi * freq * t
    out = 0.9 * np.sin(phase)
    for h in range(2, 13):
        out += (1.0 / h) / np.sqrt(1.0 + (h * freq / fc) ** 4) * np.sin(h * phase)
    return out * amp


def kick():
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 46.0 + 120.0 * np.exp(-t / 0.028)
    body = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16)
    click = shaped_noise(n, 1500.0, 6000.0) * np.exp(-t / 0.004) * 0.5
    return np.tanh((body + click) * 1.6)


def snare(tone=1.0):
    n = int(0.36 * SR)
    t = np.arange(n) / SR
    drum = (np.sin(2.0 * np.pi * 186.0 * t) + 0.6 * np.sin(2.0 * np.pi * 331.0 * t)) * np.exp(-t / 0.055)
    wires = shaped_noise(n, 900.0, 9000.0) * np.exp(-t / 0.1)
    return np.tanh((drum * 0.7 * tone + wires) * 1.3)


def hat(open_=False):
    n = int((0.35 if open_ else 0.09) * SR)
    t = np.arange(n) / SR
    return shaped_noise(n, 7000.0, 15000.0) * np.exp(-t / (0.11 if open_ else 0.022))


def tom(freq):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = freq * (1.0 + 0.5 * np.exp(-t / 0.03))
    body = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.17)
    skin = shaped_noise(n, 400.0, 3500.0) * np.exp(-t / 0.02) * 0.4
    return np.tanh((body + skin) * 1.3)


def timpani(freq):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, level, tau in ((1.0, 1.0, 0.55), (1.5, 0.55, 0.42), (2.0, 0.35, 0.3), (2.5, 0.2, 0.2), (3.0, 0.12, 0.14)):
        out += level * np.sin(2.0 * np.pi * freq * ratio * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    strike = shaped_noise(n, 150.0, 2200.0) * np.exp(-t / 0.018) * 0.7
    return np.tanh((out + strike) * 0.9)


def crash(length=2.2, tau=0.6):
    n = int(length * SR)
    t = np.arange(n) / SR
    wash = shaped_noise(n, 3200.0, 14000.0) * np.exp(-t / tau)
    ring = np.zeros(n)
    for f in (3120.0, 4270.0, 5390.0, 6810.0, 8230.0):
        ring += np.sin(2.0 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (tau * 0.7))
    stick = shaped_noise(n, 2000.0, 9000.0) * np.exp(-t / 0.012)
    return wash + ring * 0.05 + stick * 0.5


def swell(length):
    """A reversed-cymbal rise that ends at its last sample."""
    n = int(length * SR)
    t = np.arange(n) / SR
    return shaped_noise(n, 2500.0, 13000.0) * np.exp((t - length) / (length * 0.28))


def reverb_ir(tau, seed):
    """A hall: a noise burst dying away, darker as it goes; different per ear."""
    r = np.random.default_rng(seed)
    n = int(tau * 7.5 * SR)
    t = np.arange(n) / SR
    spec = np.fft.rfft(r.standard_normal(n) * np.exp(-t / tau))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = 1e-6
    spec *= 1.0 / (1.0 + (220.0 / f) ** 2) / (1.0 + (f / 5200.0) ** 2)
    ir = np.fft.irfft(spec, n)
    ir = np.concatenate([np.zeros(int(0.018 * SR)), ir])
    return ir / np.sqrt(np.sum(ir ** 2))


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]


class Mix:
    """A stereo mix with a reverb send."""

    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.dry = np.zeros((2, self.n))
        self.send = np.zeros((2, self.n))

    def add(self, sig, at, gain=1.0, pan=0.0, wet=0.2):
        """`sig` at `at` seconds; pan -1 (left) to 1 (right); `wet`: how much goes to the hall."""
        i = int(round(at * SR))
        if i < 0:
            sig = sig[-i:]
            i = 0
        m = min(len(sig), self.n - i)
        if m <= 0:
            return
        ang = (pan + 1.0) * 0.25 * math.pi
        for ch, g in ((0, math.cos(ang)), (1, math.sin(ang))):
            self.dry[ch, i:i + m] += sig[:m] * gain * g * 1.414
            self.send[ch, i:i + m] += sig[:m] * gain * g * 1.414 * wet

    def render(self, tau=0.3, hall=1.0):
        out = self.dry.copy()
        for ch in range(2):
            out[ch] += convolve(self.send[ch], reverb_ir(tau, 11 + ch))[:self.n] * hall
        return out


def shelf(x, lift_db, corner=3200.0, floor=32.0):
    """The mix's tone: a high shelf of `lift_db` from `corner` up, and nothing below `floor`."""
    n = x.shape[1]
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = 1e-6
    g = 10.0 ** (lift_db / 20.0)
    curve = (1.0 + (g - 1.0) * f ** 2 / (f ** 2 + corner ** 2)) / (1.0 + (floor / f) ** 4)
    return np.stack([np.fft.irfft(np.fft.rfft(x[ch]) * curve, n) for ch in range(2)])


def master(x, drive=1.25, peak=0.89):
    """Glues the mix (a soft clip) and sets its peak."""
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = np.tanh(x * drive) / math.tanh(drive)
    return x * peak


def write(name, x, quality=6, out_dir=None):
    """Writes a (2, n) float mix to assets/sound/tv/<name>.ogg (or into `out_dir`)."""
    ff = os.environ.get("FFMPEG") or shutil.which("ffmpeg")
    if not ff:
        sys.exit("ffmpeg not found: put it on PATH or set FFMPEG")
    out_dir = out_dir or OUT
    os.makedirs(out_dir, exist_ok=True)
    pcm = (np.clip(x.T, -1.0, 1.0) * 32767.0).astype("<i2")
    tmp = os.path.join(tempfile.gettempdir(), "kh_%s.wav" % name)
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    out = os.path.join(out_dir, name + ".ogg")
    subprocess.run([ff, "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), out], check=True)
    os.remove(tmp)
    rms = 20.0 * math.log10(math.sqrt(float(np.mean(x ** 2))) + 1e-9)
    print("%-14s %6.2f s   rms %.1f dB" % (name + ".ogg", x.shape[1] / SR, rms))


# --- The theme -------------------------------------------------------------------------

# Chords: the bass root, the section's voicing, the pad's, and the strings' running figure.
# The "5" chords are bare fifths (no third), for the guitars.
CHORDS = {
    "D": {"root": 38, "section": (57, 62, 66), "pad": (50, 57, 62, 66), "run": (62, 69, 74, 69)},
    "C": {"root": 36, "section": (55, 60, 64), "pad": (48, 55, 60, 64), "run": (60, 67, 72, 67)},
    "G": {"root": 43, "section": (55, 59, 62), "pad": (43, 55, 59, 62), "run": (62, 67, 71, 67)},
    "Bb": {"root": 34, "section": (58, 62, 65), "pad": (46, 53, 58, 62), "run": (58, 65, 70, 65)},
    "Dm": {"root": 38, "section": (57, 62, 65), "pad": (50, 57, 62, 65), "run": (62, 65, 69, 65)},
    "Gm": {"root": 43, "section": (55, 58, 62), "pad": (43, 55, 58, 62), "run": (62, 67, 70, 67)},
    "A": {"root": 33, "section": (57, 61, 64), "pad": (45, 57, 61, 64), "run": (61, 64, 69, 64)},
    "E5": {"root": 40, "section": (52, 59, 64), "pad": (40, 52, 59, 64), "run": (64, 71, 76, 71)},
    "G5": {"root": 43, "section": (55, 62, 67), "pad": (43, 55, 62, 67), "run": (62, 67, 74, 67)},
    "A5": {"root": 45, "section": (57, 64, 69), "pad": (45, 57, 64, 69), "run": (64, 69, 76, 69)},
    "C5": {"root": 36, "section": (55, 60, 67), "pad": (48, 55, 60, 67), "run": (60, 67, 72, 67)},
    "D5": {"root": 38, "section": (57, 62, 69), "pad": (50, 57, 62, 69), "run": (62, 69, 74, 69)},
}


def phrase(bar, notes):
    """A bar of the fanfare's rhythm (da, da-da, da, da, DAAA) on six notes; bar 0 = bar 1."""
    rhythm = ((0.0, 0.75), (0.75, 0.25), (1.0, 0.5), (1.5, 0.5), (2.0, 0.5), (2.5, 1.5))
    return [(bar * 4.0 + b, length, n) for (b, length), n in zip(rhythm, notes)]


def ending(top, climb, step):
    """Bars 7 and 8: the arrival held, three notes climbing back to it, then the last stabs."""
    return [(24.0, 2.5, top), (26.5, 0.5, climb[0]), (27.0, 0.5, climb[1]), (27.5, 0.5, climb[2]),
            (28.0, 0.75, top), (28.75, 0.25, top), (29.0, 0.5, top), (30.0, 0.5, step), (30.5, 1.5, top)]


# The themes. Each: its feel (`style`), the fanfare's eight chords and the bed's, the tune
# ((beat, length in beats, midi note), beat 0 = bar 1's downbeat) and the bed's quiet horn
# line (beats from the bed's first bar), the chord the arrival holds, the pickup's timpani.
#   fanfare  the original: bright brass over a rock beat and running strings.
#   rock     guitars in fifths chugging eighths under the brass, a harder beat, no strings.
#   epic     half-time: war drums, low brass, strings in eighths an octave down, a broad tune.
THEMES = {
    # The first one: heroic, in D with the flat seventh. Bright.
    "fanfare": {
        "style": "fanfare", "dominant": 45, "arrival": (50, 57, 62, 66, 69),
        "chords": ["D", "C", "G", "D", "Bb", "C", "D", "D"],
        "bed": ["D", "C", "G", "D", "D", "C", "Bb", "C"],
        "tune": [(-1.0, 0.5, 69), (-0.5, 0.25, 69), (-0.25, 0.25, 69)]
                + phrase(0, (74, 74, 74, 69, 74, 78)) + phrase(1, (76, 76, 76, 72, 76, 79))
                + phrase(2, (79, 78, 79, 74, 71, 74)) + phrase(3, (78, 76, 78, 74, 69, 74))
                + phrase(4, (77, 77, 77, 74, 77, 82)) + phrase(5, (79, 79, 79, 76, 79, 84))
                + ending(86, (81, 83, 85), 84),
        "bed_tune": [(0.0, 2.0, 62), (2.0, 2.0, 69), (4.0, 3.0, 67), (7.0, 1.0, 64), (8.0, 2.0, 67), (10.0, 2.0, 71),
                     (12.0, 4.0, 69), (16.0, 2.0, 62), (18.0, 2.0, 69), (20.0, 3.0, 67), (23.0, 1.0, 72),
                     (24.0, 2.0, 70), (26.0, 2.0, 74), (28.0, 2.0, 72), (30.0, 2.0, 76)],
    },
    # The same fanfare in D minor: the tune's thirds come down, the fifth bar leans on the
    # dominant with its leading note. Serious where the first one is sunny.
    "minor": {
        "style": "fanfare", "dominant": 45, "arrival": (50, 57, 62, 65, 69),
        "chords": ["Dm", "C", "Bb", "Dm", "Gm", "A", "Dm", "Dm"],
        "bed": ["Dm", "C", "Bb", "Dm", "Dm", "C", "Bb", "A"],
        "tune": [(-1.0, 0.5, 69), (-0.5, 0.25, 69), (-0.25, 0.25, 69)]
                + phrase(0, (74, 74, 74, 69, 74, 77)) + phrase(1, (76, 76, 76, 72, 76, 79))
                + phrase(2, (77, 77, 77, 74, 70, 74)) + phrase(3, (81, 79, 81, 77, 76, 74))
                + phrase(4, (79, 79, 79, 74, 79, 82)) + phrase(5, (81, 81, 81, 76, 81, 85))
                + ending(86, (81, 82, 85), 84),
        "bed_tune": [(0.0, 2.0, 62), (2.0, 2.0, 69), (4.0, 3.0, 67), (7.0, 1.0, 64), (8.0, 2.0, 65), (10.0, 2.0, 70),
                     (12.0, 4.0, 69), (16.0, 2.0, 62), (18.0, 2.0, 69), (20.0, 3.0, 67), (23.0, 1.0, 72),
                     (24.0, 2.0, 70), (26.0, 2.0, 74), (28.0, 2.0, 73), (30.0, 2.0, 76)],
    },
    # Arena rock in E: guitars in fifths, a five-note tune (no sweet thirds anywhere).
    "rock": {
        "style": "rock", "dominant": 47, "arrival": (52, 59, 64, 71, 76),
        "chords": ["E5", "G5", "A5", "E5", "C5", "D5", "E5", "E5"],
        "bed": ["E5", "E5", "G5", "A5", "E5", "E5", "C5", "D5"],
        "tune": [(-1.0, 0.5, 71), (-0.5, 0.25, 71), (-0.25, 0.25, 71)]
                + phrase(0, (76, 76, 76, 71, 76, 79)) + phrase(1, (79, 79, 79, 74, 79, 83))
                + phrase(2, (81, 79, 81, 76, 74, 76)) + phrase(3, (79, 76, 79, 76, 74, 76))
                + phrase(4, (79, 79, 79, 76, 79, 84)) + phrase(5, (81, 81, 81, 78, 81, 86))
                + ending(88, (83, 86, 87), 86),
        "bed_tune": [(0.0, 2.0, 64), (2.0, 2.0, 71), (4.0, 3.0, 67), (7.0, 1.0, 69), (8.0, 2.0, 71), (10.0, 2.0, 74),
                     (12.0, 4.0, 76), (16.0, 2.0, 64), (18.0, 2.0, 71), (20.0, 3.0, 67), (23.0, 1.0, 69),
                     (24.0, 2.0, 67), (26.0, 2.0, 72), (28.0, 2.0, 69), (30.0, 2.0, 74)],
    },
    # The main event: D minor at half the pace. War drums, low brass, a broad tune of long notes.
    "epic": {
        "style": "epic", "dominant": 45, "arrival": (50, 57, 62, 65, 69),
        "chords": ["Dm", "Dm", "Bb", "C", "Gm", "A", "Dm", "Dm"],
        "bed": ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"],
        "tune": [(-1.0, 1.0, 69),
                 (0.0, 1.5, 74), (1.5, 0.5, 77), (2.0, 0.5, 76), (2.5, 1.5, 74), (4.0, 2.0, 81), (6.0, 1.0, 79), (7.0, 1.0, 77),
                 (8.0, 1.5, 77), (9.5, 0.5, 79), (10.0, 0.5, 77), (10.5, 1.5, 74), (12.0, 2.0, 76), (14.0, 2.0, 79),
                 (16.0, 1.5, 79), (17.5, 0.5, 82), (18.0, 0.5, 81), (18.5, 1.5, 79), (20.0, 2.0, 81), (22.0, 2.0, 85),
                 (24.0, 3.5, 86), (27.5, 0.5, 85),
                 (28.0, 0.75, 86), (28.75, 0.25, 86), (29.0, 0.5, 86), (30.0, 0.5, 84), (30.5, 1.5, 86)],
        "bed_tune": [(0.0, 4.0, 62), (4.0, 2.0, 65), (6.0, 2.0, 64), (8.0, 4.0, 62), (12.0, 2.0, 65), (14.0, 2.0, 70),
                     (16.0, 4.0, 67), (20.0, 2.0, 70), (22.0, 2.0, 69), (24.0, 4.0, 69), (28.0, 2.0, 73), (30.0, 2.0, 76)],
    },
}
DEFAULT_THEME = "rock"   # the one written to theme.ogg (the game's): the user's pick, 2026-11-24


def guitar(freq, dur, mute=False):
    """A power chord (root, fifth, octave) through a hard clip and a speaker; `mute`: palm-muted."""
    n = int((dur + 0.08) * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, level in ((1.0, 1.0), (1.5, 0.8), (2.0, 0.55)):
        f0 = freq * ratio * 2.0 ** (rng.uniform(-6.0, 6.0) / 1200.0)
        phase = 2.0 * np.pi * f0 * t + rng.uniform(0, 2.0 * np.pi)
        for h in range(1, int(min(9, (0.2 * SR) // f0)) + 1):
            x += level / h * np.sin(h * phase)
    x = np.tanh(x * (2.2 if mute else 3.2))
    # The speaker: nothing much below the low string or above the cone.
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = 1e-6
    spec *= 1.0 / (1.0 + (70.0 / f) ** 4) / (1.0 + (f / (1700.0 if mute else 3800.0)) ** 4)
    x = np.fft.irfft(spec, n)
    return x * adsr(n, 0.004, 0.07 if mute else 0.5, 0.2 if mute else 0.75, dur, 0.06)


def build_theme(name=DEFAULT_THEME, out_name="theme", out_dir=None):
    global rng
    rng = np.random.default_rng(7)
    th = THEMES[name]
    style = th["style"]
    total = PICKUP + (FANFARE_BARS + BED_BARS) * BAR + TAIL
    mix = Mix(total)
    k, sn, hh, oh = kick(), snare(), hat(), hat(True)
    big_sn = snare(1.4)
    toms = [tom(f) for f in (196.0, 147.0, 110.0, 82.0)]
    war = [tom(f) for f in (98.0, 73.0)]

    def at(beat):
        return PICKUP + beat * BEAT

    # Pickup: a snare roll and a swell into bar 1, timpani on the dominant.
    for i in range(8):
        mix.add(sn, at(-2.0 + i * 0.25), 0.16 + 0.07 * i, 0.05, 0.25)
    mix.add(swell(PICKUP), 0.0, 0.3, 0.0, 0.3)
    for b in (-2.0, -1.0, -0.5):
        mix.add(timpani(hz(th["dominant"])), at(b), 0.45, -0.15, 0.3)

    for bar in range(FANFARE_BARS + BED_BARS):
        bed = bar >= FANFARE_BARS
        ch = CHORDS[th["bed"][bar - FANFARE_BARS] if bed else th["chords"][bar]]
        b0 = bar * 4.0
        phrase_start = bar % 2 == 0 and not bed
        last_of_phrase = (bar % 2 == 1 and not bed) or bar == FANFARE_BARS + BED_BARS - 1
        big_finish = bar == FANFARE_BARS - 1
        level = 0.72 if bed else 1.0
        # (the fills take over the end of a bar: nothing else drums through them)
        open_until = 2.0 if big_finish else (3.0 if last_of_phrase else 4.0)

        # Drums.
        if style == "epic":
            # Half-time: the kick on one, a big snare on three, low toms rolling between them.
            for b in [0.0, 2.5] + ([3.5] if bar % 2 == 1 else []):
                if b < open_until:
                    mix.add(k, at(b0 + b), 0.95 * level, 0.0, 0.06)
            if 2.0 < open_until:
                mix.add(big_sn, at(b0 + 2.0), 0.85 * level, 0.05, 0.4)
            for b, which in ((0.75, 1), (1.5, 1), (3.0, 0), (3.5, 1)):
                if b < open_until:
                    mix.add(war[which], at(b0 + b), 0.5 * level, -0.3 if which else 0.3, 0.3)
            for i in range(4):
                if i < open_until:
                    mix.add(hh, at(b0 + i), 0.16 * level, 0.3, 0.1)
        else:
            # Kick on one and three (with a push), snare on two and four, eighths on the hat.
            rock = style == "rock"
            kicks = ([0.0, 1.5, 2.0, 2.5] if rock else [0.0, 1.5, 2.0]) + ([3.5] if bar % 2 == 1 else [])
            for b in kicks:
                if b < open_until:
                    mix.add(k, at(b0 + b), (0.9 if rock else 0.8) * level, 0.0, 0.05)
            for b in (1.0, 3.0):
                if b < open_until:
                    mix.add(sn, at(b0 + b), (0.8 if rock else 0.72) * level, 0.05, 0.22)
            for i in range(8):
                if i * 0.5 < open_until:
                    wide = (rock and i % 2 == 0) or (i == 7 and bar % 4 == 3)
                    mix.add(oh if wide else hh, at(b0 + i * 0.5), (0.34 if i % 2 == 0 else 0.2) * level * (0.7 if rock and wide else 1.0), 0.3, 0.08)
        # A tom fill out of each phrase; the last fanfare bar gets a two-beat roll into the bed.
        if big_finish:
            for i in range(8):
                mix.add(sn, at(b0 + 2.0 + i * 0.125), 0.2 + 0.05 * i, 0.05, 0.25)
            for i, tm in enumerate((0, 0, 1, 1, 2, 2, 3, 3)):
                mix.add(toms[tm], at(b0 + 3.0 + i * 0.125), 0.5 + 0.04 * i, -0.5 + i * 0.14, 0.2)
            mix.add(swell(2.0 * BEAT), at(b0 + 2.0), 0.3, 0.0, 0.3)
            for i in range(4):
                mix.add(timpani(hz(ch["root"] if ch["root"] >= 38 else ch["root"] + 12)), at(b0 + 2.0 + i * 0.5), 0.3 + 0.08 * i, -0.15, 0.3)
        elif last_of_phrase:
            for i, tm in enumerate((0, 1, 2, 3)):
                mix.add(toms[tm], at(b0 + 3.0 + i * 0.25), (0.5 + 0.05 * i) * level, -0.45 + i * 0.3, 0.2)
        # The hit that starts each phrase: a crash and timpani on the root (the lockup's is the biggest).
        if phrase_start or bar == FANFARE_BARS:
            big = 1.25 if bar == 6 else (0.8 if bed else 1.0)
            mix.add(crash(), at(b0), 0.42 * big, -0.2, 0.3)
            mix.add(crash(1.8, 0.45), at(b0), 0.3 * big, 0.35, 0.3)
            mix.add(timpani(hz(ch["root"] + 12)), at(b0), 0.6 * big, -0.15, 0.3)
        elif bed and bar % 4 == 0:
            mix.add(crash(1.6, 0.4), at(b0), 0.16, 0.2, 0.3)
        elif style == "epic":
            mix.add(timpani(hz(ch["root"] + 12)), at(b0), 0.4 * level, -0.15, 0.3)

        # Bass: driving eighths on the root, the octave on the last one.
        for i in range(8):
            if big_finish and i >= 6:
                continue
            note = ch["root"] + (12 if i == 7 else 0)
            mix.add(bass(hz(note), BEAT * 0.42), at(b0 + i * 0.5), (0.36 if i % 2 == 0 else 0.29) * level, 0.0, 0.03)

        if style == "rock":
            # Guitars, one each side: the chord struck on one, palm-muted eighths after it.
            low = ch["root"] if ch["root"] >= 40 else ch["root"] + 12
            for side in (-0.75, 0.75):
                g = 0.2 * (0.7 if bed else 1.0)
                mix.add(guitar(hz(low), BEAT * 0.9), at(b0), g, side, 0.12)
                for i in range(2, 8):
                    if big_finish and i >= 4:
                        continue
                    mix.add(guitar(hz(low), BEAT * 0.3, True), at(b0 + i * 0.5), g * (0.95 if i % 2 == 0 else 0.75), side, 0.08)
                if big_finish:
                    mix.add(guitar(hz(low), BEAT * 1.9), at(b0 + 2.0), g, side, 0.15)
        elif style == "epic":
            # Strings: eighths through the chord an octave down, dark.
            for i in range(8):
                note = ch["run"][i % 4] - 12
                g = (0.24 if i % 2 == 0 else 0.16) * (0.8 if bed else 1.0)
                mix.add(string_pluck(hz(note), BEAT * 0.36, 0.55), at(b0 + i * 0.5), g, -0.5, 0.35)
                mix.add(string_pluck(hz(note + 12), BEAT * 0.36, 0.5), at(b0 + i * 0.5), g * 0.5, 0.5, 0.35)
        else:
            # Strings: running sixteenths through the chord, one desk on each side.
            for i in range(16):
                note = ch["run"][i % 4]
                g = (0.17 if i % 4 == 0 else 0.11) * (0.8 if bed else 1.0)
                mix.add(string_pluck(hz(note), BEAT * 0.2), at(b0 + i * 0.25), g, -0.55, 0.3)
                mix.add(string_pluck(hz(note + 12), BEAT * 0.2, 0.8), at(b0 + i * 0.25), g * 0.6, 0.55, 0.3)

        # The pad under it all.
        for note in ch["pad"]:
            mix.add(pad(hz(note), BAR), at(b0), 0.2 if bed else 0.15, 0.0, 0.4)

        # The section under the tune.
        if not bed and bar < 6 and style == "epic":
            # Low brass holding the chord, a tuba on its root.
            for j, note in enumerate(ch["section"]):
                mix.add(horn(hz(note - 12), 3.6 * BEAT, 0.7, (-6.0, 5.0), 0.06), at(b0), 0.16, (j - 1) * 0.5, 0.35)
            mix.add(horn(hz(ch["root"] + 12), 3.6 * BEAT, 0.6, (-5.0, 4.0), 0.06), at(b0), 0.2, 0.0, 0.3)
        elif not bed and bar < 6:
            # Three stabs with the tune, then the chord held.
            for (b, length) in ((0.0, 0.75), (0.75, 0.25), (1.0, 0.5), (2.5, 1.5)):
                for j, note in enumerate(ch["section"]):
                    mix.add(horn(hz(note), length * BEAT * 0.88, 0.75, (-6.0, 5.0)), at(b0 + b), 0.15, (j - 1) * 0.5, 0.3)
        elif not bed:
            # The arrival: the full chord, held (bar 7), then the last bar's stabs with the tune.
            hits = ((0.0, 3.5),) if bar == 6 else ((0.0, 0.75), (0.75, 0.25), (1.0, 0.5), (2.0, 0.5), (2.5, 1.5))
            for (b, length) in hits:
                for j, note in enumerate(th["arrival"]):
                    mix.add(horn(hz(note), length * BEAT * 0.9, 0.85, (-6.0, 5.0)), at(b0 + b), 0.13, (j - 2) * 0.3, 0.3)

    # The tune: trumpets, doubled an octave down (the main event's sits lower and darker,
    # with trombones two octaves under it).
    lead = {"fanfare": 1.15, "rock": 1.25, "epic": 0.95}[style]
    for (b, length, note) in th["tune"]:
        held = length >= 1.0
        dur = length * BEAT * (0.96 if held else 0.82)
        mix.add(horn(hz(note), dur, lead), at(b), 0.44 if style != "epic" else 0.36, 0.08, 0.32)
        mix.add(horn(hz(note - 12), dur, 0.9), at(b), 0.22 if style != "epic" else 0.3, -0.12, 0.32)
        if style == "epic":
            mix.add(horn(hz(note - 24), dur, 0.8, (-5.0, 4.0), 0.05), at(b), 0.2, 0.15, 0.32)
    # The bed's horn line: mellow, well back.
    for (b, length, note) in th["bed_tune"]:
        mix.add(horn(hz(note), length * BEAT * 0.95, 0.5, (-5.0, 4.0), 0.08), at(FANFARE_BARS * 4.0 + b), 0.2, -0.1, 0.45)
        mix.add(horn(hz(note - 12), length * BEAT * 0.95, 0.45, (-5.0, 4.0), 0.08), at(FANFARE_BARS * 4.0 + b), 0.12, 0.2, 0.45)

    out = mix.render(0.3, 0.9)
    # The loop: what rings on past the bed's end is folded into its start, then the file
    # ends exactly on the bar line (the game loops back to the bed's first bar).
    s0 = int(round((PICKUP + FANFARE_BARS * BAR) * SR))
    s1 = int(round((PICKUP + (FANFARE_BARS + BED_BARS) * BAR) * SR))
    tail = out[:, s1:]
    out[:, s0:s0 + tail.shape[1]] += tail
    out = master(shelf(out[:, :s1], 6.0), 1.4)
    write(out_name, out, 6, out_dir)
    print("  %s: loop from %.5f s, bar 1 at %.5f s, a bar is %.5f s" % (name, s0 / SR, PICKUP, BAR))


def build_options():
    """Every theme, side by side in assets/sound/tv/options/ (kept out of the game's import
    by a .gdignore), to listen to and to try in the game with `-- theme=<name>`."""
    out_dir = os.path.join(OUT, "options")
    os.makedirs(out_dir, exist_ok=True)
    open(os.path.join(out_dir, ".gdignore"), "w").close()
    for name in THEMES:
        build_theme(name, "theme_" + name, out_dir)


# --- The sounds ------------------------------------------------------------------------

def sweep_filter(x, fc, damp=0.5):
    """A band-pass whose centre follows `fc` (Hz per sample)."""
    out = np.empty_like(x)
    low = band = 0.0
    f = 2.0 * np.sin(np.pi * np.minimum(fc, SR / 7.0) / SR)
    for i in range(len(x)):
        low += f[i] * band
        high = x[i] - low - damp * band
        band += f[i] * high
        out[i] = band
    return out


def whoosh(length, peak_at=0.6, f_lo=350.0, f_hi=4200.0, f_end=900.0):
    """Air rushing past: noise through a band-pass that climbs to `peak_at` (a share of the
    length) and falls away; a (2, n) array, the two ears a little different."""
    n = int(length * SR)
    u = np.arange(n) / n
    rise = np.clip(u / peak_at, 0.0, 1.0)
    fall = np.clip((u - peak_at) / (1.0 - peak_at), 0.0, 1.0)
    fc = np.where(u < peak_at, f_lo * (f_hi / f_lo) ** (rise ** 1.6), f_hi * (f_end / f_hi) ** fall)
    env = np.where(u < peak_at, rise ** 2.4, (1.0 - fall) ** 1.8)
    out = np.zeros((2, n))
    for ch in range(2):
        air = sweep_filter(rng.standard_normal(n), fc * (1.0 + 0.07 * ch), 0.45)
        body = shaped_noise(n, 90.0, 420.0) * 0.5
        out[ch] = (air / (np.max(np.abs(air)) + 1e-9) + body) * env
    return out


def boom(length, f_from=120.0, f_to=38.0, tau=0.3):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = f_to + (f_from - f_to) * np.exp(-t / 0.05)
    sub = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau)
    punch = shaped_noise(n, 60.0, 900.0) * np.exp(-t / 0.035)
    return np.tanh((sub + punch * 0.8) * 1.5)


def metal(length, partials, tau, seed):
    """A struck plate: partials that don't line up, the higher ones dying sooner."""
    r = np.random.default_rng(seed)
    n = int(length * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i, f in enumerate(partials):
        out += np.sin(2.0 * np.pi * f * t + r.uniform(0, 6.28)) * np.exp(-t / (tau / (1.0 + i * 0.35))) / (1.0 + i * 0.25)
    return out / len(partials) * 2.0


def stereo(sig, pan=0.0):
    ang = (pan + 1.0) * 0.25 * math.pi
    return np.stack([sig * math.cos(ang), sig * math.sin(ang)]) * 1.414


def place(buf, sig, at, gain=1.0):
    i = int(at * SR)
    m = min(sig.shape[1], buf.shape[1] - i)
    if m > 0:
        buf[:, i:i + m] += sig[:, :m] * gain


def with_hall(buf, tau, amount):
    out = buf.copy()
    for ch in range(2):
        out[ch] += convolve(buf[ch], reverb_ir(tau, 31 + ch))[:buf.shape[1]] * amount
    return out


def fade_out(buf, seconds):
    n = int(seconds * SR)
    buf[:, -n:] *= np.linspace(1.0, 0.0, n) ** 2
    return buf


def build_sfx():
    # A panel sweeping in: one pass of air.
    buf = np.zeros((2, int(0.75 * SR)))
    place(buf, whoosh(0.6, 0.62), 0.0)
    write("tv_whoosh", fade_out(with_hall(buf, 0.12, 0.25), 0.1) / np.max(np.abs(buf)) * 0.7)

    # A logo landing: a low thump with a little steel in it.
    buf = np.zeros((2, int(1.3 * SR)))
    place(buf, stereo(boom(1.0, 125.0, 40.0, 0.26)), 0.0, 1.0)
    place(buf, stereo(metal(0.7, (523.0, 811.0, 1370.0, 1930.0, 2710.0), 0.22, 3), -0.2), 0.0, 0.16)
    place(buf, stereo(shaped_noise(int(0.25 * SR), 1800.0, 9000.0) * np.exp(-np.arange(int(0.25 * SR)) / SR / 0.03), 0.2), 0.0, 0.3)
    write("tv_slam", master(fade_out(with_hall(buf, 0.16, 0.35), 0.25), 1.2, 0.85))

    # The crests meeting: the big one. Boom, steel on steel, a wash of cymbal.
    buf = np.zeros((2, int(2.4 * SR)))
    place(buf, stereo(boom(1.6, 150.0, 34.0, 0.42)), 0.0, 1.0)
    place(buf, stereo(metal(1.4, (417.0, 689.0, 1012.0, 1489.0, 2153.0, 2890.0, 3760.0, 4920.0), 0.5, 5), -0.35), 0.0, 0.3)
    place(buf, stereo(metal(1.2, (466.0, 743.0, 1187.0, 1702.0, 2440.0, 3310.0, 4380.0), 0.42, 6), 0.35), 0.012, 0.26)
    place(buf, stereo(crash(2.0, 0.5), -0.15), 0.0, 0.22)
    place(buf, stereo(crash(1.7, 0.4), 0.3), 0.0, 0.16)
    place(buf, stereo(shaped_noise(int(0.3 * SR), 1500.0, 10000.0) * np.exp(-np.arange(int(0.3 * SR)) / SR / 0.025)), 0.0, 0.45)
    write("tv_clash", master(fade_out(with_hall(buf, 0.24, 0.4), 0.5), 1.3, 0.89))

    # The league stinger: the band rushes in, the logo thumps as it settles, the band leaves.
    buf = np.zeros((2, int(1.25 * SR)))
    place(buf, whoosh(0.34, 0.78, 300.0, 5000.0, 1500.0), 0.0, 0.9)
    place(buf, stereo(boom(0.6, 105.0, 46.0, 0.16)), 0.285, 0.75)
    place(buf, stereo(metal(0.5, (880.0, 1318.0, 1975.0, 2637.0, 3520.0), 0.2, 9), 0.1), 0.285, 0.12)
    place(buf, whoosh(0.42, 0.45, 500.0, 3600.0, 600.0), 0.58, 0.7)
    write("tv_sting", master(fade_out(with_hall(buf, 0.14, 0.3), 0.2), 1.15, 0.8))


def main():
    only = [a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("only=")]
    pick = [a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("theme=")]
    if "options" in sys.argv[1:]:
        build_options()
        return
    if pick and pick[0] not in THEMES:
        sys.exit("no theme '%s': %s" % (pick[0], ", ".join(THEMES)))
    if (not only and not pick) or "sfx" in only:
        build_sfx()
    if not only or "theme" in only:
        build_theme(pick[0] if pick else DEFAULT_THEME)


if __name__ == "__main__":
    main()
