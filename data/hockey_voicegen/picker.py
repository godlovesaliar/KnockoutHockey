"""
picker.py - audition takes and put the good ones straight into the game.

Keys:
    Space        replay current take
    Left/Right   previous / next take of this row
    Up/Down      previous / next row
    N            next row with nothing kept yet
    K            KEEP this take -> trimmed, loudness-matched mp3 in
                 assets/sound/announcer/<pbp|color>/ (row name, or <line>_NN for extra takes),
                 or assets/sound/intro/intro_<team>.mp3 for team intros (then _<team>2 ...)
    X            un-keep (removes this row's kept files from the game)
    R            mark row for redo (adds it to redo_list.txt)

The game plays every take of a line at random, so keep 3 or so per line (the counter
shows how many the line has from this tool). Godot picks new files up the next time
the editor gets focus. If you kept or removed team intros, closing the picker re-runs
tools/cut_sounds.py to cut them into home/away halves.
After a session:  python voicegen.py --redo-list   for anything you marked.
"""

import csv
import sys
import tkinter as tk
from collections import OrderedDict

import subprocess

from common import (CUT_SOUNDS, LOG_CSV, REDO_FILE, SOUND, TAKES_DIR, export_mp3, ffmpeg,
                    is_team_intro, keeper_dest, load_todo, read_kept, write_kept)

# ---- audio playback: winsound is built into Windows Python, no install needed
try:
    import winsound

    def play(path):
        winsound.PlaySound(str(path), winsound.SND_FILENAME | winsound.SND_ASYNC)

    def stop():
        winsound.PlaySound(None, winsound.SND_PURGE)
except ImportError:  # Mac/Linux fallback
    import sounddevice as sd
    import soundfile as sf

    def play(path):
        data, sr = sf.read(str(path))
        sd.stop()
        sd.play(data, sr)

    def stop():
        sd.stop()

NAMES = {"pbp": "Steve", "color": "Bobby", "pa": "PA"}


def load_takes():
    lines = OrderedDict()
    for f in sorted(TAKES_DIR.glob("*_take*.wav")):
        line_id, _, n = f.stem.rpartition("_take")
        lines.setdefault(line_id, []).append((int(n), f))
    for k in lines:
        lines[k].sort()
        lines[k] = [f for _, f in lines[k]]
    return lines


