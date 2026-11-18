## VS2A: every flat layer of the street at its own height, lowest first, so no
## two layers share a height and flicker (z-fight). Heights are metres above
## the ground plane. verify_kerbs checks they are all different and in order.
class_name StreetLevels
extends RefCounted

const GROUND := 0.005      # areas: parks, hills, downtown ground
const LOT := 0.008         # yards and lots (CityDetail3D)
const SURFACE := 0.012     # mapped paved areas (CityDetail3D)
const SIDEWALK := 0.02     # the sidewalk band along a road
const RAMP := 0.026        # a crosswalk ramp's tactile plate, on the sidewalk
const APRON := 0.03        # a driveway apron across the sidewalk (CityDetail3D)
const PATH := 0.035        # footpaths and driveways: under the asphalt
const ROAD := 0.04         # every driven road
const GUTTER := 0.041      # the concrete gutter band inside the kerb
const WEAR := 0.042        # patches, tar snakes, covers (RoadWear3D adds up to 0.002)
const STRIPE := 0.045      # zebra crossings
const PAINT := 0.047       # lane paint
const LINE := 0.05         # the double-yellow centre line
const SHADE := 0.06        # contact shading (ContactAO3D)
const KERB_LOW := 0.06     # a kerb dropped at a driveway or lot entrance
const KERB := 0.12         # the kerb top

## The flat layers in order (the kerb tops stand up and are left out).
const ORDER := [GROUND, LOT, SURFACE, SIDEWALK, RAMP, APRON, PATH, ROAD, GUTTER, WEAR, STRIPE, PAINT, LINE, SHADE]
