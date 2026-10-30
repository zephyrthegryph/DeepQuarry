/// TRUE while the boot phase timers run (`-params boot_phase_timers=1`, code/__defines/boot_phase.dm).
GLOBAL_VAR_INIT(boot_phase_on, text2num(world.params?["boot_phase_timers"] || "0"))
/// phase -> microseconds, and phase -> calls.
GLOBAL_LIST_EMPTY(boot_phase_us)
GLOBAL_LIST_EMPTY(boot_phase_calls)

/proc/boot_phase_add(phase, us)
	GLOB.boot_phase_us[phase] += us
	GLOB.boot_phase_calls[phase]++

/// Prints every phase, longest first, and the write counters the map load ran up, to the world log. Does nothing while the timers are off.
/proc/boot_phase_report(label)
	if(!GLOB.boot_phase_on)
		return
	var/list/totals = GLOB.boot_phase_us.Copy()
	totals = sortTim(totals, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	for(var/phase in totals)
		var/calls = GLOB.boot_phase_calls[phase]
		log_world("Atoms boot phase ([label]): [phase] [round(totals[phase] / 1000000, 0.01)]s over [calls] calls ([round(totals[phase] / max(calls, 1), 0.1)] us each)")
	log_world("Atoms boot phase ([label]): counters: state_changed pre-init skips [GLOB.state_changed_preinit_skipped], own_field_changed memo spared [GLOB.own_field_memo_spared], reader probes [GLOB.plan_reader_probes]")
