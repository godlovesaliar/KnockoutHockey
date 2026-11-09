# Knockout Hockey — Design Document

*Living document. Version 0.1 — 2026-11-05.*

---

## 1. Overview

**Knockout Hockey** is a 3D arcade hockey game made in Godot 4.7 for PC. It plays like the hockey games of the Genesis–N64 era: fast, responsive, three-button hockey, but with a modern, mostly realistic look. Fighting is a featured mechanic with its own mini-game. Every team is fictional. Players can create teams, players and arenas.

- **Platform:** PC (Windows), keyboard and controller. Personal project; no plans for consoles or a commercial release.
- **Players:** 1–4 local, co-op and versus.
- **First mode:** Exhibition. Season, playoffs and management come later.

### 1.1 Design pillars

1. **Feels like 1994, looks like today.** Instant input response, readable motion, few buttons. Visuals are clean and grounded, not retro.
2. **Every button press does something right away.** No input buffering that feels like lag, and no animation that locks you out of control for long.
3. **Big moments get big presentation.** Bone-crunching hits, shattered glass, slow-mo, crowd roars. The players stay human: no magic, no flaming pucks.
4. **Fights matter.** Fights are grounded, skill-based and have consequences: penalties, injuries, momentum.
5. **Everything is data.** Teams, players, jerseys and arenas are all data files, so the editors and later modes come almost for free.

---

## 2. Match structure and rules

### 2.1 Match settings (all configurable before a match)

| Setting | Options | Default |
|---|---|---|
| Format | 5v5 + G, 3v3 + G | 5v5 |
| Period length | 1–20 min (game clock) | 3 min |
| Periods | 3 (fixed for now) | 3 |
| Overtime | Off / Sudden death / Shootout / Sudden death → Shootout | SD → Shootout |
| OT length | 1–10 min | 3 min |
| Shootout rounds | 3 / 5, then sudden death | 3 |
| Offsides | On / Off | On |
| Icing | On / Off | On |
| Penalties | On / Off | On |
| Fighting | On / Off | On |
| Injuries | On / Off | On |
| Line changes | Auto / Off (fatigue disabled) | Auto |
| CPU difficulty | Rookie / Pro / All-Star / Legend | Pro |
| Catch-up AI | On / Off | Off *(to be tested, see §12)* |

### 2.2 Rules (when enabled)

- **Offsides:** standard rule with delayed offside (the play continues until the attacking team touches the puck in the zone).
- **Icing:** hybrid icing (the whistle blows once the defender wins the race to the faceoff dot line). No icing while shorthanded.
- **Penalties:** called automatically from contact events.
  - *Minor (2:00):* tripping (poke check that hits the skater, not the puck), hooking, high-sticking, holding, charging (a check started with too much distance), boarding (a hit from behind near the boards), interference (hitting a player without the puck after a grace period).
  - *Major (5:00):* fighting (both players).
  - Delayed penalty: the referee's arm goes up, the offended team can pull its goalie, and the whistle blows when the penalized team touches the puck.
  - Penalty severity depends on the referee's "strictness" (a hidden variable, scaled by difficulty).
- **No ejections.** This is a deliberate design choice.
- In **3v3**, penalties produce 4v3 power plays (capped at 5v3 for 5v5).

### 2.3 Flow of play

Opening faceoff, then open play until the whistle (goal, offside, icing, frozen puck, penalty, puck out of play, or the period ending), then a faceoff at the matching dot. There's a short intermission between periods with a Zamboni scene (skippable). Three stars are shown after the match.

---

## 3. Controls

Context-sensitive: the same buttons do different things depending on whether your team has the puck.

### 3.1 Controller (Xbox layout)

| Input | Offense (your team has the puck) | Defense |
|---|---|---|
| Left stick | Skate | Skate |
| **A** | Pass (tap) / saucer pass (hold) | Switch to the player nearest the puck |
| **X** | Shoot: tap = wrist shot, hold = slap shot (charges) | Hook / stick lift |
| **B** | Check / shoulder bump | **Body check** (hold to wind up a bigger hit) |
| **Y** | Deke (direction from the left stick) | Poke check |
| **RT** | Turbo (drains stamina) | Turbo |
| **LT** (hold) | Skate backwards (face away from the stick direction; ~72% top speed, no hard stop) | Skate backwards |
| **LB** | Protect puck (slower, harder to strip) | Block-shot stance (drop to a knee) |
| **RB** | — | — *(reserved: strategy / line call)* |
| Start | Pause menu | Pause menu |

- **One-timer:** press or hold shoot while a pass is on its way to you, and you shoot the moment it arrives.
- **Pass targeting:** a pass goes to the teammate closest to the direction of the left stick (65° cone; the angle weighs much more than distance). The stick direction is remembered for `Skater.AIM_MEMORY` (0.35 s), because players usually let the stick go a moment before the pass button. A pass leads a moving receiver by at most `PASS_LEAD_MAX` (3 m), bends gently onto the receiver's stick over the last few meters (`Puck.PASS_HOMING`), and the intended receiver catches it within `INTENDED_REACH` (1.5 m). With the stick in neutral, it goes the way the skater faces.
- **Keyboard:** Q (keyboard 1) / Num6 or M (keyboard 2) skate backwards.
- **Goalie control:** when your goalie has puck control (covered or holding it), the human takes control of the goalie: A = pass out, X = clear the puck (shoot it up ice), Y = cover it for a faceoff. After that, the goalie goes back to AI.

### 3.2 Keyboard

| Action | Key |
|---|---|
| Move | WASD |
| Pass / Switch | J |
| Shoot / Hook | K |
| Check | L |
| Deke / Poke | I |
| Turbo | Left Shift |
| Protect / Block | Space |
| Pause | Esc |

All bindings can be remapped. Keyboard player 2 uses the arrow keys and numpad (stretch goal).

### 3.3 Fight controls (mini-game, §5)

