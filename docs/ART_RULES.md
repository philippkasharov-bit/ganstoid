# Art rules (VS2)

The look every street batch must match. Written in VS2 Batch 0 from the golden
block and the reference pictures in `art/reference/`. If a later batch needs to
break a rule, change it here in the same commit and say why.

## The golden block

- **Homes:** the block round map point (5206, 3392), one street east of the spawn (album `3d_poor_block`, `3d_golden_dusk`).
- **Shops:** the row of shops round (5140, 3550), about 180 m south of the spawn (album `3d_golden_shops`).
- Shot with `debug/shot_3d.gd -- --look=<x,y> --size=40 --hour=<6.5|12|19|22>`. Every street batch re-shoots these four hours and compares them.

## Target (from the references)

1990s working-class Los Angeles at a high camera: sun-bleached, dusty, a little smog, warm.
- Stucco in pale warm colours (cream, sand, salmon, pale green), never saturated.
- Grey concrete sidewalks with slab joints, sun-bleached asphalt, dry grass strips.
- Things sit **on** the ground: a soft dark band at every wall foot.
- Night is moody but readable: warm sodium pools, a faint blue sky glow, lit windows. Never pitch black.

## Palette (where the colours live)

| What | Where in the code |
|------|-------------------|
| Asphalt (one colour for every driven road) | `CityMesh3D.ASPHALT` `#777671` |
| Sidewalk | `CityMesh3D.SIDEWALK` `#cbc7be` |
| Ground by area | `CityMesh3D.AREA_COL` |
| Walls and roofs by kind | `BuildingMesh3D.PALETTES`, `ROOF_TILE`, `ROOF_SHINGLE`, `ROOF_FLAT`, `SPANISH_WALLS` |
| Yards, lots, walls and fences | `CityDetail3D.YARDS`, `LOT_COL`, `BARRIER` |
| Surface grain (stucco, brick, asphalt, ...) | `SurfaceDetail` (strength per material) |

Rules: a new surface takes its colour from these tables, not a new hex code in a
new place. Wall colours stay pale (lightness above about 0.6); saturated colour
is for small things that should catch the eye: doors, shop awnings, gang colours,
graffiti, loot.

## Wear

- A worn house (poor block, `BuildingMesh3D.WORN_BELOW`) uses `STUCCO_WORN`; the poorest also get window bars.
- Roads: wear and patches come from `StreetDetail3D` and the asphalt grain. Batch C adds stains, patches and repairs, and removes the visible repeat (BUG-30).
- Never more wear than the references show: dusty and patched, not ruined.

## Contact shading (baked, VS2-0)

`ContactAO3D`: a multiply band on the ground, built with each chunk.

| Where | Reach | Darkest |
|-------|-------|---------|
| Building foot | 1.3 m | 0.56 |
| Wall, fence or hedge foot (both sides) | 0.55 m | 0.74 |

The walls themselves darken near the ground in the city shader (`Cutaway`, `contact`).
On Forward+ (Phil's PC), SSAO adds to both. A new kind of thing that stands on
the ground (a dumpster, a bus shelter) gets a band too.

## Colour grade by time of day (VS2-0)

`DayNight3D.GRADES`, blended by the hour: a 1D grading curve (shadow, mid,
highlight), contrast, saturation, and distance haze.

| Hour | Shadows | Highlights | Feel | Haze |
|------|---------|------------|------|------|
| night (21-5) | deep blue, lifted to 0.06-0.15 | warm (lamp light); mid-tones neutral, so sodium pools stay orange | moody, less colour (0.92) | blue-grey, 0.30 |
| dawn (6.5) | violet | warm peach | soft | peach, 0.24 |
| noon (9-16) | cool | warm, capped below white | contrast 1.22 | sandy smog, 0.15 |
| dusk (19) | violet | orange | most colour (1.1) | orange, 0.26 |

Rules: never pure black (shadows at least 0.035 by day, about 0.06-0.15 blue at night) and never pure white
(highlights at most about 0.98). The haze starts 230 m from the camera, so it
only shows towards the top of a zoomed-out view.

## Readability (VS2-0)

`debug/shot_3d.gd --grey` and `--half` (album `3d_grey`, `3d_grey_half`). In grey and at half size:
- doors, people, cars and loot must still stand out from walls and ground by brightness alone;
- a gang's colour must not be the only way to tell its members (they also differ by clothes or shape);
- if something disappears in grey, give it more contrast in brightness, not more colour.

## Speed

Every addition says what it costs (draw calls and triangles at the spawn, against `docs/VS2_AUDIT.md`).
Detail is baked into the chunk mesh or drawn as one MultiMesh per kind, never one node per object.
