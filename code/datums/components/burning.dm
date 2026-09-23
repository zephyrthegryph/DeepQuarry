GLOBAL_DATUM_INIT(fire_overlay, /mutable_appearance, mutable_appearance('icons/effects/fire.dmi', "fire", appearance_flags = RESET_COLOR|KEEP_APART))

/**
 * The burning state (doc/rewrite/temperature.md §5, H3). Three parts:
 * - a heat source: BURN_POWER watts on the parent's heat body;
 * - an integrity damage stream through the damage pipeline: the heat released
 *   burns fuel, BURN_ENERGY_PER_INTEGRITY joules per point of integrity;
 * - oxygen use: a gas command on the tile, O2 to CO2, BURN_OXYGEN_PER_JOULE.
 * It ends when the fuel runs out, the tile's oxygen runs out, or the parent
 * cools BURN_EXTINGUISH_MARGIN below its ignition point (a heat watch).
 * The ignition rule (code/datums/rules/declarations.dm) starts it.
 * Mobs use the fire stacks status effect; their body side is H2's.
 * Can only be used on atoms that use the integrity system.
 */
/datum/component/burning
	/// Fire overlay appearance we apply
	var/fire_overlay
	/// Particle holder for fire particles, if any. Still utilized over shared holders because they're movable-only
	var/obj/effect/abstract/particle_holder/particle_effect
	/// Particle type we're using for cleaning up our shared holder
	var/particle_type
	/// Fuel left, J.
	var/fuel = 0
	/// The heat watch that puts the fire out when the parent cools.
	var/cool_watch
	/// Why the fire went out (BURN_ENDED_*), for tests and examine.
	var/ended_by

/datum/component/burning/Initialize(fire_overlay = GLOB.fire_overlay, fire_particles = /particles/smoke/burning)
	if(!isatom(parent))
		return COMPONENT_INCOMPATIBLE
	var/atom/atom_parent = parent
	if(!atom_parent.uses_integrity)
		stack_trace("Tried to add /datum/component/burning to an atom ([atom_parent.type]) that does not use atom_integrity!")
		return COMPONENT_INCOMPATIBLE

	// only flammable atoms should have this component, but it's not really an error if we try to apply this to a non flammable one
	if(!(atom_parent.resistance_flags & FLAMMABLE) || (atom_parent.resistance_flags & FIRE_PROOF))
		qdel(src)
		return

	src.fire_overlay = fire_overlay
	if (fire_particles)
		if(ismovable(parent))
			var/atom/movable/movable_parent = parent
			// burning particles look pretty bad when they stack on mobs, so that behavior is not wanted for items
			movable_parent.add_shared_particles(fire_particles, "[fire_particles]_[isitem(parent)]", isitem(parent) ? NONE : PARTICLE_ATTACH_MOB)
			particle_type = fire_particles
		else
			particle_effect = new(atom_parent, fire_particles)
	fuel = atom_parent.max_integrity * BURN_ENERGY_PER_INTEGRITY
	start_heat()
	START_PROCESSING(SSburning, src)

/// The heat source and the cooling watch on the parent's heat body.
/datum/component/burning/proc/start_heat()
	var/atom/atom_parent = parent
	if(!atom_parent.create_heat_body(TRUE))
		return
	vg_heat_body_keep(atom_parent.heat_body, TRUE)
	var/limit = burn_out_temperature()
	// A lit object is at least at its ignition point.
	if(atom_parent.get_temperature() < limit + BURN_EXTINGUISH_MARGIN)
		vg_heat_body_set_temperature(atom_parent.heat_body, limit + BURN_EXTINGUISH_MARGIN)
	vg_heat_body_power(atom_parent.heat_body, BURN_POWER)
	cool_watch = heat_watch_threshold(atom_parent, limit, FALSE)

/// Below this the fire goes out.
/datum/component/burning/proc/burn_out_temperature()
	var/ignition = PROPERTY(parent, PROP_IGNITION_POINT)
	if(isnull(ignition))
		ignition = FIRE_MINIMUM_TEMPERATURE_TO_EXIST
	return max(T0C + 50, ignition - BURN_EXTINGUISH_MARGIN)

/datum/component/burning/proc/stop_heat()
	if(!isnull(cool_watch))
		heat_unwatch(cool_watch)
		cool_watch = null
	heat_unsubscribe()
	var/atom/atom_parent = parent
	if(QDELETED(atom_parent) || isnull(atom_parent.heat_body))
		return
	vg_heat_body_power(atom_parent.heat_body, 0)
	var/atom/movable/movable_parent = atom_parent
	if(!istype(movable_parent) || isnull(movable_parent.heat_fire_turf))
		vg_heat_body_keep(atom_parent.heat_body, FALSE)

