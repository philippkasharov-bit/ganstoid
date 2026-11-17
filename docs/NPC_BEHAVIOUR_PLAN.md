# Tagged: NPC behaviour overhaul ("Living City")

For the Claude that works on the code. Phil is a beginner: plain words, propose before you build anything big, and end every reply with 2 or 3 next steps, one marked **Recommended** with one line on why. One batch = one branch = one task id, named `<account>-NBx-<name>`, started from the latest `main`. Never commit straight to `main`.

## Goal

People in the city should look like they have lives: different habits, moods and memories, sensible reactions, natural variety, and no robotic loops. Everything should be automatic and flexible: add a new kind of person, place or activity by adding data, not by writing a new system. And the city must stay fast with 6,000 people.

"AAA level" here means these six things, in order of what players notice:

1. **Variety:** no two people act the same, and one person does not act the same every day.
2. **Believable reactions:** people notice, hesitate, then react by personality (flee, freeze, gawk, help, call the police), not all at once and not all the same.
3. **Memory and word of mouth:** what you do is remembered by the people who saw it, and it spreads.
4. **Social life:** groups, conversations, queues, crowds that gather around a fight and drift away after.
5. **Readable behaviour:** you can tell what someone is doing and feeling from how they move and what they say.
6. **Speed:** full detail only where the player is looking.

## What exists today (read from the code, confirm before relying on it)

| Piece | What it does now | Limit for this plan |
| --- | --- | --- |
| `NPCRoutine` | Pure functions of person id and time: shifts, loiterer share, pace, dark routes. Same person, same habits. | Good base. Habits are fixed numbers, not personality. |
| `NPCScheduleSystem` | A calendar wakes a person only when their plan changes (`WAKES_PER_TICK` = 6). | Keep this idea: it is why the sim is fast. |
| `NPCOutings` | Errand, evening out, promenade, with some habit and some variation. | Random picks, not a choice based on need or mood. |
| `NPCStreet` | Walks trips leg by leg. Full rate within `NEAR_M` 150 m, every 6th tick up to `ABSTRACT_M` 520 m, straight lines beyond, one step in 30 when unseen. | Good tiering. Keep it. |
| `ReactionSystem` | Four times a second, only round the player: gun up, followed, a body, gang warnings. | Same reaction for everyone, no personality, no delay. |
| `WitnessCallSystem`, `RecognitionSystem`, `TalkSystem` | Witnesses run home and phone it in; trust and fear per person. | Per person, but no memory of events, no spread. |
| `NeedsSystem` | Hunger, thirst, tiredness. | Player only. Civilians have no needs. |
| `CopAISystem`, `NPCCombatSystem`, `CrewSystem` | Hard-coded behaviours per role. | Each is its own small AI. Nothing shared. |
| `Crowd`, `SpatialIndex`, `EventBus`, `WanderBehavior`, `SimClock` | Avoidance, near queries, events, drift, time. | Reuse all of them. |
| `MemorySystem` (ME1) | Each person keeps one feeling about the player (-1..+1) with barks ("That's him!"), refusals and a daily fade, in `PlayerStateData.memories`. | Player only. The NB memory ring should absorb it in NB3/NB4, not duplicate it. |
| `NPCMindData`, `NPCMind`, `Archetypes` (NB1) | Traits, needs, mood, memory ring, friends; made lazily, rolled from the id; F11 People tab. | Data only: nothing in play reads it yet. |

The shape of the problem: behaviour is a set of separate hard-coded systems, each with its own rules. The plan adds one shared "brain" layer on top and moves systems onto it one at a time.

## Rules for this work

- **Strangler pattern:** the new brain runs next to the old systems behind a switch in `GameRules`. Move one behaviour at a time, compare on the soak run, and keep the old path until the new one passes. Never rewrite everything at once.
- **Deterministic:** every choice is seeded from (person id, game day, activity), never from global random order. Saves must rebuild the same world, and headless tests must repeat.
- **The sim stays engine-free** (Phase 0 rule): no scene-tree calls in `core/` brain code. Rendering reads the result.
- **Speed gate on every batch:** `verify_sim_perf` run alone (rush-hour ticks over 4 ms stay under 150), the three-day soak (`verify_soak`) and `verify_sim_life`. Record before and after numbers.
- **Nothing the player can see may pop:** when someone moves between detail tiers, their position and activity must stay plausible.

