/// TRUE while the boot phase timers run (`-params boot_phase_timers=1`, code/__defines/boot_phase.dm).
GLOBAL_VAR_INIT(boot_phase_on, text2num(world.params?["boot_phase_timers"] || "0"))
/// phase -> microseconds, and phase -> calls.
GLOBAL_LIST_EMPTY(boot_phase_us)
GLOBAL_LIST_EMPTY(boot_phase_calls)

/// phase -> type -> microseconds: the same rows split by the type of the atom that ran the phase.
GLOBAL_LIST_EMPTY(boot_phase_type_us)

/// Adds one timed phase of `A` (an atom, or null).
/proc/boot_phase_add(phase, us, atom/A)
	GLOB.boot_phase_us[phase] += us
	GLOB.boot_phase_calls[phase]++
	if(A)
		var/list/by_type = GLOB.boot_phase_type_us[phase]
		if(!by_type)
			by_type = list()
			GLOB.boot_phase_type_us[phase] = by_type
		by_type[A.type] += us

/// phase -> calls, for what is counted and not timed (the report's "counted" rows).
GLOBAL_LIST_EMPTY(boot_phase_counts)

/// Prints every phase, longest first, and the write counters the map load ran up, to the world log. Does nothing while the timers are off.
/proc/boot_phase_report(label)
	if(!GLOB.boot_phase_on)
		return
	var/list/totals = GLOB.boot_phase_us.Copy()
	totals = sortTim(totals, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	for(var/phase in totals)
		var/calls = GLOB.boot_phase_calls[phase]
		log_world("Atoms boot phase ([label]): [phase] [round(totals[phase] / 1000000, 0.01)]s over [calls] calls ([round(totals[phase] / max(calls, 1), 0.1)] us each)")
	// The types that spend the most in each of the ten longest phases.
	var/shown = 0
	for(var/phase in totals)
		if(++shown > 10)
			break
		var/list/by_type = GLOB.boot_phase_type_us[phase]
		if(!length(by_type))
			continue
		by_type = sortTim(by_type.Copy(), GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
		var/line = ""
		for(var/i in 1 to min(8, length(by_type)))
			line += " [by_type[i]]=[round(by_type[by_type[i]] / 1000000, 0.01)]s"
		log_world("Atoms boot phase ([label]): top types of [phase]:[line]")
	var/list/counted = sortTim(GLOB.boot_phase_counts.Copy(), GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	var/count_line = ""
	for(var/i in 1 to min(25, length(counted)))
		count_line += " [counted[i]]=[counted[counted[i]]]"
	log_world("Atoms boot phase ([label]): counted:[count_line]")
	log_world("Atoms boot phase ([label]): counters: state_changed pre-init skips [GLOB.state_changed_preinit_skipped], own_field_changed memo spared [GLOB.own_field_memo_spared], reader probes [GLOB.plan_reader_probes]")
