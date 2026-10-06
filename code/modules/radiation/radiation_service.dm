// The radiation system (was SSradiation). radiation_pulse() queues pulses here; the system flushes changed shielding
// to the Rust insulation layer and applies the queue every 0.5 s, yielding to the next tick when over budget. The API is
// in radiation_api.dm.
SYSTEM_DEF(radiation)
	name = "Radiation"
	periodic_runlevels = RUNLEVELS_DEFAULT
	/// FALSE stops radiation_pulse() queueing new pulses (was the subsystem's can_fire).
	var/enabled = TRUE

	/// A list of radiation sources (/datum/radiation_pulse_information) that have yet to process.
	/// Do not interact with this directly, use `radiation_pulse` instead. Owned: a pulse is
	/// deleted when it leaves the queue.
	var/list/datum/radiation_pulse_information/processing = list()
	/// Turfs whose shielding changed since the last flush to the Rust
	/// insulation layer (RAD_SHIELDING_CHANGED): a set of locations (turf -> TRUE), not
	/// entity references; emptied by every flush.
	var/list/dirty_turfs = list()
	/// world.maxz the Rust layer last saw; a new z-level forces a flush.
	var/synced_maxz = 0
	/// Cumulative work counters consumed by the lightweight profiler.
	var/profile_pulse_invocations = 0
	var/profile_pulses_completed = 0
	var/profile_dropped_sources = 0
	var/profile_targets_processed = 0
	var/profile_shielding_flushes = 0
	var/profile_shielding_cells = 0
	var/profile_signal_dispatches = 0
	var/profile_irradiations = 0
	var/profile_yields = 0
	var/profile_max_queue = 0
	var/profile_max_targets_remaining = 0
	var/list/profile_source_cost_ms = list()
	var/list/profile_source_targets = list()

CAPABILITIES(/datum/system/radiation)
	owns_many(nameof(processing), /datum/radiation_pulse_information)

