## E1: what people do for a living. Each kind of business has its jobs, from
## the floor to the boss, each with a base day's pay and how many of them a
## place usually has (weight). Pay scales with how rich the block is: the same
## till job pays more downtown than on the edge. Pure data.
class_name Jobs
extends RefCounted

## kind -> [[title, base $ a day, weight], ...]
const BY_KIND := {
	&"shop": [[&"cashier", 70, 5], [&"stock clerk", 60, 4], [&"store manager", 150, 1]],
	&"workshop": [[&"apprentice", 55, 3], [&"mechanic", 120, 3], [&"foreman", 170, 1]],
}
const POOR_PAY := 0.7     # wage multiplier on the poorest block
const RICH_PAY := 1.4     # and on the richest

## A job for someone hired at a business of this kind: [title, base pay].
static func pick(kind: StringName, rng: RandomNumberGenerator) -> Array:
	var jobs: Array = BY_KIND.get(kind, BY_KIND[&"shop"])
	var total := 0
	for j in jobs:
		total += int(j[2])
	var roll := rng.randi_range(1, total)
	for j in jobs:
		roll -= int(j[2])
		if roll <= 0:
			return [j[0], j[1]]
	return [jobs[0][0], jobs[0][1]]

## A day's pay for a base wage on a block of this wealth (0 poor .. 1 rich).
static func wage(base: int, wealth: float) -> int:
	return roundi(base * lerpf(POOR_PAY, RICH_PAY, clampf(wealth, 0.0, 1.0)))
