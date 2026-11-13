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
var _cash_label: Label        # A4: the cash value, counted toward the real number
var _shown_cash := -1.0
var _shown_dirty := 0.0
const COUNT_PER_S := 6.0      # closes the gap this many times a second (fast at first, then settles)

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
	_count_cash(delta)
	_left -= delta
	if _world == null or _left > 0.0:
		return
	_left = REFRESH_S
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var ready := SimNav.active != null and SimNav.active.usable()
	visible = player != null and ready and not player.get_component(ComponentNames.NPC).is_down and GameRules.of(_world) != null   # O1: hidden until the new-game choice
	if not visible:
		return
	var rows := _rows(player.get_component(ComponentNames.NPC), player.get_component(ComponentNames.PLAYER_STATE))
	var key := str(rows.slice(1)) + str(rows[0][0])   # A4: cash moves on its own, without a rebuild
	if key != _key:
		_key = key
		_show(rows)

## [label, value] pairs, in order.
func _rows(npc: NPCData, state: PlayerStateData) -> Array:
	if state.prison_until_tick > 0:
		return [["Status", "In prison"], ["Days left", "%.1f" % (float(state.prison_until_tick - _world.tick) / SimClock.day_ticks)]]
	var out: Array = [["Cash", "$%d  (dirty $%d)" % [npc.cash, state.dirty_cash]], ["Rank", RankSystem.name_of(state.rank)],
		["Turf", _turf(npc)], ["Block", EconomyRead.block(BlockEconomyData.block_at(_world, npc.position))]]   # E5
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
	_cash_label = null
	for r in rows:
		_grid.add_child(UiTheme.label(r[0], UiTheme.FONT_SMALL, UiTheme.DIM))
		var v := UiTheme.label(r[1], UiTheme.FONT_SMALL, UiTheme.TEXT)
		_grid.add_child(v)
		if r[0] == "Cash":
			_cash_label = v

## A4: the cash number runs up (green) or down (red) to the new amount.
func _count_cash(delta: float) -> void:
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if player == null or _cash_label == null:
		return
	var real := float(player.get_component(ComponentNames.NPC).cash)
	var dirty := float(player.get_component(ComponentNames.PLAYER_STATE).dirty_cash)
	if _shown_cash < 0.0:
		_shown_cash = real
		_shown_dirty = dirty
	var gap := real - _shown_cash
	_shown_cash = real if absf(gap) < 0.5 else _shown_cash + gap * minf(1.0, COUNT_PER_S * delta) + signf(gap) * 0.5
	_shown_dirty = move_toward(_shown_dirty, dirty, maxf(1.0, absf(dirty - _shown_dirty) * COUNT_PER_S * delta))
	_cash_label.text = "$%d  (dirty $%d)" % [roundi(_shown_cash), roundi(_shown_dirty)]
	_cash_label.add_theme_color_override("font_color", UiTheme.TEXT if absf(gap) < 0.5 else (UiTheme.GOOD if gap > 0.0 else UiTheme.BAD))

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
