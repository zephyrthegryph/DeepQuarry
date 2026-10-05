// The gas domain's API for machines (doc/rewrite/final_api.html section 14, "Gas and heat"): what a machine asks of a gas, so that no machine
// reads or edits a mixture's moles or energy itself. Mixtures stay opaque handles and every call here is one or a few Rust-backed operations.
//
//   gas_release(source, into, target_kpa, rate)   moves gas out of `source` into `into` (a mixture, or an atom whose air it is) until `into`
//                                                  reaches target_kpa, never more than `rate` litres of `source` per call. A turf it fills is woken. Returns
//                                                  the moles moved. A canister's valve, a jetpack's refill.
//   gas_sample(air)                                one read of everything a gauge shows (pressure, temperature, volume, heat capacity, each gas):
//                                                  S.pressure, S.temperature, S.partial_pressure(GAS_O2), S.share(GAS_O2).
//   /datum/gas_heater                              a heater/cooler on a room's air (the air alarm's thermostat): regulate(air, target) works the
//                                                  air toward the target at its rated energy per call, starting and stopping with its hysteresis.
//   gas_dump(source, into)                         empties a vessel into a room or another mixture.
//   gas_fill(air, fractions, kpa, temperature)     a vessel filled to a pressure with a mix (a canister preset).
//   gas_body_heat_exchange(air, body_k, body_j_per_k, share)
//                                                  a body (a cryo cell's occupant) and a gas exchange heat: share 1 settles both at the mixed
//                                                  temperature. The gas takes what the body gives, and a pipe network that owns the gas is
//                                                  woken (gas_touched()); the caller never marks it. Returns the body's new temperature.
//   gas_touched(air)                               a mixture changed in place: the pipe network that owns it (if any) re-settles.
//   GAS_OBSERVED(observation, index, GAS_OBS_x)    a named field of a dirty-gas observation record (code/__defines/atmospherics_linda/atmos_gasses.dm).
//
// Example (a canister's valve, once per interval):
//
//	gas_release(air_contents, holding || loc, release_pressure, release_flow_rate)

/// Moves gas out of `source` into `into` until `into` holds `target_kpa` (an exact solve at the mixing temperature), never more than `rate` litres
/// of `source` (its current density) when a rate is given. `into` is a mixture or an atom (its return_air()); a turf it fills is woken so the gas
/// spreads and shows. Returns the moles moved (0 when `into` is already at the target or `source` is empty).
/proc/gas_release(datum/gas_mixture/source, into, target_kpa, rate = null)
	var/datum/gas_mixture/sink = into
	var/turf/sink_turf
	if(isatom(into))
		var/atom/A = into
		sink = A.return_air()
		sink_turf = isturf(A) ? A : null
	if(!source || !sink || source == sink)
		return 0
	var/max_moles = null
	if(!isnull(rate))
		var/volume = source.return_volume()
		if(volume <= 0 || rate <= 0)
			return 0
		max_moles = rate / volume * source.total_moles()
		if(max_moles <= 0)
			return 0 // the Rust solve reads a cap of zero as no cap at all
	var/moved = source.transfer_to_pressure(sink, target_kpa, max_moles)
	if(moved > 0 && istype(sink_turf, /turf/open))
		var/turf/open/T = sink_turf
		// The gas landed in the turf's own mixture; the turf has to hear it to spread it and draw it.
		T.update_visuals()
		T.air_update_turf(FALSE, FALSE)
	return moved

// ---- one read of a mixture ----

/// What a gauge reads from a mixture in one call: its pressure (kPa), temperature (K), volume (L), heat capacity (J/K), total moles and each gas's
/// moles. A fresh one per read; it does not follow the mixture.
/datum/gas_sample
	var/pressure = 0
	var/temperature = 0
	var/volume = 0
	var/heat_capacity = 0
	var/total_moles = 0
	/// The raw read_gas_mixtures() row (GAS_READ_* layout), for the moles of each gas.
	var/list/row

/// One read of `air` (null reads as an empty, zero-volume mixture).
/proc/gas_sample(datum/gas_mixture/air)
	RETURN_TYPE(/datum/gas_sample)
	var/datum/gas_sample/S = new
	if(!air)
		return S
	var/list/readings = read_gas_mixtures(list(air))
	if(length(readings) < GAS_READ_STRIDE)
		return S
	S.row = readings
	S.pressure = readings[GAS_READ_PRESSURE]
	S.temperature = readings[GAS_READ_TEMPERATURE]
	S.volume = readings[GAS_READ_VOLUME]
	S.total_moles = readings[GAS_READ_TOTAL_MOLES]
	S.heat_capacity = readings[GAS_READ_HEAT_CAPACITY]
	return S

/// The moles of gas `gas_id` (a GAS_* key or a GAS_ID_* number).
/datum/gas_sample/proc/moles(gas_id)
	var/index = GAS_IDX(gas_id)
	if(isnull(index) || !row)
		return 0
	return row[GAS_READ_MOLES(index)]

/// The partial pressure of gas `gas_id`, kPa.
/datum/gas_sample/proc/partial_pressure(gas_id)
	if(volume <= 0)
		return 0
	return moles(gas_id) * R_IDEAL_GAS_EQUATION * temperature / volume

/// The share (0..1) of the mixture's moles that are gas `gas_id`.
/datum/gas_sample/proc/share(gas_id)
	return total_moles > 0 ? moles(gas_id) / total_moles : 0

/// The GAS_* keys of the gases present.
/datum/gas_sample/proc/gas_ids()
	. = list()
	if(!row)
		return
	for(var/i in 1 to length(GLOB.gas_path_by_idx))
		var/datum/gas/path = GLOB.gas_path_by_idx[i]
		if(path && row[GAS_READ_MOLES(i - 1)] > 0)
			. += initial(path.id)

