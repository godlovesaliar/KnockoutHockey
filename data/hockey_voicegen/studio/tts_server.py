"""
tts_server.py - an OpenAI-style speech endpoint for Chatterbox, so SillyTavern (or anything
that speaks the OpenAI TTS API) can use the same voices as the Studio.

    POST http://127.0.0.1:8004/v1/audio/speech   {"input": "...", "voice": "color"}
    GET  http://127.0.0.1:8004/v1/voices         the voice names it accepts

It reuses engine.py: voices come from hockey_voicegen/voices/ with their saved settings
(intensity, pace, temp), long text is chunked, and PyTorch stays at 2 CPU threads.
Don't run it at the same time as the Studio or voicegen: they each load their own model.

    venv\\Scripts\\python.exe studio\\tts_server.py [--port 8004]
"""

import io
import re
import shutil
import subprocess
import sys

import soundfile as sf
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

import engine as E

app = FastAPI(title="Chatterbox TTS bridge")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

BUILTIN_NAMES = {"", "default", "builtin", "built-in", E.BUILTIN.lower()}
MIME = {"wav": "audio/wav", "mp3": "audio/mpeg", "flac": "audio/flac", "opus": "audio/ogg"}


class Speech(BaseModel):
    input: str
    voice: str = "default"
    model: str = "chatterbox"
    response_format: str = "wav"
    speed: float = 1.0          # accepted for compatibility; Chatterbox has no speed control


def find_voice(name):
    """Voice id from an id ("color") or a display name ("Bobby Niedemyer"), any case."""
    key = (name or "").strip().lower()
    if key in BUILTIN_NAMES:
        return E.BUILTIN
    for display, vid in E.list_voices():
        if key in (vid.lower(), display.lower()):
            return vid
    return None


def clean(text):
    """Drop markdown marks so they aren't read aloud. Skipping *actions* is left to
    SillyTavern's own TTS options (ignore text in asterisks / only narrate quotes)."""
    text = re.sub(r"[*_`~#]+", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def encode(wav, sr, fmt):
    buf = io.BytesIO()
    sf.write(buf, wav, sr, format="WAV")
    data = buf.getvalue()
    if fmt == "wav":
        return data, fmt
    ff = shutil.which("ffmpeg")
    codec = {"mp3": ["-f", "mp3", "-b:a", "192k"], "flac": ["-f", "flac"],
             "opus": ["-f", "ogg", "-c:a", "libopus", "-b:a", "96k"]}.get(fmt)
    if not ff or not codec:
        return data, "wav"                     # no ffmpeg / unknown format: plain wav
    out = subprocess.run([ff, "-v", "error", "-i", "pipe:0", *codec, "pipe:1"],
                         input=data, capture_output=True, check=True)
    return out.stdout, fmt


@app.get("/v1/voices")
def voices():
    return {"voices": [{"id": vid, "name": display} for display, vid in E.list_voices()]}


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": "chatterbox", "object": "model"}]}


@app.post("/v1/audio/speech")
def speech(req: Speech):
    vid = find_voice(req.voice)
    if vid is None:
        names = ", ".join(v for _, v in E.list_voices()[1:])
        return JSONResponse({"error": f"Unknown voice '{req.voice}'. Try: {names}"}, 400)
    text = clean(req.input)
    if not text:
        return JSONResponse({"error": "Nothing to say."}, 400)
    meta = E.voice_meta(vid) if vid != E.BUILTIN else dict(E.DEFAULTS)
    try:
        wav, _ = E.ENGINE.generate(vid, text, meta["intensity"], meta["pace"], meta["temp"])
    except ValueError as e:
        return JSONResponse({"error": str(e)}, 400)
    wav = E.level(wav, E.ENGINE.sr)
    data, fmt = encode(wav, E.ENGINE.sr, (req.response_format or "wav").lower())
    print(f"[{vid}] {len(wav) / E.ENGINE.sr:.1f}s  {text[:70]}", flush=True)
    return Response(data, media_type=MIME.get(fmt, "audio/wav"))


if __name__ == "__main__":
    port = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv else 8004
    print("Loading Chatterbox...", flush=True)
    E.ENGINE.load()
    print(f"Ready on http://127.0.0.1:{port}/v1/audio/speech  (device: {E.ENGINE.device})")
    print("Voices:", ", ".join(v for _, v in E.list_voices()[1:]), flush=True)
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")