## The design

### 1. Who someone is: data components

Add pure-data components next to `NPCData` (no behaviour inside), all saved compactly:

- **Personality:** 8 traits from 0 to 1, rolled from the person's id plus the archetype's ranges: bold, sociable, lawful, greedy, curious, patient, paranoid, energetic. They weight every choice below. Events can nudge them slowly (a robbed shopkeeper becomes more paranoid).
- **Drives (needs):** energy, hunger, money, social, safety, fun, each 0 to 1 and drifting with time. This extends the player's `NeedsSystem` idea to everyone, but at a cheap rate (updated when someone wakes, not per tick).
- **Mood:** calm, curious, afraid, angry, happy as small decaying values. Mood changes how fast someone moves, how they react, and which barks they use.
- **Memory:** a small ring buffer per person (8 to 16 entries) of `{kind, who, where, tick, weight}`: saw a crime, was robbed, got helped, saw a body, met you. Old low-weight entries drop out.
- **Relationships:** household (family walking and eating together), workplace, friends, gang. Only a few links per person, kept as ids.
- **Archetype (data file):** trait ranges, schedule templates, activity weights, wardrobe and animation set. Start with: office worker, shop owner, student, retiree, night shifter, delivery driver, street vendor, homeless person, addict, gang member, cop on beat, tourist. New types are new data files.

### 2. What someone does: activities and a utility choice

An **activity** is a data definition: name, where it can happen (a place type), how long it lasts, what it satisfies, preconditions, whether it can be interrupted, and which animation and bark set it uses.

Starter list: work, commute, eat, shop, drink coffee, smoke, chat, wait for the bus, sit on a stoop, use the phone, walk the dog, exercise, pray, drink at a bar, sleep, hang out on a corner, deal, patrol, beg, deliver, wash a car, play basketball, watch a fight.

**Choice = utility scoring.** When someone wakes (calendar wake, as today), score each legal activity by multiplying curves for: how much it satisfies their drives, how well it fits their personality, the time of day, the distance, the cost, and a bit of habit (a bonus for what they did yesterday at this hour). Pick with weighted randomness among the top few, seeded as above, so people are not mechanical. The base schedule from `NPCRoutine` (shifts) remains a strong constraint: work is high utility at shift time, so most people still go to work.

**Places are smart objects.** Buildings and street spots advertise what can be done there (a shop: shop; a bench: sit; a bus stop: wait; a corner: hang out, deal; a bar: drink, chat). Slots have capacity, so queues and crowds form on their own. Generate them from the surveyed data and the building kinds you already have.

### 3. How someone notices: perception and attention

- **Stimulus events**, sent through `EventBus` with a position, a loudness or visibility, and a kind: gunshot, shout, crash, siren, a body, a weapon drawn, a fight.
- **Sight** uses the light and line-of-sight rule you already have in the sim (`CrimeSystem.can_see`, from the stealth work in ST2; `SightMap` is only its 3D drawing). **Hearing** uses a radius reduced by walls.
- **Attention budget:** each person notices at most one new thing per check, and the check rate depends on the tier (below). Distracted people (on the phone, drunk, in a hurry) notice less.
- **Reaction delay:** 0.3 to 1.2 s from noticing to acting, set by personality, so a crowd does not flinch in the same frame.

### 4. How someone reacts: a priority layer above activities

A reaction interrupts the current activity and puts it on a stack, so after the event the person can resume it (the shopper goes back to shopping, or goes home if still scared). Reactions are chosen by utility from personality and mood:

- flee, hide indoors, freeze, hands up (this replaces the fixed rule in `ReactionSystem`)
- gawk (slow down, stop, watch from a distance, a few steps closer if curious)
- help (a bold, sociable person goes to someone hurt)
- call the police (only if lawful and safe, with a delay, as in `WitnessCallSystem`)
- confront or fight (bold, angry, protecting their own)
- walk on, pretend nothing happened (the paranoid or the guilty)

### 5. Social life

- **Groups:** families and friends travel together at the group's pace and stop to talk.
- **Conversations:** two people stand facing each other, with gestures and short barks, then part. Others may join.
- **Queues and crowds:** at shop counters, bus stops and fights, using slot capacity.
- **Gossip:** a memory can be passed on when two people talk or one phones another, with a chance of distortion and a limit on how far and how fast it spreads. This feeds the street reputation and the morning paper's "word on the street", so what you do spreads through the hood in a believable way, not instantly everywhere.

