# Roadmap: Tagged (Ganstoid)

The batches plan for the whole game, shared by both Claude accounts. The
original plan lived outside the repository (the code still says "Phase 0-4",
"batch 1-25"); this file rebuilds it from the code and keeps it here.

How we work now (Phil, 2026-11): keep adding features in batches, then
refine them with the quality and bug checks. One batch = one branch = one
task id. When a batch is done, tick it here in the same commit.

Status: [x] done, [~] partly, [ ] not started.

## Milestones (the big picture)

| # | Milestone | Status |
|---|---|---|
| 1 | The living city: map, 6000 people, traffic, police, gangs, saving | done |
| 2 | The core crime loop: crimes, stealth, crew, turf, money, ranks | done |
| 3 | Something to do every day: hustles, paper, phone, map, GPS, rivals, reputation, corner war | done |
| 4 | Big moments and depth: heists, crib, jobs and property, joining a gang, prison | **now** (B1, B2, B6, B7, B8) |
| 5 | Look and feel: shoulder camera, people, streets, sound | later (B3, B4, B5, B10) |
| 6 | Balance and the first hour: pacing robot, tuning, tutorial | later (B9) |
| 7 | Release-ready: runs on normal PCs, settings, save safety, installer | last |

## Done: the foundation (Phases 0-4, the original plan)

- [x] Phase 0: the engine-free simulation (World, systems, events, save)
- [x] Phase 1: the core loop: crimes, witnesses, police, arrest, law tiers
- [x] Phase 2: gangs, deals, patrols and heat, raids, street talk, robbing buildings
- [x] Phase 3: your crew: recruit, loyalty, lookouts, muscle, dealers, drivers, busts
- [x] Phase 4: money: businesses, laundering, grow houses, the daily economy
- [x] The real 6 km downtown LA map, 6000 people with jobs and routines, traffic
- [x] The 3D city: cutaway, night, interiors, Blender house kit, mid-poly houses
- [x] Quality: error catcher, F12 bug reports, soak robot, photo album, BUGS.md

## Done: this round (2026-11, Phil's playtests)

- [x] NX1/TP1 next step and tips · DH1/NP1 daily hustles and morning paper
- [x] GP1/GP2 feel: run, stamina, needs, wounds, catching people
- [x] LT3 looting bodies and flats · CV1/DR1 doors and doormats
- [x] ST2 stealth: police only know what they can see · CH1 chases you can lose
- [x] MP2 fog-of-war map · MM1 minimap and GPS · PH1 the phone
- [x] PP1 pickpocket mini-game · RX1 people react to you
- [x] RV1 rivals with names · RP1 street reputation · CW1 corner war and pushes
- [x] UI1-UI6: pager, status card, stamps, prompts, title screen, layout mode (F10), motion and charts
- [x] HS1 the big score: store, stash house, armoured van; case it, crew roles, alarm, getaway
- [x] CR1 your crib: Mattress, Pad, Spot, Stash house; rest, safe, workbench, crew hangout, trophies, home laundering
- [x] RP2 legal gigs (delivery, taxi, night security), driving licence, buying homes, rent
- [x] RP3 join a gang: Prospect to Lieutenant, daily missions, a cut, leaving
- [x] JL1 prison days: head down, yard, connections, appeal, escape; the crew slips outside
- [x] AD1 admin panel (F11) with bug test, bugs and updates · QA6 test index and code map

## Indie mistakes we design against (Phil, 2026-11: "doesn't it look boring and repetitive?")

Honest status: wide but thin. Many systems, but most are menus and text;
no sound; everyone looks alike; the city doesn't show what the sim knows.
Each mistake below is checked against the game and owned by a batch.

