// Worn protection: per-zone armour, conductivity and thermal protection from
// what the mob wears (doc/rewrite/containment.md §6, roadmap C3).
//
// The body keeps, per body part flag (HEAD, UPPER_TORSO, ... HAND_RIGHT):
//   armor_by_part       the combined /datum/armor of every clothing item
//                       covering that part, accessories included: their
//                       get_armor() added key by key (interned, D2)
//   siemens_by_part     product of the siemens_coefficient of every covering
//                       item in the insulation slots
//   heat_limit_by_part  highest max_heat_protection_temperature among the
//                       insulation items whose heat_protection covers the part
//   cold_limit_by_part  lowest min_cold_protection_temperature, likewise
//   worn_insulation     surface share (dq_part_thermal_weights()) covered by
//                       thermally rated layers; scales the living mob's heat
//                       API conductance (thermal_properties())
// Read them through worn_armor_set(), worn_armor(), worn_siemens(),
// worn_heat_flags() and worn_cold_flags().
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
	/// Body part flag -> combined /datum/armor. Null when nothing is worn.
	var/alist/armor_by_part
	/// Body part flag -> siemens coefficient product; absent means 1.
	var/alist/siemens_by_part
	/// Body part flag -> highest temperature a covering item protects up to.
	var/alist/heat_limit_by_part
	/// Body part flag -> lowest temperature a covering item protects down to.
	var/alist/cold_limit_by_part
	/// Surface fraction (0..1, dq_part_thermal_weights()) covered by any
	/// thermally rated clothing: how much worn layers slow heat exchange.
	var/worn_insulation = 0

/// The body part flags the cache holds: the external limbs' body_part values.
/proc/dq_worn_zone_parts()
	var/static/list/parts = list(HEAD, UPPER_TORSO, LOWER_TORSO, LEG_LEFT, LEG_RIGHT, FOOT_LEFT, FOOT_RIGHT, ARM_LEFT, ARM_RIGHT, HAND_LEFT, HAND_RIGHT)
	return parts

/// The combined armour (/datum/armor) on body part `part` from `items`
/// (clothing in the armour slots) and their accessories. Null when nothing
/// armoured covers it.
/proc/dq_worn_armor_scan(list/items, part)
	var/list/covering = dq_worn_covering(items, part)
	var/datum/armor/combined
	for(var/obj/item/clothing/gear as anything in covering)
		var/datum/armor/layer = gear.get_armor()
		if(layer.is_empty())
			continue
		combined = combined ? combined.add(layer) : layer
	return combined

/// The clothing in `items` and the accessories on it that cover body part flag `part`.
/proc/dq_worn_covering(list/items, part)
	. = list()
	for(var/obj/item/clothing/gear in items)
		if(gear.body_parts_covered & part)
			. |= gear
		for(var/obj/item/clothing/accessory/bling in gear.accessories)
			if(bling.body_parts_covered & part)
				. |= bling

/// Clothing and accessories in this mob's armour slots covering body part flag `part`.
/mob/living/proc/covering_items(part)
	return dq_worn_covering(body_slot_items(BODY_SLOT_ARMOR), part)

/// The body part flag (HEAD, UPPER_TORSO, ...) of body zone `zone` (BP_*), or NONE.
/proc/dq_zone_body_part_flag(zone)
	var/static/alist/flags = alist(
		BP_HEAD = HEAD, BP_TORSO = UPPER_TORSO, BP_GROIN = LOWER_TORSO,
		BP_L_ARM = ARM_LEFT, BP_R_ARM = ARM_RIGHT, BP_L_HAND = HAND_LEFT, BP_R_HAND = HAND_RIGHT,
		BP_L_LEG = LEG_LEFT, BP_R_LEG = LEG_RIGHT, BP_L_FOOT = FOOT_LEFT, BP_R_FOOT = FOOT_RIGHT,
	)
	return flags[zone] || NONE

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
	worn_insulation = 0
	var/list/armor_items = owner?.body_slot_items(BODY_SLOT_ARMOR)
	var/list/insulation_items = owner?.body_slot_items(BODY_SLOT_INSULATION)
	if(!length(armor_items) && !length(insulation_items))
		return
	var/list/parts = dq_worn_zone_parts()
	for(var/part in parts)
		var/datum/armor/combined = dq_worn_armor_scan(armor_items, part)
		if(combined)
			if(!armor_by_part)
				armor_by_part = alist()
			armor_by_part[part] = combined
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

	var/insulated = NONE
	for(var/part in heat_limit_by_part)
		insulated |= part
	for(var/part in cold_limit_by_part)
		insulated |= part
	worn_insulation = dq_thermal_surface(insulated)

