// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/////////// BUBBER EDIT THIS WILL BE FORCED TO CONFLICT READ THIS
/*
	RESET THIS FILE BACK TO TG ONCE YOU GET FISH INFUSION
	RESET THIS FILE BACK TO TG ONCE YOU GET FISH INFUSION
	RESET THIS FILE BACK TO TG ONCE YOU GET FISH INFUSION
	RESET THIS FILE BACK TO TG ONCE YOU GET FISH INFUSION

*/
/datum/status_effect/fire_handler
	duration = STATUS_EFFECT_PERMANENT
	id = STATUS_EFFECT_ID_ABSTRACT
	alert_type = null
	status_type = STATUS_EFFECT_REFRESH //Custom code
	on_remove_on_mob_delete = TRUE
	tick_interval = 2 SECONDS
	processing_speed = STATUS_EFFECT_PRIORITY
	/// Current amount of stacks we have
	var/stacks
	/// Maximum of stacks that we could possibly get
	var/stack_limit = MAX_FIRE_STACKS
	/// What status effect types do we remove uppon being applied. These are just deleted without any deduction from our or their stacks when forced.
	var/list/enemy_types
	/// What status effect types do we merge into if they exist. Ignored when forced.
	var/list/merge_types
	/// What status effect types do we override if they exist. These are simply deleted when forced.
	var/list/override_types
	/// For how much firestacks does one our stack count
	var/stack_modifier = 1

/datum/status_effect/fire_handler/refresh(mob/living/new_owner, new_stacks, forced = FALSE)
	if(forced)
		set_stacks(new_stacks)
	else
		adjust_stacks(new_stacks)

/datum/status_effect/fire_handler/on_creation(mob/living/new_owner, new_stacks, forced = FALSE)
	. = ..()

	if(isanimal(owner))
		spent(src)
		return

	rel_set(src, nameof(owner), new_owner)
	set_stacks(new_stacks)

	for(var/enemy_type in enemy_types)
		var/datum/status_effect/fire_handler/enemy_effect = owner.has_status_effect(enemy_type)
		if(enemy_effect)
			if(forced)
				replaced_by(enemy_effect, src)
				continue

			var/cur_stacks = stacks
			adjust_stacks(-abs(enemy_effect.stacks * enemy_effect.stack_modifier / stack_modifier))
			enemy_effect.adjust_stacks(-abs(cur_stacks * stack_modifier / enemy_effect.stack_modifier))
			if(enemy_effect.stacks <= 0)
				spent(enemy_effect, src)

			if(stacks <= 0)
				spent(src)
				return

	if(!forced)
		var/list/merge_effects = list()
		for(var/merge_type in merge_types)
			var/datum/status_effect/fire_handler/merge_effect = owner.has_status_effect(merge_type)
			if(merge_effect)
				merge_effects += merge_effect

		if(LAZYLEN(merge_effects))
			for(var/datum/status_effect/fire_handler/merge_effect in merge_effects)
				merge_effect.adjust_stacks(stacks * stack_modifier / merge_effect.stack_modifier / LAZYLEN(merge_effects))
			spent(src)
			return

	for(var/override_type in override_types)
		var/datum/status_effect/fire_handler/override_effect = owner.has_status_effect(override_type)
		if(override_effect)
			if(forced)
				replaced_by(override_effect, src)
				continue

			adjust_stacks(override_effect.stacks)
			consumed(override_effect, src)

/**
 * Setter and adjuster procs for firestacks
 *
 * Arguments:
 * - new_stacks
 *
 */

/datum/status_effect/fire_handler/proc/set_stacks(new_stacks)
	stacks = max(0, min(stack_limit, new_stacks))
	cache_stacks()

/datum/status_effect/fire_handler/proc/adjust_stacks(new_stacks)
	stacks = max(0, min(stack_limit, stacks + new_stacks))
	cache_stacks()

/// Checks if the applicable basic mob is immune to the status effect we're trying to apply. Returns TRUE if it is, FALSE if it isn't.
// /datum/status_effect/fire_handler/proc/check_basic_mob_immunity(mob/living/basic/basic_owner)
// 	return (basic_owner.basic_mob_flags & FLAMMABLE_MOB)

/**
 * Refresher for mob's fire_stacks
 */

/datum/status_effect/fire_handler/proc/cache_stacks()
	owner.fire_stacks = 0
	var/was_on_fire = owner.on_fire
	owner.on_fire = FALSE
	for(var/datum/status_effect/fire_handler/possible_fire in owner.status_effects)
		owner.fire_stacks += possible_fire.stacks * possible_fire.stack_modifier

		if(!istype(possible_fire, /datum/status_effect/fire_handler/fire_stacks))
			continue

		var/datum/status_effect/fire_handler/fire_stacks/our_fire = possible_fire
		if(our_fire.on_fire)
			owner.on_fire = TRUE

	if(was_on_fire && !owner.on_fire)
		owner.clear_alert(ALERT_FIRE)
	else if(!was_on_fire && owner.on_fire)
		owner.throw_alert(ALERT_FIRE, /atom/movable/screen/alert/fire)
	owner.update_fire()
	update_particles()

