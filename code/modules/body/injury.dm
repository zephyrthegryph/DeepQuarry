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
		INJURY_CATEGORY_GENETIC,   // radiation
		INJURY_CATEGORY_GENETIC,   // cellular
		INJURY_CATEGORY_NEURAL,    // neural
		INJURY_CATEGORY_PAIN,      // pain
		INJURY_CATEGORY_PHYSICAL,  // digestion
	)
	return categories[kind]

/proc/injury_kind_name(kind)
	var/static/list/names = list("blunt trauma", "laceration", "puncture", "burn", "frostbite", "chemical burn", "electrical burn", "poisoning", "radiation", "cellular damage", "neural damage", "pain", "digestion")
	return names[kind]

/// Short name of an armour kind (INJURY_* or ARMOR_BLAST): "blunt", "blast".
/proc/armor_kind_name(kind)
	var/static/list/names = list("blunt", "cut", "pierce", "burn", "frostbite", "corrosive", "electric", "toxin", "radiation", "cellular", "neural", "pain", "digestion", "blast")
	return (kind >= 1 && kind <= ARMOR_KIND_COUNT) ? names[kind] : "unknown"

/// Is `kind` located on a body part (vs systemic)?
/proc/injury_is_located(kind)
	switch(kind)
		if(INJURY_BLUNT, INJURY_CUT, INJURY_PIERCE, INJURY_BURN, INJURY_FROSTBITE, INJURY_CORROSIVE, INJURY_ELECTRIC, INJURY_DIGESTION)
			return TRUE
	return FALSE


// --- Harm in ---------------------------------------------------------------------

/// The single entry point for harming a living mob, and the single mitigation
/// pipeline. Returns the amount actually applied after every mitigation.
/// `zone` is the target: a BP_* zone, a limb, an internal organ (organ
/// injuries become lesions; see the plan's receive_injury) or a robot
/// component; null = spread / systemic.
///
/// Mitigation runs in this order:
///   1. Armour for the hit part and kind (only for hits from outside the body,
///      INJURE_ARMORED). `armor_pen` points of it are ignored. Armour can turn
///      the edge of a cut or pierce, landing it as blunt trauma.
///   2. Energy shields (COMSIG_LIVING_SHIELD_INJURY: shields drain a cell for
///      what they absorb).
///   3. Resistance factors: BF_INCOMING_ALL x BF_INCOMING(category) (modifiers,
///      forms, species baselines, traits, reagents).
///   4. The body's species / part multiplier (immunities, prosthetics).
/// INJURE_IGNORE_RESISTANCE skips stages 2-4. Every stage is recorded when
/// the mob's injury trace is on or something listens to
/// COMSIG_LIVING_INJURY_EXPLAINED (see explain_injury_stages()).
/// Hot path: allocates nothing unless a listener or the trace needs it, and
/// only marks the vitals dirty instead of recomputing them.
/mob/living/proc/injure(kind, amount, zone = null, atom/source = null, armor_pen = 0, affliction = null, flags = NONE)
	if(amount <= 0 || !body || kind < 1 || kind > INJURY_KIND_COUNT)
		return 0
	if(status_flags & GODMODE)
		return 0
	if(_listen_lookup?[COMSIG_LIVING_INJURE])
		var/list/amount_ref = list(amount)
		if(SEND_SIGNAL(src, COMSIG_LIVING_INJURE, kind, amount_ref, zone, source, flags) & COMPONENT_CANCEL_INJURY)
			return 0
		amount = amount_ref[1]
	var/list/explain = (injury_trace || _listen_lookup?[COMSIG_LIVING_INJURY_EXPLAINED]) ? list() : null
	var/incoming_kind = kind
	var/before = amount

	// 1. Armour for the hit part and kind: the armour datum's deterministic
	// soak, which can also turn an edge or point (the force lands as blunt trauma).
	if(flags & INJURE_ARMORED)
		var/list/soaked = injury_armor_set(zone).soak(kind, amount, armor_pen, armor_factor(kind))
		amount = soaked[ARMOR_SOAK_AMOUNT]
		kind = soaked[ARMOR_SOAK_KIND]
		var/armor = soaked[ARMOR_SOAK_PROTECTION]
		if(armor > 0 && !(flags & INJURE_SILENT))
			armor_feedback(armor, zone)
		if(explain)
			explain += list(list(INJURY_STAGE_ARMOR, before, amount, "[armor]% [armor_kind_name(incoming_kind)] armour[kind != incoming_kind ? ", deflected to [injury_kind_name(kind)]" : ""]"))

	if(!(flags & INJURE_IGNORE_RESISTANCE) && amount > 0)
		// 2. Energy shields.
		if(_listen_lookup?[COMSIG_LIVING_SHIELD_INJURY])
			before = amount
			var/list/amount_ref = list(amount)
			SEND_SIGNAL(src, COMSIG_LIVING_SHIELD_INJURY, kind, amount_ref, zone, source, flags)
			amount = max(0, amount_ref[1])
			if(explain)
				explain += list(list(INJURY_STAGE_SHIELD, before, amount, "energy shield"))
		// 3. Resistance factors.
		before = amount
		var/resistance = incoming_injury_factor(injury_category(kind))
		amount *= resistance
		if(explain)
			explain += list(list(INJURY_STAGE_FACTORS, before, amount, "x[round(resistance, 0.01)] incoming factors"))
		// 4. Species / part multiplier.
		before = amount
		var/multiplier = body.injury_multiplier(kind, body.resolve_zone(zone))
		amount *= multiplier
		if(explain)
			explain += list(list(INJURY_STAGE_BODY, before, amount, "x[round(multiplier, 0.01)] species and part"))

	if(explain)
		explain_injury_stages(incoming_kind, kind, explain, zone, source, flags)
	if(amount <= 0)
		return 0
	. = body.receive_injury(kind, amount, zone, source, affliction, flags)
	if(!.)
		return
	BITSET(hud_updateflag, HEALTH_HUD)
	life_wake(LIFE_WAKE_BODY, "injure")
	if(!(flags & INJURE_SILENT))
		flash_weak_pain()
	body.on_status_changed()
	SEND_SIGNAL(src, COMSIG_LIVING_INJURED, kind, ., zone, source, flags)