| # | Mistake | Us now | Fix (batch) |
|---|---|---|---|
| 1 | No sound or music | none at all | AU1 |
| 2 | Menus instead of doing (E, pick a line) | most crimes | SK1 skill moments |
| 3 | Weak game feel: no impact, shake, reactions | flat | FX1 juice |
| 4 | Lifeless crowds: same people, no voices, no events | yes | LV1 living streets |
| 5 | Deep sim nobody can see | yes | LV1 (barks, events), MP3 overlays |
| 6 | Wide but shallow, everything half-done | yes | finish before adding (ROADMAP rule) |
| 7 | Same loop forever, no escalation | partly | ST1 story arc, LG1 late game |
| 8 | No story, characters or ending | none | ST1 |
| 9 | Late game turns into passive income | likely | LG1 threats to an empire |
| 10 | Huge empty map instead of a dense one | 6 km, sparse | DN1 density first |
| 11 | No art direction, generic low-poly | partly | VS1, VS2, ART1 look bible |
| 12 | Nothing worth sharing (clips, stories) | paper only | SH1 photo mode, highlights |
| 13 | Weak first 10 minutes | improved | B9 pacing, TU1 tutorial |
| 14 | Grind and money inflation | unmeasured | B9 pacing robot |
| 15 | Permadeath that feels unfair | possible | B9 tuning, clear warnings |
| 16 | Dumb enemy AI | basic | AI1 cover, flanking, search |
| 17 | Places that are only a panel (prison, crib) | yes | ART1 interiors that show it |
| 18 | Too many keys, hidden controls | many | UX1 one input map, controller |
| 19 | Text walls instead of showing | some | UX1, TU1 |
| 20 | Bugs and broken saves at launch | guarded | QA (keep), REL1 |
| 21 | Runs badly on normal PCs | unknown | REL1 quality settings, min-spec test |
| 22 | English only | yes | REL1 localisation |
| 23 | No accessibility options | few | REL1 subtitles, colours, remap |
| 24 | Hook not clear in one sentence | unclear | MK1 pitch |
| 25 | Marketing starts at launch | not started | MK1 store page, devlog, demo early |
| 26 | Legal: map credit, AI assets, real brands, music | open | REL1 credits, AI disclosure, own music |
| 27 | Never tested by strangers | yes | PT1 outside playtests |
| 28 | Early access with too little | risk | MK1 demo first |

## Next batches (re-ordered by the list above)

| # | Batch | What the player gets | Size |
|---|---|---|---|
| AU1 | **Sound and music** | City ambience by area and hour, footsteps, doors, cars, guns, crowd voices, a 90s radio in cars, UI sounds | 2 |
| FX1 | **Game feel** | Hit reactions and knockdowns, camera shake, muzzle flash, blood, slow-mo on a knockout, screen pulses on big moments | 1-2 |
| LV1 | **Living streets** | People say things (barks), street events (fights, arrests, crashes, parties, dealers busted), more traffic, people with jobs you can see | 2 |
| SK1 | **Skill moments** | Lockpicking, hotwiring, hold-ups, safe-cracking as short hands-on mini-games instead of menu lines | 2 |
| VS1/VS2 | **People and streets** | Varied people (models, clothes), parked cars, clutter, graffiti, worn ground | 4 |
| ST1 | **Story arc** | Named characters, chapters from Street rat to City boss, an ending (and play on after) | 3 |
| LG1 | **Late game** | An empire under pressure: federal case, raids, betrayal, gang wars over your business | 2 |
| B9/TU1 | **Pacing and first hour** | Pacing robot, tuning, a real tutorial | 2 |
| DN1 | **Density first** | Start in one dense district; the rest opens as you rise | 1 |
| ART1 | **Look bible** | One art direction, interiors for crib, prison, stores | 2 |
| REL1 | **Release-ready** | Settings, quality levels, languages, accessibility, credits, legal | 3 |
| MK1 | **Marketing** | One-line hook, store page, trailer, demo, devlog | ongoing |

## Older batch list (kept for reference)

| # | Batch | What the player gets | Size |
|---|---|---|---|
| B1 | ~~The big score (HS1)~~ **done** · | Rumours lead to heists (armoured van, stash house, jewellery store); case it, pick crew roles, get a car and gear, do it live | 2-3 sessions |
| B2 | ~~Your crib (CR1)~~ **done** · | Upgrade home from mattress to stash house: safe, workbench, trophies, crew hanging out | 1-2 |
| B3 | **Camera (CM1)** | Over-the-shoulder view on a key (Phil: no first person) | 1 |
| B4 | **Visuals: people (VS1)** | Better NPC figures (shared rigged models, variety), the biggest visual gap | 2 |
| B5 | **Visuals: streets (VS2)** | Parked cars, clutter, fences, graffiti, kerbs, worn ground; flats and shops less boxy | 2 |
| B6 | ~~RP jobs and property (RP2)~~ **done** · | A list of legal jobs (delivery, taxi, security), buy a flat or house, a driving licence | 2 |
| B7 | ~~Join a gang (RP3)~~ **done** · | Join a gang and rise in its ranks instead of only fighting them | 2 |
| B8 | ~~Prison (JL1)~~ **done** · | Real jail time: crew and business run without you, a way out | 1-2 |
| B9 | **Pacing robot (F3)** | Measures time to first money, rank, chase; tune the pace with numbers | 1 |
| B10 | **Sound (AU1)** | City ambience, footsteps, cars, guns, 90s radio in cars | 2 |

## Refine passes (after every 2-3 batches)

- Full suite, album and a 26-hour soak; fix what they find
- Phil plays; F12 reports become checks
- Speed: rush-hour ticks over 4 ms stay under 150 (`verify_sim_perf`)

## Dropped or parked

- Family business / legacy after death (Phil: not needed)