### 6. Natural variety

- Per-person noise on every number (pace, reaction time, patience, how long they stay).
- Idle variants: look around, check the phone, scratch, stretch, shift weight, light a cigarette.
- **Barks:** short lines by situation and mood with a per-person cooldown, shown with the existing halo text. Write them in plain, varied 90s LA English first, with the text kept in data files so French and Russian can be added.
- **Time and weather:** weekends differ from weekdays, heat sends people into shade, rain makes them hurry, special events draw crowds.
- **Resuming and mistakes:** people forget things, change plans, take a wrong turn, run late.
- **Streets:** people stop at crossings by personality (some jaywalk), keep personal space using `Crowd`, and walk in flows, not in straight lines.

### 7. Speed: four detail tiers

This builds on the tiers `NPCStreet` already has.

| Tier | Where | Cost per person | What runs |
| --- | --- | --- | --- |
| T0 full | in view and within about 40 m | highest | perception about 10 Hz, reactions, animation variants, barks, conversations |
| T1 near | within `NEAR_M` 150 m | low | decisions on wake, reactions only to loud events, simple walking |
| T2 far | to `ABSTRACT_M` 520 m | very low | calendar wakes only, step every 6th tick |
| T3 abstract | beyond | almost none | no per-tick work: where they should be is computed from their schedule |

- **Promotion:** when someone moves up a tier, rebuild a plausible state from their schedule, drives and memory so nothing pops.
- **Budget:** a hard cap on brain time per tick, with round-robin buckets, the way `WAKES_PER_TICK` works now. If the cap is hit, lower tiers slow down first.
- **Hot loops:** no allocation in them, arrays of simple values. If GDScript is too slow for the scoring loop after profiling, move only that loop to C# or GDExtension.

### 8. Tools (build these early, they make everything else easier)

- **NPC inspector** in the F11 panel: click a person to see archetype, traits, drives, mood, current activity, the top 5 utility scores and why, memory, relationships and tier.
- **Life report:** print one person's day as a timeline.
- **Soak metrics:** extend the three-day soak (`verify_soak`, `verify_sim_life`): activity mix per hour, how many are idle, people stuck over N minutes, jitter, walking through walls, departure-time spread, crowd size per hour. Fail on common-sense problems, and print the numbers.
- **Album pictures:** a conversation, a queue, a crowd round a fight, a family walking, a night street.

## Batches

| # | Batch | What Phil sees | Size |
| --- | --- | --- | --- |
| NB1 | ~~**Data and inspector**~~ **done** | Click a person, see who they are. No behaviour changes yet. | 2 sessions |
| NB2 | **Activities and choice** | Free time uses needs, personality and places, not random picks. `NPCOutings` becomes data. | 3 sessions |
| NB3 | **Perception and reactions** | Reactions vary by person, with delays and resuming. `ReactionSystem` moves over. | 3 sessions |
| NB4 | **Social** | Groups, conversations, queues, crowds, gossip. | 3 sessions |
| NB5 | **Barks and body language** | People talk and move in readable ways. Takes over roadmap LV1 "Living streets" (proposed). | 2 sessions |
| NB6 | **Archetypes and content** | A dozen archetypes and 30+ activities, all data. | 2 sessions |
| NB7 | **Tier and speed pass** | Promotion without pops, brain budget, soak numbers. | 2 sessions |
| NB8 | **Cops, gangs, crew on the same brain** | One system for everyone. Crew jobs (see `CREW_COMMAND_PLAN.md`) are activities with player-set priority. | 3 sessions |

**Recommended first step:** NB1. It changes nothing in play, so it is safe, and it gives you the inspector you need to judge every later batch.

## At the end of every batch

- Run `python3 -I tools/qa/index.py` before the commit, and tick the batch in `docs/ROADMAP.md` in the same commit.
- Run the full suite, `verify_sim_perf` alone, the soak and the album for the changed pictures. Record before and after numbers.
- Log new problems in `BUGS.md`. Push the branch at the end of the reply.
- Reply in plain words: what changed, what to watch for in the game (for example: "stand at a bus stop for two minutes and watch who arrives, who chats, who gives up"), the numbers, and 2 or 3 next steps with one marked Recommended.