| Input | Action |
|---|---|
| Left stick | Toward / away from the other fighter (on screen): step in / back off. Up / down: slip a punch |
| A | Jab (fast, light); a short right while holding or held |
| X | Haymaker (big right, visible windup) |
| B | Grab the jersey; held, B tries to break free |
| Y (hold) | Block: fists up, much less damage, costs stamina |
| RT | Uppercut (only while you're holding them) |

Presses during a punch or a stagger are buffered (0.3 s), so mashing a combo works. The prompt to drop the gloves: A yes, B no. Keyboards use the same keys as pass / shoot / check / turbo / deke.

### 3.4 Multiplayer

- Up to 4 controllers. On the side-select screen, each controller slides left (home), right (away) or stays in the middle (spectator). This allows 1v1, 2v2, 2v1, 3v1, 4vCPU co-op and so on.
- Each human controls one skater. "Switch" selects the closest skater that isn't controlled by a human.
- Each human's player has a colored ring under them and a player-number marker.

---

## 4. Core gameplay systems

### 4.1 Skating

- A custom arcade controller, not physics: acceleration, top speed, turn rate and glide friction are all tuned by hand and scaled by stats.
- **Momentum matters but never fights you.** Sharp turns at high speed cost speed and draw a wider arc. A hard stop (reversing the stick) produces an ice-spray stop.
- **Turbo:** raises top speed by about 25% and drains stamina. Stamina also drops with shift time (fatigue) and recovers on the bench.
- Skating backward is automatic for defensemen facing the puck carrier when they have no puck.

### 4.2 Puck

- A custom kinematic puck with swept collision (shape casts each physics tick). This gives clean, deterministic bounces off the boards and posts with no tunneling.
- States: **Loose** → **Controlled** (attached to a stick blade with a small dangle offset) → **In flight** (pass/shot, may leave the ice) → **Frozen** (whistle).
- Pickup: a loose puck within reach of the stick blade is grabbed; the chance depends on puck handling and the puck's relative speed. Very fast pucks may deflect off skates and sticks.
- Deflections: shots can tip off sticks and bodies near the path.
- **Boards and glass:** the puck bounces off a restitution-tuned collider. Shots high enough hit the glass. Shots over the glass go out of play.

### 4.3 Passing

- Tap pass: flat, fast pass along the ice. Speed and accuracy come from the passing stat; a passing lane blocked by a stick can be intercepted.
- Saucer (hold): a lifted pass over sticks. Slower, but can't be intercepted mid-flight.
- Leading: passes aim ahead of a moving receiver.

### 4.4 Shooting

- **Wrist shot (tap):** fast release, medium power, good accuracy.
- **Slap shot (hold → release):** about 0.4 s windup with a visible charge, max power, less accuracy, and can be interrupted by a check.
- **One-timer:** slap-shot power with wrist-shot release time, and a timing-based accuracy bonus.
- **Aiming:** the left stick at release biases the target (glove/blocker side, high/low with a tiny vertical component). Accuracy stat → spread cone.
- Goal detection: the puck fully crosses the goal line inside the net trigger.

### 4.5 Checking (the "hit" system)

- **Hit power** = relative velocity × checking stat × windup bonus, compared against the victim's balance (durability/strength).
- Outcomes by power: **bump** (the victim stumbles and may lose the puck), **check** (knocked down, recovery in about 1 s), **big hit** (ragdoll-style fall, slow-mo, crowd roar, camera shake).
- **Hits into the boards** add a multiplier. At a very high power, a **glass break** happens: the panel shatters, there's a stoppage, and a short cutscene of the repair crew (it can only happen once or twice per game).
- Hits always risk penalties (§2.2) and can trigger injuries (§4.8) and fights (§5).

### 4.6 Defense

- Poke check: a quick stick jab with a cone. If it hits the puck it knocks it loose; if it hits the skates it's tripping.
- Hook/stick lift: a lower-risk strip from behind or beside. Hooking risk goes up if held too long.
- Block-shot stance: drop to a knee in the shooting lane. Slower movement, chance to block shots.

### 4.7 Goalies

- Fully AI by default, with positioning driven by stats (angle, depth), save animations chosen from the shot vector (butterfly, glove, blocker, pad kick, stack), and rebound control.
- Goalie control goes to the human only once the goalie has the puck (§3.1).
- **Pull the goalie** (stretch goal for exhibition): delayed penalty or late game, from the pause menu or a hotkey.

### 4.8 Stamina, line changes, injuries

- Each skater has stamina; fatigue reduces speed, shot power and checking.
- **Auto line changes** on the fly when the active line's average stamina drops below a threshold and the puck is out of the defensive zone, or at stoppages. Forward lines F1–F4 and D-pairs D1–D3 in 5v5; 3v3 rotates groups of three.
- **Injuries:** a small chance after big hits or fights, scaled by durability. The injured player leaves for the rest of the game and lines are rebuilt automatically. Injuries carry over in season modes (later).

---

## 5. Fighting

### 5.1 How fights start

1. **The prompt:** after a hit above the "fight threshold", or after a scrum around the goalie, the **victim's team gets a prompt** ("Drop the gloves? A / B", about 2 s). If they accept, a fight starts with the hitter (or the nearest enforcer on the opposing team).
2. **Forced fights:** if the hit is far above the threshold, or the opponent is high in **aggression**, the opponent (CPU or AI-controlled) can **start the fight on their own with no prompt**. The hit victim's team can't refuse.
3. **Tension meter (hidden):** each team builds tension from repeated big hits, hits on stars and goalie contact. Higher tension lowers the threshold. The meter resets after a fight.

AI teams decide whether to accept or start fights based on the player's fighting stat, aggression and the score/situation.

### 5.2 The mini-game

- The camera cuts to a tighter, lower angle on the two fighters; the other skaters gather in a ring and the linesmen hover. The crowd stands.
- Each fighter has **health** (from fighting + durability), **balance** (from strength) and **stamina** (from endurance).
- **Grounded rules:** fighters grab jerseys, trade punches, tie up and wrestle. Grabbing pulls the two together, drains the held fighter's balance, makes your punches hit 30% harder and opens the uppercut; the held fighter can't slip and tries to break free (B, strength vs. stamina). Blocking reduces damage but drains stamina. Slipping (stick up / down) beats haymakers if timed right. Range matters: step in to land, back off (out of reach, stamina comes back twice as fast).
- **Feel (as built):** full-body Mixamo clips (legs and hips move; the pelvis is held over its spot so clips that step don't lunge through the other fighter), fists closed by the rig (`SkaterRig.fist`), and at contact the punching hand is pulled onto the other's face, chin or ribs, or onto their raised guard, by per-arm reach IK (`SkaterRig.reach_w` / `reach_world`); grips put the lead hand on the other's jersey the same way. The pair glides along a slowly circling axis: lunges, knockback on clean shots, the pull of a grip. Heavy shots get a short hitstop and camera shake. Every clean blow staggers the one hit for a moment.
- **HUD:** each fighter's HEALTH, BALANCE and STAMINA bars are labeled, with what drains each for the first seconds, a white chunk for damage just taken, and a status tag (HOLDING, HELD — BREAK FREE, ROCKED, WOBBLY, WINDED, BLOCKING). Under the clock: how to win. At the bottom, the controls on the human's own device (`HumanBrain.button_label`). `KH_FIGHT_LOG=1` prints each result.
- **The fight ends** when: one fighter is **knocked down** (health or balance at 0), both are exhausted, or a time limit is hit (25 s), and the linesmen break it up.
- **The winner** is whoever knocked the other down, or did more damage if no one did. A draw is possible.
- Short, readable animations: windups are clearly visible, and nothing sends anyone flying. It ends with a "helmet off, sent to the box" walk-off.

### 5.3 Consequences

| Result | Effect |
|---|---|
| Both fighters | 5:00 major (if penalties are on). Fatigue applied. |
| Winner's team | **Momentum boost**: +stats for 60–90 s of game time (speed, checking, shot accuracy), crowd boost if home. |
| Loser | Small chance of injury (if injuries are on). |
| Both | Tension meter resets. |

No ejections. If penalties are off, fighters sit out a short cooldown on the bench instead.

---

## 6. AI

- **Team AI:** a simple tactical role system. Each skater has a role per situation (forecheck F1/F2/F3, breakout, cycle, power play / penalty kill box, defensive coverage). Each role is a target position + behavior, recalculated a few times a second.
- **Skater decisions:** utility scoring for pass / shoot / skate / deke / dump in, weighted by stats and personality (aggression, selfishness).
- **Difficulty** scales reaction time, decision quality, pass/shot accuracy and goalie positioning. It does not boost stats.
- **Catch-up AI** (rubber-banding): an optional toggle that's off by default. To be tested in playtesting (§12).

---

## 7. Camera and presentation

### 7.1 Camera

- **Vertical (end-to-end) broadcast camera**, high angle, follows the puck with a small lead in the direction it's moving and soft bounds at the end boards. The side-on horizontal camera may be added later as an option.
- Zooms in for faceoffs, fights, goal celebrations and replays.
- Shake/slow-mo on big hits and glass breaks (short, can be turned off in settings).

### 7.2 Presentation features

- **Announcer text pop-ups:** "BIG HIT!", "GOAL — #19 Name (assists)", "POWER PLAY", "FIGHT!", "GLASS SHATTERED!"
- **Goal replays:** a ring buffer records about 8 s of transforms and states. After a goal, you get an instant replay with an alternate camera. Skippable.
- **Three stars** after the match, chosen by goals, assists, saves, hits and fight wins.
- **Zamboni intermission** between periods (skippable), plus a period stats summary.
- **Crowd** that reacts to goals, hits, fights and near misses. More crowd energy for the home team.
- **Arena atmosphere:** a goal horn, goal light, organ stings after stoppages.
- **Music:** a mix of synth/retro, rock and organ. Rock and synth for the menus, organ and arena music during stoppages.

---

## 8. Teams and players

### 8.1 League

- Launch build: **4 teams** (to be described by the designer).
- Goal: **32 teams** across 4 conferences: **East, West, North, South** (8 teams each, possibly two divisions of 4 each — TBD).
- Each team: name, city, abbreviation, conference, colors (primary, secondary, accent), home and away jerseys, logo (preset for now), home arena, roster, lines.

### 8.2 Roster

- 5v5: 12 forwards + 6 defense + 2 goalies (20 players, with 4 forward lines and 3 D-pairs).
- 3v3: built from the same roster (groups of 3 skaters).
- **Teams can be all male, all female or mixed.** **Gender has no effect on stats or gameplay**; only stats drive performance and play style. Body size (height and weight) is set per player and is cosmetic plus a small balance/reach effect consistent for everyone.

### 8.3 Player stats (scale 1–99)

**Skaters**

| Stat | Affects |
|---|---|
| Speed | Top speed |
| Acceleration | Time to reach top speed, turbo burst |
| Agility | Turn rate, deke effectiveness |
| Shot Power | Shot speed |
| Shot Accuracy | Shot spread |
| Passing | Pass speed, accuracy, saucer quality |
| Puck Handling | Pickup chance, ability to keep the puck when hit/poked |
| Checking | Hit power |
| Strength / Balance | Resistance to being knocked down, puck protection, fight balance |
| Defense | Poke/hook success, AI positioning, shot blocking |
| Endurance | Stamina pool and recovery |
| Fighting | Punch damage, fight health |
| Durability | Injury resistance |
| Aggression *(personality)* | AI hit and fight tendencies, penalty risk |

**Goalies**

| Stat | Affects |
|---|---|
| Reflexes | Reaction time to a shot |
| Positioning | Angle and depth |
| Glove / Blocker / Pads | Save success by area |
| Rebound Control | Where saves go |
| Puck Handling | Passing and clearing (when human controlled) |
| Endurance | Fatigue over a game |

### 8.4 Archetypes

Archetypes are templates for stat distributions and AI personality, used for generating players and as a label in the editor.

- **Forwards:** Sniper, Playmaker, Power Forward, Enforcer, Grinder, Two-Way
- **Defense:** Offensive D, Defensive D, Enforcer D
- **Goalies:** Butterfly, Hybrid, Standup

### 8.5 Appearance

Body: male/female base, height, build, skin tone, face preset, hair style/color, facial hair. Gear: helmet, visor/cage, stick hand (L/R), stick tape color, jersey number. Name on the back.

---

## 9. Editors

### 9.1 Team editor

- Team identity: name, city, abbreviation, conference.
- Colors: primary, secondary, accent, plus helmet, pants and gloves colors.
- Jerseys: home and away, built from a template (stripe patterns, collar, shoulder yokes) plus team colors. The number/name font comes from presets.
- Logo: picked from a preset library (custom logo builder later).
- Home arena: one of the arenas.
- Roster: add/edit/remove players, build lines.

### 9.2 Character (player) editor

- Name, number, position, shooting hand, archetype (pre-fills stats), all stats (fully editable, no caps), appearance (§8.5), live preview with rotation.

### 9.3 Arena editor

- Base venue: **Indoor Arena** or **Outdoor Rink** (the smaller rink becomes an outdoor venue: snow, open sky, day/night lighting).
- Center ice logo (from presets or the home team's logo).
- Ice paint colors (blue lines, red line, crease, faceoff circles).
- Seat color(s).
- Lighting preset (standard, dramatic, warm, cool, outdoor day/dusk/night).
- Goal horn sound (preset list).
- Music playlist (choose from tracks).
- The rink is always regulation size for gameplay; arenas only change visuals and audio.

All editor output is saved as user data files (§10.3). The built-in teams and arenas use the same format.

---

## 10. Technical design

### 10.1 Engine and setup

- **Godot 4.7**, GDScript, Forward+ renderer, Jolt physics (only used for ragdolls/debris; skaters and puck use custom movement).
- Physics tick at **120 Hz** for puck precision, with rendering interpolation.
- Target: 60+ FPS on the designer's PC.

### 10.2 Project structure

```
res://
  assets/          models, textures, audio (raw imports)
  data/            built-in teams, players, arenas, presets (JSON)
  docs/            this document
  scenes/
    match/         Match.tscn, Rink.tscn, Puck.tscn, Net.tscn
    actors/        Skater.tscn, Goalie.tscn, Referee.tscn
    ui/            menus, HUD, editors
    fight/         FightArena.tscn (mini-game)
  scripts/
    core/          autoloads: GameSettings, Database, InputRouter, AudioDirector
    match/         MatchDirector, Rules, Clock, Penalties, Faceoff, Replay
    actors/        SkaterController, GoalieController, state machines
    ai/            TeamAI, roles, decision scoring
    fight/         FightController, FighterState
    editors/       TeamEditor, PlayerEditor, ArenaEditor
user://
  teams/ players/ arenas/   editor output
  settings.json
```

### 10.3 Data

- JSON files with a `schema_version` field, loaded into typed GDScript classes by the `Database` autoload. Built-in content lives in `res://data/`; user content in `user://`, and user content overrides built-in content with the same ID.
- Players are referenced by ID from rosters, so a player is defined once.
- Seasons and management will add data files (schedule, standings, contracts) without changing the existing ones.

### 10.4 Key architecture

- **MatchDirector:** owns the match state machine (Pregame → Faceoff → Live → Stoppage → Intermission → Overtime/Shootout → Postgame), clock, score and rule events.
- **Rules:** listens to puck and contact events and raises offside, icing and penalty calls depending on toggles.
- **Skater:** `CharacterBody3D` with a state machine (Skating, Shooting, Passing, Checking, Stumble, Down, Fighting, Bench). Inputs come from a `Brain`, either `HumanBrain` (device input) or `AIBrain`. Swapping the brain is how switching and human goalie control work.
- **Contact events:** a central bus (`hit`, `poke`, `trip`, `shot`, `save`, `goal`, `fight_start`...) feeds rules, presentation, audio, stats and the tension meter.
- **Replay:** every actor and the puck write transforms and animation states to a ring buffer every tick.
- **Fights:** a separate scene/state on the same ice; the main match is paused, the two fighters move to a fight controller, and the outcome is passed back to MatchDirector.

### 10.5 Conventions (as of M0)

- Units are meters. The rink is centered on the origin, **length along Z, width along X, Y up**. Dimensions live in `scripts/core/rink_spec.gd`.
- **Home (side 0) defends the +Z net** (bottom of the screen). Screen-up on the vertical camera is world −Z.
- Physics layers: 1 boards, 2 nets, 3 ice, 4 skaters, 5 sticks, 6 puck.
- The puck treats the ice as a plane at y = 0 and sweeps against everything else. Bounce feel comes from the `surface` meta on colliders (`boards`, `glass`, `post`, `net`), tuned in `puck.gd`.
- Headless regression tests (exit code 0 = pass): `Godot_console.exe --headless --fixed-fps 120 --path . res://scenes/tests/PuckSelfTest.tscn` and `.../SkaterSelfTest.tscn`.
- Physics order each tick: skaters (brain → actions → movement → pickup), then the puck (priority 10), then the nets (priority 20).
- Human control follows the puck: you take whoever gains it for your team, and control jumps to the receiver **the moment a pass is released**, so you can hold shoot for a one-timer.
- Pass and shot timing (M1 defaults): pass fires on release (held ≥ 0.22 s = saucer); shoot released within 0.16 s = wrist, otherwise a slap shot that charges fully over 0.45 s more.
- **M2 additions:**
  - Teams switch ends every period (`Rink.ends_swapped`). Always ask `rink.defended_net(team)` / `attacked_net(team)`, never a fixed side. `goal_scored` reports the net index (0 = +Z net).
  - Goalies are on physics layer 7. Skaters bump them but the puck passes through, because saves are resolved in code where the puck crosses the goalie's plane. Reflexes set the reaction delay, the glove/blocker/pads stats set reach, and rebound control sets rebound speed.
  - Hit power is closing speed × checking + a lunge bonus, divided by the victim's strength. The bands are bump (< 6), knockdown (< 12.5) and BIG HIT, and hits into the boards count ×1.4.
  - Team AI hands each AI skater a role every tick. With the puck: carrier, slot support, point support. Without it: pressure, cover the slot, mark a man, or chase a loose puck. The human-controlled skater is left out of the role assignment.
  - Faceoffs are a timing press (A or X) on the drop. Pressing early makes your press count as late.
  - More tests: `M2SelfTest.tscn` (goalie, checks, pokes) and `MatchSoak.tscn` (full AI-vs-AI games, `-- games=3 period=45`).
- **M3 additions:**
  - **Entry point:** the main scene is now `scenes/ui/MainMenu.tscn`; an exhibition goes through `TeamSelect.tscn` then `RulesSelect.tscn`, which write `GameSettings.config` / `GameSettings.humans`, which `MatchDirector` reads (tests set `use_game_settings = false`).
  - **Rosters:** teams in the roster sheet (`data/knockout_hockey_rosters.csv`, the first 12 teams) dress their real players, 8 F + 5 D + 2 G, through `scripts/core/rosters.gd` (`Rosters`): forwards in lines best-first, each line a C/LW/RW where possible; defense in pairs best-first; the higher-rated goalie starts. Ratings map SKA → speed/acceleration/agility, (SKA+PHY)/2 → endurance, SHT → shot power/accuracy, PAS → passing, HND → puck handling, PHY → checking/strength/durability, DEF → defense, goalie REF/POS/GLV/BLK/RBD one for one (pads = (REF+POS)/2); fighting and aggression come from PHY plus play style (Enforcer D highest, then Grinder and Power Forward). Play styles add small nudges (`Rosters.STYLE`). The sheet's ratings center around 75 (goalies 83), so they're shifted to center on 57, the generated players' level, keeping the gaps between players one for one. Name, number, gender (body), hand, position and play style come from the sheet; skin tone and helmet are seeded from the player's name, so they're the same every game. The CSV is imported with the `keep` importer (not as a translation). `tools/roster_check.gd` prints how the game reads each roster. Teams without rows get generated players: 12 F + 6 D + 2 G. The `Lineup` class owns the forward/defense groups, `on_ice` (shared by reference with the AI and the skaters' teammate lists, so it's only changed in place), the bench and the penalty box. Benched skaters are hidden, with processing and physics off.
  - **Energy (shift fatigue):** drains at roughly 1/48 per second on the ice and recovers on the bench. Below 1, it scales speed, acceleration and shot power down to 0.82×.
  - **Line changes:** tired groups change at faceoffs, or on the fly via the bench gate on the −X boards when the puck isn't in that team's defensive zone.
  - **Rules (`MatchRules`):** delayed offside (cleared when the puck leaves the zone or everyone tags up), no-touch icing (canceled by any touch, and a shorthanded team can't ice it), and delayed penalties (the whistle goes when the offending team touches the puck).
  - **Fouls:** these come from skater events (tripping, interference, boarding), and the director rolls whether the ref calls them. Power-play goals end the earliest minor. In 3v3, a penalty gives the other team an extra skater (4-on-3).
  - **Overtime modes:** `off`, `sudden_death`, `shootout`, and `sd_so`. In the shootout, every attempt goes at the −Z net, it runs best-of-N then sudden death, and the winner gets +1 goal.
  - **Humans:** each human gets a `HumanBrain(kind: ANY/KB1/KB2/PAD)` with its own edge detection, and `TeamControl` maps humans to skaters one-to-one. Rings and P1–P4 tags are colored per player.
- **M5 additions (characters and sound; done before M4 so fights are built on real bodies):**
  - **Build step:** `godot --headless --path . -s res://tools/build_characters.gd` (add `-- body=<name>` for one body) builds every body listed in `BODIES`: `male` (Hombre_Base, Mixamo-rigged but on its original CMU skeleton), `female` (Mujer_Base, Mixamo skeleton, A-pose) and `ybot` (test body). Each body gets canonical prefix-free bone names (`Hips`, `Spine2`, `LeftUpLeg`…; the CMU spine maps LowerBack/Spine/Spine1 → Spine/Spine1/Spine2), is rescaled to its `height` with feet on y = 0, and is saved as `assets/characters/body_<name>.scn`. Every clip in `assets/animations/` is retargeted onto each body (through a T-pose reference, so A-pose bodies match) into `anims_<name>.res`. Clip names are the file names in snake_case (`Boxing (1).fbx` → `boxing_1`). Hip drift is removed. Re-run after adding models or clips.
  - **Body types:** `Skater.body_type` = `"male"`, `"female"` or `"ybot"`; it's purely visual, and stats are unaffected. Generated rosters are mixed (`MatchDirector.FEMALE_SHARE`); sheet rosters use each player's gender.
  - **Fighting (M4):** `MatchDirector` builds each team's tension from hits taken (big hit +0.7, +0.2 into the boards, check +0.22, bump +0.06; decays 0.0015/s). At `FIGHT_TENSION`, at least `FIGHT_GAP` (200 s of play) after the last fight, the team's toughest skater on the ice (fighting + aggression) squares off with the hitter (or the hitter's toughest teammate). A human on that team gets the prompt ("Drop the gloves? A / B", 3 s, play stopped); a computer team decides from fighting and aggression; an aggressive hitter (70+) with tension past `FORCED_TENSION` starts it without asking. `Fight` (scripts/fight/) runs the mini-game: sticks and gloves drop on the ice (bare hands via the `gloves_worn` instance uniform), the others form a ring open toward a low side camera, and each fighter has health (fighting + durability), balance (strength) and stamina (endurance). Moves (`Fight.MOVES`, timed to the contact frame of each Mixamo clip): jab (`lead_jab`), haymaker (`hook`, a visible half-second windup, dodged by leaning), grab (holds the jersey for 3 s: +30% damage, drains the other's balance, unlocks the uppercut), uppercut (`uppercut`), and block (hold: 30% damage, costs stamina). Health or balance at 0 = knocked down (`knocked_out`); otherwise a decision at 30 s or when both are out of gas (close = a draw). Both fighters get offsetting 5:00 majors (`Lineup.offsetting`: no power play, the team plays full strength), or sit 60 s if penalties are off; the winner's team gets 75 s of momentum (+5% speed, +10% hit power); the crowd and announcer react; play resumes with a faceoff near the fight. Computer fighters dodge or block visible haymakers by skill, work grabs into uppercuts and mix punches by aggression. Setup has a Fighting On/Off setting. `-- fight` (or `fight=prompt`) starts one at once for testing; `scenes/tests/FightSelfTest.tscn` checks the whole flow. Punch sounds are split from `punch*.mp3` into single hits by `tools/cut_sounds.py` (with male / female grunts by who takes the punch).
  - **Pause menu:** Esc / Start opens `PauseMenu` (the game tree pauses): Resume, Controls (every action for pad and both keyboards), Restart game, Quit to menu; B / Esc / Start backs out. Not over the matchup intro or a stats screen, where those buttons continue. `-- pausemenu` (or `pausemenu=controls`) opens it at once for layout checks.
  - **Matchup intro:** games with the HUD on open on the matchup screen (`Phase.INTRO`): a camera at center ice, each team's logo on a board (Sprite3D) with one of its players standing in front of it in uniform (home on the left), "VS" between, the HUD hidden, everyone else out of sight. It lasts as long as the announcer's intro (at least `INTRO_MIN`, at most `INTRO_MAX`); Enter / A skips it. Then the broadcast camera takes over for the opening faceoff. `-- nointro` skips it; the soak (no HUD) never shows it.
  - **Intermission:** at the end of each period (after the horn and banner) `Intermission` shows both teams in their colors, the score, goals by period, shots on goal, saves, hits, big hits, faceoffs won, penalties and power-play goals; the next period starts when someone presses Enter / Space or A / Start (presses in the first second are ignored). The same screen follows the final horn and returns to the setup menu. AI-only games continue by themselves. The organ plays through the break. `-- statscreen` (or `statscreen=final`) opens it at once for layout checks.
  - **Teams:** `scripts/core/teams.gd` (`Teams.LIST`) holds the league's 30 teams in three conferences of ten (`Teams.CONFERENCES`; each team's `conference`, `Teams.in_conference()`). The four launch teams come first: New Bedford Whalers (red, white, black), Minnesota Geese (green, gold, black), Rhode Island Quahogs (blue, grey, yellow) and Maine Lobsters (white, maroon, green); the rest have palettes taken from their logos and no chants yet. East: Whalers, Quahogs, Lobsters, Burlington Lake Monsters, Adirondack Trailblazers, Mystic Mariners, New Hampshire Granite, Cape Cod Cranberries, New York Rats, Quebec Poutine. Central: Geese, Michigan Mitts, Wisconsin Curds, Lake Superior Gales, Manitoba Moose Jaws, Nashville Twang, Kentucky Moonshiners, Okefenokee Swamp Things, Florida Man, Texas Armadillos. West: Tacoma Geoducks, Roswell Grays, Anchorage Sourdoughs, Portland Lumberjacks, Monterey Otters, Hollywood Stuntmen, Mojave Gila Monsters, Boise Spuds, Seattle Seagulls, Yellowstone Geysers. Every team has a 15-player roster in `data/knockout_hockey_rosters.csv` (its `conference` column agrees with the table; `tools/roster_check.gd` flags any mismatch). Abbreviations match the roster sheet. When the two jerseys are too alike (`Teams.CLASH`), the away team wears road whites with its main color as trim (`Teams.uniform_vs`). Each has a full uniform palette (jersey, trim, pants, gloves, helmet, skates, number face and outline) and its crowd chant. The setup screen picks home and away (`home_team` / `away_team` in `GameSettings`; `-- home=<i> away=<i>` on the command line); the HUD shows team names; the home crowd chants for its own team. Logos: `tools/build_logos.gd` cuts the crests out of the logo sheets in `assets/images/` (`teamlogos.jfif`, `logos2.webp`, `logos3.webp`, `logos4.png`, `logos5.jfif`, `logos6.jfif`, `logos7.jfif`, `logos8.jfif`; one logo per quadrant on a dark background (`logos7` is light: its pale background is the one filled), with per-sheet and per-logo background cutoffs for the sheets with ghost logos behind them: the background is flood-filled from each quadrant's edge, stopped by each logo's solid outer border; stray specks are dropped; soft one-pixel edge) into `assets/characters/logo_<team>.png`. Each player wears the team crest on the jersey front as a `Decal` projected onto the chest (like the back number), and the home team's logo is painted into the ice at center (`Rink.set_center_logo`, 6.4 m wide, over the red line and under the blue circle). The team editor (M7) will replace the table.
  - **Skin and uniforms:** each vertex gets its body part (torso, arm, leg, hand, foot; the head and neck are bare skin) from its dominant bone, plus its position along that part (torso by height from the hips joint to the neck, limbs from shoulder/hip to wrist/ankle). `scenes/actors/uniform_regions.gdshaderinc` turns those into pants, jersey, socks, gloves and skates per pixel, with the stripes (`hem_band`, `sleeve_band`, `cuff_start`, `sock_band`) as clean anti-aliased bands. Stripe positions are shader uniforms, so a team's design can change them. The uniform is its own skinned layer (`Outfit_*` meshes): every covered triangle is copied, welded across UV seams, smoothed (`CLOTH_SMOOTH_PASSES`) so it drapes instead of showing muscles, and pushed out along the new normals by `cloth_thickness()` (bulkier over pads). It shares the body's bones, so it deforms with every clip. `scenes/actors/uniform.gdshader` colors it per team via `SkaterVisual.uniform_colors()`. Fabric detail is procedural, pinned to the cloth by each outfit vertex's rest-pose position and normal (baked into `CUSTOM0` / `CUSTOM1` by the build step, with the arms swung out to a T-pose by the skin weights, the origin at the base of the neck and the torso scaled to 0.6 m, so A-pose and T-pose bodies get the same pattern sizes and yoke). The chest, belly and hip bulk spheres wear the same uniform material with matching coordinates (`SkaterVisual._cloth_mesh`), so stripes and the yoke carry across them: jersey knit dimples, coarser mesh panels down the sides and under the sleeves, drape folds (rings around the sleeves, long folds down the body) and sewn seams at every stripe edge, cuff and shoulder; quilted, slightly glossy nylon breezers; vertical sock ribbing (around the leg by the rest normal's heading); leather grain on the hands. Height detail becomes per-pixel normals (screen-space bump, no tangents needed), and fine patterns fade with distance (`keep()`) so they don't shimmer. `detail` = 0 gives the old flat look. Each team has a jersey design (`Teams.DESIGN_OF` → `Teams.DESIGNS`): classic, double, triple, yoke, yoke_stripe, bold, pinstripe or hoops. A design sets how many stripes the hem, sleeve and sock bands split into, their positions, whether every other stripe uses the accent color (the team's number outline), and a shoulder yoke in the trim color (`yoke_r`: one smooth shape around the base of the neck, measured on the front/back silhouette so it's continuous across body, sleeves and the chest pad; everything above the neck line is yoke). Yoke designs carry the back number a little lower (`SkaterVisual.number_drop`). Road uniforms keep the home design. Stripe positions on the cloth layer are measured again on the smoothed cloth (smoothing slides vertices along the limbs), so stripe and yoke edges stay straight instead of stepping from one ring of triangles to the next; shoulder-bone vertices are measured along the upper arm. The skin textures come from the glTF versions of the bodies, whose texture coordinates are upside down relative to the Mixamo FBX exports, so the build flips V (`flip_v` in `BODIES`). The small eyeball mesh is kept as `Eyes` with the body's eye texture (`eye_tex` meta). The body itself uses `scenes/actors/skin.gdshader`: the MakeHuman skin texture divided by its average color and tinted to `Skater.skin_tone` (one of `SkaterVisual.SKIN_TONES`, random for now, set in the player editor later). It discards skin under worn clothing (the `wear` / `wear_skates` toggles), so a jersey can come off in a fight later. Shoulder/pants bulk and goalie pads are simple meshes attached to bones. Stripes are drawn only where a triangle belongs to a single body part, so part boundaries (armpits, shoulders) don't show slivers. The back number is a `Decal` attached to the chest bone, projecting the digits forward onto the jersey so they wrap with its curve and the pads beneath (`normal_fade` keeps them off side and front surfaces). Digits come from `assets/characters/digits.png`, rendered once by `tools/build_digits.gd` (needs a window) and tinted per team in `SkaterVisual.number_texture()`. Head, chest and hip gear is placed from mesh-based anchor boxes saved by the build step, so it fits any body shape; limb gear follows the joints.
  - **Equipment models:** `godot --headless --path . -s res://tools/build_gear.gd` turns `assets/equip/` models into plain meshes in `assets/characters/`. Source textures (real team and brand logos) are dropped, surfaces are split by role so the game paints them per team, and dense scans are welded and simplified (meshoptimizer, falling back to vertex clustering for noisy scans). Outputs: two helmets (`helmet`, `helmet_b`: shell, trim, dark, visor), two goalie masks (`goalie_mask`, `goalie_mask_b`: shell, cage), `stick` (shaft, blade; heel at the origin), `goalie_stick` (body, grip, tape; same layout), `skate` (boot, steel), `glove` (a long-cuff gauntlet whose flat fingers are bent around the knuckle line into a grip and puffed to hockey-glove bulk; a right glove, mirrored for the left hand) and `catcher` (a baseball glove as the goalie's catching glove). `Skater.gear_style` picks the helmet or mask (`SkaterVisual.HELMETS`, `GoalieVisual.MASKS`, each with its own fit). The stick model is posed every frame from the heel to the top of the shaft, with the blade flat along the ice in the stick's plane and its hook toward the forehand; the mesh skews slightly when the hands and blade don't match its lie. Goalies hold the goalie stick in the blocker hand with the blade across the crease toward the glove side; they wear the catcher on the left hand, pocket toward the shooter; pads and blocker are still boxes. `tools/preview_model.gd` renders any model from the front, side and top to check orientation.
  - **Posing:** `SkaterRig` (a `SkeletonModifier3D`) runs after the clip player and builds the body procedurally: the skating stride (two-bone leg IK to the ice; cadence from speed, amplitude from push), the forward lean, twists for windups and follow-through, and arms gripping the stick (two-bone IK). The top hand is placed from its own shoulder, down and well forward at belt height within ~80% of the arm's reach so the elbow stays bent, rocking with the stride. The bottom hand slides down the shaft toward the blade. Elbow poles flare out to the sides for an open stance. Skating hard without the puck (`SkaterRig.free_arm`), the bottom hand lets go and swings forward and across as the same-side leg drives back. Goalies use free hand targets for the glove and blocker. Each region (legs, spine, arms) blends between the clip and the procedural pose, so clips can own just the upper body.
  - **Clips in use:** knockdowns (`knocked_down`, `falling_down`), stumbles (`big_side_hit`, `hit_to_body`), goal celebrations (`fist_pump`, `cheering`, `rallying`; upper body only, so legs keep gliding) and the beaten goalie's `angry_gesture`. Fight clips are imported and waiting for M4.
  - **Sound:** recordings in `assets/sound/` are cut into game clips by `python tools/cut_sounds.py` (ffmpeg; trims, fades, peak-normalizes, makes the crowd bed loop seamlessly) into `assets/sound/cut/<name>_<n>.ogg`. The `Sfx` autoload loads those (a random variant per play) in place of its synthesized stand-ins; whatever has no recording yet (stick clicks, posts, glass, the net, pads, glove saves, whistle, "ooh") is still synthesized. Recorded (ElevenLabs): slap and wrist shots, board and open-ice hits, hockey stops, strides, the goal horn, the crowd bed, cheers, boos, a rising crowd, a disappointed groan, an outraged crowd, "De-fense!", four team chants, two organ pieces and the announcer. `MatchAudio` hooks match events to it. The crowd belongs to the home team (team 0): horn and big cheer for home goals, a groan for goals against; cheers for home big hits and glove saves; boos for home penalties and cheers for the visitors'; "De-fense!" when the home team is pinned in its zone; a rising crowd as a home attack builds (faded if it fizzles); the home team's chant every minute or two; a disappointed groan when a home shot is saved by the visitors, rings a post or misses wide; and boos for the visitors' big hits on home players. The arena organ (its own channel) plays an upbeat piece through stoppages, starting at a random point and fading at the drop, and sounds the charge as a home attack builds. **Announcer:** play-by-play lines live in `assets/sound/announcer/` as `<line><n>.mp3` or `<line>_<nn>.mp3` (trailing digits = another take of the same line; just drop new files in). `AnnouncerLines` (scripts/core/announcer_lines.gd) is the list of every line by category, when it plays, and the other file names that count as its takes (the names in `data/hockey_announcer_lines.csv`, e.g. `hit_01` joins `bighit`, `period_end_01` joins `periodend`). `tools/announcer_check.gd` (`-- md=docs/ANNOUNCER_TODO.md`) reports takes per line against the target of 3 with the CSV's scripts for each. Added since: second/third period, overtime, shootout, final minute, final horn, faceoff win/loss, pass to the point, dump-ins, zone entries, behind the net, along the boards, setting up, cycling, wrist and point shots, misses, blocks, rebounds, pad/glove saves, top-shelf and calm goals, goal follow-ups (tie, lead, insurance, hat trick, power play, short-handed, comeback, reactions), hits into the boards, penalty killed, whistles, hot streaks, close games and blowouts. With `KH_AUDIO_LOG` set, lines that would have played but have no recording print as `(not recorded)`. **Two voices:** Steve Sheldon (play-by-play, calm and British, `announcer/pbp/`) calls the play; Bobby Niedemyer (color, loud, `announcer/color/`, plus the original recordings in `announcer/`) reacts after big saves, big hits, goals, the third period's call and the final horn, and fills quiet spells. One talks at a time. Each line in `AnnouncerLines` names the voice that records its new takes, but every voice's takes of a line share one pool, so Bobby's original play-by-play takes keep playing alongside Steve's. **Duets** (both in one ElevenLabs dialogue clip) go in `announcer/both/`: a duet can be a take of any line (`both/crowdreactgood_01.mp3` the crowd remark), and the banter lines are duets only (quiet spells, intermissions, after penalties, fights, goals, big hits and the final horn, blowouts and close games), each falling back to the solo line when not recorded. `Sfx.announce` plays one line at a time (a line only cuts off a lower-priority one, takes don't repeat back to back), and `MatchAudio._say` gives each line a chance and a cooldown so the commentary stays occasional: faceoff, pass, shot, fullslapshot (hard slap shots), save, bigsave (glove saves and saves right after a breakaway), bighit, pokecheck, breakaway (a carrier racing at the net with no defender between them and it), penalty / trippingcall / bigpenalty (boarding), then powerplay, and goal once goal lines exist. Offsides and icing whistles get their own calls; each period start says `period<N>` if that file exists (period2, period3: the number is part of the line, so these are looked up by exact file name), else `newperiod`, after the `periodend` call finishes; `idle` chatter fills long quiet spells. Intros: `assets/sound/intro/intro_<call>.mp3` ("Tonight: a matchup between the <team> and the <team>.") are split by `tools/cut_sounds.py` at the quietest moment between the halves into `intro_home_<call>` and `intro_away_<call>`, and the matchup screen plays the home team's opening then the away team's close (`Sfx.announce_chain`; Teams `call` names the clips). As the screen closes, Steve and Bobby welcome everyone in a duet (`intro_duet`, files `both/doubleintro*.mp3`) every game, in place of the first period's call; Steve's solo `intro` plays there only if no duet is recorded. More lines: goal, post, deke (when the carrier dekes), check, onetimer, checking ("they're really fighting for it!": possession flips between the teams three times in 5 s), downice ("heading down the ice": a carrier crossing center toward the other net with speed), turnover (the puck straight from one team's carrier to the other's), defenderup (a defenseman carrying into the offensive zone), centerice (the faceoff after a goal), big hits mixing bighit / flattened / gottahurt (+ bighitenforcer from defensemen and heavy checkers), and crowdreactgood / crowdreactbad when the home crowd has reacted the same way three times in 75 s. `fighting` is waiting for M4. Set the `KH_AUDIO_LOG` environment variable to print every announcer line and crowd reaction as it fires. Crowd reactions play one at a time on their own channel (`Sfx.crowd_react`, by priority: goal > reaction > ambient).
  - **Close-up check:** `scenes/tests/CharacterViewer.tscn -- shot=<png> view=front|side|back|quarter|top focus=<0-6> style=<gear style> save=glove|blocker|butterfly`.
- **M6 additions:**
  - **Player ring meters:** the ring under each human-controlled skater is two meters (`scenes/actors/player_ring.gdshader`, set in `SkaterVisual._update_human_tag`). The wide outer arc is sprint (stamina), going from green through yellow to red; the thin blue inner arc is legs (shift energy). Both start at the top of the screen and drain counterclockwise back toward it, over a dark track tinted with the player's color. While sprint is locked out (used up, back at 25%), the sprint track pulses red. The floating stamina bar and the corner text's legs % are gone.
  - **TV graphics (`MatchHud`):** drawn in the menu style (`MenuStyle`: the heavy slanted font, red / navy / ink, slanted bars; shared helpers `team_color`, `team_logo`, `draw_slant`, `draw_bold`, `player_name`) on the 1600 × 900 design canvas. The scorebug sits top left: away then home, each a plate in the team's color with crest and abbreviation, the score on ink, shots on goal underneath (the shootout's attempts as dots), then period and clock on brushed steel. A tab under the clock shows the power play in the team's color with the time left (or "5 ON 3"), or a delayed penalty or offside in red. Banners are slanted bars that wipe in across the middle, in a team's color with its crest when it's that team's moment (goals, big hits, the final). Lower thirds: the goal card (scorer, assists) and the penalty card (offender, foul, minutes). Flashes are a small navy tab. Hints sit bottom left only when they matter: faceoff timing, goalie with the puck, and the pause button during stoppages; they hide while a lower third is up. The HUD runs on the wall clock (each gap clamped to 0.5 s), so slow motion doesn't drag it and a pause doesn't eat a banner. `-- hudtest` fires a goal banner and card, a big-hit banner and flash, and a penalty card, for layout checks.
  - **Box score (`BoxScore`, `MatchDirector.box`):** per-player goals, assists (the scorer's teammates who touched the puck before them in the same possession, up to two), shots, hits, big hits, +/- (not on power-play goals), penalty minutes, fights and fight wins; goalies' saves and goals against. `rating()` folds a line into a simple game score; `period_start()` snapshots lines so `period_line()` gives one period.
  - **Intermission and final screens (`Intermission`):** in the pause menu's style: the dimmed game behind, the mode tag and heading ("END OF 1ST", "FINAL"), both teams' plates with the score (away left; at the final the loser fades and a red bar marks the winner), a game-stats panel with twin bars in the team colors, and the prompt bar (accept continues). Between periods: each team's HOT and COLD player over the period just played (cold only for a player whose period was negative; otherwise "Clean period"). At the end: the THREE STARS, the game's top three ratings across both teams (ties go to the winner). `-- statscreen[=final] statwait=<s>` opens it after playing a while (layout checks).
  - **Benches and penalty boxes (NHL layout, all built in `rink.gd` from `RinkSpec`):** the team benches sit along the −X boards in the neutral zone (team 0 on the +Z half, `BENCH_Z`), each 7.6 m long and 2.3 m deep, with a rubber floor, a back wall in the team's color (`Rink.set_bench_colors`), a seat, end walls with glass partitions, and no glass in front. Each bench has two hinged doors, one at each end (`BENCH_DOORS`). Across the ice on +X are the two penalty boxes (`BOX_Z`) with the timekeeper's box between them; the rink glass runs in front, and each box has one full-height door of board and glass by the timekeeper (`BOX_DOORS`). The boards, cap, ads and glass are cut around the doors (`RinkSpec.door_gaps` / `glass_gaps`); the invisible collision wall stays whole, so the puck never gets out. Doors swing out of the rink about their hinge (`Rink.open_door(id, hold)`, ids `bench<t>_<0|1>` and `box<t>`). Players off the ice stay visible at their spot: `Skater.bench_spot` or `box_spot` while `in_box_spot`. Bench spots are claimed when a player parks (`MatchDirector._claim_bench`): their current spot if it's still free, else the first free seat along the bench seat (`Rink.bench_seats`, 0.6 m apart, hips over the seat for the sitting clips), else standing at the boards. Line changes walk through the doors (`Skater.walk`: a scripted path with no physics): the tired skater goes off through the door nearer them, the fresh one comes on through the other, and each door opens just before they reach it (`MatchDirector._change_through_doors`). Penalized players and fighters skate from where they were to the box door and in to a seat (`_send_to_box`); when the penalty ends they walk back out of the box door into play, or go back to the bench if their team doesn't need them. **Bench and box animation:** parked players keep their visual running (the skater itself doesn't process) on a looping idle with the stick put away (`SkaterVisual.bench_pose`): seated on the bench and in the box (`sitting`, `sitting_2`, now and then `sitting_talking`), `holding_idle` for anyone standing at the boards; each starts at a random point in the loop at a slightly different speed. `bench_react(kind)` plays one reaction and returns to the idle: "cheer" (sitting claps, fist pumps, yells, cheering; standing claps, fist pump, cheering), "groan" (disbelief, disapproval, angry), "sulk" (angry, disapproval, rubbing an arm) and "laugh". `MatchDirector._bench_react(team, kind, chance)` sets off a bench and its box with a chance each and up to half a second's stagger: goals (the scorers' side cheers, the other groans), big hits (the hitter's bench), penalties (the other bench laughs, the offender's groans) and fights (the winner's bench). Players arriving in the box sulk. The rig skips its procedural work when a clip owns the whole body. `-- benchtest` sends two players from each team to the box and cycles reactions (layout checks). `-- look=x,y,z,tx,ty,tz` sets a fixed camera and `-- doors` swings every door open and shut, for layout checks.
  - **Names on the back:** a nameplate above the back number, in the number's colors: the player's nickname if it's `SkaterVisual.NICKNAME_MAX` (8) characters or fewer, else their last name (`SkaterVisual.back_name`), upper case. The letters come from `assets/characters/letters.png`, rendered once by `tools/build_letters.gd` (needs a window; A–Z, É Ñ Ô Ú Û, 0–9 and - ' . !, the same white face / black outline scheme as the digit sheet). `name_texture()` crops each letter tight, spaces them and tints them per team; the plate is its own Decal on the back like the number (`_back_decal`), with capitals `NAME_HEIGHT` tall, `NAME_GAP` above the number, and long names squeezed to `NAME_MAX_W`. The number moved `NUMBER_LOWER` (0.2 m) down the back to make room, so the name sits across the shoulder blades. Goalies get the same. The character viewer's players carry sample names (plain, very long, a nickname, accents, punctuation).
  - **Replays (`Replay`, `ReplayTap`):** every player's skeleton ends with a `ReplayTap` modifier (after `SkaterRig`) that records the finished pose about 30 times a second of game time: the skeleton's world transform, the stick's, visibility, and each bone's local position and rotation; `Replay` records the puck's look. The rings keep 14 s. `Replay.capture(kind, label, focus, pre, post, opts)` marks a highlight from `pre` seconds back and cuts it `post` seconds later. Playing pauses the game tree, hides the game's HUD layers, swaps in a replay camera and writes the recorded poses back onto the same skeletons (the tap overrides the pose; skeleton and stick transforms are set directly; the rig is switched off); a copy of the puck's mesh stands in for the puck, so its physics body is never moved. A red "INSTANT REPLAY" wipe covers the cut in and out; the overlay shows a REPLAY tag with what it is (and SLOW MOTION below 0.7×) and a skip prompt; any accept, back or Start skips. The arena's sound (`Sfx`: crowd, organ, the booth) keeps playing through a replay. Afterwards everything goes back exactly as it was. Schedule: goals play right away (5 s before to 1.2 s after, 0.8×, the "net" camera: low off the post of the net it went into, zooming on far-off play); knockouts play right away (2.8 s before, 0.45×, an "orbit" camera circling the fighters); big hits are saved and play at the next stoppage within 45 s (0.4×, orbit), else at the end of the period; at the end of a period and the final horn up to two unshown highlights play before the stats screen. Replays only run in games with the HUD (not the soak). `-- replaytest` stages a net-cam and an orbit replay; `-- fight=ko` starts a fight with one fighter a punch from going down.
  - **Referee (`Referee`, `RefereeVisual`, `RefBrain`):** one on-ice official, a Skater with no stick (`handles_puck` off), outside both teams, with no collisions with players or the puck (the boards still hold). Stripes come from the uniform shader's `vstripes` (vertical stripes in the accent color around the torso and sleeves) and `long_pants`, via the `referee` design in `Teams.DESIGNS`: white and black, orange armbands (the sleeve stripe in the trim color), black pants, helmet and gloves, number 27. The visual places the hands freely (the rig's ARMS_FREE): at the hips skating, one arm straight up for a delayed penalty (`signal_arm = "up"`, set by the director while `rules.has_delayed_penalty()`), or pointing at `point_at`. Officials skate taller (less crouch and lean). `RefBrain` follows the play NHL-style: along the boards on the far side from the puck, a few meters deeper into the zone it's in, facing it and stepping aside from players; `hold` / `face_at` pin it for cutscenes. Hidden during the matchup intro; recorded for replays.
  - **Cutscenes (`Cutscene`):** a run of camera shots while play is stopped (the game keeps running): each shot has a length, a framing callable (camera position, look-at), an optional lens and a start callable; shots cut like a broadcast and the camera eases within one; accept / back / Start skips (not in the first 0.4 s). **Penalty call:** at the whistle the camera cuts to the referee, stopped and squared up to the offender, pointing at them (`PENALTY_CALL` = 1.5 s) while the penalty card is up; then the ref points to the box and the camera follows the offender (who waited for the call: `_send_to_box(..., delay)`) skating through the box door to the seat. The stoppage lasts until it's done; skipping parks the offender on the box seat. Only with the HUD on, one call per stoppage (a second penalty just skates off). `-- penaltytest` calls a delayed penalty a few seconds in, then blows the whistle. **Goal celebration:** with a scorer to follow (HUD on, the scorer on the scoring team), the scorer peels off to the corner glass by the net they scored on and up to four linemates pile in around them (`CelebrateBrain`: skate to a spot, face the huddle, cheer on arrival; everyone's own brain, human or AI, comes back afterwards). Shots: out in front of the scorer looking back as they skate away (1.8 s), then the huddle against the glass from the ice, a little high (2.5 s). The goal's replay waits for it (`Replay.play_soon("goal")`: plays the clip now, or as soon as it's cut; while a goal clip is pending, the replay counts as busy so a saved hit can't jump in). Skipping goes straight to the replay. `-- goaltest` credits a home goal a few seconds into play. **Period openers:** every period (HUD on) starts with the faceoff placement as usual, then the starting lines and goalies are moved into their bench doorways (two doors per team, a short queue at each) and walk out through the doors to their spots (home first, the away team 1.6 s later), each door swinging open as they reach it; goalies settle into the crease. Shots: down the boards at the home bench (2.6 s), the same at the away bench (2.6 s), then high and wide sweeping around center ice under the period banner until everyone's in place. PREGAME waits for it; skipping, or the end, puts anyone still on the way straight on their spot. Players on the bench and in the box stay where they are (penalties carry over).
  - **Screenshot timing:** the first frame's delta is the whole load time, so `-- shot` and the debug timers wait one frame before starting their clocks.
- The puck is drawn 2.8× size with a white outline and shows through players, so it always reads from the high camera. Its collision stays regulation size.

---

## 11. Asset plan

The current assets were quick placeholders; none of them are a requirement.

| Asset | Status | Plan |
|---|---|---|
| Rink | Two Sketchfab rinks (placeholders) | Gray-box rink built in-engine with exact NHL dimensions (200×85 ft) and colliders. Final visuals: built in engine or a cleaned-up model. The smaller rink → outdoor venue. |
| Arena seating | Stadium GLB (39 MB) | Placeholder only; later a modular, lightweight bowl with recolorable seats. |
| Skater base | **M5:** male and female bases (Braingapps, rigged via Mixamo) + Y Bot for tests | More bodies: rig in Mixamo, drop in `assets/player/`, add a line to `BODIES` in the build step. |
| Animations | **M5:** 51 Mixamo clips + procedural skating rig | Hockey moves (stride, stop, shots, stick handling, goalie stance and saves) are procedural; Mixamo supplies falls, hit reactions, celebrations, fights and crowd. |
| Gear | **M5:** two helmets, stick, skates and gloves from models; uniform as a skinned layer | Shoulder and pants bulk are still simple shapes. |
| Goalie gear | Two mask models and a catcher model; pads and blocker are boxes | Pad and blocker models. |
| Stick | Colin Charleson model (skaters), CCM goalie stick model (goalies) | Tape colors per player. |
| Puck, nets | None | Built in engine. |
| Audio | **M5:** recordings for shots, hits, skates, horn and the crowd; the rest synthesized | Puck clicks, posts, glass, whistle, organ, punches, music. |
| UI | None | Fonts, preset logos, menu style. |

**Credits:** every CC-BY asset must be listed on a credits screen.

---

## 12. Open questions / to test

- **Catch-up AI:** test with and without; decide on the default.
- **CPU difficulty tuning:** reaction time and decision values for each level.
- **Conference structure:** 8 teams per conference — divisions or not?
- **Fight threshold tuning:** how often fights happen (target: about 1–2 per game when fighting is on).
- **Glass breaks:** frequency limits.
- **Horizontal camera:** add as an option later?
- **The 4 launch teams:** names, cities, colors, rosters (designer to provide).

---

## 13. Milestones

| # | Milestone | Done when |
|---|---|---|
| **M0** | Project setup | Godot project, folder structure, input map, gray-box rink with colliders, nets, puck bouncing correctly. |
| **M1** | Skate & shoot | One capsule skater (with stick) skating, picking up the puck, deking, passing to a dummy, wrist/slap shots, goals detected. *The "does it feel good?" milestone.* |
| **M2** | 3v3 hockey | Two 3v3 teams of capsules, basic AI, AI goalies, checking (bump/check/big hit), faceoffs, clock, score, periods. |
| **M3** | Full rules | 5v5, line changes and stamina, offsides/icing/penalties with toggles, player switching, OT/shootout, local multiplayer (up to 4). |
| **M4** | Fighting | Fight triggers, prompt, forced fights, the mini-game, consequences. |
| **M5** | Characters | Shared skeleton, retargeted animations, gear, recolorable jerseys, goalie model. |
| **M6** | Presentation | HUD, announcer pop-ups, replays, three stars, big-hit slow-mo, glass breaks, crowd, audio, Zamboni. |
| **M7** | Editors | Team, player and arena editors saving to `user://`. |
| **M8** | Exhibition release | Front-end menus, 4 teams, indoor and outdoor arenas, settings, credits. |
| Later | Expansion | 32 teams, season/playoffs, management/franchise, custom logo builder, horizontal camera. |