/datum/system/radiation/reactions()
	. = ..()
	. += every(0.5 SECONDS, PROC_REF(radiation_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/radiation/proc/radiation_step(dt)
	// The first flush after a map load carries every insulating turf; it goes over several ticks.
	if(!flush_shielding(budgeted = TRUE))
		return STEP_YIELD
	profile_max_queue = max(profile_max_queue, length(processing))
	while (length(processing))
		var/datum/radiation_pulse_information/pulse_information = processing[1]

		var/atom/source = pulse_information.source_ref
		if (isnull(source))
			profile_dropped_sources++
			own_remove(src, nameof(processing), pulse_information)
			continue

		profile_pulse_invocations++
		var/source_type = "[source.type]"
		var/profile_start = TICK_USAGE
		if(isnull(pulse_information.transmissions))
			trace(source, pulse_information)
			profile_max_targets_remaining = max(profile_max_targets_remaining, pulse_information.remaining_targets())
		var/targets_before = pulse_information.remaining_targets()
		pulse(source, pulse_information)
		profile_source_cost_ms[source_type] += TICK_DELTA_TO_MS(TICK_USAGE - profile_start)
		profile_source_targets[source_type] += targets_before - pulse_information.remaining_targets()

		// A pulse that has reached all its targets leaves the queue before any yield,
		// or an overloaded tick would keep re-running a finished pulse forever.
		if(!pulse_information.remaining_targets())
			profile_pulses_completed++
			own_remove(src, nameof(processing), pulse_information)

		if(length(processing) && KERNEL_OVER_BUDGET)
			profile_yields++
			return STEP_YIELD
	return STEP_DONE

/datum/system/radiation/stat_entry(msg)
	return "[msg]Pulses:[length(processing)]"

/// Sends every dirty turf's combined transmission (the turf's rad_insulation
/// times that of everything directly on it) to the Rust insulation layer.
/// Sends the dirty turfs' shielding to the Rust insulation layer. `budgeted` stops at the tick limit and returns
/// FALSE with the rest still dirty (the step carries on next tick); TRUE once nothing is left. A pulse's trace()
/// flushes everything first, unbudgeted.
/datum/system/radiation/proc/flush_shielding(budgeted = FALSE)
	if(!length(dirty_turfs) && synced_maxz == world.maxz)
		return TRUE
	var/list/cells = list()
	var/list/turfs = dirty_turfs
	var/done = 0
	for(var/turf/T as anything in turfs)
		done++
		var/transmission = T.rad_insulation
		for(var/atom/movable/on_turf as anything in contents_of(T))
			transmission *= on_turf.rad_insulation
		cells += T.x
		cells += T.y
		cells += T.z
		cells += transmission
		if(budgeted && done < length(turfs) && KERNEL_OVER_BUDGET)
			break
	// Turfs marked while this ran are past `done` and stay dirty with the unsent rest.
	dirty_turfs = done < length(turfs) ? turfs.Copy(done + 1) : list()
	synced_maxz = world.maxz
	profile_shielding_flushes++
	profile_shielding_cells += length(cells) / 4
	vg_radiation_set_cells(world.maxx, world.maxy, cells)
	return !length(dirty_turfs)

/// Collects the pulse's targets on the source's z-level and computes the
/// shielding to all of them in one Rust call (rays through the insulation layer).
/datum/system/radiation/proc/trace(atom/source, datum/radiation_pulse_information/pulse_information)
	flush_shielding()
	var/list/targets = list()
	var/list/coords = list()
	var/turf/source_turf = get_turf(source)
	if(source_turf)
		var/z = source_turf.z
		for(var/list/registry as anything in list(REGISTRY_MEMBERS(REGISTRY_RAD_COLLECTORS), REGISTRY_MEMBERS(REGISTRY_GEIGER_COUNTERS), REGISTRY_MEMBERS(REGISTRY_RADIOVOLTAIC_ITEMS), REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS)))
			for(var/atom/target as anything in registry)
				var/turf/target_turf = get_turf(target)
				if(!target_turf || target_turf.z != z)
					continue
				targets += target
				coords += target_turf.x
				coords += target_turf.y
				coords += z
	pulse_information.targets = targets
	pulse_information.transmissions = length(targets) ? vg_radiation_pulse(source_turf.x, source_turf.y, source_turf.z, pulse_information.max_range, pulse_information.threshold, coords) : list()
	if(!islist(pulse_information.transmissions) || length(pulse_information.transmissions) != length(targets))
		pulse_information.targets = list()
		pulse_information.transmissions = list()

/// Applies a traced pulse to its targets, yielding between them.
/datum/system/radiation/proc/pulse(atom/source, datum/radiation_pulse_information/pulse_information)
	var/list/targets = pulse_information.targets
	var/list/transmissions = pulse_information.transmissions
	var/pulse_strength = pulse_information.strength
	while(pulse_information.next_target <= length(targets))
		var/index = pulse_information.next_target++
		var/atom/target_atom = targets[index]
		var/current_insulation = transmissions[index]
		profile_targets_processed++
		if(current_insulation < 0 || QDELETED(target_atom))
			continue
		if(istype(target_atom, /obj/machinery/power/rad_collector))
			profile_signal_dispatches++
			PUBLISH_LEGACY(target_atom, /datum/notice/in_range_of_irradiation, pulse_information, 1)
			continue
		if(istype(target_atom, /obj/item/geiger))
			profile_signal_dispatches++
			PUBLISH_LEGACY(target_atom, /datum/notice/in_range_of_irradiation, pulse_information, current_insulation)
			continue

		if(istype(target_atom, /obj/item))
			if(current_insulation > pulse_information.threshold)
				profile_signal_dispatches++
				PUBLISH_LEGACY(target_atom, /datum/notice/in_range_of_irradiation, pulse_information, current_insulation)
			continue

		var/mob/living/target = target_atom
		if(!istype(target) || !can_irradiate_basic(target))
			continue
		profile_signal_dispatches++
		PUBLISH_LEGACY(target, /datum/notice/in_range_of_irradiation, pulse_information, current_insulation)
		if(has_trait(target, TRAIT_IRRADIATED) || current_insulation <= pulse_information.threshold)
			continue
		var/perceived_chance = 100
		var/target_pulse_strength = pulse_strength
		if(pulse_information.chance < 100)
			var/intensity = -log(1 - pulse_information.chance / 100) * (1 + pulse_information.max_range / 2) ** 2
			var/perceived_intensity = intensity * INVERSE((1 + get_dist_euclidean(source, target)) ** 2)
			perceived_intensity *= (current_insulation - pulse_information.threshold) * INVERSE(1 - pulse_information.threshold)
			perceived_chance = 100 * (1 - NUM_E ** -perceived_intensity)
			target_pulse_strength *= (1 - NUM_E ** -perceived_intensity)
		profile_signal_dispatches++
		var/irradiation_result = target.radiation_countdown_check(pulse_information)
		if(irradiation_result & CANCEL_IRRADIATION)
			continue
		if(pulse_information.minimum_exposure_time && !(irradiation_result & SKIP_MINIMUM_EXPOSURE_TIME_CHECK))
			target.radiation_countdown_start(pulse_information.minimum_exposure_time)
			continue
		if(prob(perceived_chance) && irradiate_after_basic_checks(target, target_pulse_strength))
			profile_irradiations++
			target.investigate_log("was irradiated by [source].", INVESTIGATE_RADIATION)
		if(KERNEL_OVER_BUDGET)
			return

/datum/system/radiation/proc/irradiate_after_basic_checks(mob/living/target, strength)
	PRIVATE_PROC(TRUE)

	if(!ishuman(target))
		if(ismob(target))
			target.add_radiation(strength)
			return TRUE
		return FALSE

	/// 0 = full protection, 1 = no protection.
	var/rad_vulnerability = 1 - wearing_rad_protected_clothing(target)
	if(rad_vulnerability <= 0)
		return FALSE
	target.add_radiation(round(strength * rad_vulnerability, 0.1))

	return TRUE

/// Returns whether or not the target can be irradiated by any means.
/// Does not check for clothing.
/datum/system/radiation/proc/can_irradiate_basic(atom/target)
	if (!CAN_IRRADIATE(target))
		return FALSE

	if (has_trait(target, TRAIT_IRRADIATED) && !has_trait(target, TRAIT_BYPASS_EARLY_IRRADIATED_CHECK))
		return FALSE

	if (has_trait(target, TRAIT_RADIMMUNE))
		return FALSE

	return TRUE

/// Retruns a value from 1 (full protection) to 0 (no protection)
/// If we have 4 limbs and 3 are protected, we would expect to have 0.75 returned.
/datum/system/radiation/proc/wearing_rad_protected_clothing(mob/living/carbon/human/human)
	///Check how many limbs we have.
	var/limb_count = 0
	///Check how many of our limbs are protected.
	var/protected_limbs = 0
	for(var/obj/item/organ/external/limb as anything in human.organs)
		limb_count++
		var/protected = FALSE
		for(var/obj/item/clothing as anything in human.get_clothing_on_part(limb))
			if(has_trait(clothing, TRAIT_RADIATION_PROTECTED_CLOTHING))
				protected = TRUE
				break
		// Deterministic: the limb counts as protected by the fraction its worn rad armour stops.
		protected_limbs += protected ? 1 : min(human.body.worn_armor(limb.body_part, ARMOR_RAD), 100) / 100

	if(!limb_count)
		return 0
	return (protected_limbs/limb_count)

// Queued pulses belong to the queue until processed.
// Turfs are round-long; the dirty set is flushed and cut every tick.
