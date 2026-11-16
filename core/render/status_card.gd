## UI2 (was UI2/UI21's plain rows): the status card, top left, read in one
## glance: your cash big (counting up or down as it changes), your rank with a
## bar to the next one, then the small print: hood, block, the street's mood,
## and case / job / asleep / at work while they apply. Read-only.
class_name StatusCard
extends PanelContainer

const REFRESH_S := 0.25
const RANK_EVERY_S := 2.0      # the rank score walks your businesses: not every frame
const COUNT_PER_S := 6.0       # A4: closes the gap this many times a second
const BAR_W := 150.0

var _world: World
var _cash := UiTheme.label("", 24, UiTheme.TEXT)
var _dirty := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.DIM)
var _rank := UiTheme.label("", 15, UiTheme.ACCENT)
var _points := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.DIM)
var _bar := ColorRect.new()
var _fill := ColorRect.new()
var _grid := GridContainer.new()
var _left := 0.0
var _rank_left := 0.0
var _key := ""
var _shown_cash := -1.0
var _shown_dirty := 0.0

func setup(world: World) -> void:
	_world = world
	position = Vector2(UiTheme.MARGIN, UiTheme.MARGIN)
	add_theme_stylebox_override("panel", UiPanel.card_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	add_child(col)
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 8)
	_cash.add_theme_font_override("font", UiTheme.font("bungee"))
	money.add_child(_cash)
	_dirty.size_flags_vertical = Control.SIZE_SHRINK_END
	money.add_child(_dirty)
	col.add_child(money)
	var rank := HBoxContainer.new()
	rank.add_theme_constant_override("separation", 8)
	_rank.add_theme_font_override("font", UiTheme.font("marker"))
	rank.add_child(_rank)
	_points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank.add_child(_points)
	col.add_child(rank)
	_bar.color = Color(1, 1, 1, 0.1)
	_bar.custom_minimum_size = Vector2(BAR_W, 4)
	_fill.color = UiTheme.ACCENT
	_fill.size = Vector2(0, 4)
	_bar.add_child(_fill)
	col.add_child(_bar)
	col.add_child(UiTheme.divider())
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 0)
	col.add_child(_grid)
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
	var npc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	_rank_left -= REFRESH_S
	if _rank_left <= 0.0:
		_rank_left = RANK_EVERY_S
		_show_rank(npc, state)
	var rows := _rows(npc, state)
	var key := str(rows)
	if key != _key:
		_key = key
		_show(rows)

## The rank and how far to the next one.
func _show_rank(npc: NPCData, state: PlayerStateData) -> void:
	_rank.text = RankSystem.name_of(state.rank)
	var last := state.rank >= RankSystem.THRESHOLDS.size() - 1
	if last:
		_points.text = "top of the city"
		_fill.size.x = BAR_W
		return
	var pts := RankSystem.score(_world, npc, state)
	var lo: int = RankSystem.THRESHOLDS[state.rank]
	var hi: int = RankSystem.THRESHOLDS[state.rank + 1]
	_points.text = "%d / %d to %s" % [pts, hi, RankSystem.name_of(state.rank + 1)]
	_fill.size.x = BAR_W * clampf(float(pts - lo) / float(maxi(1, hi - lo)), 0.0, 1.0)

## The small print: [label, value] pairs, in order.
func _rows(npc: NPCData, state: PlayerStateData) -> Array:
	if state.prison_until_tick > 0:
		return [["Status", "In prison"], ["Days left", "%.1f" % (float(state.prison_until_tick - _world.tick) / SimClock.day_ticks)]]
	var out: Array = [["Hood", _hood(npc)], ["Block", _turf(npc)], ["Street", EconomyRead.block(BlockEconomyData.block_at(_world, npc.position))]]   # E5
	if state.case_evidence > 0.0:
		out.append(["Case", "%d%s" % [roundi(state.case_evidence), "  WARRANT" if state.case_evidence >= CaseSystem.WARRANT_AT else ""]])
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
		var warn: bool = r[0] == "Case" and String(r[1]).contains("WARRANT")
		_grid.add_child(UiTheme.label(r[1], UiTheme.FONT_SMALL, UiTheme.BAD if warn else UiTheme.TEXT))
	reset_size()

## A4: the cash number runs up (green) or down (red) to the new amount.
func _count_cash(delta: float) -> void:
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if player == null:
		return
	var real := float(player.get_component(ComponentNames.NPC).cash)
	var dirty := float(player.get_component(ComponentNames.PLAYER_STATE).dirty_cash)
	if _shown_cash < 0.0:
		_shown_cash = real
		_shown_dirty = dirty
	var gap := real - _shown_cash
	_shown_cash = real if absf(gap) < 0.5 else _shown_cash + gap * minf(1.0, COUNT_PER_S * delta) + signf(gap) * 0.5
	_shown_dirty = move_toward(_shown_dirty, dirty, maxf(1.0, absf(dirty - _shown_dirty) * COUNT_PER_S * delta))
	_cash.text = "$%d" % roundi(_shown_cash)
	_dirty.text = "dirty $%d" % roundi(_shown_dirty) if _shown_dirty >= 0.5 else "all clean"
	_cash.add_theme_color_override("font_color", UiTheme.TEXT if absf(gap) < 0.5 else (UiTheme.GOOD if gap > 0.0 else UiTheme.BAD))

## T1: the hood and district you are in ("Pico Gardens · Boyle Heights").
static func _hood(npc: NPCData) -> String:
	var h := Hoods.data()
	var k := TerritoryData.turf_of(npc.position)
	if h == null or not (Hoods.is_block(k) or Hoods.is_street(k)):
		return "-"
	return "%s · %s" % [h.hood_of(k), h.district_of(k)]

## T3: the block you are on (the capture point) and who holds it ("Daly & Main · nobody's").
func _turf(npc: NPCData) -> String:
	var t := TerritorySystem.data(_world)
	if t == null:
		return "-"
	var c := TerritoryData.turf_of(npc.position)
	var owner := TerritorySystem.controller(t, c)
	var block: String = Hoods.data().name_of(c) if Hoods.data() != null and (Hoods.is_block(c) or Hoods.is_street(c)) else "This block"
	if owner == &"":
		return "%s · nobody's" % block
	if owner == TerritorySystem.PLAYER:
		return "%s · yours" % block
	var e: Entity = _world.entities.get(owner)
	return "%s · %s" % [block, e.get_component(ComponentNames.GANG).display_name if e != null else String(owner)]
