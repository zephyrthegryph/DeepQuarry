// Harm in, healing in, and the questions everyone else asks.
// See doc/body_architecture.md §2, §3, §5.

/// INJURY_* -> INJURY_CATEGORY_*.
/proc/injury_category(kind)
	var/static/list/categories = list(
		INJURY_CATEGORY_PHYSICAL,  // blunt
		INJURY_CATEGORY_PHYSICAL,  // cut
		INJURY_CATEGORY_PHYSICAL,  // pierce
		INJURY_CATEGORY_THERMAL,   // burn
		INJURY_CATEGORY_THERMAL,   // frostbite
		INJURY_CATEGORY_THERMAL,   // corrosive
		INJURY_CATEGORY_THERMAL,   // electric
		INJURY_CATEGORY_TOXIC,     // toxin
		INJURY_CATEGORY_ASPHYXIA,  // asphyxia
		INJURY_CATEGORY_GENETIC,   // radiation
		INJURY_CATEGORY_GENETIC,   // cellular
		INJURY_CATEGORY_NEURAL,    // neural
		INJURY_CATEGORY_PAIN,      // pain
		INJURY_CATEGORY_PHYSICAL,  // digestion
	)
	return categories[kind]

/proc/injury_kind_name(kind)
	var/static/list/names = list("blunt trauma", "laceration", "puncture", "burn", "frostbite", "chemical burn", "electrical burn", "poisoning", "asphyxiation", "radiation", "cellular damage", "neural damage", "pain", "digestion")
	return names[kind]

/// Is `kind` located on a body part (vs systemic)?
/proc/injury_is_located(kind)
	switch(kind)
		if(INJURY_BLUNT, INJURY_CUT, INJURY_PIERCE, INJURY_BURN, INJURY_FROSTBITE, INJURY_CORROSIVE, INJURY_ELECTRIC, INJURY_DIGESTION)
			return TRUE
	return FALSE


// --- Harm in ---------------------------------------------------------------------

/// The single entry point for harming a living mob. Returns the amount
/// actually applied after every mitigation.
/// `zone` is the target: a BP_* zone, a limb, an internal organ (organ
/// injuries become lesions; see the plan's receive_injury) or a robot
/// component; null = spread / systemic.
/// Hot path: allocates nothing unless something listens to
/// COMSIG_LIVING_INJURE, and only marks the vitals dirty (plus a cheap death
/// check) instead of recomputing them.
/mob/living/proc/injure(kind, amount, zone = null, atom/source = null, armor = 0, affliction = null, flags = NONE)
	if(amount <= 0 || !body || kind < 1 || kind > INJURY_KIND_COUNT)
		return 0
	if(status_flags & GODMODE)
		return 0
	if(_listen_lookup?[COMSIG_LIVING_INJURE])
		var/list/amount_ref = list(amount)
		if(SEND_SIGNAL(src, COMSIG_LIVING_INJURE, kind, amount_ref, zone, source, flags) & COMPONENT_CANCEL_INJURY)
			return 0
		amount = amount_ref[1]
	if(!(flags & INJURE_IGNORE_RESISTANCE))
		amount = mitigate_injury(kind, amount)
		amount *= body.injury_multiplier(kind, body.resolve_zone(zone))
	if(armor)
		if(armor >= 100)
			return 0
		amount *= (100 - armor) / 100
	if(amount <= 0)
		return 0
	. = body.receive_injury(kind, amount, zone, source, affliction, flags)
	if(!.)
		return
	BITSET(hud_updateflag, HEALTH_HUD)
	if(!(flags & INJURE_SILENT) && injury_category(kind) != INJURY_CATEGORY_ASPHYXIA)
		flash_weak_pain()
	body.on_status_changed()
	SEND_SIGNAL(src, COMSIG_LIVING_INJURED, kind, ., zone, source, flags)

