"""
engine.py - Chatterbox model, voice library, generation and stitching for studio.py.

Voices live in hockey_voicegen/voices/ (shared with voicegen.py): <id>.wav or <id>.mp3 is
the reference clip, <id>.json its display name and default settings.
"""

import hashlib
import json
import random
import re
import shutil
import threading
import time
from pathlib import Path

import numpy as np
import soundfile as sf

STUDIO = Path(__file__).resolve().parent
TOOL = STUDIO.parent
VOICES = TOOL / "voices"
OUTPUT = STUDIO / "output"
PROJECTS = STUDIO / "projects"
CACHE = STUDIO / "cache"            # one wav per generated conversation line
TRASH = VOICES / ".trash"
for d in (VOICES, OUTPUT, PROJECTS, CACHE):
    d.mkdir(parents=True, exist_ok=True)

BUILTIN = "(built-in voice)"
AUDIO_EXT = (".wav", ".mp3", ".flac", ".ogg")
DEFAULTS = {"intensity": 0.5, "pace": 0.5, "temp": 0.8}
TARGET_LUFS = -18.0                  # every line is levelled to this before stitching
CPU_THREADS = 2                      # all threads hard-reset this PC under long runs
MAX_CHUNK = 250                      # characters per generation (Chatterbox stops ~40 s)

# ElevenLabs-style tags in text: stripped (Chatterbox would read them aloud); some set
# the delivery instead. Values: (intensity, pace) or None to just strip.
TAGS = {
    "excited": (0.8, 0.35),
    "shouting": (1.1, 0.3),
    "yelling": (1.1, 0.3),
    "angry": (0.9, 0.35),
    "calm": (0.3, 0.5),
    "sad": (0.35, 0.5),
    "whispers": (0.25, 0.5),
}


# ---------------------------------------------------------------- voice library

def slug(name):
    s = re.sub(r"[^a-z0-9]+", "_", name.strip().lower()).strip("_")
    return s or "voice"


def voice_file(vid):
    for ext in AUDIO_EXT:
        p = VOICES / f"{vid}{ext}"
        if p.exists():
            return p
    return None


def voice_meta(vid):
    meta = dict(DEFAULTS, name=vid, notes="")
    p = VOICES / f"{vid}.json"
    if p.exists():
        try:
            meta.update(json.loads(p.read_text(encoding="utf-8")))
        except ValueError:
            pass
    return meta


def list_voices():
    """[(display name, id)] for every reference clip in voices/, built-in first."""
    ids = sorted({p.stem for p in VOICES.iterdir() if p.suffix.lower() in AUDIO_EXT})
    return [(BUILTIN, BUILTIN)] + [(voice_meta(v)["name"], v) for v in ids]


def save_voice(name, audio_path, intensity, pace, temp, notes, old_id=None):
    """Store a voice. Editing (old_id) keeps the voice's id, so files that refer to it (like
    voicegen's pbp/color) keep working; the name is only for display. audio_path None
    keeps the existing clip. Returns the id."""
    if old_id:
        vid = old_id
    else:
        vid, n = slug(name), 2
        while voice_file(vid) or vid == BUILTIN:
            vid, n = f"{slug(name)}_{n}", n + 1
    if audio_path is None and voice_file(vid):
        pass                                    # settings-only edit: keep the clip as is
    else:
        src = Path(audio_path) if audio_path else (voice_file(old_id) if old_id else None)
        if src is None or not src.exists():
            raise ValueError("Add a reference clip first (upload or record 10-20 s of speech).")
        data, sr = sf.read(str(src), always_2d=True)
        mono = data.mean(axis=1).astype(np.float32)
        for ext in AUDIO_EXT:                   # one clip per voice
            old = VOICES / f"{vid}{ext}"
            if old.exists():
                old.unlink()
        sf.write(str(VOICES / f"{vid}.wav"), mono, sr)
    (VOICES / f"{vid}.json").write_text(json.dumps({
        "name": name.strip(), "intensity": intensity, "pace": pace, "temp": temp,
        "notes": notes or "",
    }, indent=2), encoding="utf-8")
    return vid


def delete_voice(vid):
    """Moves the voice into voices/.trash (not a hard delete)."""
    TRASH.mkdir(exist_ok=True)
    for p in VOICES.glob(f"{vid}.*"):
        if p.suffix.lower() in AUDIO_EXT + (".json",):
            shutil.move(str(p), str(TRASH / f"{p.stem}_{int(time.time())}{p.suffix}"))


def clip_seconds(path):
    try:
        info = sf.info(str(path))
        return info.frames / info.samplerate
    except Exception:
        return 0.0


# ---------------------------------------------------------------- text helpers

def parse_tags(text, intensity, pace):
    """Strip [tags]; the last known one sets intensity/pace."""
    for t in re.findall(r"\[([^\]]*)\]", text):
        if TAGS.get(t.strip().lower()):
            intensity, pace = TAGS[t.strip().lower()]
    clean = re.sub(r"\s*\[[^\]]*\]\s*", " ", text).strip()
    return clean, intensity, pace


def chunk_text(text, limit=MAX_CHUNK):
    """Split long text at sentence ends so each piece fits one generation."""
    sentences = re.split(r"(?<=[.!?…])\s+", text.strip())
    chunks, cur = [], ""
    for s in sentences:
        if len(s) > limit:                      # one huge sentence: split at commas
            parts = re.split(r"(?<=[,;:])\s+", s)
        else:
            parts = [s]
        for p in parts:
            if cur and len(cur) + 1 + len(p) > limit:
                chunks.append(cur)
                cur = p
            else:
                cur = f"{cur} {p}".strip()
    if cur:
        chunks.append(cur)
    return chunks or [text]


