# Announcer lines: takes still needed (target 3 per line)

- **Steve Sheldon** (play-by-play, `assets/sound/announcer/pbp/`): 86 takes needed
- **Bobby Niedemyer** (color, `assets/sound/announcer/color/`): 9 takes needed
- **Steve & Bobby** (duets, `assets/sound/announcer/both/`): 45 takes needed
- **PA Announcer** (arena PA, `assets/sound/announcer/pa/`): 60 takes needed

## Game flow

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `intro` | Steve | 3 (3 / 0 / 0 / 0) | — |  | as the matchup screen closes, only if no duet welcome is recorded |
| `intro_duet` | Both | 4 (0 / 0 / 4 / 0) | — |  | every game, as the matchup screen closes (Steve and Bobby welcome everyone; stands in for the first period's call) |
| `newperiod` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | the first period starts (and any period without its own line) |
| `second_period` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | the second period starts |
| `third_period` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | the third period starts |
| `third_stakes` | Bobby | 4 (0 / 4 / 0 / 0) | — |  | after the third period's call ("Twenty minutes to decide it.") |
| `overtime` | Steve | 3 (3 / 0 / 0 / 0) | — |  | overtime starts |
| `shootout` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | the shootout starts |
| `final_minute` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | one minute left in the last period |
| `periodend` | Steve | 3 (3 / 0 / 0 / 0) | — | period_end_01 "That'll do it for the first period."<br>period_end_02 "The horn sounds to end the period."<br>period_end_03 "And the teams head to the locker room." | a period ends (not the game) |
| `final_horn` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | the game ends |
| `final_react` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | after the final horn call ("What a game, folks.") |

## Faceoffs

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `faceoff` | Steve | 3 (3 / 0 / 0 / 0) | — |  | players line up for a faceoff |
| `centerice` | Steve | 3 (3 / 0 / 0 / 0) | — |  | the faceoff after a goal |
| `faceoff_win` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | someone wins the draw |
| `faceoff_loss` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | the player's team loses the draw |

## Puck movement

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `pass` | Steve | 4 (4 / 0 / 0 / 0) | — |  | a pass, now and then |
| `pass_point` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a pass back to a defender at the blue line ("back to the point") |
| `dumpin` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | the puck is shot in from outside the offensive zone |
| `downice` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a carrier crosses center at speed ("carrying it up the ice") |
| `blueline` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a forward carries the puck into the offensive zone |
| `defenderup` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a defender carries the puck into the offensive zone |
| `boards_carry` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a carrier skates along the boards |
| `behindnet` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a carrier goes behind the other team's net |
| `setup` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a carrier holds the puck in the zone, looking for an opening |
| `cycle` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | quick passes low in the offensive zone |
| `deke` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a carrier dekes |
| `breakaway` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a carrier is alone in on the goalie |
| `pokecheck` | Steve | 4 (4 / 0 / 0 / 0) | — |  | a poke check knocks the puck away |
| `turnover` | Steve | 4 (4 / 0 / 0 / 0) | — |  | the puck goes straight from one team's carrier to the other's |
| `checking` | Steve | 3 (3 / 0 / 0 / 0) | — |  | possession keeps flipping ("they're really fighting for it!") |

## Shots

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `shot` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a shot (any kind) |
| `shot_wrist` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a wrist shot |
| `shot_point` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a defender shoots from the blue line |
| `fullslapshot` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a hard slap shot |
| `onetimer` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a one-timer |
| `miss` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a shot goes wide or over |
| `post` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a shot rings the post |
| `block` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a skater blocks a shot |
| `rebound` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a loose puck in the crease after a save |

## Saves

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `save` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a save |
| `save_pad` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a pad save that kicks the puck out |
| `save_glove` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a glove save |
| `bigsave` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a glove save or a save on a breakaway ("Robbed!") |
| `save_react` | Bobby | 5 (0 / 5 / 0 / 0) | — |  | after a big save call ("What a save!") |

## Goals

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `goal` | Steve | 4 (4 / 0 / 0 / 0) | — |  | a goal |
| `goal_topshelf` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a goal up high |
| `goal_calm` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a goal by a team already up three or more |
| `goal_tie` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | after a goal that ties it |
| `goal_lead` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | after a goal that breaks a tie |
| `goal_insurance` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a goal that makes it a two-goal lead in the last period |
| `goal_hattrick` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | after a player's third goal |
| `goal_powerplay` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | after a power-play goal |
| `goal_shorthanded` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | after a short-handed goal |
| `goal_comeback` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | after a goal that erases a deficit of two or more |
| `goal_emptynet` | Steve | 3 (3 / 0 / 0 / 0) | — |  | after a goal into an empty net ("...into the empty net!") |
| `goal_react` | Bobby | 4 (0 / 4 / 0 / 0) | — |  | after a goal, when nothing above fits |
| `goal_react_home` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | after a home goal ("The crowd goes wild!") |

## Hits and fights

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `check` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a regular check |
| `bighit` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a big hit |
| `hit_boards` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a big hit into the boards |
| `hit_react` | Bobby | 4 (0 / 4 / 0 / 0) | — |  | after a big hit call ("Ooh, felt that one!") |
| `bighitenforcer` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a big hit by a defender or heavy hitter |
| `fighting` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a fight starts |
| `fight_hype` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | just after the fight call, as the gloves come off |
| `fight_bigshot` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a heavy punch lands in a fight |
| `fight_rocked` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | a fighter gets rocked (hurt, wobbling) |
| `fight_knockout` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a fighter goes down: knockout |
| `fight_ko_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a knockout call |
| `fight_decision` | Steve | 3 (3 / 0 / 0 / 0) | — |  | the linesmen step in and one fighter wins on points |
| `fight_draw` | Steve | 3 (3 / 0 / 0 / 0) | — |  | the linesmen step in and it's a draw |
| `fight_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a fight in a game, when there's no fight banter |
| `injury_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after the injury call |
| `glass_break` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | a big hit shatters a pane of glass ("He put him right through the glass!") |
| `injury` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a hurt player is helped off ("He's slow to get up... and he's done for the night.") |

## Penalties and whistles

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `penalty` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a penalty (any kind without its own line) |
| `trippingcall` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | a tripping penalty |
| `bigpenalty` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a boarding penalty |
| `interference` | Steve | 3 (3 / 0 / 0 / 0) | — |  | an interference penalty |
| `hookingcall` | Steve | 0 | 3 | penalty_hook_01 "Two minutes for hooking." | a hooking penalty |
| `highstickcall` | Steve | 0 | 3 | penalty_highstick_01 "Two minutes for high-sticking." | a high-sticking penalty |
| `holdingcall` | Steve | 0 | 3 |  | a holding penalty |
| `chargingcall` | Steve | 0 | 3 |  | a charging penalty |
| `powerplay` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a team goes on the power play |
| `pk_success` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a penalty is killed off |
| `whistle` | Steve | 2 (2 / 0 / 0 / 0) | 1 |  | a whistle for a frozen puck or a puck out of play |
| `icing` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | icing |
| `offsides` | Steve | 1 (1 / 0 / 0 / 0) | 2 |  | offside |
| `goalie_pulled` | Steve | 3 (3 / 0 / 0 / 0) | — |  | a team pulls its goalie for an extra attacker |
| `penalty_dispute` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a penalty on the home team: Bobby doesn't like the call |
| `penalty_agree` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a penalty on the away team: Bobby agrees with the call |
| `pk_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a penalty is killed off |
| `offsides_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after an offside call, now and then |
| `goalie_pulled_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a team pulls its goalie |

## Color commentary

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `idle` | Bobby | 12 (0 / 12 / 0 / 0) | — |  | a long quiet spell |
| `hot_streak` | Bobby | 4 (0 / 4 / 0 / 0) | — |  | one team takes four shots in a row |
| `close_game` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | late in a one-goal or tied game |
| `blowout` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | a team is up by four or more |
| `crowdreactgood` | Bobby | 4 (0 / 3 / 1 / 0) | — |  | the home crowd keeps cheering |
| `crowdreactbad` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | the home crowd keeps booing |
| `post_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a shot rings off the post |
| `miss_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a shot misses the net |
| `block_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a blocked shot |
| `turnover_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a turnover or poke check |
| `deke_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a deke call |
| `period_recap` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after a period ends, when there's no intermission banter |
| `final_wrap` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | after the final horn, when there's no final banter |

## Knockout Mode

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `ko_intro` | Steve | 3 (3 / 0 / 0 / 0) | — |  | Knockout Mode: the first bout's tale of the tape |
| `ko_bout` | Steve | 3 (3 / 0 / 0 / 0) | — |  | Knockout Mode: a later bout's tale of the tape |
| `ko_suddendeath` | Steve | 3 (3 / 0 / 0 / 0) | — |  | Knockout Mode: a sudden-death bout |
| `ko_series_win` | Steve | 3 (3 / 0 / 0 / 0) | — |  | Knockout Mode: the series is decided |
| `ko_series_react` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | Knockout Mode: after the series call |

## Intermission: the Zamboni

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `zamboni_fan` | Both | 0 | 3 |  | a fan contest winner takes the Zamboni between periods: "They're letting another fan drive the resurfacer..." (Bobby is nervous for the boards) |
| `zamboni_crash` | Bobby | 0 | 3 |  | the fan driving the Zamboni hits the boards |
| `zamboni_good` | Bobby | 0 | 3 |  | the fan's Zamboni run ends with a clean, full sheet: hire this person |
| `zamboni_bad` | Bobby | 0 | 3 |  | the fan's Zamboni run ends patchy or wrecked: the crew will finish up |
| `zamboni_crew` | Steve | 0 | 3 |  | the crew's Zamboni is out between periods (no fan contest): a fresh sheet coming |
| `pa_zamboni_fan` | PA | 0 | 3 |  | a fan contest between periods: "Please welcome tonight's fan contest winner, who'll be driving the ice resurfacer!" |

## Banter (Steve and Bobby together)

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `banter` | Both | 4 (0 / 0 / 4 / 0) | — |  | a long quiet spell, in place of Bobby's idle remarks now and then |
| `banter_intermission` | Both | 4 (0 / 0 / 4 / 0) | — |  | after a period ends, while the teams head off (recap the period) |
| `banter_penalty` | Both | 4 (0 / 0 / 4 / 0) | — |  | after a penalty call, in place of the power-play line now and then (Bobby disputes it) |
| `banter_fight` | Both | 3 (0 / 0 / 3 / 0) | — |  | after a fight ends |
| `banter_goal` | Both | 2 (0 / 0 / 2 / 0) | 1 |  | after a goal, when nothing more specific fits |
| `banter_hit` | Both | 4 (0 / 0 / 4 / 0) | — |  | after a big hit, in place of Bobby's reaction now and then |
| `banter_blowout` | Both | 0 | 3 |  | when a team is up by four or more, in place of the blowout line now and then |
| `banter_close` | Both | 0 | 3 |  | late in a close game, in place of the close-game line now and then |
| `banter_final` | Both | 3 (0 / 0 / 3 / 0) | — |  | after the final horn, in place of Bobby's wrap-up now and then |
| `bobby_vs_pa` | Both | 3 (0 / 0 / 3 / 0) | — |  | a rare gag (about one game in four), at a stoppage mid-game: Bobby argues with the arena PA (voices/pa_ingame in the Studio) |
| `banter_whalers` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_geese` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_quahogs` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_lobsters` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_monsters` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_trailblazers` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_mariners` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_granite` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_cranberries` | Both | 2 (0 / 0 / 2 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_rats` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_mitts` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_poutine` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_geoducks` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_grays` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_curds` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_gales` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_sourdoughs` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_moosejaws` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_twang` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_moonshiners` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_swampthings` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_floridaman` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_armadillos` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_lumberjacks` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_otters` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_stuntmen` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_gilamonsters` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_spuds` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_seagulls` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_geysers` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_chupacabras` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_sweettea` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_deepdish` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_luchadores` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_northdakote` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_jawns` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_campers` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_mountaingoats` | Both | 1 (0 / 0 / 1 / 0) | — |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_axolotls` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_beacon` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_anchor` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_boxcar` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_copper` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_clipper` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |
| `banter_jalopy` | Both | 0 | 1 |  | once a game when this team plays, at a stoppage somewhere in the middle of the game (Steve and Bobby on the team) |

## PA announcer: calls

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `pa_welcome_whalers` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_geese` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_quahogs` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_lobsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_monsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_trailblazers` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_mariners` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_granite` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_cranberries` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_rats` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_mitts` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_poutine` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_geoducks` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_grays` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_curds` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_gales` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_sourdoughs` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_moosejaws` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_twang` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_moonshiners` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_swampthings` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_floridaman` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_armadillos` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_lumberjacks` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_otters` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_stuntmen` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_gilamonsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_spuds` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_seagulls` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_geysers` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_chupacabras` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_sweettea` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_deepdish` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_luchadores` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_northdakote` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_jawns` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_campers` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_mountaingoats` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_axolotls` | PA | 1 (0 / 0 / 0 / 1) | — |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_beacon` | PA | 0 | 1 |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_anchor` | PA | 0 | 1 |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_boxcar` | PA | 0 | 1 |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_copper` | PA | 0 | 1 |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_clipper` | PA | 0 | 1 |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_jalopy` | PA | 0 | 1 |  | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_goal_whalers` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_geese` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_quahogs` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_lobsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_monsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_trailblazers` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_mariners` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_granite` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_cranberries` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_rats` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_mitts` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_poutine` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_geoducks` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_grays` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_curds` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_gales` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_sourdoughs` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_moosejaws` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_twang` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_moonshiners` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_swampthings` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_floridaman` | PA | 2 (0 / 0 / 0 / 2) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_armadillos` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_lumberjacks` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_otters` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_stuntmen` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_gilamonsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_spuds` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_seagulls` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_geysers` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_chupacabras` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_sweettea` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_deepdish` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_luchadores` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_northdakote` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_jawns` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_campers` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_mountaingoats` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_axolotls` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_beacon` | PA | 0 | 1 |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_anchor` | PA | 0 | 1 |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_boxcar` | PA | 0 | 1 |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_copper` | PA | 0 | 1 |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_clipper` | PA | 0 | 1 |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_jalopy` | PA | 0 | 1 |  | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_visitors` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | an away goal, a few seconds after (flat): "Visitors' goal, scored by..." |
| `pa_scored_by` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | after a home team's goal call: "Scored by..." |
| `pa_n00_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n0_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n1_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n2_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n3_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n4_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n5_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n6_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n7_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n8_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n9_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n10_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n11_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n12_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n13_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n14_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n15_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n16_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n17_big` | PA | 2 (0 / 0 / 0 / 2) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n18_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n19_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n20_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n21_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n22_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n23_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n24_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n25_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n26_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n27_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n28_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n29_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n30_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n31_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n32_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n33_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n34_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n35_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n36_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n37_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n38_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n39_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n40_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n41_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n42_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n43_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n44_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n45_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n46_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n47_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n48_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n49_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n50_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n51_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n52_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n53_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n54_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n55_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n56_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n57_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n58_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n59_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n60_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n61_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n62_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n63_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n64_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n65_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n66_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n67_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n68_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n69_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n70_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n71_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n72_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n73_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n74_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n75_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n76_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n77_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n78_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n79_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n80_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n81_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n82_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n83_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n84_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n85_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n86_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n87_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n88_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n89_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n90_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n91_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n92_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n93_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n94_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n95_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n96_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n97_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n98_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n99_big` | PA | 1 (0 / 0 / 0 / 1) | — |  | a home goal's scorer: "Number seventeen!" |
| `pa_n00_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n0_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n1_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n2_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n3_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n4_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n5_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n6_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n7_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n8_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n9_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n10_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n11_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n12_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n13_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n14_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n15_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n16_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n17_flat` | PA | 2 (0 / 0 / 0 / 2) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n18_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n19_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n20_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n21_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n22_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n23_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n24_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n25_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n26_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n27_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n28_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n29_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n30_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n31_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n32_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n33_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n34_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n35_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n36_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n37_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n38_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n39_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n40_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n41_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n42_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n43_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n44_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n45_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n46_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n47_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n48_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n49_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n50_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n51_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n52_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n53_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n54_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n55_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n56_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n57_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n58_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n59_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n60_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n61_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n62_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n63_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n64_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n65_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n66_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n67_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n68_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n69_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n70_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n71_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n72_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n73_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n74_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n75_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n76_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n77_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n78_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n79_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n80_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n81_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n82_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n83_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n84_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n85_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n86_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n87_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n88_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n89_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n90_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n91_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n92_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n93_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n94_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n95_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n96_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n97_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n98_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_n99_flat` | PA | 1 (0 / 0 / 0 / 1) | — |  | assists, away scorers, penalties: "Number seventeen." |
| `pa_assist` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | after the scorer: "Assisted by..." |
| `pa_and` | PA | 1 (0 / 0 / 0 / 1) | 2 | pa_and_01 "And" | between two assists (or two fighters): "and" |
| `pa_penalty_whalers` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_geese` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_quahogs` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_lobsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_monsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_trailblazers` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_mariners` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_granite` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_cranberries` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_rats` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_mitts` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_poutine` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_geoducks` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_grays` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_curds` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_gales` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_sourdoughs` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_moosejaws` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_twang` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_moonshiners` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_swampthings` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_floridaman` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_armadillos` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_lumberjacks` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_otters` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_stuntmen` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_gilamonsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_spuds` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_seagulls` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_geysers` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_chupacabras` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_sweettea` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_deepdish` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_luchadores` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_northdakote` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_jawns` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_campers` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_mountaingoats` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_axolotls` | PA | 1 (0 / 0 / 0 / 1) | — |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_beacon` | PA | 0 | 1 |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_anchor` | PA | 0 | 1 |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_boxcar` | PA | 0 | 1 |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_copper` | PA | 0 | 1 |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_clipper` | PA | 0 | 1 |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_jalopy` | PA | 0 | 1 |  | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_pen_tripping` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | end of a penalty call: "Two minutes, for tripping." |
| `pa_pen_interference` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | end of a penalty call: "Two minutes, for interference." |
| `pa_pen_boarding` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | end of a penalty call: "Two minutes, for boarding." |
| `pa_pen_hooking` | PA | 0 | 3 |  | end of a penalty call: "Two minutes, for hooking." |
| `pa_pen_high_sticking` | PA | 0 | 3 |  | end of a penalty call: "Two minutes, for high-sticking." |
| `pa_pen_holding` | PA | 0 | 3 |  | end of a penalty call: "Two minutes, for holding." |
| `pa_pen_charging` | PA | 0 | 3 |  | end of a penalty call: "Two minutes, for charging." |
| `pa_pen_fighting` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | after a fight with majors: both numbers, then "Five minutes each, for fighting." |
| `pa_full_strength` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | a penalty runs out |
| `pa_hattrick` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | after a home player's third goal |
| `pa_last_minute` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | one minute left in any period ("Last minute of play in the period.") |
| `pa_end_first` | PA | 1 (0 / 0 / 0 / 1) | 2 |  | the first period ends |
| `pa_end_second` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | the second period ends |
| `pa_end_third` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | regulation ends tied |
| `pa_overtime` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | overtime is coming |
| `pa_shootout` | PA | 1 (0 / 0 / 0 / 1) | 2 |  | the shootout is coming |
| `pa_glass` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | a pane of glass is broken |
| `pa_win_whalers` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_geese` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_quahogs` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_lobsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_monsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_trailblazers` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_mariners` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_granite` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_cranberries` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_rats` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_mitts` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_poutine` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_geoducks` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_grays` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_curds` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_gales` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_sourdoughs` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_moosejaws` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_twang` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_moonshiners` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_swampthings` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_floridaman` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_armadillos` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_lumberjacks` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_otters` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_stuntmen` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_gilamonsters` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_spuds` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_seagulls` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_geysers` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_chupacabras` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_sweettea` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_deepdish` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_luchadores` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_northdakote` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_jawns` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_campers` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_mountaingoats` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_axolotls` | PA | 1 (0 / 0 / 0 / 1) | — |  | the home team wins: "Your <home> win!" |
| `pa_win_beacon` | PA | 0 | 1 |  | the home team wins: "Your <home> win!" |
| `pa_win_anchor` | PA | 0 | 1 |  | the home team wins: "Your <home> win!" |
| `pa_win_boxcar` | PA | 0 | 1 |  | the home team wins: "Your <home> win!" |
| `pa_win_copper` | PA | 0 | 1 |  | the home team wins: "Your <home> win!" |
| `pa_win_clipper` | PA | 0 | 1 |  | the home team wins: "Your <home> win!" |
| `pa_win_jalopy` | PA | 0 | 1 |  | the home team wins: "Your <home> win!" |
| `pa_thanks` | PA | 3 (0 / 0 / 0 / 3) | — |  | after the final horn: drive home safely |

## PA announcer: the arena

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `pa_noise` | PA | 4 (0 / 0 / 0 / 4) | — |  | a stoppage late in a close game, or with the home team behind: "Make some noise!" |
| `pa_intermission` | PA | 2 (0 / 0 / 0 / 2) | 1 |  | during the intermission, after the end-of-period call |
| `pa_ambient` | PA | 40 (0 / 0 / 0 / 40) | — |  | now and then at a stoppage or intermission: the 50/50, birthdays, lost keys, headlights, the dog in the restroom... |

## In the CSV, not used by the game

- penalty_slash_01 "Two minutes for slashing."
- penalty_rough_01 "Two minutes for roughing."
