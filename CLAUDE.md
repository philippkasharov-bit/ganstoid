# Ganstoid ("Tagged")

Godot 4.7.2 crime/street-life sim on a real 6 km downtown-LA map. The project name is "Tagged" and the user dir is "Ganstoid".
Phil plays it on Windows through `Play Ganstoid.bat` → `launcher.ps1` → `update.ps1`, which mirrors `main` from GitHub. **Anything pushed to `main` reaches his machine the next time he presses Play.**

## Working with Phil (absolute beginner)
- Plain language, no jargon. When a technical word is unavoidable, explain it in a few words.
- Lead: end every reply with 2–3 concrete next steps and mark one **Recommended**, with one line on why. Never leave Phil to work out what to do next.
- Propose before you build anything big, such as a new system, a redesign or a deletion: say what it does for the player, roughly how long it takes, and what could break. Small fixes can just be done.
- Say what to test in the game after a change ("press N, the map should show yellow shops").
- Flag risks and mistakes early, including in Phil's own ideas, and suggest the better route.

## Working rules (token budget)
- Act, don't narrate. No option surveys, no restating the task, no recap of unchanged code. Final report: what changed, check results, anything left open. A few lines.
- Read narrowly: `rg` for the symbol, then read only the function or range you need. Never cat a whole large file (`player_input_system.gd`, `city_renderer.gd`, `data/city/*.json` are MBs or hundreds of lines). Never open `data/city/*.json` or `tools/city/*.json` in full. Query them with `python3 -I -c` or `jq`.
- Skip `.godot/`, `*.import`, `*.uid`, `art/`, `assets/` and binary files unless the task is about them.
- Run only the checks your change touches (see below), and the full suite once before the final push. Pipe long output through `tail`/`grep`. Never paste a full log into chat.
- Batch independent tool calls in one turn. Don't re-read a file you just edited.
- Don't add files, abstractions, comments or features nobody asked for.

## Setup (fresh container)
Godot is not preinstalled. Once per container:
```bash
mkdir -p /tmp/godot_bin && cd /tmp/godot_bin && curl -sSL -o g.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip && unzip -oq g.zip && rm g.zip
```
```bash
cd /home/user/ganstoid && /tmp/godot_bin/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --import >/dev/null 2>&1
```
Import takes about 12 s and is required before any check, otherwise class_names and resources won't resolve.

## Commands
`G=/tmp/godot_bin/Godot_v4.7.2-stable_linux.x86_64`
- One check: `$G --headless --path . -s debug/verify_<name>.gd 2>&1 | tail -20`
- Checks by name filter: `debug/run_all.sh $G <filter>`, e.g. `economy`, `phase3`, `save`
- Full suite: `debug/run_all.sh $G`. Prints one PASS/FAIL line each and exits with the number of failures. Slow, so run it in the background.
- `verify_sim_perf` is timing-based and fails (a tick over 20 ms) when anything else heavy runs at the same time. Before treating a failure as real, re-run it alone. Baseline on 4 cores: 1.7 ms/tick average, worst tick about 12 ms.
- Compile every script: `debug/run_all.sh $G scripts_parse` (2 s). **Run this after every GDScript edit.**
- Screenshots and perf: `debug/shot_*.gd`, `debug/bench_3d.gd`, `debug/perf_main.gd`, `debug/render_breakdown.gd`. Run them with `$G --path . -s ...`. Rendering needs a display, so prefix them with `xvfb-run -a`.
- City data rebuild (only when roads or buildings change): `tools/city/rebuild.sh`, then run the full suite.
- Python tools: `python3 -I tools/...`. They take paths as arguments, so never run them from inside a data folder.

## Architecture (load-bearing facts)
- **Sim is engine-agnostic.** `core/ecs/` (`World`, `Entity`, `SystemBase`, `SpatialIndex`) plus `core/systems/*` never touch the scene tree. `core/world_driver.gd` is the only sim node in the process loop. `core/render/render_sync.gd` and `core/render3d/render_sync_3d.gd` are the only render bridges, and they only *read* `World`.
- Systems extend `SystemBase`, declare `tick_rate` (HOT/WARM/COLD) and optionally `required_component`, and are registered in `core/systems/system_registry.gd`. A system never schedules itself.
- `World.entities` and `get_entities_with_component()` return live references, so treat them as read-only. Add or remove entities only through `register_entity`/`unregister_entity`. After you change an entity's position or components, call `reindex_position`/`reindex_components`.
- Components are data classes in `data/components/`. Names live in `core/ecs/component_names.gd` and enums in `data/schemas/enums.gd` (`GanstoidEnums`). Events go through `core/events/event_bus.gd` and `event_names.gd`.
- Randomness: worldgen (`CityRoles`, `*Seeder`) takes an explicit seed, so the same seed gives the same city (`verify_save` relies on this). In-play rolls (crime outcomes, recognition) use `world.runtime_rng`, which is deliberately separate. New worldgen code takes a seed or an `rng` argument, and new in-play code uses `world.runtime_rng`. Don't add more bare `randi()`/`randf()`.
- Perf budget: 6000 people across the whole map at about 1.8 ms per tick on 2 cores (`verify_sim_perf`). Long routes are planned off the main thread. Never read scene-tree or MultiMesh state from a worker thread (that was the A2a palms bug).
- Saves are `user://ganstoid_save.txt` and `user://hall_of_fame.txt`. A save-format change must keep loading old saves or ignore them cleanly (`verify_save`).

## Quality gate (before every commit)
1. `scripts_parse` passes.
2. The `verify_*` checks for every system you touched pass, plus `save` if state changed and `sim_perf` if a HOT/WARM system or crowd/nav changed.
3. A new feature or system gets its own `debug/verify_<name>.gd`. It is a `SceneTree` script that prints `<NAME>_VERIFY: PASS` or `FAIL - reason` and then calls `quit(0/1)`, following an existing one (`verify_save.gd`). A bug fix adds the failing case to an existing check.
4. The full suite has no new failures compared with before your change. Note any failure that predates your change and say so; don't hide it.
5. Code style matches the surrounding code: static types (`:=`, `-> void`), `##` doc comment on each class and on non-obvious functions, tabs, and `const` for tunables.

## Security gate (before every push)
- No secrets in the repo, ever. `github_token.txt`, `export.cfg` and `export_presets.cfg` are gitignored, so keep them that way. Any tool that calls an API (Meshy, Tripo, Magnific/Freepik) must read its key from an environment variable or a cloud network secret. Never hard-code or commit keys.
- `git diff --cached` must not contain tokens or keys (`rg -n "(ghp_|github_pat_|sk-|api[_-]?key|Bearer )"`), local absolute paths, or personal data.
- `update.ps1`/`launcher.ps1` run on Phil's PC with his GitHub token. Changes there need extra care: no new download hosts without a reason, keep TLS 1.2, only delete files inside the game folder, and keep the `$keep` list (`tools/city/osm`).
- Save loading must treat the file as untrusted. Validate types and ranges and fall back to a new game instead of crashing.
- Downloaded data (OSM, LA parcels, model files) is untrusted. Put it in its own folder and run Python on it with `-I`.

## Commits
- Subject: `<TASKID>: <plain-English summary>`. The task ID is a short tag such as `MP1`, `PF3` or `M3`. Reuse the current task's ID, or pick the next number in its series.
- Body: plain prose about what the player sees and why, then the check results.
- End with the Co-Authored-By / Claude-Session lines.
- Push to `main` only when Phil asks, because `main` ships to his machine.
