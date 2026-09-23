SUBSYSTEM_DEF(radiation)
	name = "Radiation"
	flags = SS_BACKGROUND | SS_NO_INIT
	wait = 0.5 SECONDS

	/// A list of radiation sources (/datum/radiation_pulse_information) that have yet to process.
	/// Do not interact with this directly, use `radiation_pulse` instead.
	var/list/datum/radiation_pulse_information/processing = list()
	/// Turfs whose shielding changed since the last flush to the Rust
	/// insulation layer (RAD_SHIELDING_CHANGED). Keyed by turf.
	var/list/turf/dirty_turfs = list()
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

/datum/controller/subsystem/radiation/fire(resumed)
	flush_shielding()
	profile_max_queue = max(profile_max_queue, processing.len)
	while (processing.len)
		var/datum/radiation_pulse_information/pulse_information = processing[1]

		var/datum/weakref/source_ref = pulse_information.source_ref
		var/atom/source = source_ref.resolve()
		if (isnull(source))
			profile_dropped_sources++
			processing.Cut(1, 2)
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

		if (MC_TICK_CHECK)
			profile_yields++
			return

		profile_pulses_completed++
		processing.Cut(1, 2)

/datum/controller/subsystem/radiation/proc/performance_diagnostics()
	var/current_targets = 0
	if(length(processing))
		var/datum/radiation_pulse_information/current = processing[1]
		current_targets = current?.remaining_targets()
	var/list/source_costs = profile_source_cost_ms.Copy()
	sortTim(source_costs, /proc/cmp_numeric_desc, TRUE)
	if(length(source_costs) > 10)
		source_costs.Cut(11)
	return list(
		"queue" = list("pulses" = length(processing), "current_targets" = current_targets, "max_pulses" = profile_max_queue, "max_targets" = profile_max_targets_remaining),
		"work" = list("pulse_invocations" = profile_pulse_invocations, "pulses_completed" = profile_pulses_completed, "dropped_sources" = profile_dropped_sources, "targets" = profile_targets_processed, "shielding_flushes" = profile_shielding_flushes, "shielding_cells" = profile_shielding_cells, "signals" = profile_signal_dispatches, "irradiations" = profile_irradiations, "yields" = profile_yields),
		"top_source_cost_ms" = source_costs,
		"source_targets" = profile_source_targets.Copy(),
	)

/datum/controller/subsystem/radiation/stat_entry(msg)
	msg = "Pulses:[processing.len]"
	return ..()

/// Sends every dirty turf's combined transmission (the turf's rad_insulation
/// times that of everything directly on it) to the Rust insulation layer.
/datum/controller/subsystem/radiation/proc/flush_shielding()
	if(!length(dirty_turfs) && synced_maxz == world.maxz)
		return
	var/list/cells = list()
	for(var/turf/T as anything in dirty_turfs)
		var/transmission = T.rad_insulation
		for(var/atom/movable/on_turf as anything in T.contents)
			transmission *= on_turf.rad_insulation
		cells += T.x
		cells += T.y
		cells += T.z
		cells += transmission
	dirty_turfs.Cut()
	synced_maxz = world.maxz
	profile_shielding_flushes++
	profile_shielding_cells += length(cells) / 4
	vg_radiation_set_cells(world.maxx, world.maxy, cells)