/// The combined worn armour (/datum/armor) on body part flag `part`; the
/// empty armour when nothing armoured covers it. What injure()'s armour stage
/// soaks with (through /mob/living/proc/injury_armor_set()).
/datum/body/proc/worn_armor_set(part)
	RETURN_TYPE(/datum/armor)
	if(!part)
		return dq_armor_none()
	ensure_worn_protection()
	var/datum/armor/combined
	if(part in dq_worn_zone_parts())
		combined = armor_by_part?[part]
	else
		combined = dq_worn_armor_scan(owner.body_slot_items(BODY_SLOT_ARMOR), part)
	return combined || dq_armor_none()

/// Worn armour points against armour key `key` on body part flag `part`.
/datum/body/proc/worn_armor(part, key)
	if(!key || !part)
		return 0
	return worn_armor_set(part).value(key)

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

/// Fraction (0..1) of the body's surface protected from air at `temperature`:
/// the heat limits when `temperature` is above body heat, the cold limits
/// below. 1 means worn layers seal the body from it.
/datum/body/proc/worn_thermal_protection(temperature, cold)
	return dq_thermal_surface(cold ? worn_cold_flags(temperature) : worn_heat_flags(temperature))

/// Surface fraction of the covered clothing layers (0..1).
/datum/body/proc/get_worn_insulation()
	ensure_worn_protection()
	return worn_insulation

/// Body part flag -> share of the body's surface (sums to 1).
/proc/dq_part_thermal_weights()
	var/static/alist/weights = alist(
		HEAD = THERMAL_PROTECTION_HEAD,
		UPPER_TORSO = THERMAL_PROTECTION_UPPER_TORSO,
		LOWER_TORSO = THERMAL_PROTECTION_LOWER_TORSO,
		LEG_LEFT = THERMAL_PROTECTION_LEG_LEFT,
		LEG_RIGHT = THERMAL_PROTECTION_LEG_RIGHT,
		FOOT_LEFT = THERMAL_PROTECTION_FOOT_LEFT,
		FOOT_RIGHT = THERMAL_PROTECTION_FOOT_RIGHT,
		ARM_LEFT = THERMAL_PROTECTION_ARM_LEFT,
		ARM_RIGHT = THERMAL_PROTECTION_ARM_RIGHT,
		HAND_LEFT = THERMAL_PROTECTION_HAND_LEFT,
		HAND_RIGHT = THERMAL_PROTECTION_HAND_RIGHT,
	)
	return weights

/// Surface share (0..1) of body part flags `flags`.
/proc/dq_thermal_surface(flags)
	. = 0
	if(!flags)
		return
	var/alist/weights = dq_part_thermal_weights()
	for(var/part in weights)
		if(flags & part)
			. += weights[part]
	return min(., 1)

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

/// Worn layers slow a living mob's heat coupling to its surroundings (the heat
/// API's conductance) by the share of its body they cover, down to
/// WORN_INSULATION_MIN_CONDUCTANCE of bare skin when fully covered.
/mob/living/thermal_properties()
	. = ..()
	var/insulation = body?.get_worn_insulation()
	if(insulation)
		.[THERMAL_CONDUCTANCE] *= 1 - insulation * (1 - WORN_INSULATION_MIN_CONDUCTANCE)

/// Something this mob wears changed: the worn protection cache is stale.
/mob/living/proc/worn_protection_changed()
	body?.invalidate(BODY_DIRTY_ARMOR)
