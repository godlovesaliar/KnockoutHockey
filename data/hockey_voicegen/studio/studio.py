"""
studio.py - a local Chatterbox studio: clone and save voices, text to speech, and
multi-character conversations (each line generated on its own, then stitched).

    venv\\Scripts\\python.exe studio\\studio.py      (or double-click studio.bat)

Opens in your browser at http://127.0.0.1:7860. Don't run it while voicegen.py is
generating: both load the model onto the same GPU.
"""

import json
import re
import sys
import time
from pathlib import Path

import gradio as gr

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import common as C  # noqa: E402  (voicegen's helpers: game paths, mp3 export, kept.csv)
import engine as E  # noqa: E402

EXAMPLE_SCRIPT = """# One line per speaker: "Name: text". Tags like [excited] or [calm] set the delivery.
# (pause 1.5) adds extra silence after the previous line.
Steve: Good evening, everyone, and welcome to the rink.
Bobby: [excited] Steve, I have been waiting ALL week for this one!
Steve: [calm] Steady on, Bobby. The puck hasn't even dropped yet.
(pause 0.8)
Bobby: [laughs] That's never stopped me before!
"""


# ---------------------------------------------------------------- shared helpers

def voice_choices(builtin=True):
    v = E.list_voices()
    return v if builtin else v[1:]


def settings_for(vid):
    m = E.voice_meta(vid) if vid and vid != E.BUILTIN else dict(E.DEFAULTS)
    return float(m["intensity"]), float(m["pace"]), float(m["temp"])


def stamp():
    return time.strftime("%Y%m%d_%H%M%S")


def err(e):
    raise gr.Error(str(e))


# ---------------------------------------------------------------- voices tab

def load_voice(vid):
    if not vid:
        return "", None, 0.5, 0.5, 0.8, "", "", None
    m = E.voice_meta(vid)
    clip = E.voice_file(vid)
    secs = E.clip_seconds(clip) if clip else 0
    return (m["name"], str(clip) if clip else None, m["intensity"], m["pace"], m["temp"],
            m.get("notes", ""), clip_note(secs), vid)


def clip_note(secs):
    if not secs:
        return ""
    tip = ""
    if secs < 6:
        tip = " - a bit short; 10-20 s clones better"
    elif secs > 30:
        tip = " - long; trim it to the best 10-20 s"
    return f"Reference clip: {secs:.1f} s{tip}"


def new_voice():
    return "", None, 0.5, 0.5, 0.8, "", "", None, gr.Dropdown(value=None)


def ref_changed(path):
    return clip_note(E.clip_seconds(path)) if path else ""


def test_voice(name, ref, intensity, pace, temp, text, editing):
    ref_or_id = ref or editing
    if not ref_or_id:
        err("Upload or record a reference clip first.")
    try:
        wav, seed = E.ENGINE.generate(ref_or_id, text, intensity, pace, temp)
    except Exception as e:
        err(e)
    path = E.write_wav(E.OUTPUT / "tests" / f"test_{E.slug(name or 'voice')}_{seed}.wav",
                       E.level(wav, E.ENGINE.sr), E.ENGINE.sr)
    return path


def save_voice(name, ref, intensity, pace, temp, notes, editing):
    if not (name or "").strip():
        err("Give the voice a name.")
    # A clip loaded from the library is the saved one; only pass a new upload/recording.
    saved = E.voice_file(editing) if editing else None
    new_clip = ref if ref and not (saved and Path(ref).resolve() == saved.resolve()) else None
    try:
        vid = E.save_voice(name, new_clip, intensity, pace, temp, notes, old_id=editing)
    except Exception as e:
        err(e)
    gr.Info(f"Saved voice '{name.strip()}'.")
    return (gr.Dropdown(choices=voice_choices(False), value=vid), vid,
            gr.Dropdown(choices=voice_choices()), time.time())


def delete_voice(editing):
    if not editing:
        err("Pick a voice from the library first.")
    if editing in ("pbp", "color", "pa_announcer"):
        err("Steve (pbp), Bobby (color) and the PA announcer are used by voicegen.py - not deleting them here.")
    E.delete_voice(editing)
    gr.Info("Moved to voices/.trash.")
    return (gr.Dropdown(choices=voice_choices(False), value=None), None,
            gr.Dropdown(choices=voice_choices()), time.time())


