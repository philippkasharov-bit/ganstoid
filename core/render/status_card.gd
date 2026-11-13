## UI2/UI21: the always-on status card (top left), one plain style: a column
## of "label  value" rows, labels dim, values white, all the same size, no
## colour coding (bleeding and needs live in the right-hand column). Rows:
## cash, rank, turf (heat lives in the Wanted moodle, the hand in the hotbar), plus case / job / asleep / at work / prison
## while they apply. Read-only.
class_name StatusCard
extends PanelContainer

const REFRESH_S := 0.25

var _world: World
var _grid := GridContainer.new()
var _left := 0.0
var _key := ""

func setup(world: World) -> void:
	_world = world
	position = Vector2(UiTheme.MARGIN, UiTheme.MARGIN)   # UI25: one margin all round
	add_theme_stylebox_override("panel", UiPanel.card_style())
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 0)
	add_child(_grid)
	visible = false

func _process(delta: float) -> void:
	_left -= delta
	if _world == null or _left > 0.0:
		return
	_left = REFRESH_S
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var ready := SimNav.active != null and SimNav.active.is_ready()
	visible = player != null and ready and not player.get_component(ComponentNames.NPC).is_down and GameRules.of(_world) != null   # O1: hidden until the new-game choice
	if not visible:
		return
	var rows := _rows(player.get_component(ComponentNames.NPC), player.get_component(ComponentNames.PLAYER_STATE))
	var key := str(rows)
	if key != _key:
		_key = key
		_show(rows)

## [label, value] pairs, in order.
func _rows(npc: NPCData, state: PlayerStateData) -> Array:
	if state.prison_until_tick > 0:
		return [["Status", "In prison"], ["Days left", "%.1f" % (float(state.prison_until_tick - _world.tick) / SimClock.day_ticks)]]
	var out: Array = [["Cash", "$%d  (dirty $%d)" % [npc.cash, state.dirty_cash]], ["Rank", RankSystem.name_of(state.rank)],
		["Turf", _turf(npc)]]
	if state.case_evidence > 0.0:
		out.append(["Case", "%d%s" % [roundi(state.case_evidence), "  warrant" if state.case_evidence >= CaseSystem.WARRANT_AT else ""]])
	if not state.job.is_empty():
		out.append(["Job", state.job["text"]])
	if state.sleeping or state.work_until_tick > 0:
		out.append(["Status", "Asleep" if state.sleeping else "At work"])
	return out

func _show(rows: Array) -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for r in rows:
		_grid.add_child(UiTheme.label(r[0], UiTheme.FONT_SMALL, UiTheme.DIM))
		_grid.add_child(UiTheme.label(r[1], UiTheme.FONT_SMALL, UiTheme.TEXT))

func _turf(npc: NPCData) -> String:
	var t := TerritorySystem.data(_world)
	if t == null:
		return "-"
	var owner := TerritorySystem.controller(t, TerritoryData.cell_of(npc.position))
	if owner == &"":
		return "Nobody's block"
	if owner == TerritorySystem.PLAYER:
		return "Your block"
	var e: Entity = _world.entities.get(owner)
	return (e.get_component(ComponentNames.GANG).display_name if e != null else String(owner)) + " turf"
