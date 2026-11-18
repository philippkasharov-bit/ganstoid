## G4: what people leave out on an LA street. Beside most driveways a
## curbside mailbox on a post, and on many the household's three wheelie
## bins (black trash, blue recycling, green yard waste) waiting for pick-up;
## chain-link fences get their posts and top rail; every signalled or
## stop-sign corner a green street-name sign. Baked into the chunk meshes.
## VS2B: where mailboxes, bins and hydrants stand is Placement's call; this
## only draws them.
class_name StreetClutter3D
extends RefCounted

const BINS := [Color("2b2d2f"), Color("2f5d9a"), Color("3f7a3a")]
const POST := Color("5a5f63")
const MAILBOX := Color("d9d8d2")
const FENCE_POST := Color("7b8085")
const FENCE_EVERY := 2.4
const SIGN := Color("1f6b3a")
const SIGN_POLE := Color("8d9095")
const HYDRANT := Color("d6452f")

## Mailboxes, bins, fence posts and street signs within sqrt(r2) of `centre`.
static func add(m: CityMesh3D, city: CityData, real: CityReal, centre: Vector2, r2: float) -> void:
	var place := Placement.of(city)
	var reach := sqrt(r2)
	for it in place.near("mailbox", centre, reach):
		if m.owns(it[0]):
			CityDetail3D._box(m, it[0], Vector3(0.08, 1.0, 0.08), it[1], POST)
			_raised(m, it[0], Vector3(0.48, 0.24, 0.22), 1.0, it[1], MAILBOX)
	for it in place.near("bin", centre, reach):
		if m.owns(it[0]):
			CityDetail3D._box(m, it[0], Vector3(0.62, 1.05, 0.72), it[1], BINS[int(it[2]) % BINS.size()])
			_raised(m, it[0], Vector3(0.66, 0.05, 0.76), 1.05, it[1], BINS[int(it[2]) % BINS.size()].darkened(0.3))   # the lid
	for it in place.near("hydrant", centre, reach):
		if m.owns(it[0]):
			CityDetail3D._box(m, it[0], Vector3(0.3, 0.75, 0.3), it[1], HYDRANT)
	for b in real.barriers:
		if b["kind"] == "fence" and CityMesh3D._near(b["pts"], centre, r2):
			_fence(m, b["pts"])
	for x in CityDetail3D._junctions().near(centre, sqrt(r2)):
		_street_sign(m, x, RoadSpace.of(city))

## A box of `size` whose bottom is at `y`: the mailbox on its post, a bin's lid.
static func _raised(m: CityMesh3D, p: Vector2, size: Vector3, y: float, angle: float, col: Color) -> void:
	var x := Vector2.from_angle(angle) * size.x * 0.5
	var z := Vector2.from_angle(angle).orthogonal() * size.z * 0.5
	var c := [p - x - z, p + x - z, p + x + z, p - x + z]
	var st := m._tool(p)
	for i in 4:
		var a: Vector2 = c[i]
		var b: Vector2 = c[(i + 1) % 4]
		var e := b - a
		m._quad(st, [m._v(a, y), m._v(b, y), m._v(b, y + size.y), m._v(a, y + size.y)], Vector3(e.y, 0, -e.x).normalized(), col.darkened(0.06 * (i % 2)))
	m._quad(st, [m._v(c[0], y + size.y), m._v(c[1], y + size.y), m._v(c[2], y + size.y), m._v(c[3], y + size.y)], Vector3.UP, col.lightened(0.06))

## Chain-link: a post every FENCE_EVERY metres and a rail along the top.
static func _fence(m: CityMesh3D, pts: PackedVector2Array) -> void:
	var run := 0.0
	for i in pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var length := seg.length()
		if length < 0.05:
			continue
		while run <= length:
			CityDetail3D._box(m, pts[i] + seg * (run / length), Vector3(0.07, 1.55, 0.07), 0.0, FENCE_POST)
			run += FENCE_EVERY
		run -= length
		_raised(m, (pts[i] + pts[i + 1]) * 0.5, Vector3(length, 0.06, 0.06), 1.42, seg.angle(), FENCE_POST)

## A green street-name sign on the corner between a junction's first two legs.
static func _street_sign(m: CityMesh3D, x: Dictionary, space: RoadSpace) -> void:
	var legs: Array = x["legs"]
	if legs.size() < 2:
		return
	var a: Vector2 = legs[0][0]
	var b: Vector2 = legs[1][0]
	var corner := (a + b).normalized() if (a + b).length() > 0.1 else a.orthogonal()
	var at: Vector2 = space.clear(x["c"] + corner * (maxf(legs[0][1], legs[1][1]) * 0.5 + 2.2), 0.6)
	CityDetail3D._box(m, at, Vector3(0.07, 3.1, 0.07), 0.0, SIGN_POLE)
	_raised(m, at + a * 0.45, Vector3(0.9, 0.2, 0.03), 2.75, a.angle(), SIGN)
	_raised(m, at + b * 0.45, Vector3(0.9, 0.2, 0.03), 2.98, b.angle(), SIGN)