/datum/status_effect/fire_handler/fire_stacks
	id = "fire_stacks" //fire_stacks and wet_stacks should have different IDs or else has_status_effect won't work
	remove_on_fullheal = TRUE

	enemy_types = list(/datum/status_effect/fire_handler/wet_stacks)
	stack_modifier = 1

	/// If we're on fire
	var/on_fire = FALSE
	/// Reference to the mob light emitter itself
	var/obj/effect/dummy/lighting_obj/moblight
	/// Type of mob light emitter we use when on fire
	var/moblight_type = /obj/effect/dummy/lighting_obj/moblight/fire
	/// Cached particle type
	var/applied_particle_type

CAPABILITIES(/datum/status_effect/fire_handler/fire_stacks)
	owns_one(nameof(moblight), /obj/effect/dummy/lighting_obj)

/datum/status_effect/fire_handler/fire_stacks/get_examine_text()
	if(owner.on_fire)
		return

	return "[owner.p_They()] [owner.p_are()] covered in something flammable."

/datum/status_effect/fire_handler/fire_stacks/on_creation(mob/living/new_owner, new_stacks, forced = FALSE)
	. = ..()

/datum/status_effect/fire_handler/fire_stacks/tick(seconds_between_ticks)
	if(stacks <= 0)
		spent(src)
		return TRUE

	if(!on_fire)
		return TRUE

	var/decay_multiplier = 1 // has_trait(owner, TRAIT_HUSK) ? 2 : 1 // husks decay twice as fast
	adjust_stacks(owner.fire_stack_decay_rate * decay_multiplier * seconds_between_ticks)

	if(stacks <= 0)
		spent(src)
		return TRUE

	var/datum/gas_mixture/air = owner.loc.return_air()
	if(LINDA_GAS_AMT(air, GAS_O2) < 1)
		spent(src)
		return TRUE

	deal_damage(seconds_between_ticks)

/datum/status_effect/fire_handler/fire_stacks/update_particles()
	if (!on_fire)
		if (applied_particle_type)
			owner.remove_shared_particles(applied_particle_type)
		applied_particle_type = null
		return

	var/particle_type = /particles/embers/minor
	if(stacks > MOB_BIG_FIRE_STACK_THRESHOLD)
		particle_type = /particles/embers

	if (applied_particle_type == particle_type)
		return

	if (applied_particle_type)
		owner.remove_shared_particles(applied_particle_type)
	owner.add_shared_particles(particle_type)
	applied_particle_type = particle_type

/**
 * Proc that handles damage dealing and all special effects
 *
 * Arguments:
 * - seconds_between_ticks
 *
 */

/datum/status_effect/fire_handler/fire_stacks/proc/deal_damage(seconds_per_tick)
	owner.on_fire_stack(seconds_per_tick, src)

	if(owner.is_incorporeal()) // Shadekin don't spread fire in phase, but still take damage
		return

	// A hotspot already on the tile burns on its own; only light one when there is none.
	var/turf/open/location = get_turf(owner)
	if(istype(location) && !location.active_hotspot)
		location.hotspot_expose(owner.fire_burn_temperature(), 25 * seconds_per_tick, TRUE)

/**
 * Used to deal damage to humans and count their protection.
 *
 * Arguments:
 * - seconds_between_ticks
 * - no_protection: When set to TRUE, fire will ignore any possible fire protection
 *
 */

/datum/status_effect/fire_handler/fire_stacks/proc/harm_human(seconds_per_tick, no_protection = FALSE)
	var/mob/living/carbon/human/victim = owner
	var/thermal_protection = victim.get_heat_protection(victim.fire_burn_temperature())

	if(!no_protection)
		if(thermal_protection == 1) // IMMUNE
			return

	var/fire_temp_add = (BODYTEMP_HEATING_MAX + (stacks + 15)) * (1 - thermal_protection)
	victim.adjust_bodytemperature(fire_temp_add)


/**
 * Handles mob ignition, should be the only way to set on_fire to TRUE
 *
 * Arguments:
 * - silent: When set to TRUE, no message is displayed
 *
 */

/datum/status_effect/fire_handler/fire_stacks/proc/ignite(silent = FALSE)
	if(has_trait(owner, TRAIT_NOFIRE))
		return FALSE

	on_fire = TRUE
	if(!silent)
		owner.visible_message(span_warning("[owner] catches fire!"), span_userdanger("You're set on fire!"))

	if(moblight_type)
		if(moblight)
			own_clear(src, nameof(moblight), OWN_DELETE)
		rel_set(src, nameof(moblight), new moblight_type(owner))

	cache_stacks()
	return TRUE

