## E1: what people do for a living. Every business has a trade (corner store,
## diner, pawn shop, auto body, warehouse...) picked to fit its block: liquor
## stores, check cashing and pawn shops on poor blocks; record stores, clinics
## and offices on rich ones. Each trade has its jobs, from the floor to the
## boss, each with a base day's pay and how many of them a place has (weight).
## Pay scales with block wealth: the same till job pays more downtown. Data only.
class_name Jobs
extends RefCounted

## trade -> [kind it sells as ("shop"/"workshop"), wealth it suits (0 poor .. 1 rich), jobs]
## jobs: [[title, base $ a day, weight], ...]
const TRADES := {
	&"corner store": [&"shop", 0.35, [[&"cashier", 60, 4], [&"stock clerk", 55, 2], [&"owner", 130, 1]]],
	&"liquor store": [&"shop", 0.15, [[&"clerk", 55, 4], [&"night clerk", 65, 2], [&"owner", 140, 1]]],
	&"check cashing": [&"shop", 0.1, [[&"teller", 70, 3], [&"security guard", 80, 1], [&"manager", 150, 1]]],
	&"pawn shop": [&"shop", 0.15, [[&"counter man", 65, 3], [&"appraiser", 110, 1], [&"owner", 160, 1]]],
	&"laundromat": [&"shop", 0.25, [[&"attendant", 50, 3], [&"owner", 110, 1]]],
	&"taco stand": [&"shop", 0.25, [[&"cook", 60, 3], [&"cashier", 50, 2], [&"owner", 120, 1]]],
	&"diner": [&"shop", 0.45, [[&"waitress", 55, 4], [&"line cook", 75, 3], [&"dishwasher", 45, 2], [&"manager", 140, 1]]],
	&"barbershop": [&"shop", 0.4, [[&"barber", 85, 3], [&"shop owner", 140, 1]]],
	&"beauty salon": [&"shop", 0.5, [[&"stylist", 90, 3], [&"receptionist", 60, 1], [&"owner", 150, 1]]],
	&"swap meet stall": [&"shop", 0.2, [[&"vendor", 55, 4]]],
	&"sneaker store": [&"shop", 0.6, [[&"sales clerk", 65, 4], [&"store manager", 150, 1]]],
	&"record store": [&"shop", 0.6, [[&"clerk", 60, 3], [&"buyer", 95, 1], [&"owner", 140, 1]]],
	&"motel": [&"shop", 0.3, [[&"desk clerk", 60, 2], [&"housekeeper", 50, 3], [&"manager", 130, 1]]],
	&"gas station": [&"shop", 0.4, [[&"attendant", 60, 3], [&"mechanic", 110, 1], [&"manager", 140, 1]]],
	&"clinic": [&"shop", 0.65, [[&"receptionist", 75, 2], [&"nurse", 160, 3], [&"doctor", 380, 1]]],
	&"bank branch": [&"shop", 0.8, [[&"teller", 90, 3], [&"loan officer", 180, 1], [&"branch manager", 300, 1]]],
	&"office": [&"shop", 0.85, [[&"secretary", 95, 3], [&"accountant", 200, 2], [&"lawyer", 420, 1]]],
	&"auto body": [&"workshop", 0.35, [[&"apprentice", 55, 2], [&"body man", 110, 3], [&"owner", 170, 1]]],
	&"tire shop": [&"workshop", 0.25, [[&"tire tech", 65, 3], [&"owner", 140, 1]]],
	&"chop shop": [&"workshop", 0.1, [[&"stripper", 70, 3], [&"boss", 200, 1]]],
	&"warehouse": [&"workshop", 0.3, [[&"loader", 70, 5], [&"forklift driver", 95, 2], [&"foreman", 160, 1]]],
	&"garment factory": [&"workshop", 0.2, [[&"sewer", 45, 6], [&"cutter", 65, 2], [&"floor boss", 130, 1]]],
	&"machine shop": [&"workshop", 0.5, [[&"machinist", 130, 3], [&"apprentice", 60, 2], [&"foreman", 180, 1]]],
	&"construction yard": [&"workshop", 0.4, [[&"laborer", 80, 5], [&"carpenter", 130, 2], [&"site boss", 210, 1]]],
	&"scrapyard": [&"workshop", 0.15, [[&"yard hand", 55, 3], [&"owner", 130, 1]]],
}
const POOR_PAY := 0.7     # wage multiplier on the poorest block
const RICH_PAY := 1.4     # and on the richest
const FIT := 0.25         # a trade only opens on blocks within this much of the wealth it suits (unless nothing fits)

## A trade for a business of this kind on a block of this wealth.
static func trade_for(kind: StringName, wealth: float, rng: RandomNumberGenerator) -> StringName:
	var fits: Array = []
	var any: Array = []
	for t in TRADES:
		if TRADES[t][0] != kind:
			continue
		any.append(t)
		if absf(float(TRADES[t][1]) - wealth) <= FIT:
			fits.append(t)
	var pool: Array = fits if not fits.is_empty() else any
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else &"corner store"

## A job at a business of this trade: [title, base pay].
static func pick(trade: StringName, rng: RandomNumberGenerator) -> Array:
	var jobs: Array = TRADES.get(trade, TRADES[&"corner store"])[2]
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
