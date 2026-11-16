# Announcer lines: takes still needed (target 3 per line)

- **Steve Sheldon** (play-by-play, `assets/sound/announcer/pbp/`): 71 takes needed
- **Bobby Niedemyer** (color, `assets/sound/announcer/color/`): 0 takes needed
- **Steve & Bobby** (duets, `assets/sound/announcer/both/`): 30 takes needed
- **PA Announcer** (arena PA, `assets/sound/announcer/pa/`): 421 takes needed

## Game flow

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `intro` | Steve | 3 (3 / 0 / 0 / 0) | — |  | as the matchup screen closes, only if no duet welcome is recorded |
| `intro_duet` | Both | 0 | 3 |  | every game, as the matchup screen closes (Steve and Bobby welcome everyone; stands in for the first period's call) |
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
| `crowdreactgood` | Bobby | 3 (0 / 3 / 0 / 0) | — |  | the home crowd keeps cheering |
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

## Banter (Steve and Bobby together)

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `banter` | Both | 0 | 3 |  | a long quiet spell, in place of Bobby's idle remarks now and then |
| `banter_intermission` | Both | 0 | 3 |  | after a period ends, while the teams head off (recap the period) |
| `banter_penalty` | Both | 0 | 3 |  | after a penalty call, in place of the power-play line now and then (Bobby disputes it) |
| `banter_fight` | Both | 0 | 3 |  | after a fight ends |
| `banter_goal` | Both | 0 | 3 |  | after a goal, when nothing more specific fits |
| `banter_hit` | Both | 0 | 3 |  | after a big hit, in place of Bobby's reaction now and then |
| `banter_blowout` | Both | 0 | 3 |  | when a team is up by four or more, in place of the blowout line now and then |
| `banter_close` | Both | 0 | 3 |  | late in a close game, in place of the close-game line now and then |
| `banter_final` | Both | 0 | 3 |  | after the final horn, in place of Bobby's wrap-up now and then |

## PA announcer: calls

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `pa_welcome_whalers` | PA | 0 | 1 | pa_welcome_whalers "Ladies and gentlemen... welcome to Whalers hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_geese` | PA | 0 | 1 | pa_welcome_geese "Ladies and gentlemen... welcome to Geese hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_quahogs` | PA | 0 | 1 | pa_welcome_quahogs "Ladies and gentlemen... welcome to Ko-hogs hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_lobsters` | PA | 0 | 1 | pa_welcome_lobsters "Ladies and gentlemen... welcome to Lobsters hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_monsters` | PA | 0 | 1 | pa_welcome_monsters "Ladies and gentlemen... welcome to Lake Monsters hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_trailblazers` | PA | 0 | 1 | pa_welcome_trailblazers "Ladies and gentlemen... welcome to Trailblazers hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_mariners` | PA | 0 | 1 | pa_welcome_mariners "Ladies and gentlemen... welcome to Mariners hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_granite` | PA | 0 | 1 | pa_welcome_granite "Ladies and gentlemen... welcome to Granite hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_cranberries` | PA | 0 | 1 | pa_welcome_cranberries "Ladies and gentlemen... welcome to Cranberries hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_rats` | PA | 0 | 1 | pa_welcome_rats "Ladies and gentlemen... welcome to Rats hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_mitts` | PA | 0 | 1 | pa_welcome_mitts "Ladies and gentlemen... welcome to Mitts hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_poutine` | PA | 0 | 1 | pa_welcome_poutine "Ladies and gentlemen... welcome to Poutine hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_geoducks` | PA | 0 | 1 | pa_welcome_geoducks "Ladies and gentlemen... welcome to Gooey-ducks hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_grays` | PA | 0 | 1 | pa_welcome_grays "Ladies and gentlemen... welcome to Grays hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_curds` | PA | 0 | 1 | pa_welcome_curds "Ladies and gentlemen... welcome to Curds hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_gales` | PA | 0 | 1 | pa_welcome_gales "Ladies and gentlemen... welcome to Gales hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_sourdoughs` | PA | 0 | 1 | pa_welcome_sourdoughs "Ladies and gentlemen... welcome to Sourdoughs hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_moosejaws` | PA | 0 | 1 | pa_welcome_moosejaws "Ladies and gentlemen... welcome to Moose Jaws hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_twang` | PA | 0 | 1 | pa_welcome_twang "Ladies and gentlemen... welcome to Twang hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_moonshiners` | PA | 0 | 1 | pa_welcome_moonshiners "Ladies and gentlemen... welcome to Moonshiners hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_swampthings` | PA | 0 | 1 | pa_welcome_swampthings "Ladies and gentlemen... welcome to Swamp Things hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_floridaman` | PA | 0 | 1 | pa_welcome_floridaman "Ladies and gentlemen... welcome to Florida Man hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_armadillos` | PA | 0 | 1 | pa_welcome_armadillos "Ladies and gentlemen... welcome to Armadillos hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_lumberjacks` | PA | 0 | 1 | pa_welcome_lumberjacks "Ladies and gentlemen... welcome to Lumberjacks hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_otters` | PA | 0 | 1 | pa_welcome_otters "Ladies and gentlemen... welcome to Otters hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_stuntmen` | PA | 0 | 1 | pa_welcome_stuntmen "Ladies and gentlemen... welcome to Stuntmen hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_gilamonsters` | PA | 0 | 1 | pa_welcome_gilamonsters "Ladies and gentlemen... welcome to HEELA Monsters hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_spuds` | PA | 0 | 1 | pa_welcome_spuds "Ladies and gentlemen... welcome to Spuds hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_seagulls` | PA | 0 | 1 | pa_welcome_seagulls "Ladies and gentlemen... welcome to Seagulls hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_geysers` | PA | 0 | 1 | pa_welcome_geysers "Ladies and gentlemen... welcome to Geysers hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_chupacabras` | PA | 0 | 1 | pa_welcome_chupacabras "Ladies and gentlemen... welcome to Chupacabras hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_sweettea` | PA | 0 | 1 | pa_welcome_sweettea "Ladies and gentlemen... welcome to Sweet Tea hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_deepdish` | PA | 0 | 1 | pa_welcome_deepdish "Ladies and gentlemen... welcome to Deep Dish hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_luchadores` | PA | 0 | 1 | pa_welcome_luchadores "Ladies and gentlemen... welcome to Luchadores hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_northdakote` | PA | 0 | 1 | pa_welcome_northdakote "Ladies and gentlemen... welcome to North Da-koat hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_jawns` | PA | 0 | 1 | pa_welcome_jawns "Ladies and gentlemen... welcome to Jawns hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_campers` | PA | 0 | 1 | pa_welcome_campers "Ladies and gentlemen... welcome to Campers hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_mountaingoats` | PA | 0 | 1 | pa_welcome_mountaingoats "Ladies and gentlemen... welcome to Goats hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_welcome_axolotls` | PA | 0 | 1 | pa_welcome_axolotls "Ladies and gentlemen... welcome to Axolotls hockey!" | as the game opens: "Ladies and gentlemen... welcome to <home> hockey!" |
| `pa_goal_whalers` | PA | 0 | 1 | pa_goal_whalers "Whalers goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_geese` | PA | 0 | 1 | pa_goal_geese "Geese goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_quahogs` | PA | 0 | 1 | pa_goal_quahogs "Ko-hogs goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_lobsters` | PA | 0 | 1 | pa_goal_lobsters "Lobsters goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_monsters` | PA | 0 | 1 | pa_goal_monsters "Lake Monsters goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_trailblazers` | PA | 0 | 1 | pa_goal_trailblazers "Trailblazers goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_mariners` | PA | 0 | 1 | pa_goal_mariners "Mariners goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_granite` | PA | 0 | 1 | pa_goal_granite "Granite goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_cranberries` | PA | 0 | 1 | pa_goal_cranberries "Cranberries goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_rats` | PA | 0 | 1 | pa_goal_rats "Rats goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_mitts` | PA | 0 | 1 | pa_goal_mitts "Mitts goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_poutine` | PA | 0 | 1 | pa_goal_poutine "Poutine goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_geoducks` | PA | 0 | 1 | pa_goal_geoducks "Gooey-ducks goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_grays` | PA | 0 | 1 | pa_goal_grays "Grays goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_curds` | PA | 0 | 1 | pa_goal_curds "Curds goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_gales` | PA | 0 | 1 | pa_goal_gales "Gales goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_sourdoughs` | PA | 0 | 1 | pa_goal_sourdoughs "Sourdoughs goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_moosejaws` | PA | 0 | 1 | pa_goal_moosejaws "Moose Jaws goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_twang` | PA | 0 | 1 | pa_goal_twang "Twang goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_moonshiners` | PA | 0 | 1 | pa_goal_moonshiners "Moonshiners goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_swampthings` | PA | 0 | 1 | pa_goal_swampthings "Swamp Things goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_floridaman` | PA | 0 | 1 | pa_goal_floridaman "Florida Man goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_armadillos` | PA | 0 | 1 | pa_goal_armadillos "Armadillos goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_lumberjacks` | PA | 0 | 1 | pa_goal_lumberjacks "Lumberjacks goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_otters` | PA | 0 | 1 | pa_goal_otters "Otters goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_stuntmen` | PA | 0 | 1 | pa_goal_stuntmen "Stuntmen goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_gilamonsters` | PA | 0 | 1 | pa_goal_gilamonsters "HEELA Monsters goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_spuds` | PA | 0 | 1 | pa_goal_spuds "Spuds goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_seagulls` | PA | 0 | 1 | pa_goal_seagulls "Seagulls goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_geysers` | PA | 0 | 1 | pa_goal_geysers "Geysers goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_chupacabras` | PA | 0 | 1 | pa_goal_chupacabras "Chupacabras goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_sweettea` | PA | 0 | 1 | pa_goal_sweettea "Sweet Tea goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_deepdish` | PA | 0 | 1 | pa_goal_deepdish "Deep Dish goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_luchadores` | PA | 0 | 1 | pa_goal_luchadores "Luchadores goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_northdakote` | PA | 0 | 1 | pa_goal_northdakote "North Da-koat goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_jawns` | PA | 0 | 1 | pa_goal_jawns "Jawns goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_campers` | PA | 0 | 1 | pa_goal_campers "Campers goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_mountaingoats` | PA | 0 | 1 | pa_goal_mountaingoats "Goats goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_axolotls` | PA | 0 | 1 | pa_goal_axolotls "Axolotls goal!" | a home goal, a few seconds after: "<home> goal!", then scorer and assists |
| `pa_goal_visitors` | PA | 0 | 3 | pa_goal_visitors_01 "Visitors' goal, scored by..."<br>pa_goal_visitors_02 "Goal for the visitors... scored by..." | an away goal, a few seconds after (flat): "Visitors' goal, scored by..." |
| `pa_scored_by` | PA | 0 | 3 | pa_scored_by_01 "Scored by..."<br>pa_scored_by_02 "Scored by..." | after a home team's goal call: "Scored by..." |
| `pa_n00_big` | PA | 0 | 1 | pa_n00_big "Number double zero!" | a home goal's scorer: "Number seventeen!" |
| `pa_n0_big` | PA | 0 | 1 | pa_n0_big "Number zero!" | a home goal's scorer: "Number seventeen!" |
| `pa_n1_big` | PA | 0 | 1 | pa_n1_big "Number one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n2_big` | PA | 0 | 1 | pa_n2_big "Number two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n3_big` | PA | 0 | 1 | pa_n3_big "Number three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n4_big` | PA | 0 | 1 | pa_n4_big "Number four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n5_big` | PA | 0 | 1 | pa_n5_big "Number five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n6_big` | PA | 0 | 1 | pa_n6_big "Number six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n7_big` | PA | 0 | 1 | pa_n7_big "Number seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n8_big` | PA | 0 | 1 | pa_n8_big "Number eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n9_big` | PA | 0 | 1 | pa_n9_big "Number nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n10_big` | PA | 0 | 1 | pa_n10_big "Number ten!" | a home goal's scorer: "Number seventeen!" |
| `pa_n11_big` | PA | 0 | 1 | pa_n11_big "Number eleven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n12_big` | PA | 0 | 1 | pa_n12_big "Number twelve!" | a home goal's scorer: "Number seventeen!" |
| `pa_n13_big` | PA | 0 | 1 | pa_n13_big "Number thirteen!" | a home goal's scorer: "Number seventeen!" |
| `pa_n14_big` | PA | 0 | 1 | pa_n14_big "Number fourteen!" | a home goal's scorer: "Number seventeen!" |
| `pa_n15_big` | PA | 0 | 1 | pa_n15_big "Number fifteen!" | a home goal's scorer: "Number seventeen!" |
| `pa_n16_big` | PA | 0 | 1 | pa_n16_big "Number sixteen!" | a home goal's scorer: "Number seventeen!" |
| `pa_n17_big` | PA | 0 | 1 | pa_n17_big "Number seventeen!" | a home goal's scorer: "Number seventeen!" |
| `pa_n18_big` | PA | 0 | 1 | pa_n18_big "Number eighteen!" | a home goal's scorer: "Number seventeen!" |
| `pa_n19_big` | PA | 0 | 1 | pa_n19_big "Number nineteen!" | a home goal's scorer: "Number seventeen!" |
| `pa_n20_big` | PA | 0 | 1 | pa_n20_big "Number twenty!" | a home goal's scorer: "Number seventeen!" |
| `pa_n21_big` | PA | 0 | 1 | pa_n21_big "Number twenty-one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n22_big` | PA | 0 | 1 | pa_n22_big "Number twenty-two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n23_big` | PA | 0 | 1 | pa_n23_big "Number twenty-three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n24_big` | PA | 0 | 1 | pa_n24_big "Number twenty-four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n25_big` | PA | 0 | 1 | pa_n25_big "Number twenty-five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n26_big` | PA | 0 | 1 | pa_n26_big "Number twenty-six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n27_big` | PA | 0 | 1 | pa_n27_big "Number twenty-seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n28_big` | PA | 0 | 1 | pa_n28_big "Number twenty-eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n29_big` | PA | 0 | 1 | pa_n29_big "Number twenty-nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n30_big` | PA | 0 | 1 | pa_n30_big "Number thirty!" | a home goal's scorer: "Number seventeen!" |
| `pa_n31_big` | PA | 0 | 1 | pa_n31_big "Number thirty-one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n32_big` | PA | 0 | 1 | pa_n32_big "Number thirty-two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n33_big` | PA | 0 | 1 | pa_n33_big "Number thirty-three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n34_big` | PA | 0 | 1 | pa_n34_big "Number thirty-four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n35_big` | PA | 0 | 1 | pa_n35_big "Number thirty-five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n36_big` | PA | 0 | 1 | pa_n36_big "Number thirty-six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n37_big` | PA | 0 | 1 | pa_n37_big "Number thirty-seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n38_big` | PA | 0 | 1 | pa_n38_big "Number thirty-eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n39_big` | PA | 0 | 1 | pa_n39_big "Number thirty-nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n40_big` | PA | 0 | 1 | pa_n40_big "Number forty!" | a home goal's scorer: "Number seventeen!" |
| `pa_n41_big` | PA | 0 | 1 | pa_n41_big "Number forty-one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n42_big` | PA | 0 | 1 | pa_n42_big "Number forty-two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n43_big` | PA | 0 | 1 | pa_n43_big "Number forty-three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n44_big` | PA | 0 | 1 | pa_n44_big "Number forty-four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n45_big` | PA | 0 | 1 | pa_n45_big "Number forty-five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n46_big` | PA | 0 | 1 | pa_n46_big "Number forty-six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n47_big` | PA | 0 | 1 | pa_n47_big "Number forty-seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n48_big` | PA | 0 | 1 | pa_n48_big "Number forty-eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n49_big` | PA | 0 | 1 | pa_n49_big "Number forty-nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n50_big` | PA | 0 | 1 | pa_n50_big "Number fifty!" | a home goal's scorer: "Number seventeen!" |
| `pa_n51_big` | PA | 0 | 1 | pa_n51_big "Number fifty-one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n52_big` | PA | 0 | 1 | pa_n52_big "Number fifty-two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n53_big` | PA | 0 | 1 | pa_n53_big "Number fifty-three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n54_big` | PA | 0 | 1 | pa_n54_big "Number fifty-four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n55_big` | PA | 0 | 1 | pa_n55_big "Number fifty-five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n56_big` | PA | 0 | 1 | pa_n56_big "Number fifty-six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n57_big` | PA | 0 | 1 | pa_n57_big "Number fifty-seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n58_big` | PA | 0 | 1 | pa_n58_big "Number fifty-eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n59_big` | PA | 0 | 1 | pa_n59_big "Number fifty-nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n60_big` | PA | 0 | 1 | pa_n60_big "Number sixty!" | a home goal's scorer: "Number seventeen!" |
| `pa_n61_big` | PA | 0 | 1 | pa_n61_big "Number sixty-one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n62_big` | PA | 0 | 1 | pa_n62_big "Number sixty-two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n63_big` | PA | 0 | 1 | pa_n63_big "Number sixty-three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n64_big` | PA | 0 | 1 | pa_n64_big "Number sixty-four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n65_big` | PA | 0 | 1 | pa_n65_big "Number sixty-five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n66_big` | PA | 0 | 1 | pa_n66_big "Number sixty-six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n67_big` | PA | 0 | 1 | pa_n67_big "Number sixty-seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n68_big` | PA | 0 | 1 | pa_n68_big "Number sixty-eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n69_big` | PA | 0 | 1 | pa_n69_big "Number sixty-nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n70_big` | PA | 0 | 1 | pa_n70_big "Number seventy!" | a home goal's scorer: "Number seventeen!" |
| `pa_n71_big` | PA | 0 | 1 | pa_n71_big "Number seventy-one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n72_big` | PA | 0 | 1 | pa_n72_big "Number seventy-two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n73_big` | PA | 0 | 1 | pa_n73_big "Number seventy-three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n74_big` | PA | 0 | 1 | pa_n74_big "Number seventy-four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n75_big` | PA | 0 | 1 | pa_n75_big "Number seventy-five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n76_big` | PA | 0 | 1 | pa_n76_big "Number seventy-six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n77_big` | PA | 0 | 1 | pa_n77_big "Number seventy-seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n78_big` | PA | 0 | 1 | pa_n78_big "Number seventy-eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n79_big` | PA | 0 | 1 | pa_n79_big "Number seventy-nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n80_big` | PA | 0 | 1 | pa_n80_big "Number eighty!" | a home goal's scorer: "Number seventeen!" |
| `pa_n81_big` | PA | 0 | 1 | pa_n81_big "Number eighty-one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n82_big` | PA | 0 | 1 | pa_n82_big "Number eighty-two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n83_big` | PA | 0 | 1 | pa_n83_big "Number eighty-three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n84_big` | PA | 0 | 1 | pa_n84_big "Number eighty-four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n85_big` | PA | 0 | 1 | pa_n85_big "Number eighty-five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n86_big` | PA | 0 | 1 | pa_n86_big "Number eighty-six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n87_big` | PA | 0 | 1 | pa_n87_big "Number eighty-seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n88_big` | PA | 0 | 1 | pa_n88_big "Number eighty-eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n89_big` | PA | 0 | 1 | pa_n89_big "Number eighty-nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n90_big` | PA | 0 | 1 | pa_n90_big "Number ninety!" | a home goal's scorer: "Number seventeen!" |
| `pa_n91_big` | PA | 0 | 1 | pa_n91_big "Number ninety-one!" | a home goal's scorer: "Number seventeen!" |
| `pa_n92_big` | PA | 0 | 1 | pa_n92_big "Number ninety-two!" | a home goal's scorer: "Number seventeen!" |
| `pa_n93_big` | PA | 0 | 1 | pa_n93_big "Number ninety-three!" | a home goal's scorer: "Number seventeen!" |
| `pa_n94_big` | PA | 0 | 1 | pa_n94_big "Number ninety-four!" | a home goal's scorer: "Number seventeen!" |
| `pa_n95_big` | PA | 0 | 1 | pa_n95_big "Number ninety-five!" | a home goal's scorer: "Number seventeen!" |
| `pa_n96_big` | PA | 0 | 1 | pa_n96_big "Number ninety-six!" | a home goal's scorer: "Number seventeen!" |
| `pa_n97_big` | PA | 0 | 1 | pa_n97_big "Number ninety-seven!" | a home goal's scorer: "Number seventeen!" |
| `pa_n98_big` | PA | 0 | 1 | pa_n98_big "Number ninety-eight!" | a home goal's scorer: "Number seventeen!" |
| `pa_n99_big` | PA | 0 | 1 | pa_n99_big "Number ninety-nine!" | a home goal's scorer: "Number seventeen!" |
| `pa_n00_flat` | PA | 0 | 1 | pa_n00_flat "Number double zero." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n0_flat` | PA | 0 | 1 | pa_n0_flat "Number zero." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n1_flat` | PA | 0 | 1 | pa_n1_flat "Number one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n2_flat` | PA | 0 | 1 | pa_n2_flat "Number two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n3_flat` | PA | 0 | 1 | pa_n3_flat "Number three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n4_flat` | PA | 0 | 1 | pa_n4_flat "Number four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n5_flat` | PA | 0 | 1 | pa_n5_flat "Number five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n6_flat` | PA | 0 | 1 | pa_n6_flat "Number six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n7_flat` | PA | 0 | 1 | pa_n7_flat "Number seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n8_flat` | PA | 0 | 1 | pa_n8_flat "Number eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n9_flat` | PA | 0 | 1 | pa_n9_flat "Number nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n10_flat` | PA | 0 | 1 | pa_n10_flat "Number ten." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n11_flat` | PA | 0 | 1 | pa_n11_flat "Number eleven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n12_flat` | PA | 0 | 1 | pa_n12_flat "Number twelve." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n13_flat` | PA | 0 | 1 | pa_n13_flat "Number thirteen." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n14_flat` | PA | 0 | 1 | pa_n14_flat "Number fourteen." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n15_flat` | PA | 0 | 1 | pa_n15_flat "Number fifteen." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n16_flat` | PA | 0 | 1 | pa_n16_flat "Number sixteen." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n17_flat` | PA | 0 | 1 | pa_n17_flat "Number seventeen." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n18_flat` | PA | 0 | 1 | pa_n18_flat "Number eighteen." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n19_flat` | PA | 0 | 1 | pa_n19_flat "Number nineteen." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n20_flat` | PA | 0 | 1 | pa_n20_flat "Number twenty." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n21_flat` | PA | 0 | 1 | pa_n21_flat "Number twenty-one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n22_flat` | PA | 0 | 1 | pa_n22_flat "Number twenty-two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n23_flat` | PA | 0 | 1 | pa_n23_flat "Number twenty-three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n24_flat` | PA | 0 | 1 | pa_n24_flat "Number twenty-four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n25_flat` | PA | 0 | 1 | pa_n25_flat "Number twenty-five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n26_flat` | PA | 0 | 1 | pa_n26_flat "Number twenty-six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n27_flat` | PA | 0 | 1 | pa_n27_flat "Number twenty-seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n28_flat` | PA | 0 | 1 | pa_n28_flat "Number twenty-eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n29_flat` | PA | 0 | 1 | pa_n29_flat "Number twenty-nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n30_flat` | PA | 0 | 1 | pa_n30_flat "Number thirty." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n31_flat` | PA | 0 | 1 | pa_n31_flat "Number thirty-one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n32_flat` | PA | 0 | 1 | pa_n32_flat "Number thirty-two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n33_flat` | PA | 0 | 1 | pa_n33_flat "Number thirty-three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n34_flat` | PA | 0 | 1 | pa_n34_flat "Number thirty-four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n35_flat` | PA | 0 | 1 | pa_n35_flat "Number thirty-five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n36_flat` | PA | 0 | 1 | pa_n36_flat "Number thirty-six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n37_flat` | PA | 0 | 1 | pa_n37_flat "Number thirty-seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n38_flat` | PA | 0 | 1 | pa_n38_flat "Number thirty-eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n39_flat` | PA | 0 | 1 | pa_n39_flat "Number thirty-nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n40_flat` | PA | 0 | 1 | pa_n40_flat "Number forty." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n41_flat` | PA | 0 | 1 | pa_n41_flat "Number forty-one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n42_flat` | PA | 0 | 1 | pa_n42_flat "Number forty-two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n43_flat` | PA | 0 | 1 | pa_n43_flat "Number forty-three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n44_flat` | PA | 0 | 1 | pa_n44_flat "Number forty-four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n45_flat` | PA | 0 | 1 | pa_n45_flat "Number forty-five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n46_flat` | PA | 0 | 1 | pa_n46_flat "Number forty-six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n47_flat` | PA | 0 | 1 | pa_n47_flat "Number forty-seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n48_flat` | PA | 0 | 1 | pa_n48_flat "Number forty-eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n49_flat` | PA | 0 | 1 | pa_n49_flat "Number forty-nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n50_flat` | PA | 0 | 1 | pa_n50_flat "Number fifty." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n51_flat` | PA | 0 | 1 | pa_n51_flat "Number fifty-one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n52_flat` | PA | 0 | 1 | pa_n52_flat "Number fifty-two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n53_flat` | PA | 0 | 1 | pa_n53_flat "Number fifty-three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n54_flat` | PA | 0 | 1 | pa_n54_flat "Number fifty-four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n55_flat` | PA | 0 | 1 | pa_n55_flat "Number fifty-five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n56_flat` | PA | 0 | 1 | pa_n56_flat "Number fifty-six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n57_flat` | PA | 0 | 1 | pa_n57_flat "Number fifty-seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n58_flat` | PA | 0 | 1 | pa_n58_flat "Number fifty-eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n59_flat` | PA | 0 | 1 | pa_n59_flat "Number fifty-nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n60_flat` | PA | 0 | 1 | pa_n60_flat "Number sixty." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n61_flat` | PA | 0 | 1 | pa_n61_flat "Number sixty-one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n62_flat` | PA | 0 | 1 | pa_n62_flat "Number sixty-two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n63_flat` | PA | 0 | 1 | pa_n63_flat "Number sixty-three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n64_flat` | PA | 0 | 1 | pa_n64_flat "Number sixty-four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n65_flat` | PA | 0 | 1 | pa_n65_flat "Number sixty-five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n66_flat` | PA | 0 | 1 | pa_n66_flat "Number sixty-six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n67_flat` | PA | 0 | 1 | pa_n67_flat "Number sixty-seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n68_flat` | PA | 0 | 1 | pa_n68_flat "Number sixty-eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n69_flat` | PA | 0 | 1 | pa_n69_flat "Number sixty-nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n70_flat` | PA | 0 | 1 | pa_n70_flat "Number seventy." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n71_flat` | PA | 0 | 1 | pa_n71_flat "Number seventy-one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n72_flat` | PA | 0 | 1 | pa_n72_flat "Number seventy-two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n73_flat` | PA | 0 | 1 | pa_n73_flat "Number seventy-three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n74_flat` | PA | 0 | 1 | pa_n74_flat "Number seventy-four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n75_flat` | PA | 0 | 1 | pa_n75_flat "Number seventy-five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n76_flat` | PA | 0 | 1 | pa_n76_flat "Number seventy-six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n77_flat` | PA | 0 | 1 | pa_n77_flat "Number seventy-seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n78_flat` | PA | 0 | 1 | pa_n78_flat "Number seventy-eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n79_flat` | PA | 0 | 1 | pa_n79_flat "Number seventy-nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n80_flat` | PA | 0 | 1 | pa_n80_flat "Number eighty." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n81_flat` | PA | 0 | 1 | pa_n81_flat "Number eighty-one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n82_flat` | PA | 0 | 1 | pa_n82_flat "Number eighty-two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n83_flat` | PA | 0 | 1 | pa_n83_flat "Number eighty-three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n84_flat` | PA | 0 | 1 | pa_n84_flat "Number eighty-four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n85_flat` | PA | 0 | 1 | pa_n85_flat "Number eighty-five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n86_flat` | PA | 0 | 1 | pa_n86_flat "Number eighty-six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n87_flat` | PA | 0 | 1 | pa_n87_flat "Number eighty-seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n88_flat` | PA | 0 | 1 | pa_n88_flat "Number eighty-eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n89_flat` | PA | 0 | 1 | pa_n89_flat "Number eighty-nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n90_flat` | PA | 0 | 1 | pa_n90_flat "Number ninety." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n91_flat` | PA | 0 | 1 | pa_n91_flat "Number ninety-one." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n92_flat` | PA | 0 | 1 | pa_n92_flat "Number ninety-two." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n93_flat` | PA | 0 | 1 | pa_n93_flat "Number ninety-three." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n94_flat` | PA | 0 | 1 | pa_n94_flat "Number ninety-four." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n95_flat` | PA | 0 | 1 | pa_n95_flat "Number ninety-five." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n96_flat` | PA | 0 | 1 | pa_n96_flat "Number ninety-six." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n97_flat` | PA | 0 | 1 | pa_n97_flat "Number ninety-seven." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n98_flat` | PA | 0 | 1 | pa_n98_flat "Number ninety-eight." | assists, away scorers, penalties: "Number seventeen." |
| `pa_n99_flat` | PA | 0 | 1 | pa_n99_flat "Number ninety-nine." | assists, away scorers, penalties: "Number seventeen." |
| `pa_assist` | PA | 0 | 3 | pa_assist_01 "Assisted by..."<br>pa_assist_02 "With the assist going to..." | after the scorer: "Assisted by..." |
| `pa_and` | PA | 0 | 3 | pa_and_01 "And..."<br>pa_and_02 "...and..." | between two assists (or two fighters): "and..." |
| `pa_penalty_whalers` | PA | 0 | 1 | pa_penalty_whalers "Whalers penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_geese` | PA | 0 | 1 | pa_penalty_geese "Geese penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_quahogs` | PA | 0 | 1 | pa_penalty_quahogs "Ko-hogs penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_lobsters` | PA | 0 | 1 | pa_penalty_lobsters "Lobsters penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_monsters` | PA | 0 | 1 | pa_penalty_monsters "Lake Monsters penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_trailblazers` | PA | 0 | 1 | pa_penalty_trailblazers "Trailblazers penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_mariners` | PA | 0 | 1 | pa_penalty_mariners "Mariners penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_granite` | PA | 0 | 1 | pa_penalty_granite "Granite penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_cranberries` | PA | 0 | 1 | pa_penalty_cranberries "Cranberries penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_rats` | PA | 0 | 1 | pa_penalty_rats "Rats penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_mitts` | PA | 0 | 1 | pa_penalty_mitts "Mitts penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_poutine` | PA | 0 | 1 | pa_penalty_poutine "Poutine penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_geoducks` | PA | 0 | 1 | pa_penalty_geoducks "Gooey-ducks penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_grays` | PA | 0 | 1 | pa_penalty_grays "Grays penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_curds` | PA | 0 | 1 | pa_penalty_curds "Curds penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_gales` | PA | 0 | 1 | pa_penalty_gales "Gales penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_sourdoughs` | PA | 0 | 1 | pa_penalty_sourdoughs "Sourdoughs penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_moosejaws` | PA | 0 | 1 | pa_penalty_moosejaws "Moose Jaws penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_twang` | PA | 0 | 1 | pa_penalty_twang "Twang penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_moonshiners` | PA | 0 | 1 | pa_penalty_moonshiners "Moonshiners penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_swampthings` | PA | 0 | 1 | pa_penalty_swampthings "Swamp Things penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_floridaman` | PA | 0 | 1 | pa_penalty_floridaman "Florida Man penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_armadillos` | PA | 0 | 1 | pa_penalty_armadillos "Armadillos penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_lumberjacks` | PA | 0 | 1 | pa_penalty_lumberjacks "Lumberjacks penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_otters` | PA | 0 | 1 | pa_penalty_otters "Otters penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_stuntmen` | PA | 0 | 1 | pa_penalty_stuntmen "Stuntmen penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_gilamonsters` | PA | 0 | 1 | pa_penalty_gilamonsters "HEELA Monsters penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_spuds` | PA | 0 | 1 | pa_penalty_spuds "Spuds penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_seagulls` | PA | 0 | 1 | pa_penalty_seagulls "Seagulls penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_geysers` | PA | 0 | 1 | pa_penalty_geysers "Geysers penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_chupacabras` | PA | 0 | 1 | pa_penalty_chupacabras "Chupacabras penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_sweettea` | PA | 0 | 1 | pa_penalty_sweettea "Sweet Tea penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_deepdish` | PA | 0 | 1 | pa_penalty_deepdish "Deep Dish penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_luchadores` | PA | 0 | 1 | pa_penalty_luchadores "Luchadores penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_northdakote` | PA | 0 | 1 | pa_penalty_northdakote "North Da-koat penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_jawns` | PA | 0 | 1 | pa_penalty_jawns "Jawns penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_campers` | PA | 0 | 1 | pa_penalty_campers "Campers penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_mountaingoats` | PA | 0 | 1 | pa_penalty_mountaingoats "Goats penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_penalty_axolotls` | PA | 0 | 1 | pa_penalty_axolotls "Axolotls penalty." | a penalty, a few seconds after: "<team> penalty.", then the number and infraction |
| `pa_pen_tripping` | PA | 0 | 3 | pa_pen_tripping_01 "Two minutes, for tripping."<br>pa_pen_tripping_02 "Two minutes for tripping." | end of a penalty call: "Two minutes, for tripping." |
| `pa_pen_interference` | PA | 0 | 3 | pa_pen_interference_01 "Two minutes, for interference."<br>pa_pen_interference_02 "Two minutes for interference." | end of a penalty call: "Two minutes, for interference." |
| `pa_pen_boarding` | PA | 0 | 3 | pa_pen_boarding_01 "Two minutes, for boarding."<br>pa_pen_boarding_02 "Two minutes for boarding." | end of a penalty call: "Two minutes, for boarding." |
| `pa_pen_fighting` | PA | 0 | 3 | pa_pen_fighting_01 "Five minutes each, for fighting."<br>pa_pen_fighting_02 "Both players, five minutes for fighting." | after a fight with majors: both numbers, then "Five minutes each, for fighting." |
| `pa_full_strength` | PA | 0 | 3 | pa_full_strength_01 "The penalty has expired. Both teams are at full strength."<br>pa_full_strength_02 "Both teams are back at full strength." | a penalty runs out |
| `pa_hattrick` | PA | 0 | 3 | pa_hattrick_01 "Hat trick! Hat trick! Let those hats fly!"<br>pa_hattrick_02 "Ladies and gentlemen, that is a hat trick!" | after a home player's third goal |
| `pa_last_minute` | PA | 0 | 3 | pa_last_minute_01 "Last minute of play in the period."<br>pa_last_minute_02 "Ladies and gentlemen, last minute of play in the period." | one minute left in any period ("Last minute of play in the period.") |
| `pa_end_first` | PA | 0 | 3 | pa_end_first_01 "That is the end of the first period." | the first period ends |
| `pa_end_second` | PA | 0 | 3 | pa_end_second_01 "That is the end of the second period." | the second period ends |
| `pa_end_third` | PA | 0 | 3 | pa_end_third_01 "That is the end of regulation." | regulation ends tied |
| `pa_overtime` | PA | 0 | 3 | pa_overtime_01 "Ladies and gentlemen... we are going to overtime!"<br>pa_overtime_02 "Free hockey, folks! We're going to overtime!" | overtime is coming |
| `pa_shootout` | PA | 0 | 3 | pa_shootout_01 "Ladies and gentlemen... this one is going to a shootout!" | the shootout is coming |
| `pa_glass` | PA | 0 | 3 | pa_glass_01 "Ladies and gentlemen, please bear with us while the glass is replaced."<br>pa_glass_02 "There will be a short delay while the arena crew repairs the glass." | a pane of glass is broken |
| `pa_win_whalers` | PA | 0 | 1 | pa_win_whalers "Your Whalers win!" | the home team wins: "Your <home> win!" |
| `pa_win_geese` | PA | 0 | 1 | pa_win_geese "Your Geese win!" | the home team wins: "Your <home> win!" |
| `pa_win_quahogs` | PA | 0 | 1 | pa_win_quahogs "Your Ko-hogs win!" | the home team wins: "Your <home> win!" |
| `pa_win_lobsters` | PA | 0 | 1 | pa_win_lobsters "Your Lobsters win!" | the home team wins: "Your <home> win!" |
| `pa_win_monsters` | PA | 0 | 1 | pa_win_monsters "Your Lake Monsters win!" | the home team wins: "Your <home> win!" |
| `pa_win_trailblazers` | PA | 0 | 1 | pa_win_trailblazers "Your Trailblazers win!" | the home team wins: "Your <home> win!" |
| `pa_win_mariners` | PA | 0 | 1 | pa_win_mariners "Your Mariners win!" | the home team wins: "Your <home> win!" |
| `pa_win_granite` | PA | 0 | 1 | pa_win_granite "Your Granite wins!" | the home team wins: "Your <home> win!" |
| `pa_win_cranberries` | PA | 0 | 1 | pa_win_cranberries "Your Cranberries win!" | the home team wins: "Your <home> win!" |
| `pa_win_rats` | PA | 0 | 1 | pa_win_rats "Your Rats win!" | the home team wins: "Your <home> win!" |
| `pa_win_mitts` | PA | 0 | 1 | pa_win_mitts "Your Mitts win!" | the home team wins: "Your <home> win!" |
| `pa_win_poutine` | PA | 0 | 1 | pa_win_poutine "Your Poutine wins!" | the home team wins: "Your <home> win!" |
| `pa_win_geoducks` | PA | 0 | 1 | pa_win_geoducks "Your Gooey-ducks win!" | the home team wins: "Your <home> win!" |
| `pa_win_grays` | PA | 0 | 1 | pa_win_grays "Your Grays win!" | the home team wins: "Your <home> win!" |
| `pa_win_curds` | PA | 0 | 1 | pa_win_curds "Your Curds win!" | the home team wins: "Your <home> win!" |
| `pa_win_gales` | PA | 0 | 1 | pa_win_gales "Your Gales win!" | the home team wins: "Your <home> win!" |
| `pa_win_sourdoughs` | PA | 0 | 1 | pa_win_sourdoughs "Your Sourdoughs win!" | the home team wins: "Your <home> win!" |
| `pa_win_moosejaws` | PA | 0 | 1 | pa_win_moosejaws "Your Moose Jaws win!" | the home team wins: "Your <home> win!" |
| `pa_win_twang` | PA | 0 | 1 | pa_win_twang "Your Twang wins!" | the home team wins: "Your <home> win!" |
| `pa_win_moonshiners` | PA | 0 | 1 | pa_win_moonshiners "Your Moonshiners win!" | the home team wins: "Your <home> win!" |
| `pa_win_swampthings` | PA | 0 | 1 | pa_win_swampthings "Your Swamp Things win!" | the home team wins: "Your <home> win!" |
| `pa_win_floridaman` | PA | 0 | 1 | pa_win_floridaman "Your Florida Man wins!" | the home team wins: "Your <home> win!" |
| `pa_win_armadillos` | PA | 0 | 1 | pa_win_armadillos "Your Armadillos win!" | the home team wins: "Your <home> win!" |
| `pa_win_lumberjacks` | PA | 0 | 1 | pa_win_lumberjacks "Your Lumberjacks win!" | the home team wins: "Your <home> win!" |
| `pa_win_otters` | PA | 0 | 1 | pa_win_otters "Your Otters win!" | the home team wins: "Your <home> win!" |
| `pa_win_stuntmen` | PA | 0 | 1 | pa_win_stuntmen "Your Stuntmen win!" | the home team wins: "Your <home> win!" |
| `pa_win_gilamonsters` | PA | 0 | 1 | pa_win_gilamonsters "Your HEELA Monsters win!" | the home team wins: "Your <home> win!" |
| `pa_win_spuds` | PA | 0 | 1 | pa_win_spuds "Your Spuds win!" | the home team wins: "Your <home> win!" |
| `pa_win_seagulls` | PA | 0 | 1 | pa_win_seagulls "Your Seagulls win!" | the home team wins: "Your <home> win!" |
| `pa_win_geysers` | PA | 0 | 1 | pa_win_geysers "Your Geysers win!" | the home team wins: "Your <home> win!" |
| `pa_win_chupacabras` | PA | 0 | 1 | pa_win_chupacabras "Your Chupacabras win!" | the home team wins: "Your <home> win!" |
| `pa_win_sweettea` | PA | 0 | 1 | pa_win_sweettea "Your Sweet Tea wins!" | the home team wins: "Your <home> win!" |
| `pa_win_deepdish` | PA | 0 | 1 | pa_win_deepdish "Your Deep Dish wins!" | the home team wins: "Your <home> win!" |
| `pa_win_luchadores` | PA | 0 | 1 | pa_win_luchadores "Your Luchadores win!" | the home team wins: "Your <home> win!" |
| `pa_win_northdakote` | PA | 0 | 1 | pa_win_northdakote "Your North Da-koat win!" | the home team wins: "Your <home> win!" |
| `pa_win_jawns` | PA | 0 | 1 | pa_win_jawns "Your Jawns win!" | the home team wins: "Your <home> win!" |
| `pa_win_campers` | PA | 0 | 1 | pa_win_campers "Your Campers win!" | the home team wins: "Your <home> win!" |
| `pa_win_mountaingoats` | PA | 0 | 1 | pa_win_mountaingoats "Your Goats win!" | the home team wins: "Your <home> win!" |
| `pa_win_axolotls` | PA | 0 | 1 | pa_win_axolotls "Your Axolotls win!" | the home team wins: "Your <home> win!" |
| `pa_thanks` | PA | 0 | 3 | pa_thanks_01 "Thank you for coming out tonight, folks. Please drive home safely."<br>pa_thanks_02 "That's all for tonight. Get home safe, and we'll see you next time."<br>pa_thanks_03 "Thanks for coming, everybody. Please watch your step on the way out." | after the final horn: drive home safely |

## PA announcer: the arena

| Line | Records new takes | Takes (Steve / Bobby / duet / PA) | Still needed | CSV scripts | Plays when |
|---|---|---|---|---|---|
| `pa_noise` | PA | 0 | 3 | pa_noise_01 "Make some noise!"<br>pa_noise_02 "Let me hear you!"<br>pa_noise_03 "Get loud, everybody!"<br>pa_noise_04 "Come on, louder!" | a stoppage late in a close game, or with the home team behind: "Make some noise!" |
| `pa_intermission` | PA | 0 | 3 | pa_intermission_01 "There will now be a fifteen minute intermission. Grab a snack, and we'll see you back here for the next period."<br>pa_intermission_02 "We're at intermission, folks. Stick around for the chuck-a-puck at center ice." | during the intermission, after the end-of-period call |
| `pa_ambient` | PA | 0 | 3 | pa_ambient_01 "Tonight's fifty-fifty jackpot is now over four thousand dollars! Get your tickets from any seller in the concourse."<br>pa_ambient_02 "Fans, tonight's winning fifty-fifty number is... four, seven, two, two, nine, one. Please claim your prize at guest services."<br>pa_ambient_03 "Chuck-a-puck pucks are now on sale in the main concourse. All proceeds go to youth hockey."<br>pa_ambient_04 "Happy birthday to Gary, celebrating his seventy-fifth tonight in section two-oh-four!"<br>pa_ambient_05 "Tonight's game is brought to you by Pete's Tire Barn. Pete's: we'll get you rolling."<br>pa_ambient_06 "Tonight is Bark in the Park night! A big welcome to all our four-legged fans."<br>pa_ambient_07 "Tonight's attendance: eleven thousand, four hundred and twelve. Thank you for coming out!"<br>pa_ambient_08 "It's dollar hot dog night! Limit six per customer. We mean it this time."<br>pa_ambient_09 "Please welcome the Saint Agnes peewee squad, joining us here tonight!"<br>pa_ambient_10 "Keep your eyes on the video board, the kiss cam is coming up at the next stoppage!"<br>pa_ambient_11 "Congratulations to Mark and Jennifer, who just got engaged in section one-twelve! She said yes!"<br>pa_ambient_12 "Fans are reminded that throwing objects onto the ice is strictly prohibited. That includes octopus."<br>pa_ambient_13 "Stay in your seats after the game for the postgame skate with the team!"<br>pa_ambient_14 "Tonight's three stars will be announced following the game."<br>pa_ambient_15 "The Zamboni will be resurfacing the ice during intermission. Please do not feed the Zamboni."<br>pa_ambient_16 "The T-shirt toss is coming up! Get those hands up!"<br>pa_ambient_17 "Fans are reminded that this is a smoke-free facility."<br>pa_ambient_18 "Fan of the game tonight goes to the gentleman in section one-oh-eight with the light-up hat. Sir, we see you."<br>pa_ambient_19 "Would the owner of a blue pickup truck, license plate starting with K, L, Y, please return to your vehicle. Your lights are on."<br>pa_ambient_20 "Would the owner of a silver minivan parked in the Zamboni lane please move it immediately. The Zamboni would like to get by."<br>pa_ambient_21 "A set of car keys has been found at section two-twelve. They have a little rubber duck on them. Please see guest services."<br>pa_ambient_22 "Attention fans: a small dog has been found in the restroom on the upper concourse. He seems very happy. If he's yours, please see guest services."<br>pa_ambient_23 "Would the parents of Tyler, age six, please come to guest services. Tyler is fine. Tyler has had three cotton candies."<br>pa_ambient_24 "A pair of false teeth has been turned in at the lost and found. We would really like to return them."<br>pa_ambient_25 "Would the owner of a red sedan with a canoe on the roof please return to your vehicle. The canoe is leaving."<br>pa_ambient_26 "A wallet has been found near the pretzel stand. If you can describe the photos inside, it's yours."<br>pa_ambient_27 "Fans, the north concourse restrooms are temporarily closed. Please use the facilities on the south side. Sorry about that."<br>pa_ambient_28 "Would Doctor Patel please report to section one-oh-three. Doctor Patel, to section one-oh-three."<br>pa_ambient_29 "To whoever left a full plate of nachos at the top of section two-twenty: they're gone now. We're sorry."<br>pa_ambient_30 "The lost and found now has one mitten, two umbrellas, and a very confused goat. Please come and claim the goat."<br>pa_ambient_31 "Would the gentleman who lost his toupee in section one-fifteen please see guest services. No questions asked."<br>pa_ambient_32 "Attention: the Zamboni driver's lunch has gone missing from the break room. It was a tuna sandwich. He is very upset."<br>pa_ambient_33 "Fans, please do not attempt to start the wave during a power play. Thank you."<br>pa_ambient_34 "Would the owner of a white hatchback in lot C please return to your vehicle. Your car alarm has been going for forty minutes."<br>pa_ambient_35 "A reminder that the parking lot gates close one hour after the game. That means you, Dave."<br>pa_ambient_36 "Update: Tyler has been reunited with his parents. Tyler, please put down the cotton candy."<br>pa_ambient_37 "To the fan who brought the cowbell: we hear you. Everyone hears you."<br>pa_ambient_38 "Congratulations to section one-oh-six, tonight's loudest section! Free popcorn is on the way."<br>pa_ambient_39 "Attention: a hamster has been found in the press box. We have no idea how. Please see guest services."<br>pa_ambient_40 "Would the owner of a green station wagon in lot B please return to your vehicle. A raccoon is in it. He looks comfortable." | now and then at a stoppage or intermission: the 50/50, birthdays, lost keys, headlights, the dog in the restroom... |

## In the CSV, not used by the game

- penalty_hook_01 "Two minutes for hooking."
- penalty_slash_01 "Two minutes for slashing."
- penalty_rough_01 "Two minutes for roughing."
- penalty_highstick_01 "Two minutes for high-sticking."
