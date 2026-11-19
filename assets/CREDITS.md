# Asset credits

The in-game credits screen (`scripts/ui/credits.gd`, `ROLL`) lists the same assets; update both together.

Everything below from outside the project is in the game. The male and female character bases are used for every player's body (rigged through Mixamo). The hair is turned into game meshes by tools/build_hair.gd. The skater helmets, the goalie masks, sticks, skates, skater gloves, fists and the goalie's pads, boots, thigh rises, blocker and catcher are the project's own models (tools/blender/). The rink and arena are built in code.

## Models

| Asset | Author | License | Source |
|---|---|---|---|
| Female Character Base - Rigged | Braingapps | CC-BY-4.0 | https://sketchfab.com/3d-models/female-character-base-rigged-9245f75f5d0d45cb9e867d5133d5fdc1 |
| Male Character Base - Rigged | Braingapps | CC-BY-4.0 | https://sketchfab.com/3d-models/male-character-base-rigged-83d91cbfe6fd48ad87f3a2264d3bcb47 |
| Hair and Beard Pubg Mobile 3D Model (`assets/player/hair_and_beard__pubg_mobile_3d_model.glb`; five hairstyles and the beard, tinted per player) | BilloXD | CC-BY-4.0 | https://sketchfab.com/3d-models/hair-and-beard-pubg-mobile-3d-model-844243e11ccf40f8902385fe2fddd428 |
| MOSTACHE (`assets/player/mostache.glb`) | vajidkm | CC-BY-4.0 | https://sketchfab.com/3d-models/mostache-61f34dcad95b450d9cc95456f3b93072 |
| ported hair (`assets/player/ported_hair.glb`; the long braid / ponytail) | bbb59149 | CC-BY-4.0 | https://sketchfab.com/3d-models/ported-hair-e8eb76ad3c8f46f8aee7ceb076f05972 |
| Snow Trees Pack LOWPOLY (`assets/snow-trees-pack-lowpoly/`; the outdoor rink's woods, bushes and far treeline) | sixonetwo (@evan4129) | CC-BY-4.0 | https://sketchfab.com/3d-models/snow-trees-pack-lowpoly-8927ca8abbfc4871a029323480d1ad05 |
| Forest cabin low poly (`assets/forest_cabin_low_poly.glb`; the outdoor rink's warming hut) | POLYSCAN (@POLYSCAN3D) | CC-BY-4.0 | https://sketchfab.com/3d-models/forest-cabin-low-poly-557e8b5d4a364031b88148cb51c215e1 |
| Zamboni (`assets/ZAMBONI5.stl`; cleaned up into `assets/zamboni/zamboni.glb` by `tools/blender/zamboni.py`: one steering wheel kept and mounted, the other and the loose bar dropped, wheels split out to spin and steer, decimated, recolored) | marsmodels | CC BY | https://www.thingiverse.com/thing:5555849 |

## Fonts

| Asset | Author | License | Source |
|---|---|---|---|
| Playstation Buttons (`assets/fonts/PLAYB___.TTF`; the Cross, Circle, Square, Triangle, Start and Select prompts, `MenuStyle.draw_glyph`) | TracerTong (made with Fontographer 4.1.2, 1999; the font notes Sony's trademarks) | Free for personal use (commercial use: see the license file in the font package or contact the designer, tracertong.co.uk) | https://www.fonts4free.net/playstation-buttons-font.html |

## Characters and animations

Y Bot and all 72 animations under `assets/animations/` are from [Mixamo](https://www.mixamo.com) (Adobe). They're free to use in personal and commercial projects; no attribution is required. They're credited here anyway.

## Team logos, board ads and rosters

The team logos (`assets/images/teamlogos.jfif`, `logos2.webp` through `logos8.jfif`) and the board ad sheets (`assets/images/ads.jfif`, `ads2.jfif`, `ads3.jfif`) were made by the project owner with Google Gemini. The teams are fictional; some ads are parodies of local businesses. `tools/build_logos.gd` cuts the logos into `assets/characters/logo_<team>.png` and `tools/build_ads.gd` cuts the ads into `assets/images/ads/`. The roster sheet (`data/knockout_hockey_rosters.csv`) is the project owner's.

## Sound

The recordings in `assets/sound/` (shots, hits, hockey stops, skating, goal horn, crowd, cheers, boos, chants, organ) and the announcer lines in `assets/sound/announcer/` are cut into the clips in `assets/sound/cut/` by `tools/cut_sounds.py`. All of them were generated with ElevenLabs.

## Music

The menu playlist (`assets/sound/music/`; every track there plays, shuffled), from Pixabay. The Pixabay Content License doesn't require attribution; credited anyway.

| Track (file) | Artist | License | Source |
|---|---|---|---|
| Extreme Sports - Extreme (`gr0za-extreme-sports-extreme-610340.mp3`) | GR0ZA | Pixabay Content License | https://pixabay.com/music/trap-extreme-sports-extreme-610340/ |
| Uplifting Action Sport Energetic Rock (`ikoliks-uplifting-action-sport-energetic-rock-619094.mp3`) | ikoliks | Pixabay Content License | https://pixabay.com/music/rock-uplifting-action-sport-energetic-rock-619094/ |
| Sports - Sport Rock (`jonasblakewood-sports-sport-rock-622907.mp3`) | JonasBlakewood | Pixabay Content License | https://pixabay.com/music/rock-sports-sport-rock-622907/ |
| Surf Rock (`alex-morgan-surf-rock-591326.mp3`) | Alex Morgan | Pixabay Content License | Pixabay, track 591326 |
| Indie Rock (`atlasaudio-indie-rock-606263.mp3`) | AtlasAudio | Pixabay Content License | Pixabay, track 606263 |
| Rock Instrumental (`sigmamusicart-rock-instrumental-173422.mp3`) | SigmaMusicArt | Pixabay Content License | Pixabay, track 173422 |
| Hip Hop Beat Urban Rap (`sound4stock-hip-hop-beat-urban-rap-590667.mp3`) | Sound4Stock | Pixabay Content License | Pixabay, track 590667 |
| East Coast Instrumental (`sub_clair-east-coast-instrumental-623474.mp3`) | Sub_Clair | Pixabay Content License | Pixabay, track 623474 |
| Powerful Rock (`the_mountain-powerful-rock-593057.mp3`) | The_Mountain | Pixabay Content License | Pixabay, track 593057 |

## Code

Godot Engine 4.7 (MIT license) and Jolt Physics (MIT license).