/// Apply several kinds at once: alist(INJURY_BLUNT = 10, INJURY_BURN = 5).
/// (alist, because DM forbids numeric keys in a plain list literal.)
/mob/living/proc/injure_many(alist/amounts, zone = null, atom/source = null, armor = 0, flags = NONE)
	. = 0
	for(var/kind in amounts)
		. += injure(kind, amounts[kind], zone, source, armor, null, flags)

/// Factor-based mitigation: the overall and per-category incoming
/// multipliers (modifiers, forms, species, reagents). Energy shields scale
/// the amount earlier, on COMSIG_LIVING_INJURE, because they drain a cell.
/mob/living/proc/mitigate_injury(kind, amount)
	return amount * incoming_injury_factor(injury_category(kind))


// --- Healing in ------------------------------------------------------------------

/// Instant treatment by mechanism: the only way to heal. `target` is a zone,
/// a limb, an internal organ or a robot component (null = whole body).
/// Natural regeneration is TREAT_REGENERATION; admin, magic and species
/// restoration is TREAT_RESTORATION (every biology, full repair). Returns the
/// amount treated.
/mob/living/proc/mend(tag, amount, target = null)
	if(!body || amount <= 0)
		return 0
	amount *= factor(BF_HEALING_RECEIVED)
	. = body.mend(tag, amount, target)
	if(.)
		BITSET(hud_updateflag, HEALTH_HUD)

/// Clear every affliction and restore the body plan's parts. Admin heal,
/// rejuvenate, resleeve.
/mob/living/proc/fully_heal()
	body?.clear_afflictions()
	body?.restore()
	BITSET(hud_updateflag, HEALTH_HUD)


// --- Questions ----------------------------------------------------------------------

/// 0..1 fraction of wellness left. HUDs, AI flee thresholds, boss phases,
/// belly health bars, stat panels.
/mob/living/proc/vitality()
	return body ? body.get_vitality() : 1

/// Down from injury (unconscious from injury, or would be).
/mob/living/proc/is_critical()
	return stat == UNCONSCIOUS && HAS_TRAIT(src, TRAIT_CRITICAL_CONDITION)

/// Toughness including body factors.
/mob/living/proc/get_endurance()
	return (endurance + factor(BF_ENDURANCE_FLAT)) * factor(BF_ENDURANCE_MULT)

/// Injury load in a category (INJURY_CATEGORY_*).
/mob/living/proc/injury_load(category)
	return body ? body.injury_load(category) : 0

/// Any injury at all?
/mob/living/proc/is_injured()
	return body?.is_injured()

/mob/living/proc/current_pain()
	return body ? body.get_pain() : 0

/mob/living/proc/find_affliction(affliction_type, location = null)
	return body?.find_affliction(affliction_type, location)

/mob/living/proc/has_affliction(affliction_type)
	return body?.has_affliction(affliction_type)

/mob/living/proc/get_afflictions()
	return body?.afflictions || list()


// --- Item / projectile helpers ---------------------------------------------------------

/obj/item
	/// INJURY_* this item inflicts as a weapon. Null = derive from damtype,
	/// sharp and edge (see injury_kind_for).
	var/injury_kind

/// Injury kind this item inflicts when used as a weapon.
/obj/item/proc/get_injury_kind()
	return injury_kind || injury_kind_for(damtype, sharp, edge)

/// Legacy damtype + sharp/edge -> INJURY_* kind.
/proc/injury_kind_for(damtype, sharp = FALSE, edge = FALSE)
	switch(damtype)
		if(BURN)
			return INJURY_BURN
		if(ELECTROCUTE)
			return INJURY_ELECTRIC
		if(BIOACID)
			return INJURY_CORROSIVE
		if(SEARING)
			return INJURY_BURN
		if(HALLOSS)
			return INJURY_PAIN
		if(TOX)
			return INJURY_TOXIN
		if(OXY)
			return INJURY_ASPHYXIA
		if(CLONE)
			return INJURY_CELLULAR
		if(IRRADIATE)
			return INJURY_RADIATION
	if(sharp && edge)
		return INJURY_CUT
	if(sharp)
		return INJURY_PIERCE
	return INJURY_BLUNT
