## Data contract for state that exists exactly once in the sim — the player's
## escalation standing. Split out of NPCData (hardening pass): law_tier and
## beef_tiers used to live on every NPC with a doc comment saying "only
## meaningful for the player character" — meaning every civilian, cop, and
## crew member in the city was paying for a Dictionary allocation and two
## fields that only one entity would ever use. Same mistake class as the
## pre-hardening witness-memory log, just on the data-contract side instead
## of the system side.
##
## The player entity is composed as NPCData (shared physical/survival state
## — position, hunger, cash) + this (player-exclusive escalation state), not
## a replacement for NPCData. Any future system that needs "the player"
## finds them via World.get_entities_with_component(ComponentNames.PLAYER_STATE)
## — exactly one match, by construction — rather than a hardcoded id.
class_name PlayerStateData
extends Resource

## Criminal Record Ladder tier (law track). See roadmap Phase 4.
@export var law_tier: GanstoidEnums.LawTier = GanstoidEnums.LawTier.CLEAN

## World.tick of the last escalation (rise, not decay) of law_tier. Required
## to compute the locked "decay pauses and resets on any tier-3+ trigger"
## rule at all — without a timestamp there's nothing to measure the pause
## window against. EscalationTickSystem (Phase 4) is the only writer.
@export var law_tier_last_escalation_tick: int = 0

## Beef Ladder tier (rival gang track), per-faction. faction_id (StringName,
## matches GangData.id) -> GanstoidEnums.BeefTier.
@export var beef_tiers: Dictionary = {}

## Same pause-on-escalation timestamp as law_tier_last_escalation_tick, kept
## per-faction since each gang's beef track decays independently.
## faction_id (StringName) -> int (World.tick).
@export var beef_tier_last_escalation_ticks: Dictionary = {}

## good_id (StringName, matches EconomyItemData.good_id) -> quantity held.
## Player-only, same reasoning as the rest of this file -- an NPC dealer
## sells from the market's abstract stock (World.economy_items), not from
## a bag of their own, so they need no inventory of their own to track.
@export var inventory: Dictionary = {}
## INV1: where each pile sits in the bag grid: [{id, x, y, r (rotated), n}].
## inventory stays the count of record; BagGrid keeps this in step with it.
@export var bag: Array = []
## INV4: piles you dropped on the street: [{id, n, pos}]. Saved with the game.
@export var ground: Array = []

## Phase 2 batch 8 (locked): the player's standing with each gang (keyed
## by GangData.id) and with each unaffiliated "solo" dealer (keyed by
## NPCData.id), 0.0-1.0, read by DealSystem to give friendly contacts a
## price edge -- same shape and same 0.5-is-neutral convention as
## EconomyItemData.player_market_reputation, just scoped to WHO you're
## dealing with instead of WHAT good. Two separate dictionaries, not one
## keyed by "gang id or npc id, whichever applies," because a gang-wide
## standing and one specific solo's standing are genuinely different
## things: befriending one member of a gang should read on every member
## of that gang, but there's no faction to generalize a solo's trust to.
## Missing keys read as 0.5 (neutral/no history yet) via .get(key, 0.5) at
## every call site -- never backfilled with explicit 0.5 entries, so an
## untouched dictionary stays empty rather than growing one entry per
## dealer/gang in the city whether the player ever met them or not.
@export var gang_standing: Dictionary = {}
@export var solo_standing: Dictionary = {}

## Batch 11: an in-progress drug-deal handoff ({} when none). Keys:
## dealer_id, good_id, kind ("buy"/"sell"), ticks_left. While set, the
## player can't move and the dealer stands still -- see DealSystem.
@export var pending_deal: Dictionary = {}

## Batch 14: the latest street-voice line (StreetTalk) for the HUD, plus a
## counter bumped on every new line so the HUD re-shows a repeated message.
@export var last_message: String = ""
@export var message_serial: int = 0

## Batch 15: ids of NPCs in the player's crew (each also has
## NPCData.is_crew set). Capped by CrewSystem.MAX_CREW.
@export var crew_ids: Array[StringName] = []

## Batch 24: how much of the player's NPCData.cash is dirty (crime money).
## Clean = cash - dirty_cash. See Wallet.
@export var dirty_cash: int = 0

## Combat (C1). Mouse aim like Project Zomboid: the body faces the cursor, holding
## the right button raises the weapon (slower walk, tighter shots).
@export var aim_point: Vector2 = Vector2.ZERO   # world position under the mouse, metres
@export var aiming: bool = false
@export var weapon: StringName = &"fists"       # key into CombatSystem.WEAPONS
@export var ammo: int = 0                       # pistol rounds carried (G1: bought in boxes from dealers)
@export var attack_ready_tick: int = 0          # no new attack before this tick
@export var shots_fired: int = 0
@export var last_shot_tick: int = -1000000         # C6: cops treat a recent shooter as armed
## G2 needs / G3 wounds.
@export var sleeping: bool = false
@export var sleeping_home: bool = false
@export var health_at_sleep: float = 1.0
## V1: the car you are in (driving), and a hotwire in progress.
@export var work_until_tick: int = 0             # O1: on a shift until this tick (time runs fast)
@export var case_evidence: float = 0.0          # I1: what the police have on you (witness reports)
@export var prison_until_tick: int = 0           # CP1: serving time until this tick (0 = free)
@export var deeds: Dictionary = {}              # T1: deed -> count
@export var traits: Dictionary = {}             # T1: trait id -> tier (1 normal, 2 gold)
@export var fame: float = 0.0                    # F1: 0-100
@export var job: Dictionary = {}                  # JB1: the contract you are on
@export var fixer_rep: float = 0.0
@export var jobs_done: int = 0
var job_offers: Array = []                      # JB1: offers on screen (not saved)
@export var rank: int = 0                         # RK1: highest rank earned (RankSystem.NAMES)
@export var skills: Dictionary = {}                 # S1: skill -> XP
@export var vehicle_id: StringName = &""
@export var hotwire_id: StringName = &""
@export var hotwire_done_tick: int = 0
@export var burglary_id: StringName = &""   # X2: house being broken into
@export var burglary_done_tick: int = 0
var inventory_open: bool = false                # G2: I shows what you carry (not saved)
var timed: Dictionary = {}                      # TA1: the timed action under way {item, start, done} (not saved)
var ui_pick: int = -1                           # UIF1: a menu row clicked with the mouse (not saved)
var ui_move: Dictionary = {}                    # INV4: a bag<->vicinity move the UI asked for (not saved)
var ui_use: StringName = &""                     # UI5: item clicked in the bag, used next tick (not saved)
var menu_options: PackedStringArray = []        # UI1: the open E menu (not saved)
var store_id: StringName = &""                  # G1: counter whose menu is open (not saved)
var last_attack: Dictionary = {}                # the latest blow or shot, for AimView to draw