/// Apply several kinds at once: alist(INJURY_BLUNT = 10, INJURY_BURN = 5).
/// (alist, because DM forbids numeric keys in a plain list literal.)
/mob/living/proc/injure_many(alist/amounts, zone = null, atom/source = null, armor_pen = 0, flags = NONE)
	. = 0
	for(var/kind in amounts)
		. += injure(kind, amounts[kind], zone, source, armor_pen, null, flags)

/// A hit from a weapon, projectile or thrown object: its declared injury kind,
/// or its `injury_kinds` split for a mixed hit. Armour applies (INJURE_ARMORED)
/// with the weapon's armour penetration unless `armor_pen` is given. Returns
/// the amount applied.
/mob/living/proc/injure_by(obj/item/weapon, amount, zone = null, armor_pen = null, flags = NONE)
	if(!weapon)
		return 0
	if(isnull(armor_pen))
		armor_pen = weapon.armor_penetration
	return injure_split(weapon.injury_kind, weapon.injury_kinds, amount, zone, weapon, armor_pen, flags | INJURE_ARMORED)

/// `amount` as `kind`, or shared out over `kinds` (INJURY_* -> share) for a
/// mixed hit. Returns the amount applied.
/mob/living/proc/injure_split(kind, alist/kinds, amount, zone = null, atom/source = null, armor_pen = 0, flags = NONE)
	if(!length(kinds))
		return injure(kind, amount, zone, source, armor_pen, null, flags)
	. = 0
	for(var/split_kind in kinds)
		. += injure(split_kind, amount * kinds[split_kind], zone, source, armor_pen, null, flags)

/// Records one injure() call's mitigation stages: sends
/// COMSIG_LIVING_INJURY_EXPLAINED and, while the injury trace is on, logs the
/// breakdown and shows it to the admins tracing this mob.
/// `stages` is a list of list(INJURY_STAGE_*, amount_in, amount_out, detail).
/mob/living/proc/explain_injury_stages(incoming_kind, kind, list/stages, zone, atom/source, flags)
	SEND_SIGNAL(src, COMSIG_LIVING_INJURY_EXPLAINED, incoming_kind, kind, stages, zone, source, flags)
	if(!injury_trace)
		return
	var/list/parts = list()
	for(var/list/stage as anything in stages)
		parts += "[stage[1]] [round(stage[2], 0.01)]->[round(stage[3], 0.01)] ([stage[4]])"
	var/line = "INJURY TRACE [key_name(src)]: [injury_kind_name(incoming_kind)] at [zone || "body"] from [source || "nothing"]: [jointext(parts, "; ")]"
	log_attack(line)
	for(var/client/C in injury_trace)
		to_chat(C, span_notice(line))

