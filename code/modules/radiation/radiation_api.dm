// The radiation system's API (code/modules/radiation/radiation_service.dm declares the system).
//
//   SSradiation.irradiate(target, strength)   irradiate one target, limited by its protection
//   SSradiation.performance_diagnostics()     the queue, work and cost counters for the profiler
//   SSradiation.queue_pulse(pulse)            a radiation_pulse() hands its pulse over; the system owns it from here
//   SSradiation.is_enabled()                  FALSE stops radiation_pulse() queueing new pulses

/// Will attempt to irradiate the given target, limited through IC means, such as radiation protected clothing.
/datum/system/radiation/proc/irradiate(atom/target, strength)
	if (!can_irradiate_basic(target))
		return FALSE

	irradiate_after_basic_checks(target, strength)
	return TRUE

/datum/system/radiation/proc/performance_diagnostics()
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

/datum/system/radiation/proc/queue_pulse(datum/radiation_pulse_information/pulse_information)
	own_add(src, nameof(processing), pulse_information)

/datum/system/radiation/proc/is_enabled()
	return enabled
