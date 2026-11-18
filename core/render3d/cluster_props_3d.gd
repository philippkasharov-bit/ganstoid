## VS2B3: draws the designed street groups (Clusters) into the chunk meshes,
## each piece a few boxes in 90s LA colours: stoop chairs and crates, a corner
## store's payphone and newspaper boxes, a laundromat bench, a taco cart under
## its umbrella, a car-wash sign, a bus shelter, a car on blocks, dumpsters
## and pallets, a vacant lot's mattress and tyres, a construction fence, a
## basketball hoop. Where they stand is Clusters' and Placement's call.
class_name ClusterProps3D
extends RefCounted

const CHAIRS := [Color("c9b38a"), Color("2f6b5a"), Color("b8452f"), Color("e1dccf")]
const PAPERS := [Color("2f5d9a"), Color("c9a32a"), Color("b8392e")]
const DUMPSTER := [Color("2f5a3c"), Color("2d4a7a")]
const RUST := Color("7a4a32")
const WOOD := Color("9a7b55")
const DARK := Color("232426")
const METAL := Color("8d9095")
const WHITE := Color("e6e3da")
const ORANGE := Color("e0742a")

static func add(m: CityMesh3D, city: CityData, centre: Vector2, r2: float) -> void:
	var groups := Clusters.of(Placement.of(city))
	for it in groups.near(centre, sqrt(r2)):
		if m.owns(it[2]):
			_piece(m, it[1], it[2], it[3], absi(hash(it[2])))

