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
 * A shared OM behaviour ticking once a second; the burning state lives on the
 * object. Start with burning_start(O); extinguish() ends it.
 * Can only be used on objects that use the integrity system.
 */
/datum/om/behaviour/burning
	every = 1 SECONDS
	handles = list(/datum/om/event/before/attack_hand, /datum/om/event/examine)

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

/obj/declared_owned_vars()
	. = ..()
	. = (. || list()) + "burn_cool_watch"

// Base-type procs cost a proc-table entry on every subtype (tools/ci/base_proc_lint.py),
// so the burning API is global procs taking the object; the heat-watch callback runs on
// the behaviour singleton.

/// TRUE while `O` burns.
/proc/burning_active(obj/O)
	return om_attached(O, /datum/om/behaviour/burning)

/// Sets `O` on fire. Refused (FALSE) unless it uses integrity and is flammable.
/proc/burning_start(obj/O, fire_overlay = GLOB.fire_overlay, fire_particles = /particles/smoke/burning)
	if(burning_active(O))
		return TRUE
	if(!O.uses_integrity)
		stack_trace("Tried to start burning an atom ([O.type]) that does not use atom_integrity!")
		return FALSE
	// only flammable atoms should burn, but it's not really an error if we try
	if(!(O.resistance_flags & FLAMMABLE) || (O.resistance_flags & FIRE_PROOF))
		return FALSE
	O.burn_overlay = fire_overlay
	O.burn_ended_by = null
	if(fire_particles)
		// burning particles look pretty bad when they stack on mobs, so that behavior is not wanted for items
		O.add_shared_particles(fire_particles, "[fire_particles]_[isitem(O)]", isitem(O) ? NONE : PARTICLE_ATTACH_MOB)
		O.burn_particle_type = fire_particles
	O.burn_fuel = O.max_integrity * BURN_ENERGY_PER_INTEGRITY
	om_attach(O, /datum/om/behaviour/burning)
	return TRUE

/datum/om/behaviour/burning/on_start(obj/O)
	burning_start_heat(O)
	O.resistance_flags |= ON_FIRE
	if(O.burn_overlay)
		O.add_overlay(O.burn_overlay)
	O.update_icon()

/datum/om/behaviour/burning/on_stop(obj/O)
	burning_stop_heat(O)
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
/proc/burning_start_heat(obj/O)
	if(!O.create_heat_body(TRUE))
		return
	vg_heat_body_keep(O.heat_body, TRUE)
	var/limit = burn_out_temperature(O)
	// A lit object is at least at its ignition point.
	if(O.get_temperature() < limit + BURN_EXTINGUISH_MARGIN)
		vg_heat_body_set_temperature(O.heat_body, limit + BURN_EXTINGUISH_MARGIN)
	vg_heat_body_power(O.heat_body, BURN_POWER)
	var/datum/om/behaviour/burning/def = om_registry().behaviour(/datum/om/behaviour/burning)
	O.burn_cool_watch = heat_watch_threshold(def, O, limit, FALSE, TYPE_PROC_REF(/datum/om/behaviour/burning, on_cooled))

/// Below this the fire goes out.
/proc/burn_out_temperature(obj/O)
	var/ignition = PROPERTY(O, PROP_IGNITION_POINT)
	if(isnull(ignition))
		ignition = FIRE_MINIMUM_TEMPERATURE_TO_EXIST
	return max(T0C + 50, ignition - BURN_EXTINGUISH_MARGIN)

/proc/burning_stop_heat(obj/O)
	QDEL_NULL(O.burn_cool_watch)
	if(QDELETED(O) || isnull(O.heat_body))
		return
	vg_heat_body_power(O.heat_body, 0)
	if(isnull(O.heat_fire_turf))
		vg_heat_body_keep(O.heat_body, FALSE)

/// The object cooled below the burn-out temperature (burn_cool_watch, owned by this
/// behaviour singleton so no proc lands on /obj).
/datum/om/behaviour/burning/proc/on_cooled(datum/native_watch/heat/watch, reason, source)
	var/obj/O = watch?.target
	if(!istype(O) || QDELETED(O) || !burning_active(O))
		return
	if(O.get_temperature() < burn_out_temperature(O))
		burning_end(O, BURN_ENDED_COOLED)

/proc/burning_end(obj/O, reason)
	O.burn_ended_by = reason
	O.extinguish()

/obj/extinguish()
	. = ..()
	if(burning_active(src))
		om_detach(src, /datum/om/behaviour/burning)

/datum/om/behaviour/burning/tick(obj/O, dt)
	// The periodic lane this replaced passed its delta in deciseconds (10 per 1 s frame);
	// keep that rate exactly.
	burning_step(O, dt * 10)

/// One step of burning `O`, `seconds_per_tick` long.
/proc/burning_step(obj/O, seconds_per_tick)
	if(QDELETED(O))
		return
	// A burnt-down object can linger at <=0 integrity in a "broken"
	// (integrity_failure) state without being qdel'd. take_damage() CRASHes on a
	// <=0-integrity atom (atom_defense.dm), so stop burning it — put the fire out
	// instead of re-damaging a wreck every tick (this was crashing repeatedly on
	// benches/furniture caught in a sustained hotspot once atmos fires actually run).
	if(O.uses_integrity && O.get_integrity() <= 0)
		O.extinguish()
		return
	// Check if the object somehow became fireproof, put it out if so
	if(O.resistance_flags & FIRE_PROOF)
		O.extinguish()
		return
	// Oxygen: the fire draws BURN_OXYGEN_PER_JOULE from the tile (a gas command).
	// Its heat is already on the object's body (the heat source).
	var/joules = min(BURN_POWER * seconds_per_tick, O.burn_fuel)
	if(!burn_gas_step(get_turf(O), joules, FALSE))
		burning_end(O, BURN_ENDED_OXYGEN)
		return
	// Fuel and the integrity damage stream.
	O.burn_fuel -= joules
	O.deal_damage(DAMAGE_THERMAL, joules / BURN_ENERGY_PER_INTEGRITY, FIRE, flags = DAMAGE_PACKET_SILENT)
	if(QDELETED(O) || !burning_active(O))
		return
	if(O.burn_fuel <= 0)
		burning_end(O, BURN_ENDED_FUEL)

/// Alerts any examiners that the object is on fire (even though it should be rather obvious)
/datum/om/behaviour/burning/on_examine(obj/O, datum/om/event/examine/event)
	event.texts += span_danger("[O.p_Theyre()] burning!")

/// Handles searing the hand of anyone who tries to touch the object without protection.
/datum/om/behaviour/burning/on_before_attack_hand(obj/O, datum/om/event/before/attack_hand/event)
	var/mob/living/carbon/user = event.user
	if(!iscarbon(user) || user.can_touch_burning(O))
		to_chat(user, span_notice("You put out the fire on [O]."))
		O.extinguish()
		return EVENT_VETO

	user.injure(INJURY_BURN, 5, user.hand ? BP_L_HAND : BP_R_HAND, O)
	to_chat(user, span_userdanger("You burn your hand on [O]!"))
	user.emote("scream")
	playsound(O, 'sound/items/weapons/sear.ogg', 50, TRUE)
	return EVENT_VETO

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
		air.add_thermal_energy(joules)
	return TRUE