def load_info():
    """id -> {text, line, voice} and take file -> its own text, from the generation log
    (a row with variants gives each take different text)."""
    info, take_texts = {}, {}
    if LOG_CSV.exists():
        with open(LOG_CSV, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                info[row["id"]] = row
                take_texts[row["file"]] = row["text"]
    return info, take_texts


class Picker:
    def __init__(self, root):
        if not ffmpeg():
            sys.exit("ffmpeg isn't on PATH - it's needed to export keepers as mp3.")
        self.lines = load_takes()
        if not self.lines:
            sys.exit("No takes found in takes/. Run voicegen.py first.")
        self.info, self.take_texts = load_info()
        todo = load_todo()
        self.target = todo.get("target", 3)
        self.targets = {k: v.get("target", self.target) for k, v in todo.get("lines", {}).items()}
        self.kept = read_kept()
        self.ids = list(self.lines)
        self.li = 0
        self.ti = 0
        self.intros_changed = False

        root.title("Knockout Hockey - Take Picker")
        root.geometry("780x340")
        root.configure(bg="#111")
        lbl = dict(bg="#111", fg="#eee")
        self.pos = tk.Label(root, font=("Consolas", 11), **lbl)
        self.pos.pack(pady=(14, 0))
        self.idl = tk.Label(root, font=("Consolas", 18, "bold"), **lbl)
        self.idl.pack(pady=6)
        self.text = tk.Label(root, font=("Segoe UI", 15), wraplength=720, **lbl)
        self.text.pack(pady=6)
        self.take = tk.Label(root, font=("Consolas", 22, "bold"), bg="#111", fg="#4fc3f7")
        self.take.pack(pady=6)
        self.status = tk.Label(root, font=("Consolas", 12), bg="#111", fg="#9ccc65")
        self.status.pack(pady=4)
        tk.Label(root, text="Space replay | Left/Right take | Up/Down row | N next unkept | "
                 "K keep | X un-keep | R redo",
                 font=("Consolas", 10), bg="#111", fg="#777").pack(side="bottom", pady=10)

        for key, fn in {"<space>": self.replay, "<Left>": lambda e: self.move_take(-1),
                        "<Right>": lambda e: self.move_take(1), "<Up>": lambda e: self.move_line(-1),
                        "<Down>": lambda e: self.move_line(1), "n": self.next_unkept,
                        "N": self.next_unkept, "k": self.keep, "K": self.keep,
                        "x": self.unkeep, "X": self.unkeep, "r": self.redo, "R": self.redo}.items():
            root.bind(key, fn)
        self.refresh(play_it=True)

    # ---- helpers
    @property
    def line_id(self):
        return self.ids[self.li]

    @property
    def row(self):
        return self.info.get(self.line_id, {})

    @property
    def takes(self):
        return self.lines[self.line_id]

    def kept_for(self, key, value):
        return [k for k in self.kept if k[key] == value]

    def refresh(self, play_it=False, msg=""):
        mine = self.kept_for("id", self.line_id)
        line = self.row.get("line", "?")
        on_line = len(self.kept_for("line", line))
        who = NAMES.get(self.row.get("voice"), self.row.get("voice", "?"))
        self.pos.config(text=f"row {self.li + 1} of {len(self.ids)}   |   line '{line}' ({who}): "
                             f"{on_line} / {self.targets.get(line, self.target)} kept")
        self.idl.config(text=self.line_id, fg="#9ccc65" if mine else "#eee")
        self.text.config(text=self.take_texts.get(self.takes[self.ti].name, self.row.get("text", "")))
        taken = {k["take"] for k in mine}
        mark = "  (kept)" if self.takes[self.ti].name in taken else ""
        self.take.config(text=f"take {self.ti + 1} / {len(self.takes)}{mark}")
        self.status.config(text=msg or ("kept: " + ", ".join(k["game_file"] for k in mine)
                                        if mine else ""))
        if play_it:
            play(self.takes[self.ti])

    # ---- actions
    def replay(self, e=None):
        play(self.takes[self.ti])

    def move_take(self, d):
        self.ti = (self.ti + d) % len(self.takes)
        self.refresh(play_it=True)

    def move_line(self, d):
        stop()
        self.li = (self.li + d) % len(self.ids)
        self.ti = 0
        self.refresh(play_it=True)

    def next_unkept(self, e=None):
        for step in range(1, len(self.ids) + 1):
            i = (self.li + step) % len(self.ids)
            if not self.kept_for("id", self.ids[i]):
                stop()
                self.li, self.ti = i, 0
                return self.refresh(play_it=True)
        self.refresh(msg="every row has a keeper")

    def keep(self, e=None):
        self.kept = read_kept()     # studio.py may have added duets since
        take = self.takes[self.ti]
        if any(k["take"] == take.name for k in self.kept):
            return self.refresh(msg="this take is already in the game")
        voice = self.row.get("voice")
        if voice not in NAMES:
            return self.refresh(msg="no voice for this row in takes/_log.csv")
        dest = keeper_dest(self.line_id, self.row.get("line", ""), voice)
        try:
            export_mp3(take, dest, voice)
        except Exception as ex:  # ffmpeg failed
            return self.refresh(msg=f"export failed: {ex}")
        self.kept.append({"take": take.name, "id": self.line_id, "line": self.row.get("line", ""),
                          "voice": voice, "game_file": dest.relative_to(SOUND).as_posix()})
        write_kept(self.kept)
        self.intros_changed |= is_team_intro(self.row.get("line", ""))
        self.refresh(msg=f"kept -> {dest.relative_to(SOUND).as_posix()}")

    def unkeep(self, e=None):
        self.kept = read_kept()
        mine = self.kept_for("id", self.line_id)
        for k in mine:
            f = SOUND / k["game_file"]
            for p in (f, f.with_name(f.name + ".import")):
                if p.exists():
                    p.unlink()
            self.intros_changed |= is_team_intro(k["line"])
        self.kept = [k for k in self.kept if k not in mine]
        write_kept(self.kept)
        self.refresh(msg=f"removed {len(mine)} file(s) from the game")

    def redo(self, e=None):
        existing = REDO_FILE.read_text().split() if REDO_FILE.exists() else []
        if self.line_id not in existing:
            with open(REDO_FILE, "a") as f:
                f.write(self.line_id + "\n")
        self.refresh(msg="added to redo_list.txt")


if __name__ == "__main__":
    root = tk.Tk()
    picker = Picker(root)
    root.mainloop()
    stop()
    if picker.intros_changed:
        print("Team intros changed - cutting them into halves (tools/cut_sounds.py)...")
        subprocess.run([sys.executable, str(CUT_SOUNDS)], check=False)
