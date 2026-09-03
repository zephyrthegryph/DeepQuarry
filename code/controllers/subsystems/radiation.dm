SUBSYSTEM_DEF(radiation)
	name = "Radiation"
	flags = SS_BACKGROUND | SS_NO_INIT
	wait = 0.5 SECONDS

	/// A list of radiation sources (/datum/radiation_pulse_information) that have yet to process.
	/// Do not interact with this directly, use `radiation_pulse` instead.
	var/list/datum/radiation_pulse_information/processing = list()
	/// Cumulative work counters consumed by the lightweight profiler.
	var/profile_pulse_invocations = 0
	var/profile_pulses_completed = 0
	var/profile_dropped_sources = 0
	var/profile_targets_processed = 0
	var/profile_ray_turfs = 0
	var/profile_insulation_cache_hits = 0
	var/profile_insulation_cache_misses = 0
	var/profile_signal_dispatches = 0
	var/profile_irradiations = 0
	var/profile_yields = 0
	var/profile_max_queue = 0
	var/profile_max_targets_remaining = 0
	var/list/profile_source_cost_ms = list()
	var/list/profile_source_targets = list()
	/// Short-lived shielding cache shared by pulses from the same steady source.
	/// Radiation emitters fire far more often than shielding topology changes;
	/// bounding this to one second preserves responsive doors while eliminating
	/// repeated get_line/content scans for the same source/target pair.
	var/list/path_insulation_cache = list()
	var/path_insulation_cache_expires = 0

/datum/controller/subsystem/radiation/fire(resumed)
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
		profile_max_targets_remaining = max(profile_max_targets_remaining, length(pulse_information.targets_to_process))
		var/source_type = "[source.type]"
		var/targets_before = length(pulse_information.targets_to_process)
		var/profile_start = TICK_USAGE
		pulse(source, pulse_information)
		profile_source_cost_ms[source_type] += TICK_DELTA_TO_MS(TICK_USAGE - profile_start)
		profile_source_targets[source_type] += targets_before - length(pulse_information.targets_to_process)

		if (MC_TICK_CHECK)
			profile_yields++
			return

		profile_pulses_completed++
		processing.Cut(1, 2)

/datum/controller/subsystem/radiation/proc/performance_diagnostics()
	var/current_targets = 0
	if(length(processing))
		var/datum/radiation_pulse_information/current = processing[1]
		current_targets = length(current?.targets_to_process)
	var/list/source_costs = profile_source_cost_ms.Copy()
	sortTim(source_costs, /proc/cmp_numeric_desc, TRUE)
	if(length(source_costs) > 10)
		source_costs.Cut(11)
	return list(
		"queue" = list("pulses" = length(processing), "current_targets" = current_targets, "max_pulses" = profile_max_queue, "max_targets" = profile_max_targets_remaining),
		"work" = list("pulse_invocations" = profile_pulse_invocations, "pulses_completed" = profile_pulses_completed, "dropped_sources" = profile_dropped_sources, "targets" = profile_targets_processed, "ray_turfs" = profile_ray_turfs, "cache_hits" = profile_insulation_cache_hits, "cache_misses" = profile_insulation_cache_misses, "signals" = profile_signal_dispatches, "irradiations" = profile_irradiations, "yields" = profile_yields),
		"top_source_cost_ms" = source_costs,
		"source_targets" = profile_source_targets.Copy(),
	)

/datum/controller/subsystem/radiation/stat_entry(msg)
	msg = "Pulses:[processing.len]"
	return ..()

/datum/controller/subsystem/radiation/proc/pulse(atom/source, datum/radiation_pulse_information/pulse_information)
	if(world.time >= path_insulation_cache_expires)
		path_insulation_cache.Cut()
		path_insulation_cache_expires = world.time + 1 SECOND
	var/list/targets = pulse_information.targets_to_process
	var/pulse_strength = pulse_information.strength
	while(length(targets))
		var/atom/target_atom = targets[length(targets)]
		targets.len--
		profile_targets_processed++
		var/turf/target_turf = get_turf(target_atom)
		if(QDELETED(target_atom) || !target_turf || target_turf.z != source.z || get_dist(source, target_turf) > pulse_information.max_range)
			continue
		if(istype(target_atom, /obj/machinery/power/rad_collector))
			profile_signal_dispatches++
			SEND_SIGNAL(target_atom, COMSIG_IN_RANGE_OF_IRRADIATION, pulse_information, 1)
			continue
		if(istype(target_atom, /obj/item/geiger))
			var/obj/item/geiger/geiger_counter = target_atom
			var/mob/living/holder = get(geiger_counter, /mob/living)
			geiger_check(source, pulse_information, geiger_counter, holder ? holder : geiger_counter)
			continue

		var/current_insulation = cached_path_insulation(source, target_turf, pulse_information.threshold)

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

/datum/controller/subsystem/radiation/proc/cached_path_insulation(atom/source, turf/target, threshold)
	var/cache_key = "\ref[source]|\ref[target]|[threshold]"
	var/cached = path_insulation_cache[cache_key]
	if(!isnull(cached))
		profile_insulation_cache_hits++
		return cached
	profile_insulation_cache_misses++
	var/current_insulation = 1
	var/list/ray_turfs = get_line(source, target) - get_turf(source)
	profile_ray_turfs += length(ray_turfs)
	for(var/turf/turf_in_between in ray_turfs)
		var/insulation = turf_in_between.rad_insulation
		for(var/atom/on_turf as anything in turf_in_between.contents)
			insulation *= on_turf.rad_insulation
		current_insulation *= insulation
		if(current_insulation <= threshold)
			break
	path_insulation_cache[cache_key] = current_insulation
	return current_insulation

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

///Proc for when geiger counter is checked. This is called twice: Once when the geiger counter is in range of a pulse itself and once when a geiger counter is on a mob that is in range of a pulse.
/datum/controller/subsystem/radiation/proc/geiger_check(atom/source, datum/radiation_pulse_information/pulse_information, obj/item/geiger/geiger_counter, atom/target)
	if(!target)
		target = geiger_counter

	var/turf/target_turf = get_turf(target)
	if(!target_turf)
		return
	var/current_insulation = cached_path_insulation(source, target_turf, pulse_information.threshold)

	profile_signal_dispatches++
	SEND_SIGNAL(geiger_counter, COMSIG_IN_RANGE_OF_IRRADIATION, pulse_information, current_insulation)
