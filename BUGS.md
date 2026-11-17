# Bugs

The shared bug list for both Claude accounts and Phil. One line per bug, newest first in each section.
**Before fixing one:** fetch `main`, check it's still open here and no branch is already on it, then move it to "Being fixed" with your branch name.
**After fixing:** move it to "Fixed" with the commit and the check that now guards it.

How bugs get here: Phil's F12 reports (zips in the game's `bugs` folder), `debug/run_all.sh` (errors in checks),
`debug/verify_soak.gd` (the long robot run), `debug/album.sh` (the photo album), and playing.

Severity: **high** = breaks a game or loses progress · **medium** = clearly wrong, but you can play · **low** = looks off or could bite later

## Open

- **BUG-22** (found by the pacing robot): buying a shop that is nearly broke pays nothing for days (it refills its bank first); the buy option and Phone > Business should warn "struggling" first. Guard: debug/pace_robot.gd.

| ID | Severity | What happens | Where | Found by |
|----|----------|--------------|-------|----------|
| BUG-9 | low (to check on Phil's PC) | In the shop (`--store` picture) a dark curved band runs across the shop floor, under the player. It could be a curved wall drawn at floor height, or a drawing glitch. | shop interior / cutaway | album `shop_counter` |

## Ideas (not bugs)

| ID | Idea | Why it's not a bug |
|----|------|--------------------|
| IDEA-1 | Let the sun move through the day (low and long shadows at 08:00 and 18:00, short at noon). | By design: the sun is fixed at an afternoon angle so walls read by shade (`game_view_3d.gd:133`); only its colour and brightness change. The album showed 08:00 and 12:00 look the same. |

## Being fixed

| ID | Branch | Who |
|----|--------|-----|

## Fixed

| ID | What it was | Fix | Guarded by |
|----|-------------|-----|-----------|
| BUG-15 | Rush hour stuttered: walkers coming into range were snapped onto the navmesh on the main thread (~16k a rush hour, up to 6 ms each), and traffic scanned 5k streets every half second with no traffic on. | Snap only a walker who comes into range inside a building; skip the street scan when there is no background traffic (rush-hour worst tick 20-28 ms -> ~8 ms) | `verify_sim_perf` (ticks over 4 ms) |
| BUG-21 | Seen from far away in the dark: after a report, every cop within 400 m ran straight to where you were right now (live position, through walls and darkness), and armed cops and gangs shot at you from 18 m in the dark. | Police go to the crime scene, then only follow you while they can see you (the light rules; a searching eye sees 1.6x further), search where they last saw you for 25 s and give up; shooting needs sight too | `verify_stealth` |
| BUG-7 | At night building walls were pitch black, so lit windows floated. | The BUG-20 city glow lights walls dimly | album `3d_night`, `street_night` |
| BUG-20 | Night looked unnatural: hard-edged flat lamp discs and pitch-black everywhere else. | Lamp light now fades softly from under each head (warmer sodium), and a faint blue city glow keeps streets, palms and buildings readable | album `3d_night`, `street_night` |
| BUG-16 | The player figure left its ring when walking and snapped back on stopping: the gangster walk (PL2) was baked with the hips ~1.3 m ahead of the feet. | `player_model_3d.gd` re-centres the Walk and Idle hips on load (now within 0.08 m) | `verify_player_model` |
| BUG-19 | Wounded too easily: your bleeding never stopped by itself. | A laceration clots by itself after ~2 real minutes; deep and bullet wounds still need a bandage | `verify_gameplay_feel` |
| BUG-18 | Hungry and thirsty too fast. | Hunger 0.3/day (~2.5 h of play), thirst 0.55/day (~1.5 h) | `verify_needs`, `verify_gameplay_feel` |
| BUG-17 | You couldn't catch a fleeing person (your run = their jog, winded after ~14 s). | Run 5 m/s, a full breath ~30 s, breath comes back faster; someone you catch stops for 8 s | `verify_gameplay_feel`, `verify_stamina` |
| BUG-13 | `verify_sim_perf` measured a freshly placed city without cars, so it missed the real rush-hour cost. | Cars are on the streets and the city runs from 07:00 to 08:00 before the rush hour is measured (now 3.1-3.3 ms, as in the soak); limits 1.0 / 4.0 / 2.5 ms | `verify_sim_perf` |
| BUG-4 | The N map's "Find me" centred on you even at the city's edge: up to half the map was empty dark space. | `city_map_view.gd`: the view stays inside the city when centring, zooming and dragging | album `city_map` |
| BUG-3 | The N map window opened over the top-left info panel. | `hud.gd`: opens right of the panel | album `city_map` |
| BUG-14 | The Character window (K) covered the mood icons: it was docked for a 340 px width but its Health tab is ~385 px, and growing against the screen edge it slid over the column. | `character_window.gd`: its right edge stays left of the moods (`dock_right`), whatever the tab's width, until you move it | album `bag_open` |
| BUG-11 | **The game got heavy at rush hour**: about 10 ms a sim tick once a game had run a day (60% of a frame), ~4,500 people outdoors, commutes that ran all night (people walked at real speed while the clock runs 24x). | Out of sight (past 520 m) people travel at game-time speed (`npc_street.gd` `UNSEEN_PACE_SCALE`); near you nothing changes. 26-hour soak, day 2 08:00: 3.3 ms (was 9.9), 971 outdoors (was 4,142); 03:00: 114 outdoors (was 1,977) | soak's per-hour line (slowdown rule vs day 2) |
| BUG-12 | Route helpers were handed out without a queue: walkers asked last could wait for ever (shows at fast-forward and asleep). The soak's "frozen" people near you turned out to be loiterers strolling round their door (the soak no longer counts them). | `sim_nav.gd`: first-come queue; a walker that stops asking drops out | `verify_route_queue` (the last walker waited 1,506 ticks before, 10 now) |
| BUG-1 | **Stutters**: every game hour (2.5 real minutes) a ~57 ms tick (rank score and turf each scanned all 20,000 buildings), and a 171 ms first tick. | Your businesses and grow houses are counted once and kept until a building changes hands (`BuildingData.ownership_serial`); the city lists are built while loading. Hourly spike gone; first tick 54 ms (the police system setting up) | probe of every tick over 25 ms (none after the first) |
| BUG-10 | **Out of sight (over 520 m from you, most of the city), people who reached their door stood there for good instead of going in.** About 110 more an hour: homes and workplaces away from you slowly emptied while invisible crowds waited outside, and the sim got slower every hour (3.9 ms per tick at 08:00, 5.9 ms by 13:00). | `npc_street.gd`: the straight-line branch for far walkers now checks for arrival, like the near one | `verify_soak` "stuck at door" (fails without the fix) |
| BUG-6 | Not a game bug: the album's bag picture put the Character window over the Bag (the screenshot tool moved it to x=500). In the game it docks on the right, clear of the bag. | the tool no longer moves it | album `bag_open` |
| BUG-2 | 16 textures were read straight from the .png files, which an exported game doesn't have. | `SurfaceDetail.image()`: through Godot's import, the raw file only as a fallback; used by surface detail, the house kit atlas and graffiti | `run_all.sh` counts the export warning (0 now) |
| BUG-5 | **Closing the game while the hourly autosave was still writing crashed it on exit**, and the quit save could write the same file at the same moment (a damaged save in rare cases). Found because the album's clock-jumping pictures crashed every time. | `world_driver.gd`: keeps the autosave's task, waits for it before quitting or starting the next one | `verify_autosave_quit` |
| QA-a | The turf map, zoomed right in, asked for a 0 px font for hood names: 7 engine errors per run. | `turf_overlay.gd`: font size never below 1 | `run_all.sh` error catcher on `verify_play_3d` |
| QA-b | `verify_house_kit` logged 52,251 errors every run (the check, not the game: an unstarted SurfaceTool). | the check starts the tool | `run_all.sh` error catcher |
