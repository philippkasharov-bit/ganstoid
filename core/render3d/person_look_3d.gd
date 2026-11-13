## R3D3/R3D15: how a box person looks in 3D: shirt by role (you, cops,
## dealers, fixers; everyone else a muted colour from their id), skin from
## their id, and the faint see-through figure of you behind walls.
class_name PersonLook3D
extends RefCounted

const SKIN := [Color("f1c7a5"), Color("d9a77f"), Color("b07a52"), Color("8a5a3b"), Color("5e3d2a")]
const SHIRTS := [Color("4a5568"), Color("7b8794"), Color("9c4a3c"), Color("3e6a5a"), Color("b8a68a"), Color("2f3b52"), Color("e2ddd2"), Color("6b4f7a")]

static func skin(id: StringName) -> Color:
	return SKIN[absi(String(id).hash()) % SKIN.size()]

static func shirt(e: Entity, npc: NPCData) -> Color:
	if e.has_component(ComponentNames.PLAYER_STATE):
		return EntityVisualFactory.PLAYER_COLOR
	if npc.is_cop:
		return Color("2c3e66")   # navy uniform
	if npc.is_dealer:
		return EntityVisualFactory.DEALER_COLOR
	if npc.is_fixer:
		return Color(0.75, 0.5, 0.95)
	return SHIRTS[absi(String(npc.id).hash()) % SHIRTS.size()]

static func silhouette() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 1.85, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true   # drawn over whatever stands in front
	mat.albedo_color = Color(EntityVisualFactory.PLAYER_COLOR, 0.28)
	mat.render_priority = 1
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi
