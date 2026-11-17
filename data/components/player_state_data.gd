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
## HP1: the player's body parts: part -> {hp, wound, bleeding, bandaged}.
@export var body: Dictionary = {}
## LT1: the building you are inside (after a break-in, or your own place); its
## containers show in Nearby until you walk away.
@export var inside_id: StringName = &""

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
@export var endurance: float = 1.0               # ST1: breath, 0..1 (Zomboid endurance)
@export var winded: bool = false                # ST1: out of breath until it is back over Stamina.CATCH_AT
@export var wear: Dictionary = {}                # B6: weapon item -> condition 0..1 (missing = new)
@export var jammed: bool = false                # B6: the pistol jammed; the next pull clears it
@export var sleeping: bool = false
@export var sleep_until_tick: int = 0          # SL1: wake at this tick (0: when rested)
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
@export var explored: PackedByteArray = PackedByteArray()   # MP2: fog of war, one bit per ExplorationSystem cell
@export var known: Dictionary = {}                 # MP2: dealer and fixer ids you have seen -> "dealer" / "fixer"
@export var prison_choice: String = "head_down"   # JL1: how you spend prison days
@export var prison_day: int = -1000000
@export var prison_good: int = 0
@export var prison_connections: int = 0
var ui_prison: String = ""                        # JL1: a click on the prison panel (not saved)
@export var gang_member: StringName = &""          # RP3: the gang you are in
@export var gang_rank: int = 0                    # RP3: GangLifeSystem.RANKS
@export var gang_rep: int = 0
@export var gang_missions: Array = []
@export var gang_day: int = -1000000
var ui_gang: String = ""                          # RP3: a phone request ("leave") (not saved)
@export var gig: Dictionary = {}                  # RP2: the legal gig you are on
@export var gigs: Array = []                      # RP2: today's offers
@export var gig_day: int = -1000000
@export var licence: bool = false                 # RP2: driving licence
@export var properties: Array = []                # RP2: homes you own (building ids)
@export var property_prices: Dictionary = {}      # RP2: what you paid (rent is a share of it)
var ui_gig: Dictionary = {}                       # RP2: a phone request (not saved)
@export var crib: int = 0                         # CR1: home tier (CribSystem.TIERS)
@export var crib_day: int = -1000000
@export var trophies: Array = []                  # CR1: finished scores [{what, take, day}]
var ui_crib: bool = false                         # CR1: the phone or the door asked for an upgrade (not saved)
@export var heist: Dictionary = {}                # HS1: the score you are on {kind, at, target, where, take, guards, complication, stage, cased, known, from, until, work, alarm}
@export var heist_day: int = -1000000              # HS1: the day the last score was offered
@export var turf_push: Dictionary = {}            # CW1: a gang's push on one of your blocks {cell, gang, until, sent, ko, seen_down, squad}
@export var push_day: int = -1000000
@export var push_last: int = -1000000             # UI6: the day of the last push
@export var waypoint: Vector2 = Vector2.INF        # MM1: the GPS target (right-click the big map)
@export var cash_history: Array = []              # UI6: your cash each morning, the last 7 (the Bank app's chart)
@export var inbox: Array = []                     # PH1: phone messages [{from, text, at}]
@export var memories: Dictionary = {}              # ME1: who remembers you: id -> {deed, feel, day, n, reported}
@export var trial: Dictionary = {}                 # CT1: a trial coming {at, evidence, witnesses, lawyer}
@export var crew_asks: Array = []                 # CA1: what your crew wants [{id, kind, amount, until}]
@export var crew_wages: Dictionary = {}           # CA1: crew id -> $ a day, paid each morning
@export var grow: Dictionary = {}                 # BZ1: the grow at home {tents, lamp, fan, filter, plants, drying}
@export var product: Dictionary = {}              # BZ1: the weed you carry {q: stars 1-5, strain}
@export var brand: String = ""                     # BZ1: the name stamped on your bags
@export var brand_rep: float = 0.0                # BZ1: how well the street knows it (0-1)
@export var staff: Dictionary = {}                # BZ2: who works for you: id -> {at, role, skill, honesty, wage, skimmed}
@export var biz_day: Dictionary = {}              # BZ2: yesterday in numbers {shops, wages}
@export var venues: Dictionary = {}               # BZ3: your night spots: building id -> {kind, decor, back_room, last, back, fight, raided}
@export var lab: Dictionary = {}                  # BZ4: the lab at home {press, glass, fires}
@export var products: Dictionary = {}             # BZ4: stars of each drug you carry (weed: product)
@export var shipment: Dictionary = {}             # BZ4: an import waiting {good, units, at, from, until, sting}
var ui_phone: Dictionary = {}
var ui_admin: Array = []                          # AD1: [command, arg] from the admin panel (not saved)
@export var admin_god: bool = false               # AD1: admin god mode: you take no damage                     # PH1: what the phone asked for (not saved)
@export var rivals: Dictionary = {}               # RV1: gang id -> {npc, name, real, temper, grudge, level, scars, stage, down_seen}
@export var hustles: Array = []                   # DH1: today's three [{kind, need, got, pay, done, deadline}]
@export var hustle_day: int = -1000000
@export var news_today: Array = []                # NP1: [key, amount, hood] the papers would print
@export var paper: Dictionary = {}                # NP1: the latest front page
@export var paper_day: int = -1000000
@export var paper_serial: int = 0
@export var tips_seen: Array = []                 # TP1: tips already shown this life
@export var tips_on: bool = true                  # TP1: the pause menu turns tips off
var stamp: Dictionary = {}                        # UI3: a big moment for the HUD {text, sub, color} (not saved)
var stamp_serial: int = 0                         # UI3: +1 per stamp (not saved)
var barks: Array = []                            # ME1: lines over people's heads [{id, text, tone, until}] (not saved)
var verdict: Dictionary = {}                      # CT1: the court's day, for CourtWindow {lines, guilty, days} (not saved)
var cook: Dictionary = {}                         # BZ4: a cook under way {heat, t, green, boxes} (not saved)
var ui_lab: Dictionary = {}                       # BZ4: {heat} from the cook window, {order} from the phone (not saved)
var gamble: Dictionary = {}                       # BZ3: a back-room game under way (not saved)
var ui_gamble: Dictionary = {}                    # BZ3: a click at the table (not saved)
var ui_biz: Dictionary = {}                       # BZ2: {hire, at, role} or {fire} from Phone > Business (not saved)
var ui_grow: Dictionary = {}                      # BZ1: {brand} from Phone > Grow (not saved)
var ui_crew: Dictionary = {}                      # CA1: {id, choice} from Phone > Crew (not saved)
var ui_court: String = ""                         # CT1: "close" from the court window (not saved)
var message_key: String = ""                      # AU1: the StreetTalk key of the last line, for its sound (not saved)
var lift: Dictionary = {}                         # PP1: a pickpocket under way {target, f, notice, last, dir} (not saved)
var tip_text: String = ""                         # TP1: the tip on screen (not saved)
var tip_serial: int = 0                           # TP1: +1 per new tip (not saved)
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
var basket: Dictionary = {}                     # TR1: item id -> how many in the shop basket (not saved)
var ui_buy: bool = false                        # TR1: the Buy button was pressed (not saved)
var hurt_serial: int = 0                        # A3: +1 on every hit you take (not saved)
var hurt_part: String = ""                      # A3: the body part the last hit landed on (not saved)
var sneaking: bool = false                      # B3: crouched (C): slow and quiet, half as far to be seen (not saved)
var ui_hotbar: int = -1                         # HB1: a hotbar slot clicked (not saved)
var ui_treat: Dictionary = {}                   # HP3: {op: bandage|remove, part} from the health window (not saved)
var menu_options: PackedStringArray = []        # UI1: the open E menu (not saved)
var menu_notes: PackedStringArray = []          # UIF3: the note beside each row (cost, "3 watching")
var menu_title: String = ""                     # UIF3: "What now?" or the open category
var menu_parent: PackedStringArray = []         # WM1: the category list while a category is open (its fly-out is menu_options) (not saved)
var menu_parent_on: int = -1                    # WM1: which category is open (not saved)
var message_tone: int = 0                       # HT1: last line +1 good, -1 bad, 0 neutral (not saved)
var message_alert: bool = false                 # HT1: last line is big news: a pop-up, not text over the head (not saved)
var menu_serial: int = 0                       # WM1: +1 each time the menu is (re)opened, so it moves to the cursor (not saved)
var ui_pick_parent: int = -1                    # WM1: a category row clicked or hovered (not saved)
var store_id: StringName = &""                  # G1: counter whose menu is open (not saved)
var last_attack: Dictionary = {}                # the latest blow or shot, for AimView to draw
