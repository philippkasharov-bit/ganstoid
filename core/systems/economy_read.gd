## E5: what you can tell about a place by looking it over (casing it): rough
## words, never the exact sums. A home: well off, getting by or nearly broke,
## and whether it was hit lately. A shop: busy, quiet or struggling (or
## closed), and what security it has. Pure reads.
class_name EconomyRead
extends RefCounted

## A short read of a home or shop for the action menu ("well off · hit lately").
static func building(b: BuildingData) -> String:
	if b == null:
		return ""
	var bits: PackedStringArray = []
	if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
		if b.status >= 2:
			return "closed down"
		bits.append("struggling" if b.status == 1 else ("busy" if b.last_sales >= b.daily_revenue * 0.6 else "quiet"))
		if b.security > 0:
			bits.append(["camera", "guard", "armed guard"][clampi(b.security, 1, 3) - 1])
	else:
		var money := b.cash_on_hand + b.bank
		bits.append("well off" if money >= 1500 else ("getting by" if money >= 200 else "nearly broke"))
	if b.hits >= 0.5:
		bits.append("hit lately")
	return " · ".join(bits)

## How a block is doing, in a word, with its street market ("Poor · strong street").
static func block(bl: Dictionary) -> String:
	var street := "strong street" if float(bl["black"]) >= 0.6 else ("some street" if float(bl["black"]) >= 0.35 else "quiet street")
	return "%s · %s" % [BlockEconomyData.describe(float(bl["wealth"])), street]
