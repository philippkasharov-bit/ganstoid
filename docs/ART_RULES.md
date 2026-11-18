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

## Kerbs (VS2A)

`KerbRuns` works them out, `StreetDetail3D` draws them, `verify_kerbs` checks them.

| Rule | Value |
|------|-------|
| Which roads | main (`art`) and residential (`res`): the only ones with a sidewalk in the data |
| Shape | one continuous run per road edge, mitred at bends and across joins to the next road record |
| Street corner | a rounded return, radius 5 m (residential) or 8 m (arterial; the larger street wins), each street draws half; tighter if a third street is in the way |
| Driveway or lot entrance (service road, alley, aisle) | kerb dropped to 6 cm, 0.6 m sloped flare each side |
| Crosswalk ramp (`city.kerb_ramps`) | kerb flush with the road over the ramp width, 0.45 m flare, a darker grooved plate on the sidewalk (no yellow pads: 1990s) |
| Red kerb | 4.5 m either side of a hydrant (up to 5.5 m behind the kerb) |
| Meters | one per 6 m on arterials, never in a drop, a red stretch or near an end |
| Heights | `StreetLevels`: every flat street layer at its own height; kerb top 0.12 m |

## Placement (VS2B)

`Placement` (`core/city/placement.gd`) decides where a thing may stand; `verify_placement` checks it.
Order: hydrants, then driveway items, then parked cars. Every decision is seeded from
the thing's own anchor (its road, its driveway), so the street is the same whichever
chunk loads first, and saves rebuild the same cars.

| Kind | Where | Keeps clear of (m) |
|------|-------|--------------------|
| Hydrant | parkway, 0.5 m behind the kerb, every 90-120 m, sides alternating | carriageway 0.3, building 0.3, driveway 1.5, ramp 1.5, crosswalk 1.5, another hydrant 25 |
| Mailbox | beside 70% of driveways, 0.7 m past its edge | carriageway 0.3, driveway 0.5, ramp 0.8, crosswalk 1, hydrant 0.9, tree well 0.8, lamp 0.5, other items 0.6 |
| Bins (3) | beside 35% of driveways, the other side | as a mailbox; bins 0.7 apart |
| Parked car | kerb side, parallel, centre 1.2 m in from the kerb | hydrant 4.6, crosswalk and ramp 6, corner (another street) 6, driveway apron 2.9 (body 0.5 m clear), next car 0.5 end to end |

| Power pole (B2) | one side of residential streets, every 42 m | carriageway 0.4, building 0.3, driveway 1, ramp 1, crosswalk 1, hydrant 1, lamp 2 |
| Street tree (B2) | surveyed spots and house yards | carriageway 0.6, building 1, driveway 1, ramp and crosswalk 1, hydrant 1, lamp 1.5, pole 1.5, street corner 6 |
| Palm (B2) | tree wells | carriageway 0.3, building 0.5, driveway 0.8, ramp and crosswalk 0.8, hydrant 1, lamp 1.2, pole 1.2, street corner 6 |
| Street sign (B2) | the corner between a junction's first two legs | carriageway 0.5, building 0.3, driveway 0.8, ramp and crosswalk 0.6, hydrant 1, lamp 0.8, pole 0.8 |
| Graffiti (B2) | building walls and free-standing walls | never the wall with the front door |

A thing that breaks a rule slides along the kerb up to 4.5 m (cars 3 m) to a legal
spot, or is left out (trees and palms: left out). "Street corner" is the sight
triangle: nothing tall within 6 m of two streets' carriageways. Lamps and traffic
signals are the sim's (witnesses see by them) and stay put: everything else keeps
clear of them.

## Clusters (VS2B3)

Designed groups, not random scatter (`Clusters` picks and stands them, `ClusterProps3D`
draws them). At most 4 groups per 96 m block, the ones with the best hash, so the
pick never depends on build order. A required piece with no legal spot drops the
whole group. Pieces are `prop` (low) or `tall_prop` (also clear of street corners
and 2 m from doors) in Placement's rules, and keep clear of mailboxes and bins.

| Group | Anchor | Share | Pieces |
|-------|--------|-------|--------|
| Stoop | apartment front door | 45% | chairs, a crate, a trash bag |
| Corner store | shop door within 25 m of a junction | 70% | payphone, newspaper boxes, A-board |
| Laundromat | other shop doors | 8% | bench, laundry carts |
| Taco stand | other shop doors | 6% | cart, umbrella, cooler, chair |
| Car wash | big shop or industrial lot (over 900 m2) | 3% | tall sign, buckets |
| Bus stop | the map's bus stops | all | shelter, bench, trash bag |
| Car on blocks | a driveway | 6% | car shell on blocks, tyres |
| Alley dumpster | every 45 m along an alley | 55% | dumpster, pallet, trash bag |
| Shop dumpster | behind a shop (one per shop) | 25% | dumpster, pallet |
| Vacant lot | open lots, vacant land | all | mattress, tyres, trash, a crate |
| Construction | construction sites | all | chain-link panels, a work sign, a portable toilet |
| Court corner | sports pitches | all | hoop, bench, boombox |

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
