# Handoff: character look pass (gloves, hands, hair, stance)

Last updated 2026-11-08. Nothing below is committed yet. The last commit is 2a19925, "Front-end menus, board ads, menu music, restyled pause menu."

## Goal

The player models look samey and stiff. Menus, fights and replays all show them up close, so they need to look better. The user asked for four things:
1. A real hockey glove. They don't like the current gloves.
2. Hairstyles and facial hair, so players look different from each other.
3. A better ready stance.
4. Hands that actually hold the stick.

The next session will have a **Blender connection** (the `mcp__blender__*` tools). The plan is to model a proper hockey glove there, fitted to our body's hand.

## Status

| Item | State |
|---|---|
| Ready stance | Better, and the user agrees. The feet are wider, the knees bent deeper, the chest forward, and the elbows bent. |
| Stick grip | The stick runs through the middle of each fist, and the hands turn so the fingers wrap the shaft. |
| Pants | Fixed. The big pelvis ball that looked like a diaper is now a slim hip band plus a shell on each thigh. |
| Gloves | **New Blender glove in.** Modeled by `tools/blender/hand_gear.py` and exported to `assets/equip/hockey_glove.glb` (6.5k tris). `build_gear.gd` copies it to `glove.res` (`GLOVE = "blender"`). |
| Bare hands | **Fixed.** The bodies have no hands: `build_characters.gd` drops every triangle with a corner on a hand or finger bone (`_drop_hands`), from the skin and the uniform shell, since gloves, cuffs and fists always cover them. (Before 2026-11-09 the rig only shrank the finger bones, `SkaterRig.hide_fingers`, which replays didn't carry, so fingers showed through the fists there.) In fights a bare fist model (`fist.res`, 3.2k tris, skin tone) replaces the glove. Second pass (2026-11-09): built from soft masses (domed back of the hand, fingers wide enough to fuse with shallow grooves, filled palm fold, fleshy thumb) instead of boxes and bony segments, 15% bigger (`build_fist(scale=1.15)`), with a thick wrist that flares out of the sleeve and tapers away inside it so it never pokes through the jersey. |
| Hair | Five cuts, plus a braid for women, tinted per player; each player keeps the same look every game. Each cut is built twice by `build_hair.gd`: `<id>.res` (full, pushed out onto the game scalp by `SCALP_*`) and `<id>_helm.res` (pressed flat under the helmet). Under the helmet a hair-colored scalp cap (`SkaterVisual.HAIR_CAP_*`) shows through the vents. |
| Menu poses | Team select: players stand tall, lifted `PLAYER_LIFT` 0.45 m level with the crests, in a random clip-driven pose (`SkaterVisual.display_pose`, `DISPLAY_SPEC`). Clips come from `assets/animations/menu/`: `middle` Fishing Idle, `side` Holding Idle, `rest` / `lean` the male standing poses, `across` built to the user's reference (a held frame of Fishing Idle on legs and spine; the stick rides on the chest so it follows the breath; arms posed by the rig onto a fixed stick, butt hand over palm down, blade hand under palm up, via `SkaterRig.hold_x` / `hold_back`), `shoulders` one held frame of Back Squat (9.3 s); women also get `hips` / `hips_b`. The stick is placed from the grips each frame (`_display_stick`). The one-frame poses (`still` or `hold` in the spec) get `SkaterRig.breath`, a slow chest / sway / head idle laid over the clip, so every pose moves. `pose=<id>` forces one (viewer and team select). Helmet B's fit was 1.3 (oversized), now 1.16. |
| Helmet off | Fights: the stick and gloves fall from the hands to the ice (`Fight._fall`), then each fighter plays `take_off_helmet()`. That's the Focus clip, both hands on the helmet; at `HELMET_LIFT` the right hand takes it and the full hair shows, at `HELMET_DROP` it drops and tumbles to the ice. `set_fight_mode(false)` puts it back on. The clip plays at `HELMET_SPEED` 2.6 (about 1 s); `SQUARE_TIME` is 1.6 s and the fighters square up `START_GAP` 1.6 m apart, then step in. Viewer: `helmetoff=<s>` (skater 4, with `fight=1`), `helmhair=1` hides just the shell. |
| Beard and moustache | **Fixed.** The top edge of each sits right under the nose (problem 2). |

## Open problems, in order

Problems 1 and 3 are done (see the Gloves and Bare hands rows). To change the glove or fist, edit `tools/blender/hand_gear.py`, run it in Blender (`exec(open(path).read())` then `build_all(True)`), then run `godot --headless --path . --import` and `godot --headless --path . -s res://tools/build_gear.gd -- only=glove`. That rebuilds both `glove.res` and `fist.res`.

Stick stance (posed by the user in Blender, then matched in the game):
- **Blender rig:** `tools/blender/pose_rig.py` holds the game body, the gloves and cuffs, a stick, IK handles for the hands, feet and blade, and `read_pose()`. To copy any game frame into Blender, run the viewer with `posedump=<json> gripdbg=1 handdbg=1`, then call `apply_dump(path)` in Blender.
- **Gloves:** the cuff is its own mesh (`glove_cuff.res`) on the ForeArm bone, so the hand part can cock at the wrist.
- **Hand angles** (`SkaterRig`): both thumbs run down the shaft toward the blade. The top glove's back faces out and forward (palm in, thumb on top), set by `top_back_*`. The bottom glove's palm faces forward, set by `bottom_back_*`. `max_wrist_bend` is 90.
- **Hand placement** (`SkaterRig`): the top hand is in front of the off-side hip (`top_reach` 0.75, `top_out` 0.25, `top_drop` 1.0, `top_ahead` 0.5). `grip_spread` is 0.3.
- **Spine** (`SkaterVisual`): the stance was retuned to the user's Firefly reference video, which has level shoulders and the chest forward. `stance_bend` is 1.15 and `stance_sway` only 0.05. `_dip` adds at most `dip_max` (0.15) when `rig.bottom_short` says the bottom hand can't reach. The Blender pose's 0.68 sway read as leaning over sideways.
- **Blade:** without the puck, the drawn blade rests at `stance_blade_forward` / `stance_blade_side` (0.8 ahead, 0.55 out). This is visual only: gameplay's `Skater.blade_rest()` is unchanged, and with the puck the blade goes to the puck.
- **Slap shot** (`SkaterVisual`): the blade follows `_windup_arc(charge)`. It sweeps back around the forehand side near the ice (`windup_arc_end` 120°), then rises behind the shoulder (`windup_arc_reach` 0.9, `windup_arc_height` 1.9). As the blade rises, the top hand comes up and across to that side (`SkaterRig.top_lift_up` 0.85, `top_lift_across` 1.0). The hands stay at about shoulder height: hands over the head read as an overhand chop. The spine stands up into the windup (bend -0.45 × charge). The downswing runs the arc backward to the puck (the first `FOLLOW_IMPACT` 0.45 of the follow-through), then `_follow_end` rises forward to a stick level at chest height. The drawn finish holds for `FOLLOW_HOLD` (0.35 s) after the shot state ends; gameplay timing is unchanged.

### 1. Bare hands show through the gloves, and the glove doesn't meet the wrist

The user sees "4 sets of fingers": the skin hands are bigger than the new gloves and poke out of them. The new glove also doesn't join the wrist cleanly.

Why it happens:
- The body meshes have full hands. The male body uses CMU-style mitten fingers; the female body has full Mixamo fingers.
- `scenes/actors/uniform.gdshader` paints the hand area glove-colored when the instance parameter `gloves_worn` = 1.
- The old leather gauntlet was big enough to hide the hands. The new procedural glove (about 0.135 × 0.19 × 0.157 m) is smaller than the hand.

Ways to fix it:
- **Hide the body's hands while gloves are on** (recommended, needed whatever glove we end up with):
  - In `SkaterRig`, when not in fight mode, scale the Hand bone's children (the finger bones) to about 0.01. Or scale the Hand bone itself down a little and the fingers to near zero.
  - Restore them in fight mode, which needs bare fists. The fist curl (`rig.fist`) already rotates those bones.
  - `SkaterVisual.set_fight_mode()` already toggles `gloves_worn`. Toggle the hiding there too.
- Make the glove fit the actual hand. Its cuff has to cover the wrist and forearm seam: the cuff should start about 4–6 cm up the forearm and overlap the sleeve.

### 2. Beard and moustache placement (done)

The top edge of each now sits directly under the nose. Both are placed in `tools/build_hair.gd`:
- Beard: `BEARD_DROP` 0.728. A bigger value moves the beard **up**; 0.75 put the mouth ring on the nose. `BEARD_BACK` 0.05 sets it back onto the jaw (it floated in front of the face).
- Chinstrap: the same beard pushed in by `CHINSTRAP_BACK` 0.12, so only the jaw line shows. `random_look` picks beard 20%, chinstrap 10%, moustache 20%.
- Moustache: `MOUSTACHE_AT` (0, -0.96, 0.55), in head widths below the top of the head.

After changing them, rebuild with `godot --headless --path . -s res://tools/build_hair.gd`. To check, use the CharacterViewer with `facial=beard` or `facial=moustache`, `nohelmet=1`, `view=face|face_side|face_quarter|face_back` (cameras squared to the head bone; `dist=` sets the distance).

### 3. Gloves: replace the procedural one with a Blender-made glove

The procedural glove reads as a hockey glove, but it's crude. The user wants one modeled for our character, using the Blender connection.

**The glove the game expects** (`assets/characters/glove.res`, loaded by `SkaterVisual.GLOVE_MESH`):
- One surface, painted the team's glove color with `MeshUtil.material`, culling off.
- A **right** glove; the game mirrors it for the left hand.
- Axes: the wrist at the origin, fingers along +Y and curled toward −Z (the palm), the back of the hand toward +Z, the thumb on the −X side.
- Already closed in a fist around the stick. The stick runs along X through **(0, 0.065, −0.05)** m. Those values are `GRIP_UP` / `GRIP_IN` in `tools/build_gear.gd`, and must match `GRIP_OFFSET` / `GRIP_PALM` in `scripts/actors/skater_visual.gd`. If the new glove's fist is elsewhere, change both.
- Sized for a 1.8 m body. The game scales it by `hs` (body height / 1.8).
- Hockey glove anatomy:
  - a padded cuff that flares slightly
  - a segmented backhand with a knuckle roll
  - finger rolls in two or three segments
  - a thumb lock
  - a palm piece
- Keep it to roughly 3–6k triangles; 24 gloves can be on the ice. Untextured is fine. A second surface or vertex colors for trim would be a nice extra, but the code paints only one surface today.
- It doesn't need to open: in fights the gloves come off.

**How to get it into the game:**
- Export a .glb to `assets/equip/` and add an entry to `GLOVES` in `tools/build_gear.gd`. Its fields: `src`, `length`, `knuckle`, `wrist`, `thumb_*`, `curl`, `puff`, `tris`, `cluster`, `weld`.
- The `GLOVES` path *curls the fingers* of a flat-fingered glove, so a glove modeled already gripping should skip that. Add a "prebent" path that only moves, scales and orients the model, or set `curl` to ~0.
- Or simpler: write `glove.res` straight from Blender's export, using a small import function in build_gear.
- Set `GLOVE` to the new key, then run `godot --headless --path . -s res://tools/build_gear.gd -- only=glove`.
- Better still: in Blender, import our male body (`assets/player/male_character_base_-_rigged.glb`, or the built `assets/characters/body_male.scn`) and model the glove around its right hand, so the cuff and wrist fit for real.

**What's in `GLOVES` now:**
- `srg`: the armored moto scan, at `assets/equip/srg_glove.glb`. It's welded and simplified to 9k triangles, with the thumb folded in. It came out jagged with holes and isn't used.
- `leather`: the original gauntlet, at `assets/equip/glove.glb`.
- `GLOVE = "hockey"` builds the procedural one (`_build_hockey_glove`, with `_tube` / `_blob` helpers).
- The user's other test gloves are uncommitted in `assets/fortest/` (BMW, Kyorene, moto); none is usable. BMW is branded. The moto glove is a skinned mesh that imports tiny.

## What changed this session (uncommitted)

**`scripts/actors/skater_rig.gd`**
- `grip_offset` / `grip_palm`: the grip point in the fist.
- `grip_turn` (1.0): the hand turns so the glove's knuckle line runs along the shaft. It builds the knuckle and finger frame from the forearm.
- `_finger_local` / `_knuckle_local` are cached in `_cache`.
- The bottom hand targets the shaft with its grip, not its wrist.
- `grip_debug` output for the viewer.
- The top hand's reach dropped from 0.78 to 0.70 and moved further forward.

**`scripts/actors/skater_visual.gd`**
- Stance: crouch 0.21, bend 0.95, stance `lerpf(0.2, 0.15, stride)`.
- `GRIP_OFFSET` 0.065 and `GRIP_PALM` 0.05.
- Pants: the hip band plus a shell on each thigh, attached to the UpLeg bones.
- Hair: `HAIR_DIR`, `HAIR_STYLES`, `HAIR_COLORS`, `_add_hair()`, `hair_material()`, `random_look()`.
- The helmet node is named "Helmet".

**`scripts/actors/skater.gd`**
- New fields `hair_style`, `facial_hair` and `hair_color`.

**Where looks get assigned**
- `scripts/match/match_director.gd`: `_set_look()` in both the generated and the roster branch. Roster players are seeded by name.
- `scripts/ui/menu_arena.gd`: the menu players get the same seeded looks.

**`tools/build_hair.gd` (new)**
- Takes the PUBG file (`assets/player/hair_and_beard__pubg_mobile_3d_model.glb`):
  - Five hair pieces: rip_7 messy, rip_8 buzz, rip_9 shaggy, rip_10 mop, rip_11 quiff.
  - Each is fitted to its display head (rip_2..6), which sits `HAIR_DROP` 0.5 m above it.
  - The beard is rip_1.
  - Faces look +X in the source.
- Also takes `mostache.glb` and `ported_hair.glb`. The braid's head is a placeholder sphere.
- Output goes to `assets/characters/hair/<id>.res` and `.png`, in head space: the top of the head at the origin, +Z toward the face, one unit = one head width.
- `_tuck()` pulls hair above the helmet rim inside a shell ellipsoid (`SHELL_C` / `SHELL_R` / `RIM`). Hair that hangs below the head is pushed back (`NAPE_PUSH`) and shortened (`HANG_SQUASH`).

**`tools/build_gear.gd`**
- The `GLOVES` spec table, the procedural `_build_hockey_glove`, `_tube`, `_blob`.
- `_simplify()` gained `allow_cluster` and `weld_dist`.

**`scripts/tests/character_viewer.gd`**
- New arguments: `seed=`, `hair=`, `facial=`, `nohelmet=1`, `gripdbg=1` (grip axes: red knuckle, green fingers, blue palm).

**`assets/CREDITS.md`**
- Rows for the hair, moustache, braid and SRG glove, with authors and links still to add.

**Assets**
- `assets/equip/srg_glove*` (moved from `fortest/`).
- `assets/characters/hair/`.
- `assets/characters/glove.res` (rebuilt: procedural).

All four self-tests pass: Skater, M2, Fight, Puck.

## Tools

The Godot binary is `E:/Godot/Godot_v4.7.2-stable_win64_console.exe`.

- **Close-ups:** `--path . --resolution 900x900 res://scenes/tests/CharacterViewer.tscn -- focus=0 view=front|quarter|side|back zoom=0.5 look_y=0.8 wait=1.2 shot=<png>`
  - For heads, use `zoom=0.22 look_y=1.5`.
  - Add `nohelmet=1`, `hair=…`, `facial=…`, `body=male|female` as needed.
- **Self-tests:** `--headless --fixed-fps 120 --path . res://scenes/tests/{SkaterSelfTest,M2SelfTest,FightSelfTest,PuckSelfTest}.tscn`
- **Mesh check:** the scratchpad script `meshview.gd` renders a .res mesh from three sides. It's easy to rewrite if the scratchpad is gone.
- Commits use godlovesaliar@gmail.com. Push to `origin main` when the user asks.

## Suggested order for the next session

1. Hide the body hands under gloves (problem 1). That's the quick win, and it matters whatever glove we use.
2. Move the beard and moustache up (problem 2). Rebuild and check.
3. Blender: check `get_addon_status` and `get_scene_info`, then:
   - import the male body
   - model the hockey glove around its right hand to the axis convention above
   - export it, wire it into build_gear, rebuild
   - check in the viewer, front and quarter views, with `gripdbg=1`
4. Ask the user whether to commit and push. Leave `assets/fortest/` out.
