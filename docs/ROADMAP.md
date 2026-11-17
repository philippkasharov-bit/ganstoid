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
- [x] AD1 admin panel (F11) with bug test, bugs and updates · QA6 test index and code map

## Next batches (in order unless Phil says otherwise)

| # | Batch | What the player gets | Size |
|---|---|---|---|
| B1 | ~~The big score (HS1)~~ **done** · | Rumours lead to heists (armoured van, stash house, jewellery store); case it, pick crew roles, get a car and gear, do it live | 2-3 sessions |
| B2 | ~~Your crib (CR1)~~ **done** · | Upgrade home from mattress to stash house: safe, workbench, trophies, crew hanging out | 1-2 |
| B3 | **Camera (CM1)** | Over-the-shoulder view on a key (Phil: no first person) | 1 |
| B4 | **Visuals: people (VS1)** | Better NPC figures (shared rigged models, variety), the biggest visual gap | 2 |
| B5 | **Visuals: streets (VS2)** | Parked cars, clutter, fences, graffiti, kerbs, worn ground; flats and shops less boxy | 2 |
| B6 | ~~RP jobs and property (RP2)~~ **done** · | A list of legal jobs (delivery, taxi, security), buy a flat or house, a driving licence | 2 |
| B7 | **Join a gang (RP3)** | Join a gang and rise in its ranks instead of only fighting them | 2 |
| B8 | **Prison (JL1)** | Real jail time: crew and business run without you, a way out | 1-2 |
| B9 | **Pacing robot (F3)** | Measures time to first money, rank, chase; tune the pace with numbers | 1 |
| B10 | **Sound (AU1)** | City ambience, footsteps, cars, guns, 90s radio in cars | 2 |

## Refine passes (after every 2-3 batches)

- Full suite, album and a 26-hour soak; fix what they find
- Phil plays; F12 reports become checks
- Speed: rush-hour ticks over 4 ms stay under 150 (`verify_sim_perf`)

## Dropped or parked

- Family business / legacy after death (Phil: not needed)