/mob/living
	/// Clients tracing this mob's injury mitigation (admin verb), or null.
	var/list/injury_trace


// --- Armour --------------------------------------------------------------------

/// The key in a worn / natural `armor` list ("melee", "bullet", ...) that
/// resists an armour kind (INJURY_* or ARMOR_BLAST), or null when no armour
/// resists it (frostbite, cellular, neural, digestion).
/proc/injury_armor_key(kind)
	switch(kind)
		if(INJURY_BLUNT, INJURY_CUT)
			return "melee"
		if(INJURY_PIERCE)
			return "bullet"
		if(INJURY_BURN)
			return "laser"
		if(INJURY_ELECTRIC, INJURY_PAIN)
			return "energy"
		if(ARMOR_BLAST)
			return "bomb"
		if(INJURY_TOXIN, INJURY_CORROSIVE)
			return "bio"
		if(INJURY_RADIATION)
			return "rad"
	return null

/// THE armour lookup: armour points against `kind` (INJURY_* or ARMOR_BLAST)
/// at `zone` (a BP_* zone, a limb or an organ; null = averaged over the body).
/// Worn / natural armour (injury_armor_set()) plus the BF_ARMOR(kind) factor.
/mob/living/proc/injury_armor(kind, zone = null)
	return armor_factor(kind) + injury_armor_set(zone).value(injury_armor_key(kind))

/// The worn / natural armour (/datum/armor) covering `zone`, before body
/// factors: what injure()'s armour stage soaks with. Defaults to the mob's own
/// innate armour (get_armor()); humans read the worn protection cache.
/mob/living/proc/injury_armor_set(zone = null)
	RETURN_TYPE(/datum/armor)
	return get_armor()

/// Armour points the body factors add against `kind`.
/mob/living/proc/armor_factor(kind)
	if(kind < 1 || kind > ARMOR_KIND_COUNT)
		return 0
	return factor(BF_ARMOR(kind))

/// Effective armour percent (0..100) against `kind` at `zone` after
/// `armor_pen` points of penetration. Deterministic: the value callers use to
/// scale secondary effects (stuns, embeds) of a hit whose harm goes through
/// injure().
/mob/living/proc/armor_against(kind, zone = null, armor_pen = 0)
	if(armor_pen >= 100)
		return 0
	return clamp(injury_armor(kind, zone) - armor_pen, 0, 100)

/// Tell the victim their armour did something.
/mob/living/proc/armor_feedback(armor, zone)
	if(armor <= 0)
		return
	var/where = istext(zone) ? " to your [parse_zone(zone)]" : ""
	if(armor >= 100)
		to_chat(src, span_danger("Your armor absorbs the blow[where]!"))
	else
		to_chat(src, span_danger("Your armor softens the blow[where]!"))


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
		life_wake(LIFE_WAKE_BODY, "mend")

/// Clear every affliction and restore the body plan's parts. Admin heal,
/// rejuvenate, resleeve.
/mob/living/proc/fully_heal()
	body?.clear_afflictions()
	body?.restore()
	BITSET(hud_updateflag, HEALTH_HUD)
	life_wake(LIFE_WAKE_BODY, "fully healed")


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


// --- Weapon vocabulary ------------------------------------------------------------------

/obj/item
	/// INJURY_* this item inflicts as a weapon (or projectile, or thrown).
	/// Its object damage (obj_integrity) is derived from it (injury_kind_obj_damage_type()).
	var/injury_kind = INJURY_BLUNT
	/// Mixed hits: INJURY_* -> share of the damage, e.g. a searing blade
	/// alist(INJURY_BURN = 1/3, INJURY_CUT = 2/3). Null = all `injury_kind`.
	var/alist/injury_kinds

/// The obj_integrity damage type (BRUTE / BURN) an injury kind does to
/// objects and structures, or null when it can't harm them (pain, toxins,
/// electricity, radiation...). The one place object damage is derived.
/proc/injury_kind_obj_damage_type(kind)
	switch(kind)
		if(INJURY_BLUNT, INJURY_CUT, INJURY_PIERCE)
			return BRUTE
		if(INJURY_BURN, INJURY_CORROSIVE)
			return BURN
	return null

/// The obj_integrity damage type this item does to objects (see injury_kind_obj_damage_type()).
/obj/item/proc/obj_damage_type()
	return injury_kind_obj_damage_type(injury_kind)
