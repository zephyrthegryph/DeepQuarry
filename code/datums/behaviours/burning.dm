GLOBAL_DATUM_INIT(fire_overlay, /mutable_appearance, mutable_appearance('icons/effects/fire.dmi', "fire", appearance_flags = RESET_COLOR|KEEP_APART))

/**
 * The burning state (doc/rewrite/temperature.md §5, H3; was /datum/component/burning).
 * Three parts:
 * - a heat source: BURN_POWER watts on the object's heat body;
 * - an integrity damage stream through the damage pipeline: the heat released
 *   burns fuel, BURN_ENERGY_PER_INTEGRITY joules per point of integrity;
 * - oxygen use: a gas command on the tile, O2 to CO2, BURN_OXYGEN_PER_JOULE.
 * It ends when the fuel runs out, the tile's oxygen runs out, or the object
 * cools BURN_EXTINGUISH_MARGIN below its ignition point (a heat watch).
 * The ignition rule (code/datums/rules/declarations.dm) starts it.
 * Mobs use the fire stacks status effect; their body side is H2's.
 *
 * A capability the object grants itself, ticking once a second; the burning state lives on the
 * object. Start with O.start_burning(); extinguish() ends it.
 * Can only be used on objects that use the integrity system.
 */
CAPABILITY_TYPE(burning, CAP_BURNING, /datum/capability/burning, key = NONE)
/datum/capability/burning

/datum/capability/burning/entries()
	return list(
		every(1 SECONDS, then(CAP_PROC(burn_tick))),
		extend(/datum/act/attack_hand, instead(then(CAP_PROC(burn_touched)))),
		on_notice(/datum/notice/examine, then(CAP_PROC(burn_examined))),
	)

/obj
	/// Fire overlay appearance applied while burning.
	var/burn_overlay
	/// Particle type of the shared holder, for cleanup.
	var/burn_particle_type
	/// Fuel left, J.
	var/burn_fuel = 0
	/// The heat watch that puts the fire out when the object cools.
	var/tmp/datum/native_watch/heat/burn_cool_watch
	/// Why the fire went out (BURN_ENDED_*), for tests and examine.
	var/burn_ended_by

CAPABILITIES(/obj)
	op("melee_hit", item(/obj/item), hostile(), priority(OP_PRIORITY_DEFAULT - 9), label("Hit"), then(PROC_REF(melee_hit)))
	owns_one(nameof(burn_cool_watch), /datum/native_watch/heat)
	owns_one(nameof(disposal_connection), /datum/disposal_system_connection)
	owns_one(nameof(reactive_icon), /datum/reactive_icon_update)
	owns_one(nameof(talking_atom), /datum/talking_atom)
	owns_one(nameof(attached_assembly), /obj/item/assembly)
	op("vv_mass_delete_type", topic_in(VV_TOPIC, VV_HK_MASS_DEL_TYPE), needs(req_rights(R_DEBUG|R_SERVER)), asks(/datum/prompt/choice/mass_delete_scope, step = "scope"), asks(/datum/prompt/yes_no/mass_delete, step = "sure", when = PROC_REF(mass_delete_not_cancelled)), asks(/datum/prompt/yes_no/mass_delete, fields = list("second" = TRUE), step = "again", when = PROC_REF(mass_delete_not_cancelled)), then(PROC_REF(vv_topic_mass_delete_type)))


/// TRUE while this object burns.
/obj/proc/is_burning()
	return granted(src, /datum/capability/burning)

/// Catches fire. Refused (FALSE) unless the object uses integrity and is flammable.
/obj/proc/start_burning(fire_overlay = GLOB.fire_overlay, fire_particles = /particles/smoke/burning)
	if(is_burning())
		return TRUE
	if(!uses_integrity)
		stack_trace("Tried to start burning an atom ([type]) that does not use atom_integrity!")
		return FALSE
	// only flammable atoms should burn, but it's not really an error if we try
	if(!(resistance_flags & FLAMMABLE) || (resistance_flags & FIRE_PROOF))
		return FALSE
	burn_overlay = fire_overlay
	burn_ended_by = null
	if(fire_particles)
		// burning particles look pretty bad when they stack on mobs, so that behavior is not wanted for items
		add_shared_particles(fire_particles, "[fire_particles]_[isitem(src)]", isitem(src) ? NONE : PARTICLE_ATTACH_MOB)
		burn_particle_type = fire_particles
	burn_fuel = max_integrity * BURN_ENERGY_PER_INTEGRITY
	grant(src, /datum/capability/burning, src)
	return TRUE

/datum/capability/burning/on_activate(datum/activation/A)
	var/obj/O = A.holder
	O.burning_start_heat()
	O.resistance_flags |= ON_FIRE
	if(O.burn_overlay)
		O.add_overlay(O.burn_overlay)
	O.update_icon()

/datum/capability/burning/on_deactivate(datum/activation/A)
	var/obj/O = A.holder
	O.burning_stop_heat()
	if(O.burn_particle_type)
		O.remove_shared_particles("[O.burn_particle_type]_[isitem(O)]")
		O.burn_particle_type = null
	if(!QDELETED(O))
		O.resistance_flags &= ~ON_FIRE
		if(O.burn_overlay)
			O.cut_overlay(O.burn_overlay)
		O.update_icon()
	O.burn_overlay = null

