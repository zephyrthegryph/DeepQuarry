// The pipe devices whose flow law is their own Rust component (pump, volume pump, passive gate, dual-port vent, vent, scrubber,
// injector): N of each kind stepped by the device stepper with gas to move. Deterministic counts (devices, FFI calls, moles
// moved) are the figures to compare across commits; the per-step time is noisy on a shared machine.
//
// Run: tools/build/build.sh bench --scenario=pipe_devices [--bench_per_kind=8] [--bench_steps=200]

/datum/benchmark/pipe_devices
	id = "pipe_devices"
	description = "N pumps, volume pumps, passive gates, dual-port vents, vents, scrubbers and injectors stepped together: FFI calls and moles moved (counts), time per step"

/// The next floor with room air that has not been used yet.
/datum/benchmark/pipe_devices/proc/next_floor(list/used)
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air && !(cand in used))
			used += cand
			return cand
	return null

/// A powered device with its ports registered and its air topped up.
/datum/benchmark/pipe_devices/proc/ready(obj/machinery/atmospherics/D)
	D.set_use_power(USE_POWER_IDLE)
	D.set_grid_power(TRUE)
	D.set_broken_condition(FALSE)
	D.rust_register_pipe_topology()
	return D

/datum/benchmark/pipe_devices/Run()
	var/per_kind = param("per_kind", 8)
	var/steps = param("steps", 200)
	var/list/used = list()
	var/list/devices = list()
	for(var/i in 1 to per_kind)
		var/obj/machinery/atmospherics/binary/pump/P = ready(new /obj/machinery/atmospherics/binary/pump(next_floor(used)))
		P.set_target_pressure(15000)
		P.set_on(TRUE)
		P.air1.adjust_gas(/datum/gas/nitrogen, 2000)
		devices += P
		var/obj/machinery/atmospherics/binary/volume_pump/VP = ready(new /obj/machinery/atmospherics/binary/volume_pump(next_floor(used)))
		VP.air1.adjust_gas(/datum/gas/oxygen, 2000)
		devices += VP
		var/obj/machinery/atmospherics/binary/passive_gate/G = ready(new /obj/machinery/atmospherics/binary/passive_gate(next_floor(used)))
		G.set_unlocked(TRUE)
		G.set_regulate_mode(REGULATE_NONE)
		G.air1.adjust_gas(/datum/gas/nitrogen, 2000)
		devices += G
		var/obj/machinery/atmospherics/unary/vent_pump/V = ready(new /obj/machinery/atmospherics/unary/vent_pump(next_floor(used)))
		V.set_pump_direction(1)
		V.set_external_pressure_bound(ONE_ATMOSPHERE * 3)
		V.air_contents.adjust_gas(/datum/gas/nitrogen, 2000)
		rel_set(V, nameof(V.node), V)
		devices += V
		var/obj/machinery/atmospherics/unary/vent_scrubber/S = ready(new /obj/machinery/atmospherics/unary/vent_scrubber(next_floor(used)))
		S.set_scrubbing(TRUE)
		S.set_scrubbing_gas(list(GAS_CO2))
		rel_set(S, nameof(S.node), S)
		devices += S
		var/obj/machinery/atmospherics/unary/outlet_injector/J = ready(new /obj/machinery/atmospherics/unary/outlet_injector(next_floor(used)))
		J.air_contents.adjust_gas(/datum/gas/nitrogen, 2000)
		rel_set(J, nameof(J.node), J)
		devices += J
	for(var/obj/machinery/atmospherics/D as anything in devices)
		D.push_to_rust()
	var/total_before = bench_pipe_moles(devices)
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/i in 1 to steps)
		SSair.rust_step_pipe_devices()
	var/elapsed_ms = (REALTIMEOFDAY - start) * 100
	end_window("steps")
	count_metric("devices", length(devices), "devices", "none")
	count_metric("steps", steps, "steps", "none")
	metric("ms_per_step", elapsed_ms / steps, "ms")
	// Gas leaves the pipes for the rooms (and the scrubbers pull the rooms' CO2 in): what is conserved is the sum.
	count_metric("pipe_moles_moved", round(abs(total_before - bench_pipe_moles(devices)), 0.01), "mol", "none")
	for(var/obj/machinery/atmospherics/D as anything in devices)
		qdel(D)
	refresh_flush()

/// The moles held in the devices' pipe-side air.
/datum/benchmark/pipe_devices/proc/bench_pipe_moles(list/devices)
	var/total = 0
	for(var/obj/machinery/atmospherics/D as anything in devices)
		if(istype(D, /obj/machinery/atmospherics/binary))
			var/obj/machinery/atmospherics/binary/B = D
			total += B.air1.total_moles()
		else if(istype(D, /obj/machinery/atmospherics/unary))
			var/obj/machinery/atmospherics/unary/U = D
			total += U.air_contents.total_moles()
	return total
