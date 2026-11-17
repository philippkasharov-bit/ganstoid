# Tagged: Crew Command and Jobs

For the Claude that works on the code. Phil is a beginner: plain words, propose before you build anything big, and end every reply with 2 or 3 next steps, one marked **Recommended** with one line on why. One batch = one branch = one task id, named `<account>-CCx-<name>`, started from the latest `main`. Never commit straight to `main`.

## Goal

Run a gang the way Men of War lets you run soldiers, with one big addition: everything can also run by itself.

- **Hands on:** select any crew member, give orders, or take direct control of them, with their own bag, wounds and skills.
- **Hands off:** assign every member to any kind of crime or any passive role, set rules, and let them get on with it. You manage by exception, from reports.
- **Flexible:** you can change from one mode to the other at any moment, for any single person.

## Design principle: optional depth

Men of War is loved for individual control and individual inventories, but reviewers also found its inventory micromanagement overwhelming. So: deep control is always available and never required. Automation handles the boring parts, and the game asks for your attention only when something matters (a bust, a rival push, a tip, a heist).

## What exists today (read from the code, confirm before relying on it)

| Piece | What it does now |
| --- | --- |
| `CrewSystem` | Recruit civilians. Crew loosely trail the player "until real task assignment exists". |
| `CrewRoster` | Tab panel, read-only: name, job, loyalty, what they hold. |
| `CrewDealerSystem` (G), `CrewMuscleSystem` (M) | Post a member on a corner by hotkey; they sell or collect protection. |
| `CrewLoyaltySystem`, `CrewBustSystem` | Loyalty from cuts, neglect and treatment; arrests when a cop is near and the corner is hot. |
| `TerritorySystem`, `CornerWarSystem` | Influence per cell from posted crew and businesses; pushes from rival gangs. |
| `NPCData.crew_role`, `post_position`, `crew_stash`, `crew_earnings` | The data a member carries. `GanstoidEnums.CrewRole` has only a few roles. |
| `NPCData.ambition`, `crew_rank`, `crew_days` (CA1) | Crew wants (loyal, greedy, climber, rat) and a lieutenant rank that runs a corner. CC7 and CC8 build on these. |
| `ActionMenuModel`, `ContextMenu`, `PhoneSystem` | The E menu, the right-click menu, the phone. |
| `BagGridView` (with its "Nearby" grid), `HealthPanel`, `BodyDoll` | Item grid, wounds and the body figure, today for the player. |

Rule of the code base: the UI only asks (writes a request on the player state), and a system does it on the next tick. Follow this for every command here, so that orders stay testable and deterministic.

## Rules for this work

- Orders, jobs and automation live in the sim (`core/`), engine-free. The UI and the 3D view only read and ask.
- Build on the shared NPC brain from `NPC_BEHAVIOUR_PLAN.md` (activities, utility choice, memory, tiers). A crew job is an activity whose priority the player sets. Until that brain exists (NB8), build the job layer on a small adapter around the current role systems so nothing is thrown away.
- Roles stay data: a new crime means a new job definition, not a new system.
- Speed gate: `verify_sim_perf` run alone, the soak, and `verify_sim_life`. Crew orders must not add route requests faster than `CityNav` can plan them; queue them.
- Deterministic and saved: orders, queues, priorities and standing rules are saved with the crew member.
- Crew cap by rank at first (about 4 at the start, up to 12), so micromanagement stays possible. The `RankSystem` already scores crew size.

## The design

### 1. Select and order (the hands-on layer)

- **Select:** click, box-select, double-click to select all of one role, number keys for groups (Ctrl+number to set), Tab to cycle. Selection shows rings and a portrait strip along the bottom: health, stance, current order, ammo.
- **Orders** through the existing right-click menu, shown for the thing under the cursor: move, follow, hold, guard this door, watch from here (lookout, with a view cone), post on this corner (deal, protect), tail that person, fetch that item, drive me there, break in, rob, retreat to the crib, lay low. Shift-click queues several steps.
- **Stances:** passive (no fighting, avoid police), defensive (fight back only), aggressive. And standing rules: run from cops, never shoot first, protect the boss.
- **Split and group:** send two on a job, keep two with you, regroup with one key.
- **Slow time for planning.** A game-speed control down to a crawl, not a full pause (a pause does not work in co-op, and a crawl keeps the street alive).

### 2. Direct control

- One key takes control of the selected member, another returns to the boss, and a third cycles. The camera follows. They use the same controls as the boss: move, aim, search, enter, drive.
- They keep their own bag, wounds (body figure), skills and weapon.
- The boss's death still ends the run (the existing rule). A crew member's death is permanent, and affects the others' loyalty.
- While you control someone, the others keep following their orders on their own.

### 3. Individual gear