# ---------------------------------------------------------------- TTS tab

MAX_TAKES = 5


def tts_generate(vid, text, intensity, pace, temp, seed, takes, mp3, progress=gr.Progress()):
    if not (text or "").strip():
        err("Type something to say.")
    outs = []
    takes = int(takes)
    for n in range(takes):
        progress(n / takes, desc=f"Take {n + 1} of {takes}")
        s = int(seed) + n if seed is not None and int(seed) >= 0 else -1
        try:
            wav, used = E.ENGINE.generate(vid, text, intensity, pace, temp, s)
        except Exception as e:
            err(e)
        name = E.slug(E.voice_meta(vid)["name"]) if vid != E.BUILTIN else "builtin"
        path = E.write_wav(E.OUTPUT / "tts" / f"{stamp()}_{name}_{used}.wav",
                           E.level(wav, E.ENGINE.sr), E.ENGINE.sr)
        if mp3:
            E.write_mp3(path)
        outs.append(gr.Audio(value=path, visible=True, label=f"Take {n + 1} (seed {used})"))
    outs += [gr.Audio(value=None, visible=False)] * (MAX_TAKES - len(outs))
    return outs


# ---------------------------------------------------------------- conversation tab

def parse_script(script, old_lines):
    """Script text -> line dicts. Lines whose speaker and text didn't change keep their
    seed, intensity override and audio."""
    pool = {}
    for ln in old_lines or []:
        pool.setdefault((ln["speaker"], ln["text"]), []).append(ln)
    lines = []
    for raw in (script or "").splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        m = re.match(r"^\(\s*pause\s+([\d.]+)\s*s?\s*\)$", s, re.I)
        if m:
            if lines:
                lines[-1]["pause"] = float(m.group(1))
            continue
        m = re.match(r"^([^:\[\]()]{1,40}):\s*(.+)$", s)
        if not m:
            if lines:                       # a wrapped line continues the previous one
                lines[-1]["text"] += " " + s
            continue
        speaker, text = m.group(1).strip(), m.group(2).strip()
        prev = pool.get((speaker, text))
        ln = dict(prev.pop(0)) if prev else {"speaker": speaker, "text": text,
                                             "intensity": None, "seed": None, "audio": None}
        ln["pause"] = None
        lines.append(ln)
    return lines


def speakers(lines):
    seen = []
    for ln in lines:
        if ln["speaker"] not in seen:
            seen.append(ln["speaker"])
    return seen


def guess_voice(speaker):
    """'Steve' -> the voice named 'Steve Sheldon', etc."""
    s = speaker.lower()
    for name, vid in voice_choices(False):
        n = name.lower()
        if s == vid or s == n or n.split()[0] == s.split()[0]:
            return vid
    return E.BUILTIN


def line_settings(ln, cast):
    vid = cast.get(ln["speaker"]) or E.BUILTIN
    if vid != E.BUILTIN and not E.voice_file(vid):
        vid = E.BUILTIN
    intensity, pace, temp = settings_for(vid)
    if ln.get("intensity") is not None:
        intensity = float(ln["intensity"])
    return vid, intensity, pace, temp


def render_line(ln, cast):
    """Generate one line if its cached audio doesn't match its current settings."""
    vid, intensity, pace, temp = line_settings(ln, cast)
    if ln.get("seed") is None:
        ln["seed"] = E.random.randint(0, 2**31 - 1)
    key = E.line_key(vid, ln["text"], intensity, pace, temp, ln["seed"])
    path = E.CACHE / f"{key}.wav"
    if not path.exists():
        wav, _ = E.ENGINE.generate(vid, ln["text"], intensity, pace, temp, ln["seed"])
        E.write_wav(path, E.level(E.trim_silence(wav, E.ENGINE.sr), E.ENGINE.sr), E.ENGINE.sr)
    ln["audio"] = str(path)


