/atom
	///any atom that uses integrity and can be damaged must set this to true, otherwise the integrity procs will throw an error
	var/uses_integrity = FALSE

	VAR_PRIVATE/atom_integrity //defaults to max_integrity
	var/max_integrity = 500
	var/integrity_failure = 0 //0 if we have no special broken behavior, otherwise is a percentage of at what point the atom breaks. 0.5 being 50%
	///Damage under this value will be completely ignored
	var/damage_deflection = 0

	var/resistance_flags = NONE // INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | ON_FIRE | UNACIDABLE | ACID_PROOF
	/// The damage flag of the last take_damage(), for the breakpoint rules' effects.
	var/tmp/last_damage_flag
	/// DAMAGE_BAND_*, kept by the damage-flavour rules (damage.md §6).
	var/tmp/damage_band = DAMAGE_BAND_NONE

/// The essential proc to call when an atom must receive damage of any kind.
/atom/proc/take_damage(damage_amount, damage_type = BRUTE, damage_flag = "", sound_effect = TRUE, attack_dir, armour_penetration = 0)
	if(!uses_integrity)
		CRASH("[src] had /atom/proc/take_damage() called on it without it being a type that has uses_integrity = TRUE!")
	if(QDELETED(src))
		// Hitscan projectiles and explosions can already have queued a second hit
		// when the first one deletes their target. The target is gone; there is no
		// state left to damage and turning that race into a runtime only adds lag.
		return
	if(atom_integrity <= 0)
		// Already at zero integrity: destruction has already fired (or another
		// damage source reached here first this same tick). Further damage is a
		// harmless no-op — update_integrity() clamps at 0 and the `previous > 0`
		// gate below ensures atom_destruction() only ever runs on the crossing, so
		// nothing here needs to run again. This used to CRASH, which spammed
		// runtimes whenever a sustained hotspot / explosion / rapid melee landed a
		// second hit on the tick an atom broke (e.g. furniture burning down in a
		// fire — ~11 runtimes/round on Southern Cross). Matches upstream /tg/, which
		// has no such assert. See dq_take_damage_on_destroyed_atom_no_crash.
		return
	if(sound_effect)
		play_attack_sound(damage_amount, damage_type, damage_flag)
	if(resistance_flags & INDESTRUCTIBLE)
		return
	damage_amount = run_atom_armor(damage_amount, damage_type, damage_flag, attack_dir, armour_penetration)
	if(damage_amount < DAMAGE_PRECISION)
		return
	if(SEND_SIGNAL(src, COMSIG_ATOM_TAKE_DAMAGE, damage_amount, damage_type, damage_flag, sound_effect, attack_dir, armour_penetration) & COMPONENT_NO_TAKE_DAMAGE)
		return

	. = damage_amount

	var/previous_atom_integrity = atom_integrity

	update_integrity(atom_integrity - damage_amount)
	contract_report_station_damage(src, previous_atom_integrity - atom_integrity)
	if(isobj(src) && max_integrity > 0)
		var/obj/damaged_object = src
		damaged_object.material_service_event(MATERIAL_EVENT_DAMAGE, 1 - atom_integrity / max_integrity)

	// Breakpoints are rules (damage.md §6, declarations.dm). Settling runs every
	// rule the change triggered now, in declaration order: break, then destroyed.
	// Objects of those types that never materialized keep the legacy crossings.
	last_damage_flag = damage_flag
	var/datum/rule_binding/binding = dq_rules_binding_replacing(src, RULE_REPLACES_INTEGRITY_BREAK|RULE_REPLACES_INTEGRITY_DESTRUCTION)
	var/rule_breaks = binding?.replaces(RULE_REPLACES_INTEGRITY_BREAK)
	var/rule_destroys = binding?.replaces(RULE_REPLACES_INTEGRITY_DESTRUCTION)
	if(binding)
		dq_rules_settle(src)

	var/integrity_failure_amount = integrity_failure * max_integrity
	//BREAKING FIRST
	if(!rule_breaks && integrity_failure && previous_atom_integrity > integrity_failure_amount && atom_integrity <= integrity_failure_amount)
		atom_break(damage_flag)

	//DESTROYING SECOND
	if(!rule_destroys && atom_integrity <= 0 && previous_atom_integrity > 0)
		atom_destruction(damage_flag)

