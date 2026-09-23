// Interned armour (doc/rewrite/damage.md §4, roadmap D2).
//
// Armour is an immutable /datum/armor shared by every atom with the same
// values: one datum per distinct set of numbers, not one list per instance.
//
// Declaring it: a type sets `armor_spec`, a params string of armour points
// (percent) and optional flat soak per key:
//     armor_spec = "melee=40;bullet=30;laser=30;energy=10;bomb=25"
//     armor_spec = "melee=20;melee_flat=3"
// Keys: dq_armor_keys(). Missing keys are 0. An empty string clears inherited armour.
// Per-type `armor = list(...)` declarations are gone (tools/ci/check_grep.sh,
// "interned armour", rejects them).
//
// Reading it: atom.get_armor() returns the datum; datum.value(key) reads one
// key. Changing it on one instance: set_armor(datum) with a datum from
// dq_armor(), or get_armor().with(key, value). set_armor(null) restores the type's.
//
// The soak model (deterministic):
//   effective = clamp(points + bonus - penetration, 0, 100)
//   amount   -> amount x (100 - dq_armor_average_percent(effective)) / 100
//               minus the flat soak, which penetration reduces proportionally.
// The old +/-25% roll per hit is gone; dq_armor_average_percent() is its exact
// average, so average damage is unchanged. 100 or more stops the hit.
// Randomness stays in the hit roll: whether an edge is turned
// (dq_armor_turns_edge()) is rolled against the effective protection.

/// Canonical key order of armour values.
/proc/dq_armor_keys()
	var/static/list/keys = list(MELEE, BULLET, LASER, ENERGY, BOMB, BIO, ARMOR_RAD, FIRE, ACID, ARMOR_COLD)
	return keys

/// The interned armour with `values` (key -> points; "<key>_flat" -> flat soak).
/// Identical values give the same datum. Zero entries are dropped.
/proc/dq_armor(list/values)
	var/static/list/interned = list()
	var/list/percent
	var/list/flat
	for(var/key in values)
		var/number = values[key]
		if(istext(number))
			number = text2num(number)
		if(!isnum(number) || !number)
			continue
		var/base_length = length(key) - length(ARMOR_FLAT_SUFFIX)
		if(base_length > 0 && copytext(key, base_length + 1) == ARMOR_FLAT_SUFFIX)
			LAZYSET(flat, copytext(key, 1, base_length + 1), number)
		else
			LAZYSET(percent, key, number)
	var/canonical = dq_armor_canonical(percent, flat)
	. = interned[canonical]
	if(!.)
		. = new /datum/armor(canonical, percent, flat)
		interned[canonical] = .

/// Canonical text of a set of armour values: known keys in order, then any
/// others sorted, each "key=value", flats as "key_flat=value".
/proc/dq_armor_canonical(list/percent, list/flat)
	var/list/parts = list()
	var/list/keys = dq_armor_keys()
	for(var/key in keys)
		if(percent?[key])
			parts += "[key]=[percent[key]]"
		if(flat?[key])
			parts += "[key][ARMOR_FLAT_SUFFIX]=[flat[key]]"
	var/list/others = list()
	for(var/key in percent)
		if(!(key in keys))
			others += "[key]=[percent[key]]"
	for(var/key in flat)
		if(!(key in keys))
			others += "[key][ARMOR_FLAT_SUFFIX]=[flat[key]]"
	if(length(others))
		parts += sortList(others)
	return jointext(parts, ";")

/// The armour a spec string declares. Cached by the text itself, so reading a
/// type's armour costs one lookup after the first.
/proc/dq_armor_from_spec(spec)
	var/static/list/by_spec = list()
	if(!spec)
		return dq_armor_none()
	. = by_spec[spec]
	if(!.)
		. = dq_armor(params2list(spec))
		by_spec[spec] = .

/// The armour with nothing.
/proc/dq_armor_none()
	var/static/datum/armor/none
	if(!none)
		none = dq_armor(null)
	return none