def stitch_lines(lines, gap, name):
    import soundfile as sf
    clips, gaps = [], []
    sr = E.ENGINE.sr
    for ln in lines:
        if not ln.get("audio") or not Path(ln["audio"]).exists():
            return None
        wav, sr = sf.read(ln["audio"], dtype="float32")
        clips.append(wav)
        gaps.append(ln["pause"] if ln.get("pause") is not None else float(gap))
    if not clips:
        return None
    gaps[-1] = max(0.0, gaps[-1])
    out = E.stitch(clips, sr, gaps)
    return E.write_wav(E.OUTPUT / "conversations" / f"{E.slug(name or 'conversation')}_{stamp()}.wav",
                       out, sr)


def conv_sync(script, lines, cast):
    lines = parse_script(script, lines)
    cast = dict(cast or {})
    for sp in speakers(lines):
        cast.setdefault(sp, guess_voice(sp))
    return lines, cast, time.time()


def conv_generate(script, lines, cast, gap, name, mp3, progress=gr.Progress()):
    lines, cast, _ = conv_sync(script, lines, cast)
    if not lines:
        err('No lines found. Write them as "Name: text", one per line.')
    for i, ln in enumerate(lines):
        progress(i / len(lines), desc=f"Line {i + 1} of {len(lines)}: {ln['speaker']}")
        try:
            render_line(ln, cast)
        except Exception as e:
            err(f"Line {i + 1}: {e}")
    out = stitch_lines(lines, gap, name)
    if out and mp3:
        E.write_mp3(out)
    return lines, cast, out, time.time()


def conv_redo(i, lines, cast, gap, name, mp3):
    ln = lines[i]
    ln["seed"] = E.random.randint(0, 2**31 - 1)
    try:
        render_line(ln, cast)
    except Exception as e:
        err(e)
    out = stitch_lines(lines, gap, name)
    if out and mp3:
        E.write_mp3(out)
    return lines, out, time.time()


def export_duet(out_path, name):
    """Send the stitched conversation to the game as a Steve & Bobby duet."""
    name = (name or "").strip().lower()
    if not out_path or not Path(out_path).exists():
        err("Generate the conversation first.")
    if not re.fullmatch(r"[a-z0-9_]+", name):
        err("Pick a duet line (letters, digits and _ only).")
    dest = C.duet_dest(name)
    try:
        C.export_mp3(Path(out_path), dest, "both")
    except Exception as e:
        err(f"Export failed: {e}")
    kept = C.read_kept()
    rel = dest.relative_to(C.SOUND).as_posix()
    kept.append({"take": Path(out_path).name, "id": dest.stem, "line": C.take_base(dest.stem),
                 "voice": "both", "game_file": rel})
    C.write_kept(kept)
    gr.Info(f"Exported to assets/sound/{rel}")
    return f"Last export: `assets/sound/{rel}`"


def project_list():
    return sorted(p.stem for p in E.PROJECTS.glob("*.json"))