/// The parent cooled below the burn-out temperature.
/datum/component/burning/on_heat_wake(watch, reason, source)
	if(watch != cool_watch || QDELETED(src))
		return
	var/atom/atom_parent = parent
	if(atom_parent.get_temperature() < burn_out_temperature())
		end_burning(BURN_ENDED_COOLED)

/datum/component/burning/proc/end_burning(reason)
	ended_by = reason
	var/atom/atom_parent = parent
	atom_parent.extinguish()

/datum/component/burning/Destroy(force)
	STOP_PROCESSING(SSburning, src)
	stop_heat()
	fire_overlay = null
	if(particle_effect)
		QDEL_NULL(particle_effect)
	if (ismovable(parent) && particle_type)
		var/atom/movable/movable_parent = parent
		movable_parent.remove_shared_particles("[particle_type]_[isitem(parent)]")
	return ..()

/datum/component/burning/RegisterWithParent()
	RegisterSignal(parent, COMSIG_ATOM_ATTACK_HAND, PROC_REF(on_attack_hand))
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))
	RegisterSignal(parent, COMSIG_ATOM_EXTINGUISH, PROC_REF(on_extinguish))
	var/atom/atom_parent = parent
	atom_parent.resistance_flags |= ON_FIRE
	if(fire_overlay)
		atom_parent.add_overlay(fire_overlay)
	atom_parent.update_icon()

/datum/component/burning/UnregisterFromParent()
	UnregisterSignal(parent, list(
		COMSIG_ATOM_ATTACK_HAND,
		COMSIG_ATOM_EXAMINE,
		COMSIG_ATOM_EXTINGUISH,
	))
	var/atom/atom_parent = parent
	if(!QDELETED(atom_parent))
		atom_parent.resistance_flags &= ~ON_FIRE
		if(fire_overlay)
			atom_parent.cut_overlay(fire_overlay)
		atom_parent.update_icon()

/datum/component/burning/process(seconds_per_tick)
	var/atom/atom_parent = parent
	if(QDELETED(atom_parent))
		return // parent's gone; the component tears down with it
	// A burnt-down object can linger at <=0 integrity in a "broken"
	// (integrity_failure) state without being qdel'd. take_damage() CRASHes on a
	// <=0-integrity atom (atom_defense.dm), so stop burning it — put the fire out
	// instead of re-damaging a wreck every tick (this was crashing repeatedly on
	// benches/furniture caught in a sustained hotspot once atmos fires actually run).
	if(atom_parent.uses_integrity && atom_parent.get_integrity() <= 0)
		atom_parent.extinguish()
		return
	// Check if the parent somehow became fireproof, remove component if so
	if(atom_parent.resistance_flags & FIRE_PROOF)
		atom_parent.extinguish()
		return
	// Oxygen: the fire draws BURN_OXYGEN_PER_JOULE from the tile (a gas command).
	// Its heat is already on the parent's body (the heat source).
	var/joules = min(BURN_POWER * seconds_per_tick, fuel)
	if(!burn_gas_step(get_turf(atom_parent), joules, FALSE))
		end_burning(BURN_ENDED_OXYGEN)
		return
	// Fuel and the integrity damage stream.
	fuel -= joules
	atom_parent.deal_damage(DAMAGE_THERMAL, joules / BURN_ENERGY_PER_INTEGRITY, FIRE, flags = DAMAGE_PACKET_SILENT)
	if(QDELETED(atom_parent) || QDELETED(src))
		return
	if(fuel <= 0)
		end_burning(BURN_ENDED_FUEL)

/// Alerts any examiners that the parent is on fire (even though it should be rather obvious)
/datum/component/burning/proc/on_examine(atom/source, mob/user, list/examine_list)
	SIGNAL_HANDLER

	examine_list += span_danger("[source.p_Theyre()] burning!")

/// Handles searing the hand of anyone who tries to touch parent without protection.
/datum/component/burning/proc/on_attack_hand(atom/source, mob/living/carbon/user)
	SIGNAL_HANDLER

	if(!iscarbon(user) || user.can_touch_burning(source))
		to_chat(user, span_notice("You put out the fire on [source]."))
		source.extinguish()
		return COMPONENT_CANCEL_ATTACK_CHAIN

	user.injure(INJURY_BURN, 5, user.hand ? BP_L_HAND : BP_R_HAND, source)
	to_chat(user, span_userdanger("You burn your hand on [source]!"))
	user.emote("scream")
	playsound(source, 'sound/items/weapons/sear.ogg', 50, TRUE)
	return COMPONENT_CANCEL_ATTACK_CHAIN

/// Deletes the component when the atom gets extinguished
/datum/component/burning/proc/on_extinguish(atom/source, list/overlays)
	SIGNAL_HANDLER

	qdel(src)

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
