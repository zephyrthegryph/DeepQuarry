// The gas domain's API for machines (doc/rewrite/final_api.html section 14, "Gas and heat"): what a machine asks of a gas, so that no machine
// reads or edits a mixture's moles or energy itself. Mixtures stay opaque handles and every call here is one or a few Rust-backed operations.
//
//   gas_release(source, into, target_kpa, rate)   moves gas out of `source` into `into` (a mixture, or an atom whose air it is) until `into`
//                                                  reaches target_kpa, never more than `rate` litres of `source` per call. A turf it fills is woken. Returns
//                                                  the moles moved. A canister's valve, a jetpack's refill.
//   gas_sample(air)                                one read of everything a gauge shows (pressure, temperature, volume, heat capacity, each gas):
//                                                  S.pressure, S.temperature, S.partial_pressure(GAS_O2), S.share(GAS_O2).
//   gas_dump(source, into)                         empties a vessel into a room or another mixture.
//   gas_fill(air, fractions, kpa, temperature)     a vessel filled to a pressure with a mix (a canister preset).
//   heat                                           flows belong to the heat domain (code/domains/heat/): heat_link()/heat_pump() entries, heat_move().
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

/// `air` was changed in place: the pipe network that owns it (a device's port naming the network's mixture) records the change, so its
/// subscribers see it. A mixture no network owns (a room's, a private vessel's) needs nothing.
/proc/gas_touched(datum/gas_mixture/air)
	var/datum/pipe_network/network = owner_of(air)
	if(istype(network))
		network.revision++

// ---- filling a vessel ----

/// Fills `air` (emptied first) to `kpa` at `temperature`, the moles shared out by `fractions` (gas id -> share; shares above 1 overfill: an engine
/// set-up canister holds two loads). The canisters' presets.
/proc/gas_fill(datum/gas_mixture/air, list/fractions, kpa, temperature = T20C)
	if(!air || !length(fractions))
		return
	air.clear()
	heat_set(air, temperature)
	var/moles = kpa * air.return_volume() / (R_IDEAL_GAS_EQUATION * temperature)
	for(var/gas in fractions)
		air.adjust_gas(gas, moles * fractions[gas])
	heat_set(air, temperature)

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
