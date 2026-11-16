# Knockout Hockey – Voice Generator

Free, local announcer generation with **Chatterbox** (Resemble AI, MIT license) on the RTX 2070 Super.
It regenerates every Steve (play-by-play) and Bobby (color) line from the game's own script and drops
the keepers straight into the game.

```
hockey_voicegen/
  voicegen.py     batch generator: game script -> takes/
  picker.py       audition takes; K exports a game-ready mp3 into assets/sound/announcer/
  common.py       shared paths/helpers
  lines.csv       optional per-row tweaks (respellings, intensity, more takes)
  intros.csv      how Bobby says each team in the team intros
  voices/         reference clips: pbp.mp3 (Steve), color.mp3 (Bobby); .wav works too
  takes/          generated takes + _log.csv (seed/settings for every file)      [not in git]
  kept.csv        which take became which game file (picker writes it)
  retired/        old clips moved out by --retire-old                            [not in git]
  .gdignore       keeps Godot from importing anything in here
```

**The script** is `data/hockey_announcer_lines.csv` (columns `file_name, category, voice, intensity, prompt`).
To add or change a line, edit it there. voicegen asks Godot (`tools/announcer_check.gd -- json=…`) which
game line each row feeds and who voices it, so the line's voice in `announcer_lines.gd` wins over the CSV's
`voice` column. Rows for duet lines (`both/`) are skipped: make those in the Studio's Conversation tab (below).

**Team intros** are one Bobby line per team, built from `intros.csv`:
"Tonight: a matchup between the Whalers... and the Whalers." The `...` puts a clear pause in the middle,
where `tools/cut_sounds.py` splits each intro into a home half and an away half, so any home team's opening
can lead into any away team's close. Respell a team in `intros.csv` if Chatterbox says it wrong
(e.g. `the Ko-hogs`). `--only intro_` generates just the intros (plus the three game intros).

## One-time setup (Windows)

1. **Install Python 3.11** from python.org (tick "Add python.exe to PATH"). Chatterbox pins PyTorch 2.6,
   so stay on 3.11. This machine has 3.14 and 3.9, which won't work.

2. **Make a virtual environment** in this folder (Command Prompt):
   ```
   cd "C:\Users\Booker\Desktop\Knockout Hockey\data\hockey_voicegen"
   py -3.11 -m venv venv
   venv\Scripts\activate
   pip install chatterbox-tts
   ```

3. **Swap in the GPU build of PyTorch.** The pip install above pulls the CPU-only build:
   ```
   pip install --force-reinstall torch==2.6.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu124
   python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
   ```
   It should print `True NVIDIA GeForce RTX 2070 SUPER`.

4. **Voice references** are already in `voices/` (about 18 s each). Mp3 is fine; it's converted to wav once
   with ffmpeg. Clean, solo speech in the style you want; no music or crowd.

voicegen finds Godot at `E:\Godot\Godot_v4.7.2-stable_win64_console.exe`. Set the `GODOT` environment variable
if that moves. Without Godot it falls back to the last `todo.json`.

## Every-session workflow

```
venv\Scripts\activate
python voicegen.py --dry-run          # preview the plan
python voicegen.py --only faceoff     # try one category first and listen
python voicegen.py                    # everything (go get a coffee)
python picker.py                      # audition and keep
python voicegen.py --redo-list        # regenerate anything you marked R
```

- Re-running skips takes that already exist. Add rows to the game CSV and only the new ones get generated. Ctrl+C anytime.
- `--only <prefix>` matches a row's file name or its game line; `--voice pbp|color` does one announcer.
- Each game line gets at least 6 candidate takes in total (3+ per row), so you can pick the best 3.

## Picking

`K` trims the silence, matches the old clips' loudness (Steve -18 LUFS, Bobby -14), and writes a mono
128 kbps mp3 into `assets/sound/announcer/pbp/` or `color/`. The first keeper of a row uses the row's
name (`faceoff_01.mp3`). Extra keepers get the next free `<line>_NN` (`faceoff_04.mp3`), which the game
counts as another take of the same line. The top bar shows how many keepers the line has against the
target of 3. `X` takes a row's keepers back out of the game. `N` jumps to the next row with no keeper.
Godot imports the new mp3s the next time the editor gets focus.

Team intro keepers go to `assets/sound/intro/intro_<team>.mp3` (a second keeper is `intro_<team>2.mp3`,
played at random with the first). When you close the picker after keeping or removing any intro, it runs
`tools/cut_sounds.py` to re-cut the halves. If a team cuts in the wrong place, add its split time (seconds)
to `INTRO_SPLIT_AT` in cut_sounds.py.

## Replacing the old clips

The old Steve/Bobby clips can't be used commercially, so they all go. Once you're happy with the
Chatterbox sound:

```
python voicegen.py --retire-old
```

This moves every clip in `announcer/`, `announcer/pbp/`, `announcer/color/` and `intro/` that picker didn't
export into `retired/` (outside the game and git), then re-cuts the intro halves. It's a move, not a delete.
(`intro_anchor` and `intro_beacon` match no current team and get retired too.) Old duets in `announcer/both/` are
retired too; duets exported from the Studio are kept. Then run `announcer_check.gd` to see what's still short.