/// The heat source and the cooling watch on the object's heat body.
/obj/proc/burning_start_heat()
	if(!create_heat_body(TRUE))
		return
	vg_heat_body_keep(heat_body, TRUE)
	var/limit = burn_out_temperature()
	// A lit object is at least at its ignition point.
	if(get_temperature() < limit + BURN_EXTINGUISH_MARGIN)
		vg_heat_body_set_temperature(heat_body, limit + BURN_EXTINGUISH_MARGIN)
	vg_heat_body_power(heat_body, BURN_POWER)
	rel_set(src, nameof(burn_cool_watch), heat_watch_threshold(src, src, limit, FALSE, TYPE_PROC_REF(/obj, burning_cooled)))

/// Below this the fire goes out.
/obj/proc/burn_out_temperature()
	var/ignition = PROPERTY(src, PROP_IGNITION_POINT)
	if(isnull(ignition))
		ignition = FIRE_MINIMUM_TEMPERATURE_TO_EXIST
	return max(T0C + 50, ignition - BURN_EXTINGUISH_MARGIN)

/obj/proc/burning_stop_heat()
	rel_clear(src, nameof(burn_cool_watch))
	if(QDELETED(src) || isnull(heat_body))
		return
	vg_heat_body_power(heat_body, 0)
	if(isnull(heat_fire_turf))
		vg_heat_body_keep(heat_body, FALSE)

/// The object cooled below the burn-out temperature (burn_cool_watch).
/obj/proc/burning_cooled(datum/native_watch/heat/watch, reason, source)
	if(QDELETED(src) || !is_burning())
		return
	if(get_temperature() < burn_out_temperature())
		burning_end(BURN_ENDED_COOLED)

/obj/proc/burning_end(reason)
	burn_ended_by = reason
	extinguish()

/obj/extinguish()
	. = ..()
	if(is_burning())
		revoke(src, /datum/capability/burning, src)

/datum/capability/burning/proc/burn_tick(datum/act/timer/A)
	var/obj/O = A.holder
	O.burning_step(A.dt / (1 SECONDS))

/// One step of burning, `seconds_per_tick` long.
/obj/proc/burning_step(seconds_per_tick)
	if(QDELETED(src))
		return
	// A burnt-down object can linger at <=0 integrity in a "broken"
	// (integrity_failure) state without being qdel'd. take_damage() CRASHes on a
	// <=0-integrity atom (atom_defense.dm), so stop burning it — put the fire out
	// instead of re-damaging a wreck every tick (this was crashing repeatedly on
	// benches/furniture caught in a sustained hotspot once atmos fires actually run).
	if(uses_integrity && get_integrity() <= 0)
		extinguish()
		return
	// Check if the object somehow became fireproof, put it out if so
	if(resistance_flags & FIRE_PROOF)
		extinguish()
		return
	// Oxygen: the fire draws BURN_OXYGEN_PER_JOULE from the tile (a gas command).
	// Its heat is already on the object's body (the heat source).
	var/joules = min(BURN_POWER * seconds_per_tick, burn_fuel)
	if(!burn_gas_step(get_turf(src), joules, FALSE))
		burning_end(BURN_ENDED_OXYGEN)
		return
	// Fuel and the integrity damage stream.
	burn_fuel -= joules
	deal_damage(DAMAGE_THERMAL, joules / BURN_ENERGY_PER_INTEGRITY, FIRE, flags = DAMAGE_PACKET_SILENT)
	if(QDELETED(src) || !is_burning())
		return
	if(burn_fuel <= 0)
		burning_end(BURN_ENDED_FUEL)

/// Alerts any examiners that the object is on fire (even though it should be rather obvious)
/datum/capability/burning/proc/burn_examined(datum/notice/examine/A)
	var/obj/O = A.holder
	A.texts += span_danger("[O.p_Theyre()] burning!")

/// Handles searing the hand of anyone who tries to touch the object without protection.
/datum/capability/burning/proc/burn_touched(datum/act/attack_hand/A)
	var/obj/O = A.holder
	var/mob/living/carbon/user = A.user
	if(!iscarbon(user) || user.can_touch_burning(O))
		to_chat(user, span_notice("You put out the fire on [O]."))
		O.extinguish()
		return TRUE

	user.injure(INJURY_BURN, 5, user.hand ? BP_L_HAND : BP_R_HAND, O)
	to_chat(user, span_userdanger("You burn your hand on [O]!"))
	user.emote("scream")
	play_sfx(O, SFX_ITEMS_WEAPONS_SEAR)
	return TRUE

/**
 * The gas side of a fire releasing `joules` on `location`, shared by burning
 * objects and burning mobs: a gas command turning the oxygen it needs
 * (BURN_OXYGEN_PER_JOULE) into CO2, and, with `heat_to_gas`, the heat into the
 * tile's gas (a burning object's heat goes to its own body instead).
 * Returns FALSE, doing nothing, when the tile has too little oxygen.
 */
/proc/burn_gas_step(turf/location, joules, heat_to_gas = TRUE)
	var/datum/gas_mixture/air = location?.return_air()
	if(!air)
		return FALSE
	var/oxygen = joules * BURN_OXYGEN_PER_JOULE
	if(air.get_moles(GAS_O2) < max(oxygen, BURN_MIN_OXYGEN_MOLES))
		return FALSE
	air.adjust_multiple_gases(list(GAS_O2 = -oxygen, GAS_CO2 = oxygen))
	if(heat_to_gas)
		heat_add(air, joules, HEAT_SOURCE_FIRE)
	return TRUE