# ---------------------------------------------------------------- audio helpers

def trim_silence(wav, sr, thresh_db=-45.0, pad=0.05):
    if wav.size == 0:
        return wav
    level = 10 ** (thresh_db / 20) * max(1e-9, float(np.abs(wav).max()))
    loud = np.where(np.abs(wav) > level)[0]
    if loud.size == 0:
        return wav
    p = int(pad * sr)
    return wav[max(0, loud[0] - p): min(wav.size, loud[-1] + p)]


def level(wav, sr, lufs=TARGET_LUFS):
    """Loudness-match a clip (falls back to peak for clips too short to measure)."""
    import pyloudnorm as pyln
    if wav.size == 0:
        return wav
    try:
        loud = pyln.Meter(sr).integrated_loudness(wav) if wav.size > sr * 0.5 else None
    except ValueError:
        loud = None
    if loud is None or not np.isfinite(loud):
        gain = 0.5 / max(1e-9, float(np.abs(wav).max()))
    else:
        gain = 10 ** ((lufs - loud) / 20)
    out = wav * gain
    peak = float(np.abs(out).max())
    return out / peak * 0.98 if peak > 0.98 else out


def stitch(clips, sr, gaps):
    """clips: list of arrays; gaps: seconds of silence after each (negative = overlap)."""
    out = np.zeros(0, dtype=np.float32)
    for wav, gap in zip(clips, gaps):
        if gap < 0 and out.size:                # overlap: mix the start into the tail
            n = min(int(-gap * sr), out.size, wav.size)
            out[out.size - n:] += wav[:n]
            out = np.concatenate([out, wav[n:]])
        else:
            out = np.concatenate([out, wav])
        if gap > 0:
            out = np.concatenate([out, np.zeros(int(gap * sr), dtype=np.float32)])
    peak = float(np.abs(out).max()) if out.size else 0
    return out / peak * 0.98 if peak > 0.98 else out


def write_wav(path, wav, sr):
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(path), wav, sr)
    return str(path)


def write_mp3(wav_path):
    import subprocess
    ff = shutil.which("ffmpeg")
    if not ff:
        return None
    mp3 = Path(wav_path).with_suffix(".mp3")
    subprocess.run([ff, "-v", "error", "-y", "-i", str(wav_path), "-b:a", "192k", str(mp3)],
                   check=True)
    return str(mp3)


# ---------------------------------------------------------------- the model

class Engine:
    def __init__(self):
        self.model = None
        self.sr = 24000
        self.lock = threading.Lock()
        self._conds = {}         # (path, mtime) -> prepared reference
        self._builtin = None

    @property
    def device(self):
        import torch
        return "cuda" if torch.cuda.is_available() else "cpu"

    def load(self):
        if self.model is None:
            import torch
            from chatterbox.tts import ChatterboxTTS
            torch.set_num_threads(CPU_THREADS)
            self.model = ChatterboxTTS.from_pretrained(device=self.device)
            self.sr = self.model.sr
            self._builtin = self.model.conds
        return self.model

    def _use_voice(self, vid, intensity):
        """vid: a voice id, BUILTIN, or a path to an unsaved reference clip."""
        m = self.model
        if not vid or vid == BUILTIN:
            m.conds = self._builtin
            return
        path = Path(vid) if Path(str(vid)).suffix.lower() in AUDIO_EXT and Path(vid).exists() \
            else voice_file(vid)
        if path is None:
            raise ValueError(f"Voice '{vid}' has no reference clip.")
        key = (str(path), path.stat().st_mtime)
        if key not in self._conds:
            m.prepare_conditionals(str(path), exaggeration=intensity)
            self._conds[key] = m.conds
        m.conds = self._conds[key]

    def generate(self, vid, text, intensity=0.5, pace=0.5, temp=0.8, seed=-1):
        """One clip (long text is chunked and joined). Returns (float32 array, seed)."""
        import torch
        text, intensity, pace = parse_tags(text, intensity, pace)
        if not text:
            raise ValueError("Nothing to say.")
        seed = int(seed) if seed is not None and int(seed) >= 0 else random.randint(0, 2**31 - 1)
        with self.lock:
            self.load()
            self._use_voice(vid, intensity)
            torch.manual_seed(seed)
            parts = []
            for chunk in chunk_text(text):
                wav = self.model.generate(chunk, exaggeration=float(intensity),
                                          cfg_weight=float(pace), temperature=float(temp))
                parts.append(trim_silence(wav.squeeze(0).cpu().numpy().astype(np.float32), self.sr))
        gap = np.zeros(int(0.18 * self.sr), dtype=np.float32)
        out = parts[0]
        for p in parts[1:]:
            out = np.concatenate([out, gap, p])
        return out, seed


ENGINE = Engine()


def line_key(vid, text, intensity, pace, temp, seed):
    """Cache name for a conversation line: same voice clip + text + settings + seed."""
    path = voice_file(vid) if vid and vid != BUILTIN else None
    stamp = path.stat().st_mtime if path else 0
    raw = json.dumps([vid, stamp, text, intensity, pace, temp, seed])
    return hashlib.sha1(raw.encode()).hexdigest()[:16]