Until you retire them, old and new takes of a line play side by side, which is handy for comparing.

## Tuning

| where | what |
|---|---|
| `LEVELS` in voicegen.py | CSV `low/medium/high` → Chatterbox intensity ("exaggeration") and pace ("cfg_weight") |
| `TAGS` | ElevenLabs tags in the CSV text (`[shouting]`, `[calm]`…) are stripped; some adjust the settings |
| `VOICE_BOOST` | Bobby gets +0.1 intensity, since he's the loud one |
| `lines.csv` | per-row overrides: `text` (respell for pronunciation), `intensity`, `pace`, `takes` |
| `--temp` | 1.0 gives wilder variation between takes, 0.6 steadier |

- Punctuation and CAPS matter: `SCORES!` reads hotter than `scores.`, and `...` adds a pause.
- High intensity speeds speech up, so keep pace around 0.3 for big calls.

## Notes

- First run downloads the model (~2 GB) and caches it.
- Every file carries Resemble's inaudible "Perth" watermark, which marks it as AI-generated.
- A few seconds per short line on the 2070 Super: the full set (~730 takes) is roughly an hour or two unattended.

## Chatterbox Studio (general-purpose GUI)

```
studio.bat          (or: venv\Scripts\python.exe studio\studio.py)
```

A local app that opens in your browser at http://127.0.0.1:7860. It shares this folder's venv and `voices/`
library (Steve and Bobby are already in it). **Don't run it while voicegen.py is generating:** both load the
model onto the same GPU.

- **Voices:** upload or record a 10–20 s reference clip, trim it on the waveform, name it, and set its default
  intensity, pace and variation. **Test** speaks a line with the unsaved clip; **Save voice** stores it as
  `voices/<id>.wav` + `<id>.json`. Editing a voice keeps its id, so renaming Steve doesn't break voicegen's `pbp`.
  Delete moves the voice to `voices/.trash/` (Steve and Bobby are protected).
- **Text to Speech:** any voice (or Chatterbox's built-in one), up to 5 takes at once, fixed or random seed.
  Long text is split at sentences and joined. Files land in `studio/output/tts/`.
- **Conversation:** write a script as `Name: text`, one line each. Tags like `[excited]`, `[shouting]`, `[calm]`
  set the delivery, and `(pause 1.5)` adds silence after the previous line. **Update cast** lists the characters;
  pick a voice for each (names like "Steve" match "Steve Sheldon" automatically). **Generate** makes each line on
  its own, levels them all to -18 LUFS, and stitches them with the gap you set (negative = overlap). Each line has
  its own player, an intensity override and **Redo**, which regenerates just that line with a new seed and
  re-stitches. Unchanged lines are cached in `studio/cache/`, so editing one line only regenerates that line.
  Save/Load keeps the script, cast and seeds in `studio/projects/`. Output goes to `studio/output/conversations/`.
- **Game duets:** in the Conversation tab, "Send to game" exports the stitched conversation to
  `assets/sound/announcer/both/<line>.mp3` (a second export becomes `<line>2`, and so on), levelled to -16 LUFS and
  recorded in `kept.csv` so `--retire-old` leaves it. Pick a duet line (`banter_goal`, `intro_duet`, `banter_<team>`…).

## SillyTavern (TTS server)

`tts_server.bat` runs Chatterbox as an OpenAI-style speech endpoint at
`http://127.0.0.1:8004/v1/audio/speech`, using the same voices and settings as the Studio
(`studio/tts_server.py`, built on `studio/engine.py`). Close the Studio and voicegen first.

In SillyTavern: Extensions → TTS → Provider **OpenAI Compatible**
- Provider Endpoint: `http://127.0.0.1:8004/v1/audio/speech`
- API key: anything (it isn't checked); Model: `chatterbox`
- Available Voices: `pbp, color, pa_announcer, pa_announcer_2, pa_ingame, default`
  (ids from `voices/`; display names like `Bobby Niedemyer` work too; `default` is the built-in voice)
- Tick Enabled, then pick a voice per character. Use SillyTavern's own options to skip
  `*actions*` or narrate only quotes; the server just strips markdown marks.

Speed isn't supported (Chatterbox has no speed control). The model needs a few GB of
video memory, so a large LLM in koboldcpp on the same 8 GB card can push it out; use a smaller
or more CPU-offloaded model if generation fails or crawls. `http://127.0.0.1:8004/v1/voices` lists the voices.

## Crashes

This PC hard-resets (no blue screen) when the GPU's power draw spikes, which Chatterbox does at the start of every
take. Cap the GPU before long runs, in an **admin** Command Prompt (both reset on reboot):

```
nvidia-smi -pl 150
nvidia-smi -lgc 300,1500
```

What actually fixed it (2026-11-13) was limiting PyTorch to **2 CPU threads**: voicegen's `--threads` now defaults to 2 and the Studio uses 2 as well. A full run with 2 threads didn't crash, and the CPU averaged 43 °C. `--pause 1` also rests the GPU between takes. If a crash cuts a run short, takes missing from `takes/_log.csv` should
be deleted so they regenerate.