// ---- a heater/cooler on a room's air ----

/**
 * A heater/cooler working a room's air toward a target temperature: the air alarm's thermostat. Each regulate() call is one interval of its work:
 * it moves at most `rated_joules` (heating) and closes at most `share` of the gap to the target, so a small room is never overshot. Cooling pumps
 * the heat out into the hull at a coefficient of performance of the air's temperature over `hull_temperature`, so a cold room is cooled more
 * slowly. It starts once the air is `start_gap` off the target and stops within `stop_gap` of it, and never works a near vacuum.
 */
/datum/gas_heater
	var/rated_joules = 1000
	var/share = 0.25
	var/hull_temperature = T20C
	var/start_gap = 2
	var/stop_gap = 0.5
	/// The air must hold this much pressure (kPa) to be worked.
	var/min_pressure = 1
	/// GAS_HEATER_IDLE, GAS_HEATER_COOLING or GAS_HEATER_HEATING.
	var/state = GAS_HEATER_IDLE
	/// What the last regulate() moved into the air, J (negative: out of it).
	var/last_joules = 0

/// One interval of work on `air` toward `target` (K). `allowed` FALSE stops it (its owner's own rule: the alarm will not hold an unsafe target).
/// Returns the state after the call (GAS_HEATER_*).
/datum/gas_heater/proc/regulate(datum/gas_mixture/air, target, allowed = TRUE)
	last_joules = 0
	if(!air)
		state = GAS_HEATER_IDLE
		return state
	var/datum/gas_sample/S = gas_sample(air)
	var/gap = target - S.temperature
	if(state == GAS_HEATER_IDLE)
		if(allowed && abs(gap) > start_gap && S.pressure >= min_pressure)
			state = gap < 0 ? GAS_HEATER_COOLING : GAS_HEATER_HEATING
	else if(!allowed || abs(gap) <= stop_gap || S.pressure < min_pressure)
		state = GAS_HEATER_IDLE
	if(state == GAS_HEATER_IDLE || S.heat_capacity <= 0)
		return state
	var/wanted = share * S.heat_capacity * gap // what closing this interval's share of the gap takes
	if(gap >= 0)
		last_joules = min(wanted, rated_joules)
	else
		var/cop = S.temperature / hull_temperature
		last_joules = -min(-wanted, rated_joules, cop * rated_joules)
	air.set_temperature(S.temperature + last_joules / S.heat_capacity)
	return state

// ---- a body and a gas ----

/// A body of `body_temperature` (K) and `body_capacity` (J/K) exchanges heat with `air`: `share` (0..1) of the way to the temperature both would
/// settle at. The gas takes exactly what the body gives up. Returns the body's new temperature (the caller sets it); `air` is changed in place.
/proc/gas_body_heat_exchange(datum/gas_mixture/air, body_temperature, body_capacity, share = 1)
	if(!air || body_capacity <= 0 || share <= 0)
		return body_temperature
	var/datum/gas_sample/S = gas_sample(air)
	if(S.heat_capacity <= 0)
		return body_temperature
	var/settled = (body_capacity * body_temperature + S.heat_capacity * S.temperature) / (body_capacity + S.heat_capacity)
	if(abs(settled - body_temperature) < 0.001) // already settled: the body's capacity would magnify rounding into a phantom change of the gas
		return body_temperature
	var/body_after = body_temperature + min(share, 1) * (settled - body_temperature)
	var/gas_after = S.temperature + body_capacity * (body_temperature - body_after) / S.heat_capacity
	air.set_temperature(gas_after)
	if(gas_after != S.temperature)
		gas_touched(air)
	return body_after

/// `air` was changed in place: the pipe network that owns it (a device's port naming the network's mixture) records the change, so its
/// subscribers see it. A mixture no network owns (a room's, a private vessel's) needs nothing.
/proc/gas_touched(datum/gas_mixture/air)
	var/datum/pipe_network/network = owner_of(air)
	if(istype(network))
		network.mark_dirty()

// ---- filling a vessel ----

/// Fills `air` (emptied first) to `kpa` at `temperature`, the moles shared out by `fractions` (gas id -> share; shares above 1 overfill: an engine
/// set-up canister holds two loads). The canisters' presets.
/proc/gas_fill(datum/gas_mixture/air, list/fractions, kpa, temperature = T20C)
	if(!air || !length(fractions))
		return
	air.clear()
	air.set_temperature(temperature)
	var/moles = kpa * air.return_volume() / (R_IDEAL_GAS_EQUATION * temperature)
	for(var/gas in fractions)
		air.adjust_gas(gas, moles * fractions[gas])
	air.set_temperature(temperature)

/// The pressure of `air`, kPa (0 for none): a read of Rust-owned gas, never cached by a condition that asks it (READS_FROM: nothing to publish).
/proc/gas_pressure_of(datum/gas_mixture/air)
	READS_FROM()
	return air ? air.return_pressure() : 0

/// Empties `source` into `into` (a mixture or an atom whose air it is): a ruptured vessel, a room filler. Returns the moles moved.
/proc/gas_dump(datum/gas_mixture/source, into)
	var/datum/gas_mixture/sink = isatom(into) ? into:return_air() : into
	if(!source || !sink)
		return 0
	var/sink_volume = max(sink.return_volume(), 1)
	// A target the sink cannot reach before the source runs dry: everything moves.
	var/target = sink.return_pressure() + 2 * source.return_pressure() * source.return_volume() / sink_volume + 1
	return gas_release(source, into, target)
