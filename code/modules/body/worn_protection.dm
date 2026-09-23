// Worn protection: per-zone armour, conductivity and thermal protection from
// what the mob wears (doc/rewrite/containment.md §6, roadmap C3).
//
// The body keeps, per body part flag (HEAD, UPPER_TORSO, ... HAND_RIGHT):
//   armor_by_part       armour key ("melee", ...) -> points of every clothing
//                       item covering that part, accessories included (the
//                       old get_covering_clothing() sum)
//   siemens_by_part     product of the siemens_coefficient of every covering
//                       item in the insulation slots
//   heat_limit_by_part  highest max_heat_protection_temperature among the
//                       insulation items whose heat_protection covers the part
//   cold_limit_by_part  lowest min_cold_protection_temperature, likewise
// Read them through worn_armor(), worn_siemens(), worn_heat_flags() and
// worn_cold_flags().
// It holds numbers only, never item references, and is rebuilt in one pass
// the first time it is read after BODY_DIRTY_ARMOR is set.
//
// What sets BODY_DIRTY_ARMOR:
//   - a ledger move in or out of a body slot (/mob/living/on_slot_changed());
//   - LEGACY: /obj/item/equipped() and dropped() (factors.dm) and
//     /mob/living/on_equipment_changed(), until equip is a ledger move;
//   - /obj/item/proc/worn_protection_changed(): anything that changes a worn
//     item's armour, coverage, conductivity or thermal protection in place
//     (toggles, rig seals, accessories) calls it.
//
// Which slots count is data on the slot definitions (BODY_SLOT_ARMOR,
// BODY_SLOT_INSULATION), read through body_slot_items().

/datum/body
	/// Body part flag -> list(armour key -> points). Null when nothing is worn.
	var/alist/armor_by_part
	/// Body part flag -> siemens coefficient product; absent means 1.
	var/alist/siemens_by_part
	/// Body part flag -> highest temperature a covering item protects up to.
	var/alist/heat_limit_by_part
	/// Body part flag -> lowest temperature a covering item protects down to.
	var/alist/cold_limit_by_part

/// The body part flags the cache holds: the external limbs' body_part values.
/proc/dq_worn_zone_parts()
	var/static/list/parts = list(HEAD, UPPER_TORSO, LOWER_TORSO, LEG_LEFT, LEG_RIGHT, FOOT_LEFT, FOOT_RIGHT, ARM_LEFT, ARM_RIGHT, HAND_LEFT, HAND_RIGHT)
	return parts

/// Armour key -> points on body part `part` from `items` (clothing in the armour
/// slots) and their accessories. Null when nothing covers it.
/proc/dq_worn_armor_scan(list/items, part)
	var/list/covering = list()
	for(var/obj/item/clothing/gear in items)
		if(gear.body_parts_covered & part)
			covering |= gear
		for(var/obj/item/clothing/accessory/bling in gear.accessories)
			if(bling.body_parts_covered & part)
				covering |= bling
	var/list/points
	for(var/obj/item/clothing/gear as anything in covering)
		for(var/key in gear.armor)
			LAZYINITLIST(points)
			points[key] += gear.armor[key]
	return points

/// Product of the conductivity of `items` (clothing in the insulation slots) covering `part`.
/proc/dq_worn_siemens_scan(list/items, part)
	. = 1
	for(var/obj/item/clothing/C in items)
		if(C.body_parts_covered & part)
			. *= C.siemens_coefficient

