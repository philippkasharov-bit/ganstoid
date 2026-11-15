# Bugs

The shared bug list for both Claude accounts and Phil. One line per bug, newest first in each section.
**Before fixing one:** fetch `main`, check it's still open here and no branch is already on it, then move it to "Being fixed" with your branch name.
**After fixing:** move it to "Fixed" with the commit and the check that now guards it.

How bugs get here: Phil's F12 reports (zips in the game's `bugs` folder), `debug/run_all.sh` (errors in checks),
`debug/verify_soak.gd` (the long robot run), `debug/album.sh` (the photo album), and playing.

Severity: **high** = breaks a game or loses progress · **medium** = clearly wrong, but you can play · **low** = looks off or could bite later

## Open

| ID | Severity | What happens | Where | Found by |
|----|----------|--------------|-------|----------|
| BUG-9 | low (to check on Phil's PC) | In the shop (`--store` picture) a dark curved band runs across the shop floor, under the player. It could be a curved wall drawn at floor height, or a drawing glitch. | shop interior / cutaway | album `shop_counter` |
| BUG-7 | low (to check on Phil's PC) | At night (22:00) the building walls are pitch black, so only the lit windows show and they seem to float. The server draws in OpenGL mode without the screen-space lighting Phil's PC has, so it may look fine there. | night lighting, `game_view_3d.gd` | album `street_night`, `3d_night` |
| BUG-6 | low | With the bag open, the Character window opens on top of the Bag window and hides its close button (×) and part of the floor list. | window start positions in `hud.gd` | album `bag_open` |
| BUG-2 | low (high if the game is ever exported to an .exe) | 16 textures (stucco, brick, kit atlas, graffiti...) are read straight from the .png files. That works when running from source, but in an exported game the files aren't there and the textures would silently disappear. | `surface_detail.gd:42`, `kit_batch_3d.gd:34`, `graffiti3d.gd:25`, `ui_theme.gd:95` (`Image.load_from_file`) | Godot warning, error catcher |
| BUG-1 | medium (to confirm) | The first game hour after a new game has a hitch: one sim tick took 140–160 ms (about 9 frames), at 08:00 with 1500 people. `verify_sim_perf` warms up 20 s first, so it never sees this. | sim, probably the first wave of route planning after `settle_all` | soak |

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
| BUG-4 | The N map's "Find me" centred on you even at the city's edge: up to half the map was empty dark space. | `city_map_view.gd`: the view stays inside the city when centring, zooming and dragging | album `city_map` |
| BUG-3 | The N map window opened over the top-left info panel. | `hud.gd`: opens right of the panel | album `city_map` |
| BUG-5 | **Closing the game while the hourly autosave was still writing crashed it on exit**, and the quit save could write the same file at the same moment (a damaged save in rare cases). Found because the album's clock-jumping pictures crashed every time. | `world_driver.gd`: keeps the autosave's task, waits for it before quitting or starting the next one | `verify_autosave_quit` |
| QA-a | The turf map, zoomed right in, asked for a 0 px font for hood names: 7 engine errors per run. | `turf_overlay.gd`: font size never below 1 | `run_all.sh` error catcher on `verify_play_3d` |
| QA-b | `verify_house_kit` logged 52,251 errors every run (the check, not the game: an unstarted SurfaceTool). | the check starts the tool | `run_all.sh` error catcher |