def save_project(name, script, lines, cast, gap):
    if not (name or "").strip():
        err("Name the conversation first.")
    data = {"name": name.strip(), "script": script, "cast": cast, "gap": gap,
            "lines": [{k: ln.get(k) for k in ("speaker", "text", "intensity", "seed", "pause")}
                      for ln in lines]}
    (E.PROJECTS / f"{E.slug(name)}.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    gr.Info(f"Saved '{name.strip()}'.")
    return gr.Dropdown(choices=project_list(), value=E.slug(name))


def load_project(pid):
    p = E.PROJECTS / f"{pid}.json"
    if not pid or not p.exists():
        err("Pick a saved conversation.")
    d = json.loads(p.read_text(encoding="utf-8"))
    lines = d.get("lines", [])
    cast = d.get("cast", {})
    for ln in lines:            # point at cached audio if it's still there
        vid, intensity, pace, temp = line_settings(ln, cast)
        key = E.line_key(vid, ln["text"], intensity, pace, temp, ln.get("seed"))
        path = E.CACHE / f"{key}.wav"
        ln["audio"] = str(path) if path.exists() else None
    return d.get("name", pid), d.get("script", ""), lines, cast, d.get("gap", 0.35), time.time()


# ---------------------------------------------------------------- UI

CSS = """
.line-row {border-bottom: 1px solid var(--border-color-primary); padding: 6px 0;}
.speaker {font-weight: 600;}
"""


def build():
    with gr.Blocks(title="Chatterbox Studio") as demo:
        gr.Markdown("## Chatterbox Studio")
        voices_version = gr.Number(value=0, visible=False)

        # ------------------------------------------------ Voices
        with gr.Tab("Voices"):
            editing = gr.State(None)
            with gr.Row():
                with gr.Column(scale=1):
                    library = gr.Dropdown(choices=voice_choices(False), value=None,
                                          label="Voice library", interactive=True)
                    new_btn = gr.Button("New voice")
                    gr.Markdown(
                        "**Cloning tips:** 10-20 seconds of one person speaking, no music or "
                        "echo, in the style you want back (an energetic read clones energetic). "
                        "Record yourself or friends **with their permission**, and don't clone "
                        "real public figures. Drag the waveform handles to trim.")
                with gr.Column(scale=2):
                    v_name = gr.Textbox(label="Name")
                    v_ref = gr.Audio(label="Reference clip", sources=["upload", "microphone"],
                                     type="filepath", editable=True)
                    v_info = gr.Markdown()
                    with gr.Row():
                        v_int = gr.Slider(0.25, 2.0, 0.5, step=0.05, label="Intensity (exaggeration)")
                        v_pace = gr.Slider(0.0, 1.0, 0.5, step=0.05, label="Pace (cfg weight)")
                        v_temp = gr.Slider(0.05, 1.5, 0.8, step=0.05, label="Variation (temperature)")
                    v_notes = gr.Textbox(label="Notes", lines=2)
                    v_test_text = gr.Textbox(label="Test line",
                                             value="This is how I sound. Pretty good, right?")
                    with gr.Row():
                        test_btn = gr.Button("Test")
                        save_btn = gr.Button("Save voice", variant="primary")
                        del_btn = gr.Button("Delete voice", variant="stop")
                    v_test_out = gr.Audio(label="Test result", interactive=False)

        # ------------------------------------------------ TTS
        with gr.Tab("Text to Speech"):
            with gr.Row():
                with gr.Column(scale=2):
                    t_voice = gr.Dropdown(choices=voice_choices(), value=E.BUILTIN, label="Voice")
                    t_text = gr.Textbox(label="Text", lines=6,
                                        placeholder="Type anything. Long text is split at sentences "
                                                    "and joined. [excited], [calm] etc. set delivery.")
                    with gr.Row():
                        t_int = gr.Slider(0.25, 2.0, 0.5, step=0.05, label="Intensity")
                        t_pace = gr.Slider(0.0, 1.0, 0.5, step=0.05, label="Pace")
                        t_temp = gr.Slider(0.05, 1.5, 0.8, step=0.05, label="Variation")
                    with gr.Row():
                        t_takes = gr.Slider(1, MAX_TAKES, 1, step=1, label="Takes")
                        t_seed = gr.Number(-1, precision=0, label="Seed (-1 = random)")
                        t_mp3 = gr.Checkbox(False, label="Also save mp3")
                    t_btn = gr.Button("Generate", variant="primary")
                with gr.Column(scale=2):
                    t_outs = [gr.Audio(visible=(n == 0), interactive=False, label=f"Take {n + 1}")
                              for n in range(MAX_TAKES)]
                    gr.Markdown(f"Files are saved in `{E.OUTPUT / 'tts'}`.")

        # ------------------------------------------------ Conversation
        with gr.Tab("Conversation"):
            lines = gr.State([])
            cast = gr.State({})
            version = gr.Number(value=0, visible=False)
            with gr.Row():
                with gr.Column(scale=3):
                    c_name = gr.Textbox(label="Conversation name", value="conversation")
                    c_script = gr.Textbox(label="Script", lines=12, value=EXAMPLE_SCRIPT)
                    with gr.Row():
                        c_gap = gr.Slider(-0.5, 2.0, 0.35, step=0.05,
                                          label="Gap between lines (s, negative = overlap)")
                        c_mp3 = gr.Checkbox(True, label="Also save mp3")
                    with gr.Row():
                        c_sync = gr.Button("Update cast")
                        c_btn = gr.Button("Generate conversation", variant="primary")
                    c_out = gr.Audio(label="Conversation", interactive=False)
                with gr.Column(scale=2):
                    gr.Markdown("**Cast**: who voices each character")

                    @gr.render(inputs=[lines, cast], triggers=[version.change, voices_version.change])
                    def cast_ui(lines_v, cast_v):
                        sps = speakers(lines_v)
                        if not sps:
                            gr.Markdown("*Write some lines, then press Update cast.*")
                        for sp in sps:
                            dd = gr.Dropdown(choices=voice_choices(), label=sp, interactive=True,
                                             value=cast_v.get(sp, E.BUILTIN))

                            def set_cast(v, c, sp=sp):
                                c = dict(c)
                                c[sp] = v
                                return c
                            dd.change(set_cast, [dd, cast], cast)
                    with gr.Accordion("Send to game (Steve & Bobby duet)", open=False):
                        d_name = gr.Dropdown(choices=C.duet_lines(), allow_custom_value=True,
                                             label="Duet line", info="banter_goal, intro_duet, "
                                             "banter_<team> ... a second export becomes <name>2")
                        d_btn = gr.Button("Export to announcer/both/")
                        d_info = gr.Markdown()
                    with gr.Accordion("Save / load", open=False):
                        p_pick = gr.Dropdown(choices=project_list(), label="Saved conversations")
                        with gr.Row():
                            p_save = gr.Button("Save")
                            p_load = gr.Button("Load")

            gr.Markdown("**Lines** - listen, nudge a line's intensity, or redo just that line.")

            @gr.render(inputs=[lines], triggers=[version.change])
            def lines_ui(lines_v):
                for i, ln in enumerate(lines_v):
                    with gr.Row(elem_classes="line-row", equal_height=True):
                        gr.Markdown(f"<span class='speaker'>{i + 1}. {ln['speaker']}</span>  \n"
                                    f"{ln['text']}")
                        inten = gr.Number(value=ln.get("intensity"), label="Intensity (blank = voice)",
                                          minimum=0.25, maximum=2.0, step=0.05, scale=0, min_width=150)
                        gr.Audio(value=ln.get("audio"), interactive=False, show_label=False,
                                 scale=2, buttons=["download"])
                        redo = gr.Button("Redo", scale=0, min_width=80)

                    def set_int(v, ls, i=i):
                        ls = [dict(x) for x in ls]
                        ls[i]["intensity"] = v
                        return ls
                    inten.change(set_int, [inten, lines], lines)
                    redo.click(lambda ls, c, g, n, m, i=i: conv_redo(i, ls, c, g, n, m),
                               [lines, cast, c_gap, c_name, c_mp3], [lines, c_out, version])

        # ------------------------------------------------ wiring
        vfields = [v_name, v_ref, v_int, v_pace, v_temp, v_notes, v_info, editing]
        library.change(load_voice, library, vfields)
        new_btn.click(new_voice, None, vfields + [library])
        v_ref.change(ref_changed, v_ref, v_info)
        test_btn.click(test_voice, [v_name, v_ref, v_int, v_pace, v_temp, v_test_text, editing],
                       v_test_out)
        save_btn.click(save_voice, [v_name, v_ref, v_int, v_pace, v_temp, v_notes, editing],
                       [library, editing, t_voice, voices_version])
        del_btn.click(delete_voice, editing, [library, editing, t_voice, voices_version]).then(
            new_voice, None, vfields + [library])

        t_voice.change(settings_for, t_voice, [t_int, t_pace, t_temp])
        t_btn.click(tts_generate, [t_voice, t_text, t_int, t_pace, t_temp, t_seed, t_takes, t_mp3],
                    t_outs)

        c_sync.click(conv_sync, [c_script, lines, cast], [lines, cast, version])
        c_script.blur(conv_sync, [c_script, lines, cast], [lines, cast, version])
        c_btn.click(conv_generate, [c_script, lines, cast, c_gap, c_name, c_mp3],
                    [lines, cast, c_out, version])
        d_btn.click(export_duet, [c_out, d_name], d_info)
        p_save.click(save_project, [c_name, c_script, lines, cast, c_gap], p_pick)
        p_load.click(load_project, p_pick, [c_name, c_script, lines, cast, c_gap, version])
        demo.load(conv_sync, [c_script, lines, cast], [lines, cast, version])
    return demo


if __name__ == "__main__":
    build().queue().launch(
        inbrowser="--no-browser" not in sys.argv, server_name="127.0.0.1", server_port=7860,
        theme=gr.themes.Soft(), css=CSS, allowed_paths=[str(E.TOOL)])
