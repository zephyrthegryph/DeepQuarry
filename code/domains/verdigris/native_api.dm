// The native layer's calls for content that have no domain of their own: its allocator report, background jobs (the station layout), the
// cave generator, the EMP and radiation fields and the chemistry cycle. Content does not call the vg_ binds (lint_scopes.toml, legacy_forms).

/// The native allocator's diagnostics (a list).
/proc/native_allocator_diagnostics()
	return vg_verdigris_allocator_diagnostics()

/// Submits a station layout request (`payload`, JSON text) as a native job; returns the job id.
/proc/native_station_layout_submit(payload)
	return vg_verdigris_submit_station_layout(payload)

/// The status text of native job `job_id`.
/proc/native_job_poll(job_id)
	return vg_verdigris_job_poll(job_id)

/// One page of a finished station layout job's result: `section` from `offset`, at most `limit` entries (JSON text).
/proc/native_station_layout_section(job_id, section, offset, limit)
	return vg_verdigris_station_layout_section(job_id, section, offset, limit)

/// Frees native job `job_id` and its result.
/proc/native_job_finish(job_id)
	return vg_verdigris_job_finish(job_id)

/// The EMP strength falloff rings around (x, y, z) for the four `ranges`, on a map of the given size.
/proc/native_emp_falloff(x, y, z, max_x, max_y, max_z, list/ranges)
	return vg_emp_falloff(x, y, z, max_x, max_y, max_z, ranges)

/// Loads the radiation grid's cells (`max_x` by `max_y`).
/proc/native_radiation_set_cells(max_x, max_y, list/cells)
	return vg_radiation_set_cells(max_x, max_y, cells)

/// Casts one radiation pulse from (x, y, z) over `range`, down to `threshold`, at `targets`.
/proc/native_radiation_pulse(x, y, z, range, threshold, list/targets)
	return vg_radiation_pulse(x, y, z, range, threshold, targets)

/// A cave map by cellular automata.
/proc/native_cave_automata(limit_x, limit_y, iterations, initial_wall_cell)
	return vg_generate_automata(limit_x, limit_y, iterations, initial_wall_cell)

/// One metabolism cycle over the flat `args_flat` list.
/proc/native_chem_metabolism_cycle(list/args_flat)
	return vg_chem_metabolism_cycle(args_flat)
