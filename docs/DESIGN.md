# Knockout Hockey — Design Document

*Living document. Version 0.2 — written 2026-11-05, checked against the build 2026-11-12.*

Sections 1–9 describe the game as designed. Anything in them that isn't in the build yet is marked *(not built yet)*; §13 has the milestone status and §14 the open work. Section 10 is how it's built.

---

## 1. Overview

**Knockout Hockey** is a 3D arcade hockey game made in Godot 4.7 for PC. It plays like the hockey games of the Genesis–N64 era: fast, responsive, three-button hockey, but with a modern, mostly realistic look. Fighting is a featured mechanic with its own mini-game. Every team is fictional. Players can create teams, players and arenas.

- **Platform:** PC (Windows), keyboard and controller. Personal project; no plans for consoles or a commercial release.
- **Players:** 1–4 local, co-op and versus.
- **Modes:** Exhibition, Knockout Mode (a card of fights, §10.5 M3) and Practice. Shootout mode, Season, playoffs and management come later (they're "coming soon" on the menus).

### 1.1 Design pillars

1. **Feels like 1994, looks like today.** Instant input response, readable motion, few buttons. Visuals are clean and grounded, not retro.
2. **Every button press does something right away.** No input buffering that feels like lag, and no animation that locks you out of control for long.
3. **Big moments get big presentation.** Bone-crunching hits, shattered glass, slow-mo, crowd roars. The players stay human: no magic, no flaming pucks.
4. **Fights matter.** Fights are grounded, skill-based and have consequences: penalties, injuries, momentum.
5. **Everything is data.** Teams, players, jerseys and arenas are all data files, so the editors and later modes come almost for free.

---

## 2. Match structure and rules

### 2.1 Match settings (all configurable before a match)

Set on the rules screen before an exhibition (`RulesSelect.RULES`); the saved defaults are under RULES AND OPTIONS > RULES.

| Setting | Options | Default |
|---|---|---|
| Format | 5v5 + G, 3v3 + G | 5v5 |
| Period length | 1, 2, 3, 5, 7, 10, 20 min (game clock) | 3 min |
| Periods | 3 (fixed for now) | 3 |
| Overtime | Off / Sudden death / Shootout / Sudden death → Shootout | SD → Shootout |
| OT length | 1, 3, 5 min | 3 min |
| Shootout rounds | 3 / 5, then sudden death | 3 |
| Offsides | On / Off | On |
| Icing | On / Off | On |
| Penalties | On / Off | On |
| Fighting | On / Off | On |
| Line changes | Auto / Off (fatigue disabled) | Auto |
| CPU difficulty | Rookie / Pro / All-Star / Legend | Pro |
| Camera | Broadcast / Close / Side / High (§7.1) | Broadcast |
| Camera turns | Never / With my team | Never |
| Injuries | On / Off | On |
| Catch-up AI | On / Off | Off *(to be tested, see §12)* |

### 2.2 Rules (when enabled)

- **Offsides:** delayed offside: the linesman's arm goes up and play goes on until the puck leaves the zone or every attacker tags up; an attacker touching the puck in the zone first blows it dead.
- **Icing:** no-touch icing (any touch cancels it). No icing while shorthanded. *(Hybrid icing, a race to the faceoff dot line, was the original plan.)*
- **Penalties:** called automatically from contact events; the referee rolls whether each foul is called (`MatchDirector.FOUL_CHANCE`).
  - *Minor (2:00), built:* tripping (a poke check that hits the skater, not the puck), boarding (a hit from behind near the boards), interference (hitting a player without the puck after a grace period).
  - *Minor, not built yet:* hooking, high-sticking, holding, charging (a check started with too much distance). The announcer CSV already has hooking, slashing, roughing and high-sticking calls waiting for them.
  - *Major (5:00):* fighting (both players, offsetting, so no power play).
  - Delayed penalty: the referee's arm goes up and the whistle blows when the penalized team touches the puck. The team with the puck can pull its goalie for an extra attacker meanwhile (§4.7); the computer does once it has the puck out of its own zone.
  - How often fouls get called depends on the referee's **strictness**, a hidden variable rolled each game: about 0.85 (Rookie) to 1.1 (Legend) plus a random spread, clamped to 0.65–1.35. It scales each foul's call chance (`MatchDirector.ref_strictness`; `-- ref=<x>` sets it, `-- reflog` prints it).
- **No ejections.** This is a deliberate design choice.
- In **3v3**, penalties produce 4v3 power plays (capped at 5v3 for 5v5).

### 2.3 Flow of play

Matchup intro, period-opener walkout, opening faceoff, then open play until the whistle (goal, offside, icing, frozen puck, penalty, puck out of play, or the period ending), then a faceoff at the matching dot. Between periods there's the intermission stats screen with hot and cold players, and the organ; a Zamboni scene is planned (skippable) *(not built yet: waiting on a Zamboni model)*. Three stars are shown after the match.

---

## 3. Controls

Context-sensitive: the same buttons do different things depending on whether your team has the puck.

### 3.1 Controller (PlayStation prompts)

The whole game is playable with a controller, including typing names (the on-screen keyboard, `PadKeyboard`). On-screen prompts are PlayStation buttons, drawn from the PlayStation button font (`assets/fonts/PLAYB___.TTF`) by `MenuStyle.draw_glyph`; code may name pad buttons by their Xbox position (A, X, LB...) and `MenuStyle.pad_label` translates. Godot's JOY_BUTTON_A / B / X / Y are Cross / Circle / Square / Triangle; Start and Select are Start and Select.

| Input | Offense (your team has the puck) | Defense |
|---|---|---|
| Left stick | Skate | Skate |
| **Cross** | Pass (tap) / saucer pass (hold) | Switch to the player nearest the puck |
| **Square** | Shoot: tap = wrist shot, hold = slap shot (charges) | Hook / stick lift |
| **Circle** | Check / shoulder bump | **Body check** (hold to wind up a bigger hit) |
| **Triangle** | Deke (direction from the left stick) | Poke check |
| **R2** | Turbo (drains stamina) | Turbo |
| **L2** (hold) | Skate backwards (face away from the stick direction; ~72% top speed, no hard stop) | Skate backwards |
| **L1** | Protect puck (slower, harder to strip) | Block-shot stance (drop to a knee) |
| **R1** | — | — *(reserved: strategy / line call)* |
| Start | Pause menu | Pause menu |
| Select | Camera angle | Camera angle |

- **One-timer:** press or hold shoot while a pass is on its way to you, and you shoot the moment it arrives.
- **Pass targeting:** a pass goes to the teammate closest to the direction of the left stick (65° cone; the angle weighs much more than distance). The stick direction is remembered for `Skater.AIM_MEMORY` (0.35 s), because players usually let the stick go a moment before the pass button. A pass leads a moving receiver by at most `PASS_LEAD_MAX` (3 m), bends gently onto the receiver's stick over the last few meters (`Puck.PASS_HOMING`), and the intended receiver catches it within `INTENDED_REACH` (1.5 m). With the stick in neutral, it goes the way the skater faces.
- **Goalie control:** when your goalie has puck control (covered or holding it), the human takes control of the goalie: Cross = pass out, Square = clear the puck (shoot it up ice), Triangle = cover it for a faceoff. After that, the goalie goes back to AI.

### 3.2 Keyboard

| Action | Keyboard 1 | Keyboard 2 |
|---|---|---|
| Move | WASD | Arrow keys |
| Pass / Switch | J | Num1 or , |
| Shoot / Hook | K | Num2 or . |
| Check | L | Num3 or / |
| Deke / Poke | I | Num5 or ; |
| Turbo | Shift | Num0 or Ctrl |
| Protect / Block shot | Space | NumEnter or ' |
| Skate backwards | Q | Num6 or M |
| Fight block (R1) | U | Num4 or N |
| Pause | Esc | Esc |
| Camera angle | C | C |

F3 shows or hides the FPS counter. The bindings live in code (`HumanBrain.KB1` / `KB2` / `PAD`, `InputRouter`); there's no remapping screen yet *(not built yet)*.

### 3.3 Fight controls (mini-game, §5)

| Input | Action |
|---|---|
| Left stick | Toward / away from the other fighter (on screen): step in / back off. Up / down: slip a punch |
| Cross (A) | Jab (lead hand, fast, light) |
| Square (X) | Cross (rear hand, straight) |
| Triangle (Y) | Hook (dominant hand, like the cross; big, visible windup) |
| L1 (hold) | Modifier: the three punches go to the body (less damage, more balance, drain stamina); with R1, block low |
| R1 (hold) | Block high (head shots); with L1, block low (body shots). Much less damage, costs stamina; the wrong guard lets the punch through |
| Circle (B) | Grab the jersey. While holding, the free right hand punches: Cross = right to the body, Square = right hook, Triangle = uppercut (the same for every style; no jab). Held: mash Circle to break free. Holding while they're getting loose: mash Circle to hang on. Every press costs stamina on either side |

Presses during a punch or a stagger are buffered (0.3 s), so mashing a combo works; Circle presses while tied up are never buffered. The prompt to drop the gloves: Cross yes, Circle no. Keyboards use the same keys as pass / shoot / deke / check, protect for L1 and block (U / Num4 or N) for R1.

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
- **Hits into the boards** add a multiplier (×1.4). At a very high power, a **glass break** happens: the panel shatters, there's a stoppage, and a short cutscene of the repair crew (it can only happen once or twice per game). As built: a big hit into the boards with power 19+ (after balance and the boards) breaks the pane behind the victim 60% of the time, a second one 25%, never more than two a game, and never where there's no glass (the open bench fronts, the box doors). The pane goes, jagged teeth stay in the frame, 150 shards fly (most into the seats, some onto the ice, where they lie until the repair), "GLASS SHATTERED!", a big crowd roar, longer slow motion and shake, and the whistle a second later. The stoppage plays its cutscene (after the penalty call, if there is one): the hole up close, then wider as the new pane is lowered in. *(No repair crew yet: the pane comes down on its own.)* `-- glasstest` breaks one a moment into play.
- As built, a big hit is a knockdown clip (not a ragdoll), 0.45 s of slow motion, camera shake, a "BIG HIT!" / "CRUSHED INTO THE BOARDS!" banner, the hitter's bench cheering and a saved replay.
- Hits always risk penalties (§2.2) and can trigger injuries (§4.8) and fights (§5).

### 4.6 Defense

- Poke check: a quick stick jab with a cone. If it hits the puck it knocks it loose; if it hits the skates it's tripping.
- Hook/stick lift: a lower-risk strip from behind or beside. Hooking risk goes up if held too long.
- Block-shot stance: drop to a knee in the shooting lane. Slower movement, chance to block shots.

### 4.7 Goalies

- Fully AI by default, with positioning driven by stats (angle, depth), save animations chosen from the shot vector (butterfly, glove, blocker, pad kick, stack), and rebound control.
- Goalie control goes to the human only once the goalie has the puck (§3.1).
- **Pull the goalie:** delayed penalty or late game, from the pause menu (GOALIE) or Select / G in play. The goalie skates to the bench door nearer their net (7.5 m/s) and, once off, the freshest forward comes on through the other door. Putting them back: the skater nearest the bench heads off while the goalie skates back to the crease. A goalie pulled for a delayed penalty comes back at the whistle; otherwise they stay off for a faceoff outside their own zone. The computer pulls when the other team has a delayed penalty, or when it's down one or two in the last period of regulation with 12% of the period left (20 s at least, 2 min at most; 1.6x that down two), once it has the puck out of its own zone, and puts the goalie back when it's no longer behind. The HUD hints at it when it makes sense, the tab under the clock says EMPTY NET, the other team's AI shoots at an empty net from anywhere with a lane, and a goal into it is an EMPTY-NET GOAL (no goal against for the goalie). `-- pulltest` (the away team pulls a few seconds in) and `-- pulltest=late` (the away team is down one with 25 s left).

### 4.8 Stamina, line changes, injuries

- Each skater has stamina; fatigue reduces speed, shot power and checking.
- **Auto line changes** on the fly when the active line's average stamina drops below a threshold and the puck is out of the defensive zone, or at stoppages. Forward lines F1–F4 and D-pairs D1–D3 in 5v5; 3v3 rotates groups of three.
- **Injuries:** a small chance after big hits or fights, scaled by durability. The injured player leaves for the rest of the game and lines are rebuilt automatically. Injuries carry over in season modes (later). As built (with the Injuries setting on): a big hit hurts the player hit 3.5% of the time (×1.6 into the boards), the loser of a fight 12% (×2 if knocked out); durability scales both from 1.7× (frailest) to 0.4× (toughest). At most two a team, and only while the team still has a spare forward and defender. A player hurt in play stays down; the whistle goes when their team touches the puck, or after 4 s. At the stoppage they're helped slowly to the bench and sit there, an INJURY lower third says they're out for the game, and the lines are rebuilt without them. `-- injurytest` hurts a home skater a moment into play.

---

## 5. Fighting

### 5.1 How fights start

1. **The prompt:** once the hit team's tension passes the threshold, the **victim's team gets a prompt** ("Drop the gloves? Cross / Circle", 3 s, play stopped). If they accept, their toughest skater on the ice fights the hitter (or the hitter's toughest teammate, if the hitter won't fight). *(A scrum around the goalie as a trigger: not built yet.)*
2. **Forced fights:** if the hitter is high in **aggression** (70+) and the tension is well past the threshold, they **start the fight on their own with no prompt**. The hit victim's team can't refuse.
3. **Tension meter (hidden):** each team builds tension from the hits it takes (big hits most, more into the boards); it slowly decays, and fights are at least 200 s of play apart. The meter drops after a fight or a refusal. *(Extra tension for hits on stars and goalie contact: not built yet.)*

AI teams decide whether to accept or start fights based on the player's fighting stat, aggression and the score/situation.

### 5.2 The mini-game

- The camera cuts to a tighter, lower angle on the two fighters; the other skaters gather in a ring and the linesmen hover. The crowd stands.
- Each fighter has **health** (from fighting + durability), **balance** (from strength) and **stamina** (from endurance).
- Each fighter has a **style** (`PlayerStats.fighting_style()`) with its own idle, jab, cross and hook (`assets/animations/fight/reworked/`, `<move>1-3`). Body shots reuse the same clips, bent forward at the waist. The uppercut, clinch hook, guards and reactions are shared by every style.
  - Who fights how: most hockey fighters are untrained swingers, so the **brawler** is the common style and the **boxer**, the clean, trained technique, is rare. `fighting_style()` is a weighted pick seeded from the player's ratings (the same player always fights the same way): fighting (more so with agility over strength) raises the boxer's odds, aggression the brawler's, strength over agility the grinder's. On the rosters (390 skaters): about 18% box, 61% brawl, 21% grind; enforcers mostly brawl, grinders and stay-at-home D lean grinder.
  - **Boxer:** quick, tight punches that are cheap on stamina but hit a little lighter.
  - **Brawler:** wide haymakers that hit harder and drain more balance, cost more stamina and are easier to slip.
  - **Grinder:** short, compact punches that hit balance and stamina harder.
  - **Reach is the body, not the style.** Whether a punch can land is measured from the punching shoulder to where the knuckles land, in the thrower's own arm lengths (`Fight._need`; the arms scale with height, `BodyBuild`; the arm is measured to the wrist bone, so the knuckles are `FIST`, 9 cm at scale 1, further on, and the reach IK holds the wrist that much short of the target): each move gets a share (`MOVES` reach: jab 1.02, crosses 1.0, hooks 0.95, grab 1.6 to the collar with an open hand). From `STEER` (0.2 s) before contact the punch is called every tick with slack (`REACH_EARLY`: the punch is still turning the shoulders and lunging in), so the glove goes where the call says: a miss can come into reach, and a hit turns into a block (glove onto the forearms) the moment the guard comes up, or back if it drops; once steered it isn't dropped. At contact it's judged for real, reach, slip and guard alike, so the defender's time to react is unchanged; a steered punch gets `REACH_STEERED` (0.05) slack there. Out of reach, the arm straightens and the glove visibly stops short. (It used to be called once, 0.2 s out: some punches wind up faster than that, so the call came on their first frame, before the step and the shoulder turn. In playtests punches visibly landed but didn't count, and in AI sims the early call disagreed with contact on 59 of 125 punches: 24 steered onto the target and then judged out of reach by a few cm or blocked, 29 not steered but counted. Now 6 of 159, all visibly short.) Each style clip has its own body turn while it's thrown (`STYLE_CLIPS` yaw / body_yaw, calibrated with `-- fightdebug fightmove=<move> fightstyle=<n> fightyaw=<rad>`, about 0.67 m sideways per rad): the one stance turn for every clip sent most fists 15–40 cm to the side; calibrated, they arrive within about 10 cm sideways. They still come in at chest height (head shots lift 15–25 cm, eased over `STEER`). A taller fighter lands from further off. The computer keeps its distance hip to hip in its own arm lengths (`AI_REACH`, by aggression, plus `AI_STYLE` reach: the boxer at the end of its punches, the brawler crowding in); not from the shoulder, since in the stance the rear shoulder sits well back until the punch turns the body.
  - The style shows on a colored tag by each fighter's name on the HUD, and on the "drop the gloves?" prompt, with a one-line read on the other fighter's style (`Fight.STYLE_BLURBS`).
  - The computer fights each style its own way (`Fight.AI_STYLE`): the **boxer** stays at the end of the jab, reads and slips more, counters a blocked or slipped punch with a straight right and backs off to breathe early; the **brawler** walks you down, swings big and often, guards and slips less, fights until it's nearly empty and jumps on a hurt fighter; the **grinder** grabs a lot, hangs on harder, digs to the body, and answers a blocked punch by tying you up.
  - `-- fightstyle=<a>[,<b>]` forces the styles for testing (with `fighteven`, both on the same ratings, to weigh the styles alone); the `KH_FIGHT_LOG` result names both styles and the winner. At equal ratings the boxer still wins most (12–3 over the brawler, 9–5 over the grinder; grinder 9–6 over brawler): measured before reach moved to the body; still to be rechecked and evened out (§12).
- **Grounded rules:** fighters grab jerseys, trade punches, tie up and wrestle. Grabbing pulls the two together, drains the held fighter's balance, makes your punches hit 15% harder (and cost 30% more) and swaps in a one-handed set (cross, right hook, uppercut); the held fighter can't slip and mashes to break free while the holder mashes to hang on (strength-weighted, every press costs stamina). Head and body punches (L1) need the matching high or low block (R1, R1+L1). Slipping (stick up / down) beats hooks if timed right. Range matters: step in to land, back off (out of reach, stamina comes back twice as fast). Backing off is slower than stepping in and only reaches just past a jab (`FIGHT_GAP_MAX`), and hanging back out of range for `STALL_TIME` gets the pair shoved back together by the linesman, so nobody can run out the clock. A clean hit leaves the one hit reeling until just after the thrower recovers (`HIT_EDGE`), so landing first wins the next exchange; only for `CHAIN_EDGE` hits in a row, after which the one taking them recovers first (no stun-locks). A blocked punch holds the blocker in their guard until just before the thrower recovers. Stamina is two layers: wind, refilled up to a ceiling that every punch thrown wears down (misses more, never below 40%), shown as a dark block on the HUD bar; low wind means slower, softer punches and a guard that leaks more. Grabs go past a guard, a punch beats a grab; tie-up presses count strength, balance and wind against the other's; the computer mashes at a human pace and grabs mostly when the other is covering up or it is winded. A winded computer fighter backs off to get its wind back and comes back in at its style's line or near its worn-down ceiling, whichever is lower (waiting for a line above the ceiling, both fighters used to hang back and run out the clock); it fights on if the other is just as gassed, only covers up within the other's reach (a guard costs wind), and the other closes at full speed while it's too far to throw. Wind comes back faster past the other's arm (`AI_REACH[2]` of it). Fights run up to 40 s. **Rocked:** clean damage builds a shock meter (heavy shots and low durability faster; it drains quickly, so it takes a burst); past `ROCK_AT` of full health (easier the more hurt they are), or an uppercut on the chin under half health, the fighter is rocked: the clinch breaks and they're knocked apart, they wobble on the `dizzy_idle` loop, take 30% more, punch 25% softer and slower and pull weaker in a tie-up, and once under 35% health and a second into it a heavy clean shot drops them. Recovery fills slowly standing in, 3.5x covering up, 2x backed off, 2.5x tying them up; clean hits knock it back. The computer covers up high when rocked and goes for the finish when the other is. HUD: a banner and "ROCKED — COVER UP n%". The clinch uppercut is the right-hand uppercut half of `elbow_uppercut_combo` (1.0–1.75 s). Mixamo's `uppercut` is left-handed and, even mirrored (`uppercut_mirrored`, `MIRRORED` in tools/build_characters.gd), spins the hips about 95° (to about 130° off square), which at clinch range turned the thrower side-on with the punch swinging across the body; the clinch hook (`punching`) also plays without the stance turn (`yaw` 0).
- **Feel (as built):** full-body Mixamo clips (legs and hips move; the pelvis is held over its spot so clips that step don't lunge through the other fighter), fists closed by the rig (`SkaterRig.fist`), and at contact the punching hand is pulled onto the other's face, chin or ribs, or onto their raised guard, by per-arm reach IK (`SkaterRig.reach_w` / `reach_world`); grips put the lead hand on the other's jersey the same way. The pair glides along a slowly circling axis: lunges, knockback on clean shots, the pull of a grip. Heavy shots get a short hitstop and camera shake. Every clean blow staggers the one hit for a moment.
- **HUD** (`FightHud`, in the menu style like the match's TV graphics, on the 1600 x 900 design canvas): a slim header across the top, each fighter's dark strip mirrored either side of a small steel clock: a team-color stripe, the crest, name and style (in its color), one health bar and two hairlines under it, balance (yellow) and stamina (blue), no labels. They drain toward the outside, with a white chunk for damage just taken and the stamina tank worn away for the rest of the fight shaded in; the strip of the one hit jolts. Under a strip, a tab only for what the human has to act on (HOLDING, HELD — BREAK FREE, ROCKED; winded, wobbly and guards show in the meters and the fighter) and, for a human only, short coaching call-outs. Banners wipe in across the middle ("#2 HAYWOOD GOT ROCKED!") and quick calls show in a navy tab, as in a match. At the bottom, one strip with the controls that matter now on the human's own buttons (the clinch set while holding, the struggle while held), softened after the first seconds. `KH_FIGHT_LOG=1` prints each result. `-- fightdebug` marks every contact (red: where the clip alone put the fist, before the reach IK; green: where the punch lands) and prints a `[reach]` line: the gap, split into along the line (+ past, − short), up and sideways, and the target's distance from the shoulder in arm lengths (over 1: the arm can't get there); `tools/reach_report.py <logs>` sums them up. `-- fightlog` (on with fightdebug too) writes every punch's call to `user://fight_calls.log` and the console: time, YOU / cpu, style, move, how far it had to go against its reach, the call on the way in and at contact, and why it missed (out of reach, slipped) or which guard took it. Measure in a window (headless runs agree, but check). First measurement (302 contacts, 2026-11-11): the IK moved the fist about 30 cm on average and over 15 cm on 82% of clean hits, mostly short, low and off to the side; crosses and hooks were worst (40–50 cm), jabs best (20 cm); 40% of hits landed beyond a fully stretched arm, most of all the boxer's cross and hook from its longer AI range and the shorter (female) bodies. **Hit feedback:** a clean hit flashes a starburst where it lands, jolts the hit fighter's bars, adds a short hitstop (longer on heavies) and, for a human who took it, flashes the screen edges red; head shots spray spit, and under half health blood too (more the more hurt), leaving spots on the ice until the fight ends. Blood is an option (VIDEO > BLOOD, on by default); off leaves the spit.
- **The fight ends** when: one fighter is **knocked down** (health or balance at 0), both are out of wind for 4 s, or the time limit is hit (40 s), and the linesmen break it up.
- **The winner** is whoever knocked the other down, or did more damage if no one did (within 8% of each other is a draw).
- Short, readable animations: windups are clearly visible, and nothing sends anyone flying. Helmets come off as they square up; afterwards both skate to the box (§10.5 M6). A short **winner's skate / taunt** (a few seconds, skippable, winner only) is planned *(not built yet)*.

### 5.3 Consequences

| Result | Effect |
|---|---|
| Both fighters | Offsetting 5:00 majors (if penalties are on): no power play. |
| Winner's team | **Momentum** for 75 s of game time: +5% top speed, +10% hit power. The winner's bench cheers; the crowd cheers a home win and boos an away one. *(Shot accuracy in the boost and a lasting crowd boost: not built yet.)* |
| Loser | Small chance of injury (if injuries are on, §4.8): helped to the bench instead of the box, out for the game. |
| Both | Tension meter drops. |

No ejections. If penalties are off, fighters sit out 60 s instead. Knockout Mode skips all of this (no box, faceoff or momentum).

---

## 6. AI

- **Team AI:** a simple tactical role system. As built (`TeamAI.Role`), every tick each AI skater gets a role: with the puck, carrier, receiver, slot support, point support (two) or net-front support; without it, chase a loose puck, pressure the carrier, cover the slot or mark a man; plus heading off for a change. Each role is a target position + behavior. *(Set plays, forecheck F1/F2/F3, breakouts, cycles and power play / penalty kill boxes: not built yet.)*
- **Skater decisions:** utility scoring for pass / shoot / skate / deke / dump in, weighted by stats and personality (aggression, selfishness). AI skaters steer around the nets (§10.5).
- **Difficulty** scales how often the AI thinks (reaction time), one-timer and check choices, and the computer's faceoff timing. It does not boost stats. *(Pass/shot accuracy and goalie positioning by difficulty: not built yet; tuning is in §12.)*
- **Catch-up AI** (rubber-banding): an optional toggle that's off by default. To be tested in playtesting (§12). As built, it's deliberately subtle and helps whichever team is down two or more, human or computer: at three or more down, +3% top speed, 15% tighter and 3% harder shots and AI decisions as if 0.1 more difficulty; down two, 60% of that.

---

## 7. Camera and presentation

### 7.1 Camera

- **Vertical (end-to-end) broadcast camera** by default, high angle, follows the puck with a small lead in the direction it's moving and soft bounds at the end boards. Four play angles in all (Broadcast, Close, Side, High), picked on the rules screen or in the pause menu; Side is the horizontal camera (§10.5 M6).
- Cuts to its own shots for the matchup intro, period openers, faceoffs, fights, penalty calls, goal celebrations and replays.
- Shake and slow motion on big hits (short), longer for a glass break. *(A setting to turn them off: not built yet.)*

### 7.2 Presentation features

- **TV graphics:** banners ("BIG HIT!", "GOAL!", "POWER PLAY", fight results), the scorebug, goal and penalty lower thirds (§10.5 M6). Also "GLASS SHATTERED!", "EMPTY-NET GOAL!", the INJURY lower third and the EMPTY NET tab.
- **Replays:** a 14 s ring buffer of every player's pose and the puck. Goals and knockouts replay right away; big hits are saved for the next stoppage or the end of the period. Skippable.
- **Three stars** after the match, chosen by goals, assists, saves, hits and fight wins (`BoxScore.rating`).
- **Intermission:** a period stats screen with hot and cold players. *(The Zamboni scene: not built yet; waits for a model.)*
- **Crowd** that reacts to goals, hits, fights and near misses, chants for the home team, and stands and cheers in the stands. More crowd energy for the home team.
- **Announcers:** two voices, play-by-play and color, with duets and banter (§10.5 M5 Sound; open work in §14).
- **Arena atmosphere:** a goal horn and organ (an upbeat piece through stoppages, the charge as a home attack builds). *(A goal light: not built yet.)*
- **Music:** a rock / hip-hop playlist in `assets/sound/music/` plays across the menus (`Sfx.play_music`); the organ and crowd carry the games. *(Synth/retro tracks and arena music during stoppages: not yet.)*

---

## 8. Teams and players

### 8.1 League

- The **KHL** (Knockout Hockey League): **39 teams** in 3 conferences of 13, **East, Central and West** (`Teams.LIST`, listed in §10.5 M5 Teams). The four launch teams (Whalers, Geese, Quahogs, Lobsters) have the designer's colors and crowd chants; every team has a logo and a roster. *(Divisions: undecided, §12.)*
- Each team: name, city, abbreviation, conference, colors and full uniform palette, jersey design, home and road uniforms, logo, announcer intro, roster, lines. *(A home arena per team: waits for the arena editor; everyone plays in the same building, dressed in the home team's colors.)*
- League logos (main, championship belt, monogram) are drawn but not in the game yet *(not built yet)*.

### 8.2 Roster

- Planned 5v5 roster: 12 forwards + 6 defense + 2 goalies (20 players, 4 forward lines and 3 D-pairs). **As built**, each team's roster sheet has 15: 8 forwards (3 C, 3 LW, 2 RW), 5 defense, 2 goalies, split in order into forward lines of 3 and D-pairs (`Lineup.build_groups`), so the third line and third pair come up one short (§10.5 M3 Rosters).
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

As built they're the roster sheet's play styles (`playstyle`; `Rosters.STYLE` nudges the ratings):

- **Forwards:** Sniper, Playmaker, Power Forward, Speedster, Grinder, Two-Way
- **Defense:** Offensive D, Puck-Moving D, Stay-at-Home D, Shutdown D, Enforcer D
- **Goalies:** Butterfly, Hybrid, Stand-Up, Scrambler

Separately, every skater has a **fighting style** (boxer, brawler, grinder) picked from their ratings (§5.2).

### 8.5 Appearance

Body: male/female base, height, weight (build), skin tone, eye color, hair style/color, facial hair. Gear: helmet or goalie mask model, visor, stick hand (L/R), stick graphics, blade tape, jersey number. Name (or a short nickname) on the back. Roster players' skin tone and helmet are seeded from their name; created players pick everything (§9.2). *(Face presets: not built yet.)*

**Body size (built, `BodyBuild`, scripts/actors/body_build.gd):** each player's height and weight (the roster sheet's `height` / `weight_lbs`, `Skater.height_m` / `weight_kg`) set their size. Height scales the whole body evenly, skates and gear included, so nobody looks stretched: the roster average for the body type (male 6'2" / 92.9 kg, female 5'8" / 71.6 kg) renders at the model's own size, so the rosters run about ±6%. Weight sets the build: width follows the square root of weight / height against the average, and what the height scale hasn't already covered goes to a "build" blend shape on the skin, jersey and pants (rosters about ±0.15, held to −0.2..+0.35). The shape moves each vertex straight out from the axis of the bone it rides on, by a share per bone (`BodyBuild.GIRTH`: most at the belly and hips, some on the upper arms and thighs, none on the head, hands and feet), so every layer moves by the same rule and the jersey stays over the skin; the pants pads fill out to match (`BodyBuild.point`). Made once per body mesh; the skin's comes with the face's jaw and smile shapes (`FaceRig`), and `MeshLod` keeps blend shapes on its simplified levels. Goalies get it too. Check: `CharacterViewer.tscn -- lineup=1 view=lineup pose=hips sizes=<in>x<lb>,...`.

---

## 9. Editors

### 9.1 Team editor *(not built yet)*

- Team identity: name, city, abbreviation, conference.
- Colors: primary, secondary, accent, plus helmet, pants and gloves colors.
- Jerseys: home and away, built from a template (stripe patterns, collar, shoulder yokes) plus team colors. The number/name font comes from presets.
- Logo: picked from a preset library (custom logo builder later).
- Home arena: one of the arenas.
- Roster: add/edit/remove players, build lines.

Main menu **CUSTOMIZE** opens the editors: Create Player, Create Team, Create Arena, Create Uniform and Edit Roster. Only Create Player is built; the rest show as "coming soon".

### 9.2 Character (player) editor

**Built (`scenes/ui/CreatePlayer.tscn`, `create_player.gd`, data in `CustomPlayers`):** tabs PLAYER (editing: new or a saved player, first / last name, nickname, number, position C/LW/RW/D/G, shoots / catches, play style), SKILLS (skill mode, the ratings, reset), LOOK (gender, height 5'0"–7'0", weight 120–290 lb in 5s (defaults 6'2" / 205 for men, 5'8" / 160 for women; a gender change moves an untouched default to the other's), skin tone, eye color, hair style, hair color, facial hair for men) and GEAR (helmet or mask model, visor, stick, blade tape, a preview jersey for this screen only). The player stands on the ice on the right, rebuilt as settings change, with the camera on what the row changes (face, back, blade); mouse drag turns around them. Names: the on-screen keyboard on a pad, typing into the row from a keyboard.

- **Skill modes:** *Realistic with Points*: every rating starts at 60 with a pool to spend (90 for skaters, enough for all six at 75, the roster sheet's average; 130 for goalies); a point costs 1 below 80, 2 below 90, 3 above; down to 40 gives points back. *Free*: any rating 1 to 99. Ratings are on the roster sheet's scale (`CustomPlayers.as_row` feeds `Rosters.stats`).
- **Sticks** (`Skater.stick_style`, `stick.gdshader`): Plain Wood, Plain Black, Black on White, White on Black, Home on Away, Away on Home ("X on Y": X graphics on a Y stick; home / away are the club's home and road jersey colors, `Skater.club_colors`). **Blade tape** (`Skater.stick_tape`): White, Black, Team Color (home jersey) or No Tape, wrapped round the middle of the blade with the heel and toe bare; the knob on the butt end stays taped.
- **Free Agency:** saved players (`user://custom_players.json`) start as free agents (`team` = `CustomPlayers.FREE_AGENT`). **Edit Roster** (Customize, to come) signs them to teams and moves players between teams.

### 9.3 Arena editor *(not built yet)*

- Base venue: **Indoor Arena** or **Outdoor Rink** (an outdoor venue: snow, open sky, day/night lighting; not built yet either).
- Center ice logo (from presets or the home team's logo).
- Ice paint colors (blue lines, red line, crease, faceoff circles).
- Seat color(s).
- Lighting preset (standard, dramatic, warm, cool, outdoor day/dusk/night).
- Goal horn sound (preset list).
- Music playlist (choose from tracks).
- The rink is always regulation size for gameplay; arenas only change visuals and audio.

All editor output is saved as user data files (§10.3). Planned: the built-in teams and arenas move to the same format (today the teams are in code, `Teams.LIST`, and the rosters in the CSV).

---

## 10. Technical design

### 10.1 Engine and setup

- **Godot 4.7.2**, GDScript, Forward+ renderer, Jolt physics as the engine's physics server (skaters and puck use custom movement; nothing uses rigid bodies yet).
- Physics tick at **120 Hz** for puck precision, with physics interpolation.
- Target: 60+ FPS on the designer's PC (RTX 2070 Super) on Quality graphics; the Performance option is for laptops and integrated graphics (§10.5 M8).
- 1600 × 900 design canvas for all 2D (menus and HUDs scale from it).

### 10.2 Project structure (as built)

```
res://
  assets/          models, clips, textures, images (logos, ads), fonts, sound, music
  data/            knockout_hockey_rosters.csv (every team's roster), hockey_announcer_lines.csv (scripts)
  docs/            this document, ANNOUNCER_TODO.md (generated), logo prompts, handoff notes
  scenes/
    match/         Match.tscn, Rink.tscn, Puck.tscn, Net.tscn, Practice.tscn, crowd/ice shaders
    actors/        Skater.tscn, Goalie.tscn, skin/uniform/face/stick shaders
    ui/            MainMenu, TeamSelect, RulesSelect, Options, CreatePlayer, Credits
    tests/         self-tests, the soak, character/arena viewers
  scripts/
    core/          autoloads (InputRouter, GameSettings, Sfx, FpsCounter); Teams, Rosters,
                   CustomPlayers, AnnouncerLines, RinkSpec, MeshLod, MeshUtil
    match/         MatchDirector, MatchRules, Lineup, TeamControl, KnockoutMode, Practice,
                   Rink, Arena, Puck, Net, BroadcastCamera, Replay, Cutscene, MatchHud,
                   Intermission, BoxScore, MatchAudio, PauseMenu
    actors/        Skater, Goalie, Referee, PlayerStats, BodyBuild, SkaterRig, *Visual, FaceRig;
                   brains/ (Human, Script, Celebrate, HoldSpot, Ref)
    ai/            TeamAI, AIBrain
    fight/         Fight, FightHud
    ui/            menus, MenuStyle, MenuInput, PadKeyboard
    editors/       (empty: the team and arena editors go here)
  tools/           build steps (characters, gear, logos, digits, letters, title, ads), checks
                   (announcer, roster), sound cutting (cut_sounds.py), blender/ model scripts
user://
  settings.cfg            rules and options
  custom_players.json     created players
  fight_calls.log         `-- fightlog` output
```

### 10.3 Data

- **As built:** the teams are a table in code (`Teams.LIST`); every roster is a row in `data/knockout_hockey_rosters.csv` (read by `Rosters`); created players are JSON in `user://custom_players.json` (`CustomPlayers`); settings are a ConfigFile in `user://settings.cfg`.
- **Planned:** JSON files with a `schema_version` field for teams, players and arenas, built-in content in `res://data/` and user content in `user://` overriding built-in content with the same ID; players referenced by ID from rosters, so a player is defined once. This comes with the team editor (M7).
- Seasons and management will add data files (schedule, standings, contracts) without changing the existing ones.

### 10.4 Key architecture

- **MatchDirector:** owns the match phase (`Phase`: INTRO → PREGAME → FACEOFF → LIVE → STOPPAGE → PERIOD_END → SHOOTOUT → FINAL, plus FIGHT), the clock, score, lineups, tension and momentum, and hands Knockout Mode to `KnockoutMode`.
- **MatchRules:** offside, icing and delayed-penalty logic, depending on the toggles; the director turns skater fouls into calls.
- **Skater:** `CharacterBody3D`. Inputs come from a `Brain` (`HumanBrain` for a device, `AIBrain`, or scripted brains for cutscenes, celebrations and the referee). Swapping the brain is how switching and human goalie control work.
- **Events:** signals on the skaters (`pass_released`, `shot_released`, `hit_landed`, `poke_succeeded`, fouls) and the director (`goal`, `whistle_blown`, `penalty_called`, `faceoff_won`, `phase_changed`...) feed the rules, HUD, audio (`MatchAudio`), box score and tension meter.
- **Replay:** a `ReplayTap` at the end of every skeleton records its finished pose about 30 times a second into a 14 s ring; `Replay` records the puck.
- **Fights:** `Fight` runs on the same ice while the director sits in `Phase.FIGHT`; the outcome goes back to the director (box, momentum, faceoff), or to `KnockoutMode`.

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
  - More tests: `M2SelfTest.tscn` (goalie, checks, pokes) `MatchSoak.tscn` (full AI-vs-AI games, `-- games=3 period=45`) and `RulesExtrasCheck.tscn` (pulling the goalie by hand and the computer's late pull, injuries, glass breaks, catch-up AI, referee strictness).
- **M3 additions:**
  - **Entry point:** the main scene is now `scenes/ui/MainMenu.tscn`; an exhibition goes through `TeamSelect.tscn` then `RulesSelect.tscn`, which write `GameSettings.config` / `GameSettings.humans`, which `MatchDirector` reads (tests set `use_game_settings = false`).
  - **Knockout Mode** (Game Modes): `GameSettings.mode = "knockout"`; TeamSelect goes straight to the match (no rules screen) and `MatchDirector` hands over to `KnockoutMode` (scripts/match/knockout_mode.gd) instead of starting a game. Five random skaters per team are drawn and paired off; each pair fights at center ice in the normal `Fight`, ringed by the other eight (the rest sit on the benches). Per bout: KO 3 points, win on points 2, draw 1 each. Best total after five wins; level means sudden-death bouts between random roster players until one is won. No penalties, faceoffs or momentum. `-- knockout` starts it from the match scene; `scenes/tests/KnockoutSelfTest.tscn` runs a full computer-vs-computer card.
  - **Rosters:** teams in the roster sheet (`data/knockout_hockey_rosters.csv`, all 39 teams) dress their real players, 8 F + 5 D + 2 G, through `scripts/core/rosters.gd` (`Rosters`): forwards in lines best-first, each line a C/LW/RW where possible; defense in pairs best-first; the higher-rated goalie starts. Ratings map SKA → speed/acceleration/agility, (SKA+PHY)/2 → endurance, SHT → shot power/accuracy, PAS → passing, HND → puck handling, PHY → checking/strength/durability, DEF → defense, goalie REF/POS/GLV/BLK/RBD one for one (pads = (REF+POS)/2); fighting and aggression come from PHY plus play style (Enforcer D highest, then Grinder and Power Forward). Play styles add small nudges (`Rosters.STYLE`). The sheet's ratings center around 75 (goalies 83), so they're shifted to center on 57, the generated players' level, keeping the gaps between players one for one. Name, number, gender (body), hand, position and play style come from the sheet; skin tone and helmet are seeded from the player's name, so they're the same every game. The CSV is imported with the `keep` importer (not as a translation). `tools/roster_check.gd` prints how the game reads each roster. Teams without rows get generated players: 12 F + 6 D + 2 G. The `Lineup` class owns the forward/defense groups, `on_ice` (shared by reference with the AI and the skaters' teammate lists, so it's only changed in place), the bench and the penalty box. Benched skaters are hidden, with processing and physics off.
  - **Energy (shift fatigue):** drains at roughly 1/48 per second on the ice and recovers on the bench. Below 1, it scales speed, acceleration and shot power down to 0.82×.
  - **Line changes:** tired groups change at faceoffs, or on the fly via the bench gate on the −X boards when the puck isn't in that team's defensive zone.
  - **Rules (`MatchRules`):** delayed offside (cleared when the puck leaves the zone or everyone tags up), no-touch icing (canceled by any touch, and a shorthanded team can't ice it), and delayed penalties (the whistle goes when the offending team touches the puck).
  - **Fouls:** these come from skater events (tripping, interference, boarding), and the director rolls whether the ref calls them. Power-play goals end the earliest minor. In 3v3, a penalty gives the other team an extra skater (4-on-3).
  - **Overtime modes:** `off`, `sudden_death`, `shootout`, and `sd_so`. In the shootout, every attempt goes at the −Z net, it runs best-of-N then sudden death, and the winner gets +1 goal.
  - **Humans:** each human gets a `HumanBrain(kind: ANY/KB1/KB2/PAD)` with its own edge detection, and `TeamControl` maps humans to skaters one-to-one. Rings and P1–P4 tags are colored per player.
- **M5 additions (characters and sound; done before M4 so fights are built on real bodies):**
  - **Build step:** `godot --headless --path . -s res://tools/build_characters.gd` (add `-- body=<name>` for one body) builds every body listed in `BODIES`: `male` (Hombre_Base, Mixamo-rigged but on its original CMU skeleton), `female` (Mujer_Base, Mixamo skeleton, A-pose) and `ybot` (test body). Each body gets canonical prefix-free bone names (`Hips`, `Spine2`, `LeftUpLeg`…; the CMU spine maps LowerBack/Spine/Spine1 → Spine/Spine1/Spine2), is rescaled to its `height` with feet on y = 0, has its hands cut away (gloves and fists always cover them), and is saved as `assets/characters/body_<name>.scn`. Every clip in `assets/animations/` (searched recursively; clips are grouped by use into `fight/`, `hits/`, `bench/`, `reactions/`, `goalie/`, `shooting/` and `menu/`, and file names must stay unique across folders) is retargeted onto each body (through a T-pose reference, so A-pose bodies match) into `anims_<name>.res`. Clip names are the file names in snake_case (`Boxing (1).fbx` → `boxing_1`). Hip drift is removed. Re-run after adding models or clips.
  - **Body types:** `Skater.body_type` = `"male"`, `"female"` or `"ybot"`; it's purely visual, and stats are unaffected. Generated rosters are mixed (`MatchDirector.FEMALE_SHARE`); sheet rosters use each player's gender.
  - **Fighting (M4):** `MatchDirector` builds each team's tension from hits taken (big hit +0.7, +0.2 into the boards, check +0.22, bump +0.06; decays 0.0015/s). At `FIGHT_TENSION`, at least `FIGHT_GAP` (200 s of play) after the last fight, the team's toughest skater on the ice (fighting + aggression) squares off with the hitter (or the hitter's toughest teammate). A human on that team gets the prompt ("Drop the gloves? A / B", 3 s, play stopped); a computer team decides from fighting and aggression; an aggressive hitter (70+) with tension past `FORCED_TENSION` starts it without asking. `Fight` (scripts/fight/) runs the mini-game: sticks and gloves drop on the ice (bare hands via the `gloves_worn` instance uniform), the others form a ring open toward a low side camera, and each fighter has health (fighting + durability), balance (strength) and stamina (endurance). Moves (`Fight.MOVES`, timed to the contact frame of each Mixamo clip): jab (`lead_jab`), cross (`cross_punch`), hook (`hook`, visible windup, dodged by leaning); with L1 the body versions (body jab = `lead_jab` with `SkaterRig.bow` bending the thrower forward, body cross `boxing_1`, body hook `boxing`), which drain stamina; grab (holds the jersey up to 4.5 s or until mashed loose: +15% damage, drains the other's balance, swaps in body shot `boxing_1` / right hook `punching` / uppercut `elbow_uppercut_combo`); block high or low (R1, +L1; a held frame of `center_block` / `body_block` with the breathing idle; 25% damage, only against punches at that level). Hit reactions per punch in `Fight.HIT_CLIPS` (the hooks use `big_side_hit` until a proper side head-snap clip exists). Health or balance at 0 = knocked down, with a finish picked by the blow that did it (`Fight.FINISH_BY`: big head shots mostly `stunned` straight back or `knocked_out`, other head shots `knocked_out` / `dying2`, body shots `dying` / `dying2`, a grip that drained their balance `dying` / `knocked_out`; each starts where its fall begins, and the finish and KO replay hold until the body is down; `-- kofinish=<clip>` forces one); otherwise a decision at 40 s or when both are out of gas for 4 s (close = a draw). Both fighters get offsetting 5:00 majors (`Lineup.offsetting`: no power play, the team plays full strength), or sit 60 s if penalties are off; the winner's team gets 75 s of momentum (+5% speed, +10% hit power); the crowd and announcer react; play resumes with a faceoff near the fight. Computer fighters dodge or block visible haymakers by skill, work grabs into uppercuts and mix punches by aggression and style (`Fight.AI_STYLE`). Setup has a Fighting On/Off setting. `-- fight` (or `fight=prompt`) starts one at once for testing; `scenes/tests/FightSelfTest.tscn` checks the whole flow. Punch sounds are split from `punch*.mp3` into single hits by `tools/cut_sounds.py` (with male / female grunts by who takes the punch).
  - **Pause menu:** Esc / Start opens `PauseMenu` (the game tree pauses): Resume, Controls (every action for pad and both keyboards), Restart game, Quit to menu; B / Esc / Start backs out. Not over the matchup intro or a stats screen, where those buttons continue. `-- pausemenu` (or `pausemenu=controls`) opens it at once for layout checks.
  - **Matchup intro:** games with the HUD on open on the matchup screen (`Phase.INTRO`): a camera at center ice, each team's logo on a board (Sprite3D) with one of its players standing in front of it in uniform (home on the left), "VS" between, the HUD hidden, everyone else out of sight. It lasts as long as the announcer's intro (at least `INTRO_MIN`, at most `INTRO_MAX`); Enter / A skips it. Then the broadcast camera takes over for the opening faceoff. `-- nointro` skips it; the soak (no HUD) never shows it.
  - **Intermission:** at the end of each period (after the horn and banner) `Intermission` shows both teams in their colors, the score, goals by period, shots on goal, saves, hits, big hits, faceoffs won, penalties and power-play goals; the next period starts when someone presses Enter / Space or A / Start (presses in the first second are ignored). The same screen follows the final horn and returns to the setup menu. AI-only games continue by themselves. The organ plays through the break. `-- statscreen` (or `statscreen=final`) opens it at once for layout checks.
  - **Teams:** `scripts/core/teams.gd` (`Teams.LIST`) holds the league's 39 teams in three conferences of thirteen (`Teams.CONFERENCES`; each team's `conference`, `Teams.in_conference()`). The four launch teams come first: New Bedford Whalers (red, white, black), Minnesota Geese (green, gold, black), Rhode Island Quahogs (blue, grey, yellow) and Maine Lobsters (white, maroon, green); the rest have palettes taken from their logos and no chants yet. East: Whalers, Quahogs, Lobsters, Burlington Lake Monsters, Adirondack Trailblazers, Mystic Mariners, New Hampshire Granite, Cape Cod Cranberries, New York Rats, Quebec Poutine. Central: Geese, Michigan Mitts, Wisconsin Curds, Lake Superior Gales, Manitoba Moose Jaws, Nashville Twang, Kentucky Moonshiners, Okefenokee Swamp Things, Florida Man, Texas Armadillos. West: Tacoma Geoducks, Roswell Grays, Anchorage Sourdoughs, Portland Lumberjacks, Monterey Otters, Hollywood Stuntmen, Mojave Gila Monsters, Boise Spuds, Seattle Seagulls, Yellowstone Geysers. Expansion teams (added 2026-11-11, at the end of the list so saved team indices hold): East: Carolina Sweet Tea, Philadelphia Jawns, Pine Barrens Campers; Central: Chicago Deep Dish, Mexico City Luchadores, North Dakote (one name, no city); West: Baja Chupacabras, Rocky Mountain Goats, Xochimilco Axolotls. The roster sheet's `display_name` is the name shown (`Rosters.display_name`); the Luchadores have ring names with no last name, so the whole ring name goes where the last name would. Team select steps through teams by conference (`Teams.menu_order`) and shows each team's conference as a colored badge on its name plate (`Teams.CONFERENCE_COLORS`). Every team has a 15-player roster in `data/knockout_hockey_rosters.csv` (its `conference` column agrees with the table; `tools/roster_check.gd` flags any mismatch). Abbreviations match the roster sheet. When the two jerseys are too alike (`Teams.CLASH`), the away team wears road whites with its main color as trim (`Teams.uniform_vs`). Each has a full uniform palette (jersey, trim, pants, gloves, helmet, skates, number face and outline); the four launch teams also have crowd chants. The setup screen picks home and away (`home_team` / `away_team` in `GameSettings`; `-- home=<i> away=<i>` on the command line); the HUD shows team names; the home crowd chants for its own team. Logos: every team's logo is its own image in `assets/images/` (`<team>.jfif`, one logo on a white or off-white background, redrawn in Gemini in a flat NHL-primary style); `tools/build_logos.gd` (`SHEETS`: one entry per image, with per-logo background cutoffs, `keep` for logos with small separate pieces and `recolor` to swap flat colors to the team's) flood-fills the background from the edges, drops stray specks and leaves a soft one-pixel edge, into `assets/characters/logo_<team>.png`. Two old four-logo sheets are kept only for the two spare logos. `tools/build_logo_sheet.gd` (needs a window) renders every logo to `docs/logo_sheet.png` to compare them. Each player wears the team crest on the jersey front as a `Decal` projected onto the chest (like the back number), and the home team's logo is painted into the ice at center (`Rink.set_center_logo`, 6.4 m wide, over the red line and under the blue circle). The team editor (M7) will replace the table.
  - **Skin and uniforms:** each vertex gets its body part (torso, arm, leg, hand, foot; the head and neck are bare skin) from its dominant bone, plus its position along that part (torso by height from the hips joint to the neck, limbs from shoulder/hip to wrist/ankle). `scenes/actors/uniform_regions.gdshaderinc` turns those into pants, jersey, socks, gloves and skates per pixel, with the stripes (`hem_band`, `sleeve_band`, `cuff_start`, `sock_band`) as clean anti-aliased bands. Stripe positions are shader uniforms, so a team's design can change them. The uniform is its own skinned layer (`Outfit_*` meshes): every covered triangle is copied, welded across UV seams, smoothed (`CLOTH_SMOOTH_PASSES`) so it drapes instead of showing muscles, and pushed out along the new normals by `cloth_thickness()` (bulkier over pads). It shares the body's bones, so it deforms with every clip. `scenes/actors/uniform.gdshader` colors it per team via `SkaterVisual.uniform_colors()`. Fabric detail is procedural, pinned to the cloth by each outfit vertex's rest-pose position and normal (baked into `CUSTOM0` / `CUSTOM1` by the build step, with the arms swung out to a T-pose by the skin weights, the origin at the base of the neck and the torso scaled to 0.6 m, so A-pose and T-pose bodies get the same pattern sizes and yoke). The chest, belly and hip bulk spheres wear the same uniform material with matching coordinates (`SkaterVisual._cloth_mesh`), so stripes and the yoke carry across them: jersey knit dimples, coarser mesh panels down the sides and under the sleeves, drape folds (rings around the sleeves, long folds down the body) and sewn seams at every stripe edge, cuff and shoulder; quilted, slightly glossy nylon breezers; vertical sock ribbing (around the leg by the rest normal's heading); leather grain on the hands. Height detail becomes per-pixel normals (screen-space bump, no tangents needed), and fine patterns fade with distance (`keep()`) so they don't shimmer. `detail` = 0 gives the old flat look. Each team has a jersey design (`Teams.DESIGN_OF` → `Teams.DESIGNS`): classic, double, triple, yoke, yoke_stripe, bold, pinstripe or hoops. A design sets how many stripes the hem, sleeve and sock bands split into, their positions, whether every other stripe uses the accent color (the team's number outline), and a shoulder yoke in the trim color (`yoke_r`: one smooth shape around the base of the neck, measured on the front/back silhouette so it's continuous across body, sleeves and the chest pad; everything above the neck line is yoke). Yoke designs carry the back number a little lower (`SkaterVisual.number_drop`). Road uniforms keep the home design. Stripe positions on the cloth layer are measured again on the smoothed cloth (smoothing slides vertices along the limbs), so stripe and yoke edges stay straight instead of stepping from one ring of triangles to the next; shoulder-bone vertices are measured along the upper arm. The skin textures come from the glTF versions of the bodies, whose texture coordinates are upside down relative to the Mixamo FBX exports, so the build flips V (`flip_v` in `BODIES`). The small eyeball mesh is kept as `Eyes` with the body's eye texture (`eye_tex` meta). The body itself uses `scenes/actors/skin.gdshader`: the MakeHuman skin texture divided by its average color and tinted to `Skater.skin_tone` (one of `SkaterVisual.SKIN_TONES`, seeded from the player's name for roster players and set in the player editor for created ones). It discards skin under worn clothing (the `wear` / `wear_skates` toggles), so a jersey can come off in a fight later. Shoulder/pants bulk and goalie pads are simple meshes attached to bones. Stripes are drawn only where a triangle belongs to a single body part, so part boundaries (armpits, shoulders) don't show slivers. The back number is a `Decal` attached to the chest bone, projecting the digits forward onto the jersey so they wrap with its curve and the pads beneath (`normal_fade` keeps them off side and front surfaces). Digits come from `assets/characters/digits.png`, rendered once by `tools/build_digits.gd` (needs a window) and tinted per team in `SkaterVisual.number_texture()`. Head, chest and hip gear is placed from mesh-based anchor boxes saved by the build step, so it fits any body shape; limb gear follows the joints.
  - **Equipment models:** `godot --headless --path . -s res://tools/build_gear.gd` turns `assets/equip/` models into plain meshes in `assets/characters/`. Source textures (real team and brand logos) are dropped, surfaces are split by role so the game paints them per team, and dense scans are welded and simplified (meshoptimizer, falling back to vertex clustering for noisy scans). Outputs: two goalie masks (`goalie_mask`, `goalie_mask_b`: shell, cage), and, copied over from the project's own Blender models (`tools/blender/`), two helmets (`helmet`: modern two-piece, `helmet_b`: classic one-piece; shell, trim, dark, visor, visor clips; `helmet_gear.py`, modeled on the male head from `tools/dump_heads.gd` and set on each body's crown, scaled by head width, so the Y chin strap sits under the chin; `Skater.visor` drops the visor surfaces), `stick` (shaft, tape: blade and butt-end knob; heel at the origin) and `goalie_stick` (body, grip, tape; same layout) (`stick_gear.py`), `skate` (boot, steel; `skate_gear.py`), `glove`, `glove_cuff` and `fist` (`hand_gear.py`; a right glove, mirrored for the left hand) and the goalie's pads, boots, thigh rises, blocker and catcher (`goalie_gear.py`). `Skater.gear_style` picks the helmet or mask (`SkaterVisual.HELMETS`, `GoalieVisual.MASKS`, each with its own fit). The stick model is posed every frame from the heel to the top of the shaft, with the blade flat along the ice in the stick's plane and its hook toward the forehand; the mesh skews slightly when the hands and blade don't match its lie. Goalies hold the goalie stick in the blocker hand with the blade across the crease toward the glove side; they wear the catcher on the left hand, pocket toward the shooter. `tools/preview_model.gd` renders any model from the front, side and top to check orientation.
  - **Posing:** `SkaterRig` (a `SkeletonModifier3D`) runs after the clip player and builds the body procedurally: the skating stride (two-bone leg IK to the ice; cadence from speed, amplitude from push), the forward lean, twists for windups and follow-through, and arms gripping the stick (two-bone IK). The top hand is placed from its own shoulder, down and well forward at belt height within ~80% of the arm's reach so the elbow stays bent, rocking with the stride. The bottom hand slides down the shaft toward the blade. Elbow poles flare out to the sides for an open stance. Skating hard without the puck (`SkaterRig.free_arm`), the bottom hand lets go and swings forward and across as the same-side leg drives back. Goalies use free hand targets for the glove and blocker. Each region (legs, spine, arms) blends between the clip and the procedural pose, so clips can own just the upper body.
  - **Clips in use:** knockdowns (`knocked_down`, `falling_down`), stumbles (`big_side_hit`, `hit_to_body`), goal celebrations (`fist_pump`, `cheering`, `rallying`; upper body only, so legs keep gliding) and the beaten goalie's `angry_gesture`. Fight clips: see §5.2 and the M4 notes.
  - **Sound:** recordings in `assets/sound/` are cut into game clips by `python tools/cut_sounds.py` (ffmpeg; trims, fades, peak-normalizes, makes the crowd bed loop seamlessly) into `assets/sound/cut/<name>_<n>.ogg`. The `Sfx` autoload loads those (a random variant per play) in place of its synthesized stand-ins; whatever has no recording yet (stick clicks, posts, glass, the net, pads, glove saves, whistle, "ooh") is still synthesized. Recorded (ElevenLabs): slap and wrist shots, board and open-ice hits, hockey stops, strides, the goal horn, the crowd bed, cheers, boos, a rising crowd, a disappointed groan, an outraged crowd, "De-fense!", four team chants, two organ pieces and the announcer. `MatchAudio` hooks match events to it. The crowd belongs to the home team (team 0): horn and big cheer for home goals, a groan for goals against; cheers for home big hits and glove saves; boos for home penalties and cheers for the visitors'; "De-fense!" when the home team is pinned in its zone; a rising crowd as a home attack builds (faded if it fizzles); the home team's chant every minute or two; a disappointed groan when a home shot is saved by the visitors, rings a post or misses wide; and boos for the visitors' big hits on home players. The arena organ (its own channel) plays an upbeat piece through stoppages, starting at a random point and fading at the drop, and sounds the charge as a home attack builds. **Announcer:** play-by-play lines live in `assets/sound/announcer/` as `<line><n>.mp3` or `<line>_<nn>.mp3` (trailing digits = another take of the same line; just drop new files in). `AnnouncerLines` (scripts/core/announcer_lines.gd) is the list of every line by category, when it plays, and the other file names that count as its takes (the names in `data/hockey_announcer_lines.csv`, e.g. `hit_01` joins `bighit`, `period_end_01` joins `periodend`). `tools/announcer_check.gd` (`-- md=docs/ANNOUNCER_TODO.md`) reports takes per line against the target of 3 with the CSV's scripts for each. Added since: second/third period, overtime, shootout, final minute, final horn, faceoff win/loss, pass to the point, dump-ins, zone entries, behind the net, along the boards, setting up, cycling, wrist and point shots, misses, blocks, rebounds, pad/glove saves, top-shelf and calm goals, goal follow-ups (tie, lead, insurance, hat trick, power play, short-handed, comeback, reactions), hits into the boards, penalty killed, whistles, hot streaks, close games and blowouts. With `KH_AUDIO_LOG` set, lines that would have played but have no recording print as `(not recorded)`. **Two voices:** Steve Sheldon (play-by-play, calm and British, `announcer/pbp/`) calls the play; Bobby Niedemyer (color, loud, `announcer/color/`, plus the original recordings in `announcer/`) reacts after big saves, big hits, goals, the third period's call and the final horn, and fills quiet spells. One talks at a time. Each line in `AnnouncerLines` names the voice that records its new takes, but every voice's takes of a line share one pool, so Bobby's original play-by-play takes keep playing alongside Steve's. **Duets** (both in one ElevenLabs dialogue clip) go in `announcer/both/`: a duet can be a take of any line (`both/crowdreactgood_01.mp3` the crowd remark), and the banter lines are duets only (quiet spells, intermissions, after penalties, fights, goals, big hits and the final horn, blowouts and close games), each falling back to the solo line when not recorded. `Sfx.announce` plays one line at a time (a line only cuts off a lower-priority one, takes don't repeat back to back), and `MatchAudio._say` gives each line a chance and a cooldown so the commentary stays occasional: faceoff, pass, shot, fullslapshot (hard slap shots), save, bigsave (glove saves and saves right after a breakaway), bighit, pokecheck, breakaway (a carrier racing at the net with no defender between them and it), penalty / trippingcall / bigpenalty (boarding), then powerplay, and goal once goal lines exist. Offsides and icing whistles get their own calls; each period start says `period<N>` if that file exists (period2, period3: the number is part of the line, so these are looked up by exact file name), else `newperiod`, after the `periodend` call finishes; `idle` chatter fills long quiet spells. Intros: `assets/sound/intro/intro_<call>.mp3` ("Tonight: a matchup between the <team> and the <team>.") are split by `tools/cut_sounds.py` at the quietest moment between the halves into `intro_home_<call>` and `intro_away_<call>`, and the matchup screen plays the home team's opening then the away team's close (`Sfx.announce_chain`; Teams `call` names the clips). As the screen closes, Steve and Bobby welcome everyone in a duet (`intro_duet`, files `both/doubleintro*.mp3`) every game, in place of the first period's call; Steve's solo `intro` plays there only if no duet is recorded. More lines: goal, post, deke (when the carrier dekes), check, onetimer, checking ("they're really fighting for it!": possession flips between the teams three times in 5 s), downice ("heading down the ice": a carrier crossing center toward the other net with speed), turnover (the puck straight from one team's carrier to the other's), defenderup (a defenseman carrying into the offensive zone), centerice (the faceoff after a goal), big hits mixing bighit / flattened / gottahurt (+ bighitenforcer from defensemen and heavy checkers), and crowdreactgood / crowdreactbad when the home crowd has reacted the same way three times in 75 s. `fighting` plays as a fight starts and `banter_fight` after it; `glass_break` (Bobby, with a goal-sized crowd roar), `injury`, `goalie_pulled` and the `goal_emptynet` follow-up are hooked up but not recorded yet; there are no calls during a fight yet, and Knockout Mode has no lines of its own (§14). Set the `KH_AUDIO_LOG` environment variable to print every announcer line and crowd reaction as it fires. Crowd reactions play one at a time on their own channel (`Sfx.crowd_react`, by priority: goal > reaction > ambient).
  - **Goalies off the crease (`GoalieVisual`):** on a scripted walk (the period-opener walkout, bench trips) or skating well out of the crease, the goalie blends from the ready crouch to a travel pose: upright, a long relaxed stride at the skaters' cadence, the torso counter-rotating and rocking over the pushing leg, the glove swinging with the stride and the stick carried in the blocker hand with its blade on the ice. In the crease the ready stance breathes. The face behind the mask is alive too: hair at the hairline (the flattened under-helmet cut) and facial hair, eyes on the puck with a focused expression in the crease, and looking where it skates (now and then a word or a smirk) when traveling.
  - **Close-up check:** `scenes/tests/CharacterViewer.tscn -- shot=<png> view=front|side|back|quarter|top focus=<0-6> style=<gear style> save=glove|blocker|butterfly`; `gwalk=1` has the goalie skate a loop at walkout pace (`focus=6` follows it).
- **M6 additions:**
  - **Player ring meters:** the ring under each human-controlled skater is two meters (`scenes/actors/player_ring.gdshader`, set in `SkaterVisual._update_human_tag`). The wide outer arc is sprint (stamina), going from green through yellow to red; the thin blue inner arc is legs (shift energy). Both start at the top of the screen and drain counterclockwise back toward it, over a dark track tinted with the player's color. While sprint is locked out (used up, back at 25%), the sprint track pulses red. While a slap shot is held (past the wrist-shot window), a dark well opens inside the legs ring and fills orange from the center out as the shot charges (`charge`). The floating stamina bar, the floating slap-shot bar and the corner text's legs % are gone.
  - **TV graphics (`MatchHud`):** drawn in the menu style (`MenuStyle`: the heavy slanted font, red / navy / ink, slanted bars; shared helpers `team_color`, `team_logo`, `draw_slant`, `draw_bold`, `player_name`) on the 1600 × 900 design canvas. The scorebug sits top left: away then home, each a plate in the team's color with crest and abbreviation, the score on ink, shots on goal underneath (the shootout's attempts as dots), then period and clock on brushed steel. A tab under the clock shows the power play in the team's color with the time left (or "5 ON 3"), or a delayed penalty or offside in red. Banners are slanted bars that wipe in across the middle, in a team's color with its crest when it's that team's moment (goals, big hits, the final). Lower thirds: the goal card (scorer, assists) and the penalty card (offender, foul, minutes). Flashes are a small navy tab. Hints sit bottom left only when they matter: faceoff timing, goalie with the puck, and the pause button during stoppages; they hide while a lower third is up. The HUD runs on the wall clock (each gap clamped to 0.5 s), so slow motion doesn't drag it and a pause doesn't eat a banner. `-- hudtest` fires a goal banner and card, a big-hit banner and flash, and a penalty card, for layout checks.
  - **Box score (`BoxScore`, `MatchDirector.box`):** per-player goals, assists (the scorer's teammates who touched the puck before them in the same possession, up to two), shots, hits, big hits, +/- (not on power-play goals), penalty minutes, fights and fight wins; goalies' saves and goals against. `rating()` folds a line into a simple game score; `period_start()` snapshots lines so `period_line()` gives one period.
  - **Intermission and final screens (`Intermission`):** in the pause menu's style: the dimmed game behind, the mode tag and heading ("END OF 1ST", "FINAL"), both teams' plates with the score (away left; at the final the loser fades and a red bar marks the winner), a game-stats panel with twin bars in the team colors, and the prompt bar (accept continues). Between periods: each team's HOT and COLD player over the period just played (cold only for a player whose period was negative; otherwise "Clean period"). At the end: the THREE STARS, the game's top three ratings across both teams (ties go to the winner). `-- statscreen[=final] statwait=<s>` opens it after playing a while (layout checks).
  - **Benches and penalty boxes (NHL layout, all built in `rink.gd` from `RinkSpec`):** the team benches sit along the −X boards in the neutral zone (team 0 on the +Z half, `BENCH_Z`), each 7.6 m long and 2.3 m deep, with a rubber floor, a back wall in the team's color (`Rink.set_bench_colors`), a seat, end walls with glass partitions, and no glass in front. Each bench has two hinged doors, one at each end (`BENCH_DOORS`). Across the ice on +X are the two penalty boxes (`BOX_Z`) with the timekeeper's box between them; the rink glass runs in front, and each box has one full-height door of board and glass by the timekeeper (`BOX_DOORS`). The boards, cap, ads and glass are cut around the doors (`RinkSpec.door_gaps` / `glass_gaps`); the invisible collision wall stays whole, so the puck never gets out. Doors swing out of the rink about their hinge (`Rink.open_door(id, hold)`, ids `bench<t>_<0|1>` and `box<t>`). Players off the ice stay visible at their spot: `Skater.bench_spot` or `box_spot` while `in_box_spot`. Bench spots are claimed when a player parks (`MatchDirector._claim_bench`): their current spot if it's still free, else the first free seat along the bench seat (`Rink.bench_seats`, 0.6 m apart, hips over the seat for the sitting clips), else standing at the boards. Line changes walk through the doors (`Skater.walk`: a scripted path with no physics): the tired skater goes off through the door nearer them, the fresh one comes on through the other, and each door opens just before they reach it (`MatchDirector._change_through_doors`). Penalized players and fighters skate from where they were to the box door and in to a seat (`_send_to_box`); when the penalty ends they walk back out of the box door into play, or go back to the bench if their team doesn't need them. **Bench and box animation:** parked players keep their visual running (the skater itself doesn't process) on a looping idle with the stick put away (`SkaterVisual.bench_pose`): seated on the bench and in the box (`sitting`, `sitting_2`, now and then `sitting_talking`), `holding_idle` for anyone standing at the boards; each starts at a random point in the loop at a slightly different speed. `bench_react(kind)` plays one reaction and returns to the idle: "cheer" (sitting claps, fist pumps, yells, cheering; standing claps, fist pump, cheering), "groan" (disbelief, disapproval, angry), "sulk" (angry, disapproval, rubbing an arm) and "laugh". `MatchDirector._bench_react(team, kind, chance)` sets off a bench and its box with a chance each and up to half a second's stagger: goals (the scorers' side cheers, the other groans), big hits (the hitter's bench), penalties (the other bench laughs, the offender's groans) and fights (the winner's bench). Players arriving in the box sulk. The rig skips its procedural work when a clip owns the whole body. `-- benchtest` sends two players from each team to the box and cycles reactions (layout checks). `-- look=x,y,z,tx,ty,tz` sets a fixed camera and `-- doors` swings every door open and shut, for layout checks.
  - **Names on the back:** a nameplate above the back number, in the number's colors: the player's nickname if it's `SkaterVisual.NICKNAME_MAX` (8) characters or fewer, else their last name (`SkaterVisual.back_name`), upper case. The letters come from `assets/characters/letters.png`, rendered once by `tools/build_letters.gd` (needs a window; A–Z, É Ñ Ô Ú Û, 0–9 and - ' . !, the same white face / black outline scheme as the digit sheet). `name_texture()` crops each letter tight, spaces them and tints them per team; the plate is its own Decal on the back like the number (`_back_decal`), with capitals `NAME_HEIGHT` tall, `NAME_GAP` above the number, and long names squeezed to `NAME_MAX_W`. The number moved `NUMBER_LOWER` (0.2 m) down the back to make room, so the name sits across the shoulder blades. Goalies get the same. The character viewer's players carry sample names (plain, very long, a nickname, accents, punctuation).
  - **Play angles (`BroadcastCamera`):** four play angles, picked on the rules screen (CAMERA) or in the pause menu mid-game. The pause menu shows the angle live and keeps it in `GameSettings` (`camera`, `camera_follow`) for the next game. **Broadcast** (default, unchanged): 24 m up, 8.5 m back, end to end. **Close**: 8.5 m up and 11 m back, a lower tilt toward the play, centered between the puck and the skater you control (`cam.player`, set by the director / practice every frame). **Side**: from the penalty-box side, 14.5 m up and 13.5 m back, with the rink running across the screen and the benches on the far side. **High**: 40 m straight down, the 16-bit look; it sees through the roof, trusses, lights and scoreboard, which sit on `Arena.RAFTERS_LAYER` and are left out of its cull mask. Each angle has a screen-up direction on the ice. `InputRouter.screen_fwd` follows it, and `HumanBrain` turns the stick by it (`InputRouter.to_world`), so up on the stick is always up on the screen. The fight mini-game turns it back (`to_screen`), since it reads the stick in its own camera's terms. **CAMERA TURNS: With my team** (only when every human is on one team) turns the angle 180° whenever that team would attack down the screen (or left, on Side), so after the change of ends they still attack up / right. `-- cam=broadcast|close|side|high [camfollow]` picks one from the command line; C / Back still cycles every mode, debug views included. `godot --headless --path . -s res://scripts/tests/camera_check.gd` checks the stick turns and flips.
  - **Arena (`scripts/match/arena.gd`, built by `Rink` unless `build_arena` is off):** everything is generated from the rink's rounded outline (`RinkSpec.perimeter` at growing offsets), so the stands follow its corners. There's an 18-row lower bowl starting 3.4 m out (clear of the benches and boxes), a cross aisle, and a suite level: a balcony with a glass rail, suite seats and warm windows. Above it, the upper bowl's fascia juts out and carries an LED ribbon board. Then come a steeper 15-row upper bowl, a top concourse, the back wall and a dark roof (34 m) with trusses. Aisles line up row to row. Seats (team color) and fans are MultiMeshes split into 8 sectors so stands off screen are culled; about 17k seats, 85% full. Fans are low-poly seated figures animated in `scenes/match/crowd.gdshader`: shirts in the home jersey or trim (about half), the visitors' jersey (10%) or everyday colors, with random skin, pants and hair. Crowd excitement comes from `Sfx.crowd_reacted` (goal cheers 1.0, cheers 0.72, chants 0.55, boos 0.25–0.45…, holding a few seconds, then easing back to calm). The keenest fans stand first, bounce and throw their arms up. `Arena.goal(team)` erupts for home goals. **Lights:** a grid of bright fixtures over the ice at 29 m, a ring of dimmer ones over the stands on a catwalk, and six shadowless spot lights for the shine on the ice; the match environment has glow on. Nothing on the roof casts shadows. **Scoreboard:** four-sided and hung over center ice with its bottom at 25.5 m, above the broadcast camera (24 m), so it never blocks play; it shows in cutscenes, replays and menus. Wide screens face the sides and narrow ones the ends; each is a SubViewport drawn by `ArenaScreen`. In a game they show both teams (color, crest, abbreviation, score; visitors first like the TV scorebug), the period, clock and shots. After a goal: a pulsing GOAL! in the scorers' colors (6 s). With no game: the home crest. LED rings above and below, and the fascia ribbon, scroll an atlas of the board-ad sponsors with the home crest panel between every two (`Arena.set_teams` rebuilds it). The menus dress the arena in the featured team's colors. `scenes/tests/ArenaViewer.tscn -- look=x,y,z,tx,ty,tz [fov=] [excite=0..1] [goal=0|1] [home= away=] [noarena] [stats] shot=<png>` views the building without a game. With the whole bowl in view it's about 2M triangles and 300 draw calls (60 fps on an RTX 2070 Super).
  - **Replays (`Replay`, `ReplayTap`):** every player's skeleton ends with a `ReplayTap` modifier (after `SkaterRig`) that records the finished pose about 30 times a second of game time: the skeleton's world transform, the stick's, visibility, and each bone's local position and rotation; `Replay` records the puck's look. The rings keep 14 s. `Replay.capture(kind, label, focus, pre, post, opts)` marks a highlight from `pre` seconds back and cuts it `post` seconds later. Playing pauses the game tree, hides the game's HUD layers, swaps in a replay camera and writes the recorded poses back onto the same skeletons (the tap overrides the pose; skeleton and stick transforms are set directly; the rig is switched off); a copy of the puck's mesh stands in for the puck, so its physics body is never moved. A red "INSTANT REPLAY" wipe covers the cut in and out; the overlay shows a REPLAY tag with what it is (and SLOW MOTION below 0.7×) and a skip prompt; any accept, back or Start skips. The arena's sound (`Sfx`: crowd, organ, the booth) keeps playing through a replay. Afterwards everything goes back exactly as it was. Schedule: goals play right away (5 s before to 1.2 s after, 0.8×, the "net" camera: low off the post of the net it went into, zooming on far-off play); knockouts play right away (2.8 s before, 0.45×, an "orbit" camera circling the fighters); big hits are saved and play at the next stoppage within 45 s (0.4×, orbit), else at the end of the period; at the end of a period and the final horn up to two unshown highlights play before the stats screen. Replays only run in games with the HUD (not the soak). `-- replaytest` stages a net-cam and an orbit replay; `-- fight=ko` starts a fight with one fighter a punch from going down.
  - **Referee (`Referee`, `RefereeVisual`, `RefBrain`):** one on-ice official, a Skater with no stick (`handles_puck` off), outside both teams, with no collisions with players or the puck (the boards still hold). Stripes come from the uniform shader's `vstripes` (vertical stripes in the accent color around the torso and sleeves) and `long_pants`, via the `referee` design in `Teams.DESIGNS`: white and black, orange armbands (the sleeve stripe in the trim color), black pants, helmet and gloves, number 27. The visual places the hands freely (the rig's ARMS_FREE): at the hips skating, one arm straight up for a delayed penalty (`signal_arm = "up"`, set by the director while `rules.has_delayed_penalty()`), or pointing at `point_at`. Officials skate taller (less crouch and lean). `RefBrain` follows the play NHL-style: along the boards on the far side from the puck, a few meters deeper into the zone it's in, facing it and stepping aside from players; `hold` / `face_at` pin it for cutscenes. Hidden during the matchup intro; recorded for replays.
  - **Cutscenes (`Cutscene`):** a run of camera shots while play is stopped (the game keeps running): each shot has a length, a framing callable (camera position, look-at), an optional lens and a start callable; shots cut like a broadcast and the camera eases within one; accept / back / Start skips (not in the first 0.4 s). **Penalty call:** at the whistle the camera cuts to the referee, stopped and squared up to the offender, pointing at them (`PENALTY_CALL` = 1.5 s) while the penalty card is up; then the ref points to the box and the camera follows the offender (who waited for the call: `_send_to_box(..., delay)`) skating through the box door to the seat. The stoppage lasts until it's done; skipping parks the offender on the box seat. Only with the HUD on, one call per stoppage (a second penalty just skates off). `-- penaltytest` calls a delayed penalty a few seconds in, then blows the whistle. **Goal celebration:** with a scorer to follow (HUD on, the scorer on the scoring team), the scorer peels off to the corner glass by the net they scored on and up to four linemates pile in around them (`CelebrateBrain`: skate to a spot, face the huddle, cheer on arrival; everyone's own brain, human or AI, comes back afterwards). Shots: out in front of the scorer looking back as they skate away (1.8 s), then the huddle against the glass from the ice, a little high (2.5 s). The goal's replay waits for it (`Replay.play_soon("goal")`: plays the clip now, or as soon as it's cut; while a goal clip is pending, the replay counts as busy so a saved hit can't jump in). Skipping goes straight to the replay. `-- goaltest` credits a home goal a few seconds into play. **Period openers:** every period (HUD on) starts with the faceoff placement as usual, then the starting lines and goalies are moved into their bench doorways (two doors per team, a short queue at each) and walk out through the doors to their spots (home first, the away team 1.6 s later), each door swinging open as they reach it; goalies settle into the crease. Shots: down the boards at the home bench (2.6 s), the same at the away bench (2.6 s), then high and wide sweeping around center ice under the period banner until everyone's in place. PREGAME waits for it; skipping, or the end, puts anyone still on the way straight on their spot. Players on the bench and in the box stay where they are (penalties carry over).
  - **Screenshot timing:** the first frame's delta is the whole load time, so `-- shot` and the debug timers wait one frame before starting their clocks.
- **Going around the nets:** AI skaters steer with `Net.detour(from, to, radius)`, which hands back the target when the way is clear, else the best corner of the net's footprint (grown by the skater's radius); a target inside the net (a puck in it) is moved out to the nearest side first. `AIBrain._route` runs every move (arrive, chase, carry, pressure) through both nets. Goalies never set up behind their goal line, so a loose puck on the line or just in the net is covered from out front. `godot --headless --path . -s res://scripts/tests/net_route_check.gd` walks a body to targets all around a net.
- **M8 additions:**
  - **Saved settings (`GameSettings`):** the rules (`config`) and the player's options (`options`: volumes 0–10 for master, music, effects, crowd and announcer; display Window / Borderless / Fullscreen, VSync, anti-aliasing 0/2/4/8×, frame cap, graphics Quality / Performance, fight blood On / Off) are saved to `user://settings.cfg` and loaded at startup, so the last rules used are the next game's defaults. The rules screen saves on start and back, the pause menu when the camera changes, the options screen on the way out. `GameSettings` makes the Music, Effects, Crowd and Announcer audio buses; `Sfx` puts its players on them (crowd, reactions and organ on Crowd). Video options aren't applied in headless runs.
  - **Rules and options (`scenes/ui/Options.tscn`, `options_menu.gd`):** tabs RULES (the rules screen's rows, `RulesSelect.RULES`, editing the saved defaults), AUDIO, VIDEO and CONTROLS (the pause menu's chart, `PauseMenu.draw_controls_chart`), switched with LB / RB (Q / E) or a click. Rows work like the rules screen; each tab ends in a RESET row. Changes apply at once; audio changes play a sample on their bus (a cheer for the crowd, a line for the booth). `-- tab=rules|audio|video|controls sel=<n> shot=<png>`.
  - **Game extras:** a sub-list on the main menu (CREDITS; RECORDS and UNLOCKABLES coming soon). **Credits (`scenes/ui/Credits.tscn`, `credits.gd`):** a roll in a dark panel that scrolls by itself and loops; up / down or the wheel takes over for 2.5 s. Its `ROLL` list must carry every CC-BY asset in the game (keep it in step with `assets/CREDITS.md`); entries still missing an author show "Author to be added" in orange. `-- scroll=<px> shot=<png>` holds the roll at one spot.
  - Coming back from a screen lands on its main menu item (`GameSettings.menu_select`).
  - **Main menu (as built):** PLAY NOW; GAME MODES (Exhibition, Knockout Mode, Practice; Shootout coming soon); SEASON MODE (coming soon); CUSTOMIZE (Create Player; Create Team, Create Arena, Create Uniform and Edit Roster coming soon); RULES AND OPTIONS; GAME EXTRAS (Credits; Records and Unlockables coming soon); QUIT. The menus play the music playlist (`assets/sound/music/`).
  - **Graphics option (Quality / Performance, VIDEO tab):** Quality is the full look. Performance, for laptops and integrated graphics, renders at 0.75 scale with FSR, no MSAA, two-split hard sun shadows, a 2048 shadow atlas and no menu fog or depth of field. Both get the LODs: the crowd is split into culled chunks with 6-sided fans past 30 m and in the upper bowl (seats don't use instance or vertex colors, which fixed see-through seats on AMD integrated graphics); players get generated mesh LODs (`MeshLod`, keeping blend shapes); bench and box players cast no sun shadows and freeze their idle off screen. The menu stages are physics-interpolated, and cameras moved every frame have interpolation off so they don't lag a tick. Quality must look the same as it did before the option existed.
  - **FPS counter (`FpsCounter` autoload):** F3 shows or hides it; it starts hidden.
  - **Title font:** the chrome title words (KNOCKOUT, HOCKEY, the team select's VS) use Baron Kuffner (`assets/fonts/`, `MenuStyle.TITLE_FONT`), upright, letter-spaced by `TITLE_SPACING` (12 px per 100 px of size). The font's loose splatter specks shouldn't get rims, so the words are baked: `godot --path . res://tools/BuildTitle.tscn` (needs a window) draws each word plain at 2×, splits it into connected shapes (anything under 12% of the biggest is a speck; drips touching a letter stay with it), grows the white, red and navy rims and the shadow from the letters only (exact distance transform) and lays the chrome fill over letters and specks, saving `assets/ui/title/<word>_<size>.png`. `chrome_text` uses the image when it exists, else builds the word live from layered Labels. Rebake after changing the font, spacing or words. `-- titlefont=<file> titlespacing=<n>` previews another face live.
- The puck is drawn 2.8× size with a white outline and shows through players, so it always reads from the high camera. Its collision stays regulation size.

---

## 11. Asset plan

The current assets were quick placeholders; none of them are a requirement.

| Asset | Status | Plan |
|---|---|---|
| Rink | Built in engine (`rink.gd` from `RinkSpec`) | Exact NHL dimensions (200×85 ft), boards, glass, benches, boxes and colliders, all in code. The Sketchfab rinks were removed. An outdoor venue still to come. |
| Arena seating | **M6:** generated bowl (`Arena`) | Stepped lower and upper bowls, suites, roof, light rig and a center-hung scoreboard built in code; seats and fans recolor per team. The Stadium GLB is unused. |
| Skater base | **M5:** male and female bases (Braingapps, rigged via Mixamo) + Y Bot for tests | More bodies: rig in Mixamo, drop in `assets/player/`, add a line to `BODIES` in the build step. |
| Animations | 86 Mixamo clips (fights, hits, falls, bench, reactions, goalie, shooting, menu) + procedural skating rig | Hockey moves (stride, stop, shots, stick handling, goalie stance and saves) are procedural; Mixamo supplies falls, hit reactions, celebrations, fights, bench idles and the crowd. **Needed:** many more fight clips (§14), better checking animations, a proper side head-snap reaction for hooks. |
| Gear | Two helmets (`helmet_gear.py`, visor optional) and the sticks modeled in Blender; skates, gloves and fists modeled in Blender for the project; the jersey modeled in Blender (`build_jersey.py`); pants and socks as a skinned layer | Shoulder and pants bulk are still simple shapes. |
| Goalie gear | Two mask models; stick, pads, boots, thigh rises, blocker and catcher modeled in Blender for the project (`goalie_gear.py`) | |
| Stick | Skater and goalie sticks modeled in Blender for the project (`stick_gear.py`) | Six stick graphics and four blade tapes per player. |
| Puck, nets | Built in engine | |
| Logos | All 39 team logos cut in (Gemini, one image per team); KHL league logos drawn | Wire the league logos in (title, scorebug, center ice, playoffs); their flaws are listed in §14. |
| Audio | Recorded (ElevenLabs): shots, hits, punches and grunts, skates, horn, crowd bed and reactions, four team chants, "De-fense!", two organ pieces, every team's announcer intro, two announcers plus duets; nine music tracks. Synthesized stand-ins: stick clicks, posts, glass, the net, pads, glove saves, whistle, "ooh" | Record the synthesized ones; chants for the other 35 teams; the announcer backlog (§14). |
| UI | Menu style (`MenuStyle`), Baron Kuffner title font, PlayStation button font, TV graphics, fight HUD | |
| Zamboni | None | Waits on a model from the designer. |

**Credits:** every CC-BY asset must be listed on the credits screen (`credits.gd` `ROLL`, kept in step with `assets/CREDITS.md`); entries without an author show in orange.

---

## 12. Open questions / to test

- **Catch-up AI:** test with and without; decide on the default and whether the boost is enough to notice.
- **CPU difficulty tuning:** reaction time and decision values for each level.
- **Conference structure:** 13 teams per conference: divisions or not?
- **Fight threshold tuning:** how often fights happen (target: about 1–2 per game when fighting is on).
- **Fight style balance:** at equal ratings the boxer still wins most (§5.2). The boxer should be a rare, trained style, not the best one by style alone, and reach should come from the body, not the style.
- **Glass breaks:** how often they happen in practice at power 19+ (soak games: count them).
- **Injuries and referee strictness:** whether the rates feel right over a few games.
- **Button prompts:** the PlayStation button font stays unless the game ever goes commercial (then licensed images).

---

## 13. Milestones

| # | Milestone | Done when | Status (2026-11-12) |
|---|---|---|---|
| **M0** | Project setup | Godot project, folder structure, input map, gray-box rink with colliders, nets, puck bouncing correctly. | Done |
| **M1** | Skate & shoot | One capsule skater (with stick) skating, picking up the puck, deking, passing to a dummy, wrist/slap shots, goals detected. *The "does it feel good?" milestone.* | Done (Practice mode keeps it) |
| **M2** | 3v3 hockey | Two 3v3 teams of capsules, basic AI, AI goalies, checking (bump/check/big hit), faceoffs, clock, score, periods. | Done |
| **M3** | Full rules | 5v5, line changes and stamina, offsides/icing/penalties with toggles, player switching, OT/shootout, local multiplayer (up to 4). | Done, except four of the seven planned minor penalties |
| **M4** | Fighting | Fight triggers, prompt, forced fights, the mini-game, consequences. | Done and being reworked (styles, reach, rocked, hit feedback), plus Knockout Mode. Left: §14.2 |
| **M5** | Characters | Shared skeleton, retargeted animations, gear, recolorable jerseys, goalie model. | Done, plus body size from height and weight, faces, hair, names on the back and the referee |
| **M6** | Presentation | HUD, announcer pop-ups, replays, three stars, big-hit slow-mo, glass breaks, crowd, audio, Zamboni. | Mostly done. Left: Zamboni, goal light, the glass repair crew, the announcer backlog (§14.1) |
| **M7** | Editors | Team, player and arena editors saving to `user://`. | Player editor done; team, arena and uniform editors and Edit Roster to come |
| **M8** | Exhibition release | Front-end menus, 4 teams, indoor and outdoor arenas, settings, credits. | Menus, 39 teams, settings (with Performance graphics) and credits done. Left: outdoor arena, Shootout mode |
| Later | Expansion | 32 teams, season/playoffs, management/franchise, custom logo builder, horizontal camera. | 39 teams and the side camera are already in; the rest to come |

---

## 14. Open work

What's built but not finished, and what's waiting. The not-built items are also marked through §2–§9.

### 14.1 Announcer

- **Takes still needed:** about 124 (Steve 99, Bobby 18, duets 7) against the target of 3 per line. `tools/announcer_check.gd -- md=docs/ANNOUNCER_TODO.md` regenerates the list with the CSV's scripts.
- **Recorded files that never play** (the name matches no line): the team banter files.
- **Recheck the whole line list** against what's in the game now: Knockout Mode, the fight rework (styles, rocked, knockdowns, decisions), period openers, the penalty-call and goal-celebration cutscenes, created players and the new teams.
- **Fights need far more lines:** play-by-play and color reactions during a fight (big shots, a fighter rocked, the clinch, the knockdown, a decision, a draw, the styles), not just `fighting` at the start and `banter_fight` after.
- **Knockout Mode** has no announcer lines of its own yet (the tale of the tape, each bout's result, the final card).
- **Team banter (in progress):** one or two duet files per team (`both/banter_<team>.mp3`) that play **once per game, at a random time**, when that team is playing. Recorded so far: Quahogs (2), North Dakote, Mountain Goats, Florida Man. Not wired in yet.
- **Unused CSV penalty calls** (hooking, slashing, roughing, high-sticking) wait for those penalties.

### 14.2 Fights

- Rebalance the styles (§12).
- Fists still arrive at chest height (the IK lifts head shots 15–25 cm).
- **Many more fight clips:** more punches per style, more reactions (a proper side head-snap for hooks), more knockdowns and finishes.
- Winner's skate / taunt after a fight (§5.2).
- Jersey: a slight flare at the back of the male collar mid-punch; the jersey creases into itself at the shoulder.

### 14.3 Presentation and content

- More replay camera angles to cycle through; better checking animations.
- Wire in the KHL logos. Known flaws: the main logo's spiky knuckles and gradient letters, a stray stroke under the monogram's K/H, and the belt is too busy at small sizes.
- Crowd chants for the 35 teams without one.
- Record the synthesized sounds (§11).

### 14.4 Not built yet (from the plan)

The Zamboni; a repair crew for glass breaks; hooking, high-sticking, holding and charging; a setting to turn off shake and slow motion; a goal light; the team, arena and uniform editors and Edit Roster; the outdoor arena; Shootout mode; a remapping screen; Season, playoffs and management; Records and Unlockables.
