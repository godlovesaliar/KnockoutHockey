# Announcer lines: takes still needed (target 3 per line)

- **Steve Sheldon** (play-by-play, `assets/sound/announcer/pbp/`): 111 takes needed
- **Bobby Niedemyer** (color, `assets/sound/announcer/color/`): 26 takes needed
- **Steve & Bobby** (duets, `assets/sound/announcer/both/`): 7 takes needed

## Game flow

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `intro` | Steve | 2 (2 / 0 / 0) | 1 | intro_01 "Welcome to tonight's matchup, hockey fans!"<br>intro_02 "It's a packed house tonight, and the teams are taking the ice."<br>intro_03 "Here we go, hockey fans! Let's drop the puck!" | as the matchup screen closes, only if no duet welcome is recorded |
| `intro_duet` | Both | 4 (0 / 0 / 4) | — |  | every game, as the matchup screen closes (Steve and Bobby welcome everyone; stands in for the first period's call) |
| `newperiod` | Steve | 3 (2 / 1 / 0) | — | period_start_01 "And we're underway!"<br>period_start_02 "Puck is dropped, here we go!" | the first period starts (and any period without its own line) |
| `second_period` | Steve | 4 (3 / 1 / 0) | — | second_period_01 "Start of the second period." | the second period starts |
| `third_period` | Steve | 4 (3 / 1 / 0) | — | third_period_01 "Here we go, start of the third." | the third period starts |
| `third_stakes` | Bobby | 0 | 3 | third_stakes_01 "Twenty minutes to decide it."<br>third_stakes_02 "Third period, and everything is on the line." | after the third period's call ("Twenty minutes to decide it.") |
| `overtime` | Steve | 3 (3 / 0 / 0) | — | overtime_01 "We're going to overtime!"<br>overtime_02 "Sudden death! Next goal wins!" | overtime starts |
| `shootout` | Steve | 2 (2 / 0 / 0) | 1 | shootout_01 "It comes down to a shootout!" | the shootout starts |
| `final_minute` | Steve | 3 (3 / 0 / 0) | — | final_minute_01 "One minute remaining!"<br>final_minute_02 "Under a minute to go, this is it!" | one minute left in the last period |
| `periodend` | Steve | 5 (3 / 2 / 0) | — |  | a period ends (not the game) |
| `final_horn` | Steve | 2 (2 / 0 / 0) | 1 | final_horn_01 "And that's the game!"<br>final_horn_02 "The final horn sounds!" | the game ends |
| `final_react` | Steve | 2 (2 / 0 / 0) | 1 | final_react_01 "What a game, folks. What a game." *(CSV: Bobby)* | after the final horn call ("What a game, folks.") |

## Faceoffs

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `faceoff` | Steve | 5 (3 / 2 / 0) | — | faceoff_01 "Faceoff at center ice."<br>faceoff_02 "Drop of the puck..."<br>faceoff_03 "Lined up for the faceoff." | players line up for a faceoff |
| `centerice` | Steve | 4 (3 / 1 / 0) | — |  | the faceoff after a goal |
| `faceoff_win` | Steve | 0 | 3 | faceoff_win_01 "Wins the draw!"<br>faceoff_win_02 "Clean win on the faceoff." | someone wins the draw |
| `faceoff_loss` | Steve | 0 | 3 | faceoff_loss_01 "Lost the faceoff." | the player's team loses the draw |

## Puck movement

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `pass` | Steve | 6 (3 / 3 / 0) | — |  | a pass, now and then |
| `pass_point` | Steve | 0 | 3 | pass_point_01 "Pass back to the point." | a pass back to a defender at the blue line ("back to the point") |
| `dumpin` | Steve | 0 | 3 | dumpin_01 "Dumps it in deep." | the puck is shot in from outside the offensive zone |
| `downice` | Steve | 1 (0 / 1 / 0) | 2 | downice_01 "Carrying it up the ice..." | a carrier crosses center at speed ("carrying it up the ice") |
| `blueline` | Steve | 0 | 3 | blueline_01 "Crossing the blue line." | a forward carries the puck into the offensive zone |
| `defenderup` | Steve | 1 (0 / 1 / 0) | 2 |  | a defender carries the puck into the offensive zone |
| `boards_carry` | Steve | 3 (3 / 0 / 0) | — | boards_carry_01 "Moving it along the boards." | a carrier skates along the boards |
| `behindnet` | Steve | 3 (3 / 0 / 0) | — | behindnet_01 "Behind the net with it." | a carrier goes behind the other team's net |
| `setup` | Steve | 0 | 3 | setup_01 "Looking for an opening..." | a carrier holds the puck in the zone, looking for an opening |
| `cycle` | Steve | 0 | 3 | cycle_01 "Cycling it down low." | quick passes low in the offensive zone |
| `deke` | Steve | 3 (0 / 3 / 0) | — |  | a carrier dekes |
| `breakaway` | Steve | 1 (0 / 1 / 0) | 2 |  | a carrier is alone in on the goalie |
| `pokecheck` | Steve | 1 (0 / 1 / 0) | 2 |  | a poke check knocks the puck away |
| `turnover` | Steve | 4 (3 / 1 / 0) | — | turnover_01 "Stolen away!"<br>turnover_02 "Turnover!"<br>turnover_03 "Picks his pocket!"<br>turnover_04 "Coughs it up." | the puck goes straight from one team's carrier to the other's |
| `checking` | Steve | 3 (2 / 1 / 0) | — |  | possession keeps flipping ("they're really fighting for it!") |

## Shots

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `shot` | Steve | 3 (1 / 2 / 0) | — | shot_01 "He shoots!"<br>shot_02 "Takes the shot!" | a shot (any kind) |
| `shot_wrist` | Steve | 0 | 3 | shot_wrist_01 "Wrist shot!" | a wrist shot |
| `shot_point` | Steve | 0 | 3 | shot_point_01 "Fires from the point!" | a defender shoots from the blue line |
| `fullslapshot` | Steve | 1 (0 / 1 / 0) | 2 | slapshot_01 "Slapshot!" | a hard slap shot |
| `onetimer` | Steve | 3 (0 / 3 / 0) | — |  | a one-timer |
| `miss` | Steve | 0 | 3 | miss_01 "Wide of the net."<br>miss_02 "Just misses!" | a shot goes wide or over |
| `post` | Steve | 2 (0 / 2 / 0) | 1 | post_01 "Off the post!"<br>post_02 "Hits iron!" | a shot rings the post |
| `block` | Steve | 0 | 3 | block_01 "Blocked!"<br>block_02 "Gets right in the shooting lane." *(CSV: Bobby)* | a skater blocks a shot |
| `rebound` | Steve | 0 | 3 | rebound_01 "Rebound in front!"<br>rebound_02 "Loose puck in the crease!" | a loose puck in the crease after a save |

## Saves

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `save` | Steve | 1 (0 / 1 / 0) | 2 | save_01 "Save!"<br>save_02 "Great stop by the goalie!" | a save |
| `save_pad` | Steve | 0 | 3 | save_pad_01 "Kicked away by the pad!" | a pad save that kicks the puck out |
| `save_glove` | Steve | 0 | 3 | save_glove_01 "Glove save!" | a glove save |
| `bigsave` | Steve | 1 (0 / 1 / 0) | 2 | save_big_01 "Robbed!" | a glove save or a save on a breakaway ("Robbed!") |
| `save_react` | Bobby | 0 | 3 | save_react_01 "What a save!" | after a big save call ("What a save!") |

## Goals

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `goal` | Steve | 4 (0 / 4 / 0) | — | goal_01 "He scores!"<br>goal_02 "GOAL!"<br>goal_04 "Lights the lamp!"<br>goal_05 "It's in! It's in!" | a goal |
| `goal_topshelf` | Steve | 0 | 3 | goal_topshelf_01 "Top shelf!" | a goal up high |
| `goal_calm` | Steve | 0 | 3 | goal_calm_01 "And he scores."<br>goal_calm_02 "That one finds the back of the net." | a goal by a team already up three or more |
| `goal_tie` | Steve | 0 | 3 | goal_tie_01 "That ties it up!" | after a goal that ties it |
| `goal_lead` | Steve | 0 | 3 | goal_lead_01 "And they take the lead!" | after a goal that breaks a tie |
| `goal_insurance` | Bobby | 0 | 3 | goal_insurance_01 "That's an insurance goal right there." | after a goal that makes it a two-goal lead in the last period |
| `goal_hattrick` | Steve | 0 | 3 | goal_hattrick_01 "That's a hat trick!" | after a player's third goal |
| `goal_powerplay` | Steve | 0 | 3 | goal_powerplay_01 "Power play goal!" | after a power-play goal |
| `goal_shorthanded` | Steve | 0 | 3 | goal_shorthanded_01 "Short-handed goal!" | after a short-handed goal |
| `goal_comeback` | Steve | 0 | 3 | goal_comeback_01 "What a comeback!" | after a goal that erases a deficit of two or more |
| `goal_react` | Bobby | 0 | 3 | goal_react_02 "You won't see a prettier one than that."<br>goal_react_03 "The goalie had no chance on that one." | after a goal, when nothing above fits |
| `goal_react_home` | Steve | 0 | 3 | goal_react_home_01 "The crowd goes wild!" | after a home goal ("The crowd goes wild!") |

## Hits and fights

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `check` | Steve | 2 (0 / 2 / 0) | 1 |  | a regular check |
| `bighit` | Steve | 2 (0 / 2 / 0) | 1 | hit_01 "Big hit!"<br>hit_02 "Leveled him!" | a big hit |
| `hit_boards` | Steve | 0 | 3 | hit_boards_01 "Hammered into the boards!" | a big hit into the boards |
| `hit_react` | Bobby | 1 (0 / 1 / 0) | 2 | hit_react_01 "Ooh, he felt that one!" | after a big hit call ("Ooh, felt that one!") |
| `bighitenforcer` | Bobby | 1 (0 / 1 / 0) | 2 |  | after a big hit by a defender or heavy hitter |
| `fighting` | Steve | 1 (0 / 1 / 0) | 2 | fight_01 "The gloves are off!"<br>fight_02 "They're going at it!" | a fight starts |

## Penalties and whistles

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `penalty` | Steve | 1 (0 / 1 / 0) | 2 | penalty_01 "Penalty on the play."<br>penalty_02 "He's headed to the box." | a penalty (any kind without its own line) |
| `trippingcall` | Steve | 1 (0 / 1 / 0) | 2 | penalty_trip_01 "Two minutes for tripping." | a tripping penalty |
| `bigpenalty` | Steve | 1 (0 / 1 / 0) | 2 |  | a boarding penalty |
| `interference` | Steve | 1 (0 / 1 / 0) | 2 |  | an interference penalty |
| `powerplay` | Steve | 3 (0 / 3 / 0) | — | powerplay_01 "They're on the power play."<br>powerplay_02 "Man advantage." | a team goes on the power play |
| `pk_success` | Steve | 0 | 3 | pk_success_01 "Penalty killed off!"<br>pk_success_02 "And we're back to full strength." | a penalty is killed off |
| `whistle` | Steve | 0 | 3 | whistle_01 "There's the whistle." | a whistle for a frozen puck or a puck out of play |
| `icing` | Steve | 2 (0 / 2 / 0) | 1 | icing_01 "Icing." | icing |
| `offsides` | Steve | 2 (0 / 2 / 0) | 1 | offsides_01 "Offsides. We'll come back for a faceoff." | offside |

## Color commentary

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `idle` | Bobby | 5 (0 / 5 / 0) | — | idle_01 "Tight game tonight."<br>idle_02 "Neither team giving an inch out there."<br>idle_03 "Both goalies have been sharp tonight."<br>idle_04 "They need to generate more chances."<br>idle_05 "Good defensive structure out there."<br>idle_06 "You can feel the energy in this building." | a long quiet spell |
| `hot_streak` | Bobby | 0 | 3 | hot_streak_01 "They're all over them right now!"<br>hot_streak_02 "Total control of this period." | one team takes four shots in a row |
| `close_game` | Bobby | 0 | 3 | close_game_01 "One-goal game!" *(CSV: Steve)*<br>close_game_02 "This one is anybody's game." | late in a one-goal or tied game |
| `blowout` | Bobby | 0 | 3 | blowout_01 "This one's getting out of hand."<br>blowout_02 "They're just looking to salvage some pride now." | a team is up by four or more |
| `crowdreactgood` | Bobby | 3 (0 / 2 / 1) | — |  | the home crowd keeps cheering |
| `crowdreactbad` | Bobby | 2 (0 / 2 / 0) | 1 |  | the home crowd keeps booing |

## Banter (Steve and Bobby together)

| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `banter` | Both | 4 (0 / 0 / 4) | — |  | a long quiet spell, in place of Bobby's idle remarks now and then |
| `banter_intermission` | Both | 4 (0 / 0 / 4) | — |  | after a period ends, while the teams head off (recap the period) |
| `banter_penalty` | Both | 4 (0 / 0 / 4) | — |  | after a penalty call, in place of the power-play line now and then (Bobby disputes it) |
| `banter_fight` | Both | 3 (0 / 0 / 3) | — |  | after a fight ends |
| `banter_goal` | Both | 2 (0 / 0 / 2) | 1 |  | after a goal, when nothing more specific fits |
| `banter_hit` | Both | 4 (0 / 0 / 4) | — |  | after a big hit, in place of Bobby's reaction now and then |
| `banter_blowout` | Both | 0 | 3 |  | when a team is up by four or more, in place of the blowout line now and then |
| `banter_close` | Both | 0 | 3 |  | late in a close game, in place of the close-game line now and then |
| `banter_final` | Both | 3 (0 / 0 / 3) | — |  | after the final horn, in place of Bobby's wrap-up now and then |

## In the CSV, not used by the game

- penalty_hook_01 "Two minutes for hooking."
- penalty_slash_01 "Two minutes for slashing."
- penalty_rough_01 "Two minutes for roughing."
- penalty_highstick_01 "Two minutes for high-sticking."
