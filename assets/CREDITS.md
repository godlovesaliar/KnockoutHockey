# Asset credits

The in-game credits screen (`scripts/ui/credits.gd`, `ROLL`) lists the same assets; update both together.

Everything below from outside the project is in the game. The players' bodies are the project's own: `tools/blender/mpfb_body.py` generates them with MPFB (the MakeHuman Plugin For Blender, from the MakeHuman community, installed from Blender's extension platform; what it generates is CC0, and only the bodies it generated are in the game, not the extension), with our own eyes, and `tools/blender/skin_paint.py` paints their skin. The hair and facial hair are the project's own: `tools/blender/hair_gear.py` builds every style on the game's heads (and the strand grain picture), and `tools/build_hair.gd` turns them into the game's meshes. The skater helmets, the goalie masks, sticks, skates, skater gloves, fists and the goalie's pads, boots, thigh rises, blocker and catcher are the project's own models (tools/blender/). So are the outdoor rink's trees (`tools/blender/trees.py` builds `assets/trees/`): the bare hardwoods are grown with the Easy Tree Blender extension (Jacob Johnston, GPL-3.0, https://github.com/jacobcjohnston/Easy-Tree; only the trees it grew are in the game, not the extension), the evergreens are built by the script, and the far trees' cut-outs are rendered from both. The outdoor rink's warming hut is ours too (`tools/blender/hut.py` builds `assets/hut/`: the model, and its wood and stone pictures, which the script makes itself). So are the goals (`tools/blender/net.py` builds `assets/net/net.glb`: the pipes, the padding and the netting) and the ice resurfacer (`tools/blender/zamboni.py` builds `assets/zamboni/zamboni.glb`; the Thingiverse model it replaced on 2026-11-21 is no longer in the game). The people in plain clothes (the fans in close-ups, the Zamboni's driver) are the same bodies in our own sweatshirt, jeans and boots (`tools/blender/plain_clothes.py` builds `assets/characters/plain_<body>.glb`, and `tools/build_fans.gd` the bodies that wear them). The rink and arena are built in code.

## Models

| Asset | Author | License | Source |
|---|---|---|---|
| Bark001 (`assets/trees/bark.jpg`, shrunk; the bark on the outdoor rink's trees. It ships with Easy Tree) | ambientCG | CC0 | https://ambientcg.com/view?id=Bark001 |

## Fonts

The controller button prompts are drawn in code (`MenuStyle.draw_glyph`); the Playstation Buttons font they used to come from was removed on 2026-11-21.

The three fonts the game uses (author and license as each font file states them):

| Asset | Author | License | Source |
|---|---|---|---|
| Spray.ME (`assets/fonts/sprayme.ttf`; the game title, `MenuStyle.TITLE_FONT`, also baked into the title pictures in `assets/ui/title/` by `tools/build_title.gd`) | Michał "Neoqueto" Nowak (Copyright Michał "Neoqueto" Nowak 2012; built with FontStruct) | CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/) | http://fontstruct.com/fontstructions/show/718516 |
| Russo One (`assets/fonts/RussoOne-Regular.ttf`; the word HOCKEY in the title and the "Russo" lettering in the Create Team badge builder) | Jovanny Lemonad (Copyright (c) 2011-2012, Jovanny Lemonad (jovanny.ru), with Reserved Font Name "Russo") | SIL Open Font License 1.1 (http://scripts.sil.org/OFL) | http://jovanny.ru |
| Michroma (`assets/fonts/Michroma.ttf`; the "Wide" lettering in the Create Team badge builder) | Vernon Adams | SIL Open Font License 1.1 (http://scripts.sil.org/OFL) | https://fonts.google.com/specimen/Michroma |

The other six fonts in `assets/fonts/` are not used by the game (they only load through the `titlefont=` test option) and are not credited: Great Lakes NF and Great Lakes Shadow NF (Nick Curtis, 1001Fonts Free For Commercial Use License), Opsilon (GGBotNet, SIL Open Font License), JOGRUNGE (JVMIYO, no license stated in the file), Baron Kuffner and Tracion (no author or license in the file).

## Characters and animations

Y Bot and all 72 animations under `assets/animations/` are from [Mixamo](https://www.mixamo.com) (Adobe). They're free to use in personal and commercial projects; no attribution is required. They're credited here anyway.

## Team logos, board ads and rosters

The team logos (`assets/images/teamlogos.jfif`, `logos2.webp` through `logos8.jfif`) and the board ad sheets (`assets/images/ads.jfif`, `ads2.jfif`, `ads3.jfif`) were made by the project owner with Google Gemini. The teams are fictional; some ads are parodies of local businesses. `tools/build_logos.gd` cuts the logos into `assets/characters/logo_<team>.png` and `tools/build_ads.gd` cuts the ads into `assets/images/ads/`. The roster sheet (`data/knockout_hockey_rosters.csv`) is the project owner's.

## Sound

The recordings in `assets/sound/` (shots, hits, hockey stops, skating, goal horn, crowd, cheers, boos, chants, organ) and the announcer lines in `assets/sound/announcer/` are cut into the clips in `assets/sound/cut/` by `tools/cut_sounds.py`. All of them were generated with ElevenLabs.

## Music

The broadcast theme (the matchup screen's music) and the TV graphics' sounds in `assets/sound/tv/` are the project's own: `tools/build_theme.py` synthesizes them from scratch (no samples, no outside recordings).

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