///the sound played when the atom is damaged.
/atom/proc/play_attack_sound(damage_amount, damage_type = BRUTE, damage_flag = 0)
	switch(damage_type)
		if(BRUTE)
			if(damage_amount)
				playsound(src, 'sound/items/weapons/smash.ogg', 50, TRUE)
			else
				playsound(src, 'sound/items/weapons/tap.ogg', 50, TRUE)
		if(BURN)
			playsound(src.loc, 'sound/items/tools/welder.ogg', 100, TRUE)

/// Handles the integrity of an atom changing. This must be called instead of changing integrity directly.
/atom/proc/update_integrity(new_value)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!uses_integrity)
		CRASH("/atom/proc/update_integrity() was called on [src] when it doesn't use integrity!")
	var/old_value = atom_integrity
	new_value = max(0, new_value)
	if(atom_integrity == new_value)
		return
	atom_integrity = new_value
	on_update_integrity(old_value, new_value)
	dq_rules_publish(src, RULE_KEY_INTEGRITY)
	return new_value

/// Returns the atom's current integrity. Use this instead of reading atom_integrity (which is private).
/atom/proc/get_integrity()
	return atom_integrity

/// How much integrity the atom is missing (0 when intact).
/atom/proc/get_integrity_damage()
	return max(0, max_integrity - atom_integrity)

/// Repairs the atom by repair_amount, clamped to max_integrity. Fires atom_fix() when crossing
/// back above the integrity_failure threshold. Returns the new integrity.
/atom/proc/repair_damage(repair_amount)
	if(!uses_integrity)
		CRASH("/atom/proc/repair_damage() was called on [src] when it doesn't use integrity!")
	if(repair_amount <= 0)
		return atom_integrity
	var/integrity_failure_amount = integrity_failure * max_integrity
	var/previous_atom_integrity = atom_integrity
	update_integrity(min(max_integrity, atom_integrity + repair_amount))
	contract_report_station_repair(src, atom_integrity - previous_atom_integrity)
	if(dq_rules_binding_replacing(src, RULE_REPLACES_INTEGRITY_BREAK))
		dq_rules_settle(src)
	else if(integrity_failure && previous_atom_integrity <= integrity_failure_amount && atom_integrity > integrity_failure_amount)
		atom_fix()
	return atom_integrity

/// Handle updates to your atom's integrity
/atom/proc/on_update_integrity(old_value, new_value)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_CALL_PARENT(TRUE)

/// Called after the atom takes damage and integrity is below integrity_failure level
/atom/proc/atom_break(damage_flag)
	SHOULD_CALL_PARENT(TRUE)

/// Called when integrity is repaired above the breaking point having been broken before
/atom/proc/atom_fix()
	SHOULD_CALL_PARENT(TRUE)

///what happens when the atom's integrity reaches zero.
/atom/proc/atom_destruction(damage_flag)
	SHOULD_CALL_PARENT(TRUE)

/// The damage left of a hit after this atom's own mitigation (damage.md §4):
/// innate armour (get_armor(): the deterministic soak against `damage_flag`,
/// after `armour_penetration`), then material response (impact_factor()) for
/// the hit's DAMAGE_* kind. The kind comes from the packet being delivered
/// (receive_damage() sets GLOB.incoming_damage_kind), else from the flag.
/atom/proc/run_atom_armor(damage_amount, damage_type, damage_flag = 0, attack_dir, armour_penetration = 0)
	var/kind = GLOB.incoming_damage_kind || dq_damage_kind_for_flag(damage_flag)
	GLOB.incoming_damage_kind = 0
	if(!uses_integrity)
		CRASH("/atom/proc/run_atom_armor was called on [src] without being implemented as a type that uses integrity!")
	if(damage_flag == MELEE && damage_amount < damage_deflection)
		return 0
	if(damage_type != BRUTE && damage_type != BURN)
		return 0
	if(damage_flag)
		damage_amount = get_armor().soak_key(damage_flag, damage_amount, armour_penetration)
	damage_amount *= impact_factor(kind)
	return round(damage_amount, DAMAGE_PRECISION)

/// DAMAGE_* kind of the packet receive_damage() is delivering through
/// take_damage(), read and cleared by run_atom_armor(). 0 outside a delivery.
GLOBAL_VAR_INIT(incoming_damage_kind, 0)