/// Collects the pulse's targets on the source's z-level and computes the
/// shielding to all of them in one Rust call (rays through the insulation layer).
/datum/controller/subsystem/radiation/proc/trace(atom/source, datum/radiation_pulse_information/pulse_information)
	flush_shielding()
	var/list/targets = list()
	var/list/coords = list()
	var/turf/source_turf = get_turf(source)
	if(source_turf)
		var/z = source_turf.z
		for(var/list/registry as anything in list(GLOB.rad_collectors, GLOB.geiger_counters, GLOB.material_radiovoltaic_items, GLOB.living_mob_list))
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
/datum/controller/subsystem/radiation/proc/pulse(atom/source, datum/radiation_pulse_information/pulse_information)
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
			SEND_SIGNAL(target_atom, COMSIG_IN_RANGE_OF_IRRADIATION, pulse_information, 1)
			continue
		if(istype(target_atom, /obj/item/geiger))
			profile_signal_dispatches++
			SEND_SIGNAL(target_atom, COMSIG_IN_RANGE_OF_IRRADIATION, pulse_information, current_insulation)
			continue

		if(istype(target_atom, /obj/item))
			if(current_insulation > pulse_information.threshold)
				profile_signal_dispatches++
				SEND_SIGNAL(target_atom, COMSIG_IN_RANGE_OF_IRRADIATION, pulse_information, current_insulation)
			continue

		var/mob/living/target = target_atom
		if(!istype(target) || !can_irradiate_basic(target))
			continue
		profile_signal_dispatches++
		SEND_SIGNAL(target, COMSIG_IN_RANGE_OF_IRRADIATION, pulse_information, current_insulation)
		if(HAS_TRAIT(target, TRAIT_IRRADIATED) || current_insulation <= pulse_information.threshold)
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
		var/irradiation_result = SEND_SIGNAL(target, COMSIG_IN_THRESHOLD_OF_IRRADIATION, pulse_information)
		if(irradiation_result & CANCEL_IRRADIATION)
			continue
		if(pulse_information.minimum_exposure_time && !(irradiation_result & SKIP_MINIMUM_EXPOSURE_TIME_CHECK))
			target.AddComponent(/datum/component/radiation_countdown, pulse_information.minimum_exposure_time)
			continue
		if(prob(perceived_chance) && irradiate_after_basic_checks(target, target_pulse_strength))
			profile_irradiations++
			target.investigate_log("was irradiated by [source].", INVESTIGATE_RADIATION)
		if(MC_TICK_CHECK)
			return

/// Will attempt to irradiate the given target, limited through IC means, such as radiation protected clothing.
/datum/controller/subsystem/radiation/proc/irradiate(atom/target, strength)
	if (!can_irradiate_basic(target))
		return FALSE

	irradiate_after_basic_checks(target, strength)
	return TRUE

/datum/controller/subsystem/radiation/proc/irradiate_after_basic_checks(mob/living/target, strength)
	PRIVATE_PROC(TRUE)

	if(!ishuman(target))
		if(ismob(target))
			target.radiation += strength
			return TRUE
		return FALSE

	/// 0 = full protection, 1 = no protection.
	var/rad_vulnerability = 1 - wearing_rad_protected_clothing(target)
	if(rad_vulnerability <= 0)
		return FALSE
	target.radiation += round(strength * rad_vulnerability, 0.1)

//	target.AddComponent(/datum/component/irradiated)
	return TRUE

/// Returns whether or not the target can be irradiated by any means.
/// Does not check for clothing.
/datum/controller/subsystem/radiation/proc/can_irradiate_basic(atom/target)
	if (!CAN_IRRADIATE(target))
		return FALSE

	if (HAS_TRAIT(target, TRAIT_IRRADIATED) && !HAS_TRAIT(target, TRAIT_BYPASS_EARLY_IRRADIATED_CHECK))
		return FALSE

	if (HAS_TRAIT(target, TRAIT_RADIMMUNE))
		return FALSE

	return TRUE

/// Retruns a value from 1 (full protection) to 0 (no protection)
/// If we have 4 limbs and 3 are protected, we would expect to have 0.75 returned.
/datum/controller/subsystem/radiation/proc/wearing_rad_protected_clothing(mob/living/carbon/human/human)
	///Check how many limbs we have.
	var/limb_count = 0
	///Check how many of our limbs are protected.
	var/protected_limbs = 0
	for(var/obj/item/organ/external/limb as anything in human.organs)
		limb_count++

		for(var/obj/item/clothing as anything in human.get_clothing_on_part(limb))
			if(HAS_TRAIT(clothing, TRAIT_RADIATION_PROTECTED_CLOTHING)) //If our clothing
				protected_limbs++
				break

			var/rad_resistance = clothing.armor["rad"]
			if(prob(rad_resistance))
				protected_limbs++
				break

	if(!limb_count)
		return 0
	return (protected_limbs/limb_count)
