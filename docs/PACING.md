# Pacing (B9)

Measured by the pacing robot (`debug/pace_robot.gd`): a bot plays the first
14 game days on the test district with 1,500 people, the way a typical
player might (mug when broke, rob a shop in the evening, a daily 4-hour
shift, a weed grow from $700, deal hand to hand, a grower from $1,500,
buy the cheapest shop when clean money allows, then a car wash). At 1x
a game day is an hour of real play.

Run: `$G --headless --path . -s debug/pace_robot.gd` (PACE_DAYS, PACE_SEED, PACE_POP).

## 2026-11-17, seed 4242, 14 days, 1,500 people

| Milestone | Game day | Real time at 1x |
|---|---|---|
| $500 cash | 1.9 | about 2 hours |
| Grow set up | 3.5 | 3.5 hours |
| Rank: Hustler | 6.9 | 7 hours |
| Grower hired | 7.9 | 8 hours |
| $2,000 cash | 9.9 | 10 hours |
| First business | never | more than 14 hours |
| First arrest | never | |

Income over the 14 days: robberies $2,605 (14), weed $1,774 (65 bags,
2 harvests by hand before the grower), shifts $840, muggings $505 (6),
businesses $0. End: $3,906 cash, of it $3,119 dirty; case file 0.

## What the numbers say

1. **The clean-money wall.** A shop costs ten days of its takings in clean
   money, and almost all early money is dirty. Washing needs a business you
   already own. So a player who earns well still can't buy a first business
   in 14 hours of play: stuck.
2. **Crime is too safe.** 14 robberies and 6 muggings, no arrest, the case
   file back to 0 every time. The police never felt close.
3. **Slow start.** $500 takes about two real hours; the first hour should
   already feel like progress.
4. **Ranks.** Soldier (needed for imports, gun crates) is past day 14.

Tuning is proposed to Phil before it is changed (see the session report).
