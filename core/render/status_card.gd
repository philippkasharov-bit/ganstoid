## UI2/UI6: the always-on status card (top left): money, rank, heat, what is
## in your hand, money split and turf. Needs show as moodles on the right and
## the clock top-right (Zomboid layout). Read-only.
class_name StatusCard
extends PanelContainer

const HEAT_COLORS := [Color("6fbf73"), Color("e8c547"), Color("e8913a"), Color("e0533d"), Color("b0203a")]
var _world: World
var _top := Label.new()
var _mid := Label.new()
var _bottom := Label.new()
var _left := 0.0

func setup(world: World) -> void:
	_world = world
	position = Vector2(12, 10)
	add_theme_stylebox_override("panel", UiPanel.card_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	for l in [_top, _mid, _bottom]:
		l.add_theme_color_override("font_color", UiPanel.TEXT)
	_top.add_theme_font_size_override("font_size", 18)
	_top.add_theme_font_override("font", UiTheme.font("bungee"))
	_mid.add_theme_font_size_override("font_size", 14)
	_bottom.add_theme_font_size_override("font_size", 13)
	_bottom.add_theme_color_override("font_color", UiPanel.DIM)
	box.add_child(_top)
	box.add_child(_mid)
	box.add_child(_bottom)
	visible = false

func _process(delta: float) -> void:
	_left -= delta
	if _world == null or _left > 0.0:
		return
	_left = 0.25
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var ready := SimNav.active != null and SimNav.active.is_ready()
	visible = player != null and ready and not player.get_component(ComponentNames.NPC).is_down and GameRules.of(_world) != null   # O1: hidden until the new-game choice
	if visible and player.get_component(ComponentNames.PLAYER_STATE).prison_until_tick > 0:
		var left: int = player.get_component(ComponentNames.PLAYER_STATE).prison_until_tick - _world.tick
		_top.text = "IN PRISON"
		_mid.text = "%.1f days left (time runs fast)" % (float(left) / SimClock.day_ticks)
		return
	if not visible:
		return
	var npc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	_top.text = "$%d   ·   %s" % [npc.cash, RankSystem.name_of(state.rank)]
	if state.work_until_tick > 0:
		_top.text += "   ·   AT WORK"
	_top.add_theme_color_override("font_color", UiPanel.ACCENT)
	var heat := clampi(state.law_tier, 0, HEAT_COLORS.size() - 1)
	_mid.text = "Heat: %s   ·   %s%s%s" % [String(GanstoidEnums.LawTier.keys()[state.law_tier]).capitalize(), String(state.weapon).capitalize(), " (%d)" % state.ammo if state.weapon == &"pistol" else "", "   ·   BLEEDING" if npc.bleeding else ""]
	_mid.add_theme_color_override("font_color", HEAT_COLORS[heat] if not npc.bleeding else Color("e0533d"))
	var clean := npc.cash - state.dirty_cash
	if state.case_evidence > 0.0:
		_mid.text += "   ·   Case %d%s" % [roundi(state.case_evidence), " WARRANT" if state.case_evidence >= CaseSystem.WARRANT_AT else ""]
	if not state.job.is_empty():
		_mid.text += "   ·   JOB: %s" % state.job["text"]
	_bottom.text = "%sclean $%d / dirty $%d   ·   %s" % ["ASLEEP   ·   " if state.sleeping else "", clean, state.dirty_cash, _turf(npc)]

func _turf(npc: NPCData) -> String:
	var t := TerritorySystem.data(_world)
	if t == null:
		return ""
	var owner := TerritorySystem.controller(t, TerritoryData.cell_of(npc.position))
	if owner == &"":
		return "nobody's block"
	if owner == TerritorySystem.PLAYER:
		return "YOUR block"
	var e: Entity = _world.entities.get(owner)
	return (e.get_component(ComponentNames.GANG).display_name if e != null else String(owner)) + " turf"
