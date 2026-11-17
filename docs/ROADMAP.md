# Roadmap: Tagged (Ganstoid)

The batches plan for the whole game, shared by both Claude accounts. The
original plan lived outside the repository (the code still says "Phase 0-4",
"batch 1-25"); this file rebuilds it from the code and keeps it here.

How we work now (Phil, 2026-11): keep adding features in batches, then
refine them with the quality and bug checks. One batch = one branch = one
task id. When a batch is done, tick it here in the same commit.

Status: [x] done, [~] partly, [ ] not started.

Setting rule (Phil): it's the 1990s in America. Weed is illegal, there are no
legal shops, awards or newspaper ratings for it; the street talks and the paper
prints busts.

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
- [x] AU1 sound, all made by code (tools/audio/synth.py): day and night city, crowd murmur, steps, doors, guns, cars passing, police siren, engine, two radio stations, interface sounds; Sound and Music volume in the Esc menu
- [x] ME1 the city remembers: people you robbed, hurt, threatened or helped know you again; they shout it (speech bubbles), run, call the police once, or tip you off; a store you held up won't serve you; friends join your crew more readily; grudges fade over about a month
- [x] CT1 court case: an arrest with a real case is a charge and a trial in two days; the people who remember you are the witnesses; scare them, pay them or hire a lawyer; the court window shows who talked and the verdict (Phone > Case, admin: Trial now)
- [x] CA1 crew with ambitions: loyal, greedy, climber or rat; wages, lieutenants (their corner pays +50%), a sour lieutenant walks off with a friend and 15% of your cash, a rat gets you a warning and then testifies; Phone > Crew to answer
- [x] BZ1 grow it yourself: gear from a hardware counter, seeds from a dealer, tents at home (more with a bigger crib), water, feed, harvest, dry, bag; 1-5 stars (strain, lamp, fan, care, growing skill); your stamp and its name on the street; regulars on your corners; cutting; the smell is the risk (a filter helps); Phone > Grow
- [x] BZ2 staff: hire a grower (runs the grow from a stock of seeds and food, bags into a stash) or a shop manager (+ up to 40% takings); skill stars, a daily wage, honesty you can only guess (shifty ones skim); unpaid or fired without severance, a grower becomes a witness; Phone > Business
- [x] BZ3 nightlife: turn a shop you own into a nightclub, gentlemen's club or card room (licence, clean money); fit-out and a good manager add stars; takings at closing by hood and stars; a bouncer stops fights; washes more dirty money; an illegal back room pays big until vice raids it; back-room blackjack and dice at night at pawn shops and liquor stores
- [x] BZ4 drug chain: a pill press (pill powder from dealers), a hands-on meth cook (keep the heat in the green; past the red it burns), imports from Soldier rank (cash up front, a warehouse pick-up window, sometimes a sting); stars on every drug set its price; step on coke and heroin; your clubs' door staff sell your pills; new chemistry skill; Phone > Connect
- [x] QL3 quality in street words (Schwag to Chronic, Baking soda to Uncut; workers Green to A pro; night spots Dive to The place to be); six weed strains with their own high, smell, speed, yield and best market; doves and speedy whites; you set your own prices (Phone > Prices): all buyers bite at its worth, half at 1.5x
- [x] LT4 looting by searching: every piece of furniture its own container (fridge, cabinets, medicine cabinet, drawers, wardrobe, under the bed, shelf, sofa, TV stand, a wall safe in rich homes), each searched with a timed bar (moving breaks it off), pockets too; 19 new valuables and business supplies in the tables; pawn (clean) or fence (dirty); deal hand to hand at your own price
- [x] UI7 a modern phone (dark, app tiles with badges, scrolls); rings at people's feet for who they are to you (crew, police, gang, friend, scared, enemy; strangers none) and a name card on hover; a deal window (your price, the odds, Offer) and a pawn / fence window (sell one or all) · UP1 the updater no longer sticks on a locked file

## Indie mistakes we design against (Phil, 2026-11: "doesn't it look boring and repetitive?")

Honest status: wide but thin. Many systems, but most are menus and text;
no sound; everyone looks alike; the city doesn't show what the sim knows.
Each mistake below is checked against the game and owned by a batch.

| # | Mistake | Us now | Fix (batch) |
|---|---|---|---|
| 1 | No sound or music | AU1 done (code-made); voices and real music later | AU1, AU2 |
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
| AU1 | ~~**Sound and music**~~ **done** · | City ambience by area and hour, footsteps, doors, cars, guns, crowd voices, a 90s radio in cars, UI sounds | 2 |
| ME1 | ~~**The city remembers** (killer 1)~~ **done** · | Everyone you robbed, hurt, helped or paid remembers you: clerks refuse you, victims cross the street, people you helped tip you off or join you | 2 |
| CT1 | ~~**Court case** (killer 2)~~ **done** · | Arrested: a trial built from the real evidence (who saw you, what you carried); before it, scare or pay witnesses, hire a lawyer | 2 |
| CA1 | ~~**Crew with ambitions** (killer 3)~~ **done** · | Crew have wants: one gets greedy, one talks to police, one wants your chair; promote, pay or cut them loose | 2 |
| QL1 | **Quality on everything** (weed done in BZ1; the rest with each BZ batch) | Every product, item, tool, piece of gear, business, worker and job has a quality from 1 to 5 stars (Trash, Street, Good, Premium, Legendary). It comes from your gear, your skill, your workers and how well you looked after it; it sets the price, how fast it sells, who buys, and your name. Stars show on every card, shop and the Business app | with BZ1 |
| QL2 | **Ideas in the same direction** (Phil: all of them, 1990s-real) | Done in BZ1: your own stamp on the bags, customers who remember your quality (regulars), cutting. Still to come: crossbreed seeds for new strains; big buyers who order 50 bags of 4-star by Friday; worn gear caps quality; underground events (a back-room poker game, a club-night battle). No legal weed, no weed awards, no paper ratings: the street talks, the paper only prints busts | with BZ2-BZ7 |
| BZ1 | ~~**Grow it yourself**~~ **done** · | Buy gear at a grow shop (tent, lights, fan, filter, seeds), set it up in a place you own, tend the plants (water, feed, light), harvest, dry and bag, sell; more tents, then hydro; smell and neighbours are the risk | 2 |
| BZ2 | ~~**Workers and the Business app**~~ **done** · | Hire staff for any business (wage, skill, loyalty; they can steal or talk), shifts, one Business app: money in and out, stock, staff, heat | 1-2 |
| BZ3 | ~~**Nightlife: clubs, strip clubs, casinos**~~ **done** (card rooms, not casinos: 1990s LA) · | Buy and run them: licence, bouncers, DJ, staff, VIP rooms; nights earn by hood; launder through them; a back-room card game; play blackjack and slots yourself | 3 |
| BZ4 | ~~**The drug chain**~~ **done** · | Weed to pills (press) to a cook lab (a short cook mini-game, fire risk) to imports; your own corners, delivery, your clubs; prices by hood | 2-3 |
| BZ5 | **Big illegal side** (proposed) | Chop shop, counterfeit cash, fencing ring, gun running, loan sharking, gambling dens; laundering through your legal fronts with limits and audits | 3 |
| BZ6 | **Big legal side** (proposed) | Car wash, laundromat, restaurant, shop chain, flats to rent, trucking, security firm; upgrades, competition, taxes and audits | 2-3 |
| BZ7 | **Empire view** (proposed) | A map layer of everything you own, the daily ledger, raids and robberies by rivals on your places | 1 |
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