## One piece `kind` at `p`, facing `a` (radians), varied by `roll`.
static func _piece(m: CityMesh3D, kind: String, p: Vector2, a: float, roll: int) -> void:
	var f := Vector2.from_angle(a)   # out from the anchor
	match kind:
		"chair":
			var c: Color = CHAIRS[roll % CHAIRS.size()]
			CityDetail3D._box(m, p, Vector3(0.48, 0.45, 0.48), a, c)
			StreetClutter3D._raised(m, p - f * 0.2, Vector3(0.48, 0.45, 0.06), 0.45, a + PI * 0.5, c)   # the back
		"crate":
			CityDetail3D._box(m, p, Vector3(0.5, 0.35, 0.4), a, [Color("2f6fb0"), ORANGE, Color("3a8a4a")][roll % 3])
		"trash_bag":
			CityDetail3D._box(m, p, Vector3(0.55, 0.5, 0.5), a + 0.4, DARK)
		"bench":
			CityDetail3D._box(m, p, Vector3(1.7, 0.45, 0.45), a + PI * 0.5, WOOD)
			StreetClutter3D._raised(m, p - f * 0.2, Vector3(1.7, 0.4, 0.06), 0.45, a + PI * 0.5, WOOD.darkened(0.15))
		"payphone":
			CityDetail3D._box(m, p, Vector3(0.12, 1.2, 0.12), a, METAL)
			StreetClutter3D._raised(m, p, Vector3(0.45, 0.65, 0.3), 1.2, a, Color("3f6fa8"))
		"news_box":
			CityDetail3D._box(m, p, Vector3(0.5, 0.95, 0.45), a, PAPERS[roll % PAPERS.size()])
		"ad_board":
			CityDetail3D._box(m, p, Vector3(0.6, 1.0, 0.25), a + PI * 0.5, WHITE)
		"laundry_cart":
			CityDetail3D._box(m, p, Vector3(0.7, 0.85, 0.5), a, METAL.lightened(0.2))
		"cart":
			CityDetail3D._box(m, p, Vector3(1.7, 1.0, 0.85), a + PI * 0.5, WHITE)
			StreetClutter3D._raised(m, p, Vector3(1.75, 0.08, 0.9), 1.0, a + PI * 0.5, Color("b8392e"))
		"umbrella":
			CityDetail3D._box(m, p, Vector3(0.06, 2.1, 0.06), a, METAL)
			StreetClutter3D._raised(m, p, Vector3(2.1, 0.12, 2.1), 2.1, a, [Color("d9b03a"), Color("2f8a5a"), Color("c94a3a")][roll % 3])
		"cooler":
			CityDetail3D._box(m, p, Vector3(0.6, 0.45, 0.4), a, Color("2f6fb0"))
		"tall_sign":
			CityDetail3D._box(m, p, Vector3(0.18, 4.2, 0.18), a, METAL)
			StreetClutter3D._raised(m, p, Vector3(2.6, 1.0, 0.15), 4.2, a + PI * 0.5, Color("2f8ac0"))
		"bucket":
			CityDetail3D._box(m, p, Vector3(0.32, 0.38, 0.32), a, ORANGE)
		"shelter":
			var side := f.orthogonal()
			for s in [-1.4, 1.4]:
				CityDetail3D._box(m, p + side * s - f * 0.6, Vector3(0.08, 2.4, 0.08), a, METAL)
			StreetClutter3D._raised(m, p - f * 0.6, Vector3(0.05, 1.8, 3.0), 0.4, a, Color("bcd2d8"))   # the back glass
			StreetClutter3D._raised(m, p, Vector3(1.5, 0.08, 3.1), 2.4, a, METAL.darkened(0.2))   # the roof
		"car_shell":
			var c2: Color = [Color("7a3b2e"), Color("3a4a6a"), Color("6a6a60")][roll % 3]
			for s in [Vector2(1.5, 0.75), Vector2(1.5, -0.75), Vector2(-1.5, 0.75), Vector2(-1.5, -0.75)]:
				CityDetail3D._box(m, p + f * s.x + f.orthogonal() * s.y, Vector3(0.3, 0.3, 0.3), a, Color("8a8478"))   # cinder blocks
			StreetClutter3D._raised(m, p, Vector3(4.3, 0.75, 1.75), 0.3, a, c2)
			StreetClutter3D._raised(m, p - f * 0.3, Vector3(2.2, 0.55, 1.6), 1.05, a, c2.darkened(0.15))   # the cab
		"tire":
			CityDetail3D._box(m, p, Vector3(0.62, 0.22, 0.62), a, DARK)
		"dumpster":
			CityDetail3D._box(m, p, Vector3(1.9, 1.25, 1.15), a + PI * 0.5, DUMPSTER[roll % DUMPSTER.size()])
			StreetClutter3D._raised(m, p, Vector3(1.95, 0.06, 1.2), 1.25, a + PI * 0.5, DARK)
		"pallet":
			CityDetail3D._box(m, p, Vector3(1.2, 0.14, 1.0), a, WOOD)
		"mattress":
			CityDetail3D._box(m, p, Vector3(1.9, 0.22, 0.95), a, Color("d8cfb8"))
		"fence_panel":
			CityDetail3D._box(m, p, Vector3(2.4, 1.8, 0.05), a + PI * 0.5, METAL.lightened(0.1))
		"work_sign":
			CityDetail3D._box(m, p, Vector3(0.06, 1.0, 0.06), a, METAL)
			StreetClutter3D._raised(m, p, Vector3(0.6, 0.6, 0.04), 1.0, a + PI * 0.5, ORANGE)
		"toilet":
			CityDetail3D._box(m, p, Vector3(1.1, 2.3, 1.1), a, Color("2f6fb0"))
		"hoop":
			CityDetail3D._box(m, p, Vector3(0.12, 3.05, 0.12), a, METAL)
			StreetClutter3D._raised(m, p + f * 0.4, Vector3(1.8, 1.05, 0.05), 2.9, a + PI * 0.5, WHITE)
			StreetClutter3D._raised(m, p + f * 0.7, Vector3(0.45, 0.04, 0.45), 3.05, a, ORANGE)   # the rim
		"boombox":
			CityDetail3D._box(m, p, Vector3(0.6, 0.3, 0.2), a, METAL.darkened(0.3))