/// Mean armour percent of the old per-hit roll, which spread `effective` by
/// +/-25% (integer steps, floor of a quarter) and clamped it to 0..100. Equal
/// to `effective` up to 80; above that the clamp shaves the top. This keeps
/// average damage what it was when the roll went away.
/proc/dq_armor_average_percent(effective)
	if(effective <= 0)
		return 0
	if(effective >= 100)
		return 100
	var/spread = round(effective * 0.25)
	if(effective + spread <= 100)
		return effective
	var/total = 0
	for(var/step in -spread to spread)
		total += min(effective + step, 100)
	return total / (2 * spread + 1)

/// Effective protection, 0..100, of `points` of armour against `penetration`.
/proc/dq_armor_effective(points, penetration = 0)
	if(penetration >= 100)
		return 0
	return clamp(points - max(penetration, 0), 0, 100)

/// Whether armour at `effective` percent turns the edge or point of a hit of
/// injury kind `kind`: a cut or pierce stopped this way lands as blunt trauma.
/// The one sharp-to-blunt rule; rolled with the hit.
/proc/dq_armor_turns_edge(kind, effective)
	if(kind != INJURY_CUT && kind != INJURY_PIERCE)
		return FALSE
	return effective > 0 && prob(effective)


/datum/armor
	/// Canonical text of the values; the intern key.
	var/canonical
	/// key -> armour points (percent). Nonzero entries only. Shared; never write it.
	var/list/percent
	/// key -> flat soak, or null. Shared; never write it.
	var/list/flat

/datum/armor/New(canonical, list/percent, list/flat)
	..()
	src.canonical = canonical
	src.percent = percent
	src.flat = flat

/datum/armor/Destroy(force)
	if(!force)
		// Interned and shared; nothing may delete one.
		return QDEL_HINT_LETMELIVE
	return ..()

/datum/armor/vv_edit_var(var_name, var_value)
	return FALSE

/// Armour points (percent) against key `key`.
/datum/armor/proc/value(key)
	return percent?[key] || 0

/// Flat soak against key `key`.
/datum/armor/proc/flat_value(key)
	return flat?[key] || 0

/// TRUE when this armour has no values.
/datum/armor/proc/is_empty()
	return !length(percent) && !length(flat)

/// key -> points for every key in dq_armor_keys(), zeros included: the old
/// armour list shape, for display.
/datum/armor/proc/to_list()
	. = list()
	for(var/key in dq_armor_keys())
		.[key] = value(key)
	for(var/key in percent)
		.[key] = percent[key]

/// Every value, flats as "<key>_flat", ready for dq_armor().
/datum/armor/proc/raw_values()
	. = list()
	for(var/key in percent)
		.[key] = percent[key]
	for(var/key in flat)
		.["[key][ARMOR_FLAT_SUFFIX]"] = flat[key]

/// This armour with `key` set to `number`.
/datum/armor/proc/with(key, number)
	var/list/values = raw_values()
	values[key] = number
	return dq_armor(values)

/// This armour with every entry of `changes` (key -> number) set.
/datum/armor/proc/with_values(list/changes)
	var/list/values = raw_values()
	for(var/key in changes)
		values[key] = changes[key]
	return dq_armor(values)

/// This armour plus `other`, key by key (layers worn over one another).
/datum/armor/proc/add(datum/armor/other)
	if(!other || other.is_empty())
		return src
	if(is_empty())
		return other
	var/list/values = raw_values()
	var/list/extra = other.raw_values()
	for(var/key in extra)
		values[key] += extra[key]
	return dq_armor(values)

/// This armour with every value multiplied by `multiplier`.
/datum/armor/proc/scaled(multiplier)
	var/list/values = raw_values()
	for(var/key in values)
		values[key] *= multiplier
	return dq_armor(values)