/**
 * Handles mob extinguishing, should be the only way to set on_fire to FALSE
 */

/// Hooked to before/atom_extinguish on the owner.
/datum/status_effect/fire_handler/fire_stacks/proc/on_extinguish_event(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	extinguish()

/datum/status_effect/fire_handler/fire_stacks/proc/extinguish()
	own_clear(src, nameof(moblight), OWN_DELETE)
	on_fire = FALSE
	cache_stacks()
	for(var/obj/item/equipped in (owner.get_equipped_items()))
		equipped.extinguish()

/datum/status_effect/fire_handler/fire_stacks/on_remove()
	if(on_fire)
		extinguish()
	set_stacks(0)
	owner.update_fire()
	if (applied_particle_type)
		owner.remove_shared_particles(applied_particle_type)
	return ..()

/datum/status_effect/fire_handler/fire_stacks/on_apply()
	. = ..()
	observe(owner, /datum/notice/atom_extinguish, src, then(PROC_REF(on_extinguish_event)))
	owner.update_fire()

/datum/status_effect/fire_handler/fire_stacks/proc/add_fire_overlay(mob/living/source)
	if(stacks <= 0 || !on_fire)
		return

	var/mutable_appearance/created_overlay = owner.get_fire_overlay(stacks, on_fire)
	if(isnull(created_overlay))
		return

	source.overlays |= created_overlay

// WET
/datum/status_effect/fire_handler/wet_stacks
	id = "wet_stacks"

	enemy_types = list(/datum/status_effect/fire_handler/fire_stacks)
	stack_modifier = -1
	/// If the mob has the TRAIT_SLIPPERY_WHEN_WET trait, the mob gets this component while it's wet

/datum/status_effect/fire_handler/wet_stacks/on_apply()
	. = ..()
	observe(owner, /datum/notice/trait_gained, src, then(PROC_REF(on_owner_trait_changed)))
	observe(owner, /datum/notice/trait_lost, src, then(PROC_REF(on_owner_trait_changed)))
	update_wet_stack_modifier()
	if(has_trait(owner, TRAIT_SLIPPERY_WHEN_WET))
		become_slippery()
	add_trait(owner, TRAIT_IS_WET,  TRAIT_STATUS_EFFECT(id))
	owner.add_shared_particles(/particles/droplets)

/datum/status_effect/fire_handler/wet_stacks/on_remove()
	. = ..()
	remove_trait(owner, TRAIT_IS_WET, TRAIT_STATUS_EFFECT(id))
	if(has_trait(owner, TRAIT_SLIPPERY_WHEN_WET))
		no_longer_slippery()
	owner.remove_shared_particles(/particles/droplets)

/// Trait gain/loss on the owner: TRAIT_WET_FOR_LONGER retunes the stack
/// modifier, TRAIT_SLIPPERY_WHEN_WET toggles slipperiness.
/datum/status_effect/fire_handler/wet_stacks/proc/on_owner_trait_changed(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(N, /datum/notice/trait_gained))
		var/datum/notice/trait_gained/gained = N
		if(gained.trait == TRAIT_WET_FOR_LONGER)
			update_wet_stack_modifier()
		else if(gained.trait == TRAIT_SLIPPERY_WHEN_WET)
			become_slippery()
	else if(istype(N, /datum/notice/trait_lost))
		var/datum/notice/trait_lost/lost = N
		if(lost.trait == TRAIT_WET_FOR_LONGER)
			update_wet_stack_modifier()
		else if(lost.trait == TRAIT_SLIPPERY_WHEN_WET)
			no_longer_slippery()

/datum/status_effect/fire_handler/wet_stacks/proc/update_wet_stack_modifier()
	stack_modifier = has_trait(owner, TRAIT_WET_FOR_LONGER) ? -3.5 : -1

/datum/status_effect/fire_handler/wet_stacks/proc/become_slippery()
	add_trait(owner, TRAIT_NO_SLIP_WATER, TRAIT_STATUS_EFFECT(id))

/datum/status_effect/fire_handler/wet_stacks/proc/no_longer_slippery()
	remove_trait(owner, TRAIT_NO_SLIP_WATER, TRAIT_STATUS_EFFECT(id))

/datum/status_effect/fire_handler/wet_stacks/get_examine_text()
	return "[owner.p_They()] look[owner.p_s()] a little soaked."

/datum/status_effect/fire_handler/wet_stacks/tick(seconds_between_ticks)
	var/decay = has_trait(owner, TRAIT_WET_FOR_LONGER) ? -0.035 : -0.5
	adjust_stacks(decay * seconds_between_ticks)
	if(stacks <= 0)
		spent(src)

// /datum/status_effect/fire_handler/wet_stacks/check_basic_mob_immunity(mob/living/basic/basic_owner)
// 	return !(basic_owner.basic_mob_flags & IMMUNE_TO_GETTING_WET)
/// BUBBER EDIT END