- **Crew tab in the bag window:** each member's grid next to yours, so you can drag items between people who are standing close.
- **Loadouts:** presets such as dealer kit, lookout kit (pager), muscle kit, burglar kit, driver kit. One click equips what the stash holds.
- **Ammo types** per weapon, as in Men of War, kept simple at first (one or two types).
- **Auto-resupply** is a rule, not a chore: "restock from the crib stash when below X."

### 4. Jobs and automation (the hands-off layer)

**The assignment table:** one row per crew member, one column per job, each cell a priority from 0 (off) to 4, as in RimWorld's work tab. A template button assigns a whole crew in two clicks.

**Job definitions (data):** name, where it happens, what it needs (tools, skill, hours), what it produces (cash, items, influence, heat), its risk and its crime type. Starting list:

- *Active crime:* mugging, pickpocketing, burglary, car theft, dealing, muscle and protection, smuggling, grow house, enforcer, driver, lookout.
- *Passive:* legal cover job, guard the crib, collect cuts, scout and inform, recruit, cook and craft, bookkeeping and laundering, patch people up, lay low, rest.

**Standing rules per person or job:** shift (day or night), the area, the risk they accept, a **heat limit** (stop when the block is too hot), their cut, and what to do with the take (keep, stash, hand over).

**How it runs:**

- Each hour, an idle member picks the best available job by priority, skill, distance, risk and current heat, using the same utility choice as every NPC.
- Real consequences stay: automated crimes have witnesses and heat, the evidence gate and `CrewBustSystem` still apply, loyalty still moves.
- **Off-screen resolution:** a member out of sight resolves each hour as one outcome (money, heat, bust chance, injury chance) from their skill and the job's risk. The moment you look at them or take control, they play out for real from a plausible state. This keeps the city fast.
- **Reports:** the phone and the morning paper tell you what happened. You are interrupted only for events that need you.

### 5. Gang scale: lieutenants

- Promote a loyal member to lieutenant. Give them a **block or hood** and standing orders ("hold it, keep dealers posted, push for more turf, avoid police") and a budget.
- They manage the people under them with the same job table, and report each night. You only step in when you want to.
- Hands-on for a small crew, lieutenants for a gang: that is how the micromanagement stays fun as you grow.

### 6. Autonomy and morale

- Loyalty, fear and personality decide obedience. A low-loyalty member may refuse a risky order, argue, or quit.
- Gunfire nearby makes people duck or flee unless trained or bold (suppression), as in the soldier games.
- Free time: members hang out at the crib, eat, sleep and talk, so the crew looks alive.

### 7. Co-op (later)

Each friend controls their own member or members, with the boss as host. Authority stays with the host's sim. No full pause. Do this only after solo is fun.

## Batches

| # | Batch | What Phil gets | Size |
| --- | --- | --- | --- |
| CC1 | **Select and order** | Click and box-select, a bottom portrait strip, move, hold, follow, watch. The roster becomes clickable. | 3 sessions |
| CC2 | **Direct control** | Take over any member with a key and switch back. Own bag and wounds. | 2 sessions |
| CC3 | **Crew gear** | Crew tab, hand over items, loadouts. | 2 sessions |
| CC4 | **Jobs table** | The assignment grid, job data for today's roles, hourly pick and off-screen outcomes. | 3 sessions |
| CC5 | **New crimes as jobs** | Burglary, car theft, mugging, smuggling, enforcer. | 3 sessions |
| CC6 | **Standing rules and reports** | Shifts, risk and heat limits, phone and paper reports. | 2 sessions |
| CC7 | **Stances and morale** | Stances, refusing orders, suppression. | 2 sessions |
| CC8 | **Lieutenants** | Hood-level standing orders and nightly reports. | 2 sessions |
| CC9 | **Co-op** | Friends control crew members. | later |

**Recommended first step:** CC1 plus CC2. Select, order, take control: that is where the Men of War feeling starts, and it needs no new simulation.

## Checks to add

- `verify_crew_orders`: every order type completes, is queued, can be cancelled, survives save and load, and gives the same result on a rerun.
- `verify_crew_jobs`: priorities are respected; a member never takes a job they cannot do; the heat limit stops a job; the off-screen outcome matches the on-screen average over many runs.
- Soak: nobody stuck for more than N minutes, no queue growth, no route-request spikes, and `verify_sim_perf` unchanged.

## At the end of every batch

- Run `python3 -I tools/qa/index.py` before the commit, and tick the batch in `docs/ROADMAP.md` in the same commit.
- Run the full suite, `verify_sim_perf` alone, the soak and the album for the changed pictures. Add a line to `debug/album.txt` for every new screen or window.
- Log new problems in `BUGS.md`. Push the branch at the end of the reply.
- Reply in plain words: what changed, what to test in the game (for example: "box-select two crew, right-click a corner, and press F to take control of one"), and 2 or 3 next steps with one marked Recommended.
