# VS2 Step 0: street look audit and speed baseline

Checked on 2026-11-17 against `main` 667a862. Nothing in the game was changed.
Pictures: `debug/shot_3d.gd -- --look=<x,y> --size=34 --hour=12` (software renderer, judge shapes not colours).

| Spot | Map point |
|------|-----------|
| bend | 5266, 3378 |
| junction | 5177, 3302 |
| driveway | 5185.6, 3386.7 |
| crosswalk end | 5169, 3375.7 |
| chunk seam | 5325.2, 3378 |

## Leads

| Lead | Verdict | What the picture or the code shows |
|------|---------|------------------------------------|
| Kerb gaps at bends | **confirmed** (BUG-23) | Kerbs are cut per road segment in 2 m pieces (`street_detail_3d.gd` `_kerbs`), so each segment ends square. On the outside of a bend a wedge-shaped gap opens. 1,077 of the 2,340 kerbed joints bend more than 10°. |
| Jagged road edge at bends | **confirmed, new** (BUG-24) | The road surface itself has a saw-tooth edge on the outside of the bend. |
| Junction corners | **confirmed** (BUG-25) | The kerb stops `CORNER_M` (2.5 m) short of the junction and ends square: no rounded return around the corner. |
| Driveways | **confirmed** (BUG-26) | The kerb is cut with square ends at a driveway: no flare and no dropped edge. |
| Crosswalk ramps | **confirmed** (BUG-27) | `city.kerb_ramps` (15,566 ramps from the survey) is loaded but never used. The kerb runs straight through at full height where a crosswalk meets it. |
| Kerbs only on main roads | **confirmed** (BUG-28) | `KERBED` is only `art` and `res`. Service roads (3,247), alleys (405) and parking aisles (806) have no kerb, so the pavement and road meet with nothing between. Alleys and aisles may be right without one; service roads usually have one. |
| Doubled kerbs at chunk seams | **not confirmed** | Each piece goes to exactly one chunk, by its start point (`city_mesh_3d.gd` `_tool`). The seam picture shows nothing doubled or missing. |
| Very long segments missed at a chunk edge | unsure, low risk | Some segments are very long (810 m `res`, 614 m `art`) while a chunk only takes geometry within 480 m. Not seen in the pictures. Batch A's seam check should cover it. |
| Parked cars on things | **confirmed** (BUG-29) | `VehicleSeeder` puts kerbside cars along the kerb without checking hydrants, driveways, crosswalks or bus stops. |
| Street clutter unchecked | **confirmed** (BUG-29) | `StreetClutter` mailboxes and bins are not checked against driveways, ramps or doors. Only signs use `RoadSpace.clear`. |
| Repeating ground texture | **confirmed** (BUG-30) | Sandy lots and plazas show a clear diamond tiling pattern. The ground at the seam spot looks flat and washed out. |

## Speed baseline (before VS2)

**Sim** (`verify_sim_perf`, run alone, 6,000 people, 4 cores): PASS.

| Hour | Average per tick | Worst tick |
|------|------------------|------------|
| 03:00 | 0.37 ms | 2.6 ms |
| 08:00 (rush) | 2.17 ms | 8.7 ms |
| 11:00 | 1.98 ms | 14.8 ms |

**Drawing** (`shot_3d.gd --breakdown`, at the spawn point 5165, 3371):

- 585 draw calls, 1.49 M primitives in view, 3.54 M triangles loaded in 19 groups.
- People are by far the biggest layer: 2.70 M triangles (1,708 per person, 188 groups).
- City chunks are next: 0.50 M triangles (about 29,700 per chunk).
- Everything else (cars, palms, poles, clutter) adds up to under 0.35 M.

Limits of this baseline:
- No frame times. There is no graphics card in the cloud container, and `bench_3d.gd` (1,200 frames on the software renderer) ran past 15 minutes without finishing. Frame times need Phil's PC: bench_3d writes `bench_3d.txt` in the game's user folder.
- `--breakdown` measures before `--look`/`--hour` are applied, so the night and dense-apartment-block (975, 2925) runs gave the spawn numbers again. A Batch 0 fix: measure after moving the camera.

VS2 rule from here: every batch reports draw calls and triangles at the spawn point against these numbers, and the sim must stay within `verify_sim_perf`.

## After each batch

| Batch | Draw calls at the spawn | Primitives | Chunk build (7 chunks, average / worst) | `verify_sim_perf` |
|-------|-------------------------|------------|------------------------------------------|-------------------|
| before (Step 0) | 585 | 1.488 M | 1415-1449 / 1605-2012 ms (two runs) | PASS |
| 0 (shading, grade) | 589 | 1.491 M | same build | PASS |
| A (kerbs) | 591 | 1.477 M | 1262-1464 / 1533-2093 ms (three runs); kerb runs alone 64-76 ms | see below |
| B1 (placement) | 592 | 1.467 M | 3D view start-up 5.1-5.9 s against 5.4 s without B1 (same machine, same hour); Placement itself about 0.6 s once at a new game (hydrants), driveway items about 6 ms a district when a chunk first asks | not run (no sim change beyond parked-car spots) |

Chunk build times swing a lot from run to run on the shared cloud machine; the
kerb work itself costs about 70 ms of a chunk's 1.3-1.5 s, built off the main thread.

`verify_sim_perf` on 2026-11-18 (a new, slower cloud machine): Batch A failed it run
alone (rush hour 3.08 ms/tick, 337 ticks over 4 ms), and so did Batch 0 on the same
machine the same hour (3.14 ms/tick, 324 ticks over 4 ms); on 2026-11-17 Batch 0 passed
(2.17 ms/tick). Every hour slowed alike, 03:00 included, and the check runs the sim
only, which no VS2 batch touches: the machine, not the change. Judge it on a quiet machine.