/// Effective protection (0..100) against key `key` after `penetration`
/// points, with `bonus` points added (body factors).
/datum/armor/proc/effective(key, penetration = 0, bonus = 0)
	return dq_armor_effective(value(key) + bonus, penetration)

/// What is left of `amount` against key `key`: the deterministic soak.
/datum/armor/proc/soak_key(key, amount, penetration = 0, bonus = 0)
	if(!key || amount <= 0)
		return amount
	var/protection = effective(key, penetration, bonus)
	if(protection >= 100)
		return 0
	if(protection > 0)
		amount *= (100 - dq_armor_average_percent(protection)) / 100
	var/flat_soak = flat_value(key)
	if(flat_soak > 0 && penetration < 100)
		amount = max(0, amount - flat_soak * (100 - max(penetration, 0)) / 100)
	return amount

/// injure()'s armour stage: `amount` of injury kind `kind` against this
/// armour, `penetration` points ignored, `bonus` points added (BF_ARMOR).
/// Returns list(amount left, kind that lands, effective protection) indexed by
/// ARMOR_SOAK_*. The list is reused by the next call: read it at once.
/datum/armor/proc/soak(kind, amount, penetration = 0, bonus = 0)
	var/static/list/result = list(0, 0, 0)
	var/key = injury_armor_key(kind)
	var/protection = key ? effective(key, penetration, bonus) : 0
	result[ARMOR_SOAK_AMOUNT] = key ? soak_key(key, amount, penetration, bonus) : amount
	result[ARMOR_SOAK_KIND] = dq_armor_turns_edge(kind, protection) ? INJURY_BLUNT : kind
	result[ARMOR_SOAK_PROTECTION] = protection
	return result


// ---- Atoms ----

/atom
	/// This type's innate armour: a params string of points per key (see
	/// code/game/atom/armor.dm). Read it through get_armor().
	var/armor_spec
	/// This instance's armour when it differs from its type's (set_armor()).
	var/tmp/datum/armor/armor_override

/// This atom's armour. The one accessor: never read armour any other way.
/atom/proc/get_armor()
	RETURN_TYPE(/datum/armor)
	return armor_override || dq_armor_from_spec(armor_spec)

/// Give this instance armour `new_armor` (an interned datum); null restores
/// its type's.
/atom/proc/set_armor(datum/armor/new_armor)
	var/datum/armor/type_armor = dq_armor_from_spec(armor_spec)
	armor_override = (!new_armor || new_armor == type_armor) ? null : new_armor
	armor_changed()

/// Set one armour key on this instance.
/atom/proc/set_armor_value(key, number)
	set_armor(get_armor().with(key, number))

/// This atom's armour changed.
/atom/proc/armor_changed()
	return

/obj/item/armor_changed()
	worn_protection_changed()


// ---- Shields (damage.md §4 step 1) ----

/// The slots a holder blocks from: hands, the suit, and ears (headsets and
/// event items that shield).
/proc/dq_shield_slots()
	var/static/list/slots = list(SLOT_ID_HAND_L, SLOT_ID_HAND_R, SLOT_ID_SUIT, SLOT_ID_EAR_L, SLOT_ID_EAR_R)
	return slots

/// Mitigation step 1: does something this holder holds or wears block the hit
/// outright? Each item in dq_shield_slots() gets its handle_shield() in turn.
/// Returns what the blocking item's handle_shield() returned: positive for a
/// block, negative for a special projectile outcome (PROJECTILE_FORCE_MISS,
/// PROJECTILE_CONTINUE), 0 when nothing blocked. Hit resolution calls this
/// before a hit lands, so a blocked hit never reaches injure().
/mob/living/proc/check_shields(damage = 0, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	for(var/slot in dq_shield_slots())
		var/obj/item/shield = get_equipped_item(slot)
		if(!shield)
			continue
		. = shield.handle_shield(src, damage, damage_source, attacker, def_zone, attack_text)
		if(.)
			return
	return 0
