// A machine joining and leaving its area's power: rel_set(M, power_area, ...) runs the machine's three channel-draw contributes_to entries
// (the gate of each, the target stat check, the demand row) and the area's reverse-index update. A machine of each kind already on the map is
// detached and attached again, N cycles, and the wall time per join is reported. The run is outside an init frame, so it prices the evaluation,
// not the batched settle.
//
// Run: tools/build/build.sh bench -DCITESTING_FULL_MAP --scenario=machine_power_join [--arg=machines=3000] [--arg=cycles=10]

/datum/benchmark/machine_power_join
	id = "machine_power_join"
	description = "Machines detached from and attached to their area's power again: wall time per join and the stat evaluations it ran"

/datum/benchmark/machine_power_join/proc/join_pass(list/machines, cycles)
	var/start = REALTIMEOFDAY
	var/evals_before = GLOB.stat_evals
	for(var/c in 1 to cycles)
		for(var/obj/machinery/M as anything in machines)
			var/area/A = M.power_area
			rel_set(M, nameof(M.power_area), null)
			rel_set(M, nameof(M.power_area), A)
	. = list((REALTIMEOFDAY - start) * 100, GLOB.stat_evals - evals_before)

/datum/benchmark/machine_power_join/Run()
	var/wanted = param("machines", 3000)
	var/cycles = param("cycles", 10)
	var/list/machines = list()
	for(var/obj/machinery/M in world)
		if(isnull(M.power_area) || QDELETED(M))
			continue
		machines += M
		if(length(machines) >= wanted)
			break
	if(!length(machines))
		return fail("no machine on the map has a power area")
	count_metric("machines", length(machines), "machines", "none")
	count_metric("cycles", cycles, "cycles", "none")
	join_pass(machines, 1) // warm the tables
	begin_window()
	var/list/result = join_pass(machines, cycles)
	end_window("join")
	metric("ms_per_join", result[1] / (length(machines) * cycles), "ms")
	count_metric("stat_evals_per_join", round(result[2] / (length(machines) * cycles), 0.01), "evals", "none")
