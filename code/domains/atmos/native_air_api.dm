// The atmos domain's calls into the native gas engine, for content: which turfs a turf passes air to, the work to move gas between two
// mixtures and a batch of transfers in one call. Content does not call the vg_ binds (lint_scopes.toml, legacy_forms).

/// The turfs `turf` passes air to now.
/proc/atmos_adjacent_turfs_of(turf/turf)
	return vg_atmos_adjacent_turfs(turf)

/// The specific power (J per mole) of moving gas from `source`'s mixture into `sink`.
/proc/atmos_specific_power(datum/gas_mixture/source, datum/gas_mixture/sink)
	return vg_specific_power(source, sink)

/// A batch of gas transfers (`operations`) applied in one call; returns the moles each actually moved.
/proc/atmos_batch_transfer(list/operations)
	return vg_batch_transfer_hook(operations)