/// Rebuilds the cache if it is stale.
/datum/body/proc/ensure_worn_protection()
	if(!(dirty & BODY_DIRTY_ARMOR))
		return
	dirty &= ~BODY_DIRTY_ARMOR
	armor_by_part = null
	siemens_by_part = null
	heat_limit_by_part = null
	cold_limit_by_part = null
	var/list/armor_items = owner?.body_slot_items(BODY_SLOT_ARMOR)
	var/list/insulation_items = owner?.body_slot_items(BODY_SLOT_INSULATION)
	if(!length(armor_items) && !length(insulation_items))
		return
	var/list/parts = dq_worn_zone_parts()
	for(var/part in parts)
		var/list/points = dq_worn_armor_scan(armor_items, part)
		if(points)
			if(!armor_by_part)
				armor_by_part = alist()
			armor_by_part[part] = points
		var/siemens = dq_worn_siemens_scan(insulation_items, part)
		if(siemens != 1)
			if(!siemens_by_part)
				siemens_by_part = alist()
			siemens_by_part[part] = siemens
	for(var/obj/item/clothing/C in insulation_items)
		var/heat = C.worn_heat_limit()
		if(!isnull(heat))
			var/heat_flags = C.get_heat_protection_flags()
			for(var/part in parts)
				if(!(heat_flags & part))
					continue
				if(!heat_limit_by_part)
					heat_limit_by_part = alist()
				var/current = heat_limit_by_part[part]
				if(isnull(current) || heat > current)
					heat_limit_by_part[part] = heat
		var/cold = C.worn_cold_limit()
		if(!isnull(cold))
			var/cold_flags = C.get_cold_protection_flags()
			for(var/part in parts)
				if(!(cold_flags & part))
					continue
				if(!cold_limit_by_part)
					cold_limit_by_part = alist()
				var/current = cold_limit_by_part[part]
				if(isnull(current) || cold < current)
					cold_limit_by_part[part] = cold

/// Worn armour points against armour key `key` on body part flag `part`.
/datum/body/proc/worn_armor(part, key)
	if(!key || !part)
		return 0
	ensure_worn_protection()
	var/list/points
	if(part in dq_worn_zone_parts())
		points = armor_by_part?[part]
	else
		points = dq_worn_armor_scan(owner.body_slot_items(BODY_SLOT_ARMOR), part)
	return points?[key] || 0

/// Siemens coefficient of what is worn over body part flag `part` (1 = bare).
/datum/body/proc/worn_siemens(part)
	if(!part)
		return 1
	ensure_worn_protection()
	if(part in dq_worn_zone_parts())
		var/siemens = siemens_by_part?[part]
		return isnull(siemens) ? 1 : siemens
	return dq_worn_siemens_scan(owner.body_slot_items(BODY_SLOT_INSULATION), part)

/// Body part flags protected from heat at `temperature`: the old
/// get_heat_protection_flags() answer, restricted to the parts thermal
/// protection counts.
/datum/body/proc/worn_heat_flags(temperature)
	. = 0
	ensure_worn_protection()
	for(var/part in heat_limit_by_part)
		if(heat_limit_by_part[part] >= temperature)
			. |= part

/// Body part flags protected from cold at `temperature`.
/datum/body/proc/worn_cold_flags(temperature)
	. = 0
	ensure_worn_protection()
	for(var/part in cold_limit_by_part)
		if(cold_limit_by_part[part] <= temperature)
			. |= part

// ---- Items ----

/// Highest temperature this item or any accessory on it protects up to, or
/// null. The item protects at T exactly when this is at least T, which is what
/// handle_high_temperature() answers.
/obj/item/clothing/proc/worn_heat_limit()
	. = max_heat_protection_temperature || null
	for(var/obj/item/clothing/C in accessories)
		var/limit = C.worn_heat_limit()
		if(!isnull(limit) && (isnull(.) || limit > .))
			. = limit

/// Lowest temperature this item or any accessory on it protects down to, or null.
/obj/item/clothing/proc/worn_cold_limit()
	. = min_cold_protection_temperature || null
	for(var/obj/item/clothing/C in accessories)
		var/limit = C.worn_cold_limit()
		if(!isnull(limit) && (isnull(.) || limit < .))
			. = limit

/// This item's armour, coverage, conductivity or thermal protection changed in
/// place: whoever wears it (directly, or through the clothing it is attached
/// to) recomputes their worn protection.
/obj/item/proc/worn_protection_changed()
	for(var/atom/A = loc; A && !isturf(A); A = A.loc)
		if(isliving(A))
			var/mob/living/L = A
			L.worn_protection_changed()
			return

/// Something this mob wears changed: the worn protection cache is stale.
/mob/living/proc/worn_protection_changed()
	body?.invalidate(BODY_DIRTY_ARMOR)
