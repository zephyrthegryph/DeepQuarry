// The DM view of the Rust power domain's cable regions (M3b). There is no
// per-network datum: a machine holds the number of the region its node is on
// (`/obj/machinery/power/var/power_region`, 0 = none) and everything else asks
// the procs below with that number. Rust (verdigris/domains/power) owns the
// topology and the ledger; DM keeps only what Rust deliberately does not:
// the monitor warning, and which machines sit on a region
// (so readers can walk them), in one flat list per region in
// `SSmachines.power_grids`.
//
// Region ids are stable across edits that keep the region (a merge keeps the
// larger region's id; a split keeps the parent id for one side). A region
// Rust no longer knows is dropped at the next power step.
//
// Change channels are raised on each machine bound to the region
// (CHANGE_POWER_GRID_* in om.dm), so something that waits on a grid watches a
// machine that is on it.
//
// Negative ids are detached test grids (`power_test_grid()`): their numbers
// are their own ledger and Rust never sees them.

#define PGRID_AVAIL 1
#define PGRID_LOAD 2
#define PGRID_BROWNOUT 3
/// TRUE while a timed power_warn() is showing (cleared by power_warn_expire()).
#define PGRID_PROBLEM_TIMED 4
/// The material overlay's own standing warning.
#define PGRID_MATERIAL_PROBLEM 5
/// The warning state last announced on CHANGE_POWER_GRID_STATE.
#define PGRID_PROBLEM_SHOWN 6
/// Machines bound to the region.
#define PGRID_NODES 7
#define PGRID_FIELDS 7

/// The state list of region `id`, made on first use (null for 0).
/proc/power_grid(id)
	if(!id)
		return null
	var/list/grid = SSmachines.power_grids[id]
	if(grid)
		return grid
	grid = new /list(PGRID_FIELDS)
	grid[PGRID_AVAIL] = 0
	grid[PGRID_LOAD] = 0
	grid[PGRID_BROWNOUT] = FALSE
	grid[PGRID_PROBLEM_TIMED] = FALSE
	grid[PGRID_MATERIAL_PROBLEM] = FALSE
	grid[PGRID_PROBLEM_SHOWN] = FALSE
	grid[PGRID_NODES] = list() // one per live region; created because a machine joined
	SSmachines.power_grids[id] = grid
	power_grid_refresh(id)
	return grid

/// Raises `bits` on every machine bound to region `id`.
/proc/power_grid_changed(id, bits)
	var/list/grid = id ? SSmachines.power_grids[id] : null
	if(!grid)
		return
	for(var/obj/machinery/power/M as anything in grid[PGRID_NODES])
		native_changed(M, bits, NATIVE_SRC_POWER)

/// Polls region `id`'s numbers from Rust (once a power step). FALSE when Rust
/// no longer has the region.
/proc/power_grid_refresh(id)
	if(id <= 0)
		return TRUE
	var/list/grid = SSmachines.power_grids[id]
	if(!grid)
		return FALSE
	var/list/info = vg_power_region_read(id)
	if(!info)
		return FALSE
	var/old_avail = grid[PGRID_AVAIL]
	var/old_load = grid[PGRID_LOAD]
	grid[PGRID_AVAIL] = info[1]
	grid[PGRID_LOAD] = info[2]
	// Rust reports raw numbers only (rust_core.md §15). Smoothing is the reader's: a monitor's UI eases
	// what it shows on the client, DM keeps no eased copy.
	var/bits = 0
	var/brown = !!info[3]
	if(brown != grid[PGRID_BROWNOUT])
		grid[PGRID_BROWNOUT] = brown
		bits |= CHANGE_POWER_GRID_STATE
	if(old_avail != info[1] || old_load != info[2])
		bits |= CHANGE_POWER_GRID_RATE
	if(bits)
		power_grid_changed(id, bits)
	return TRUE

/// Announces a warning that started or ended since the last announcement.
/proc/power_grid_sync_problem(id)
	var/list/grid = SSmachines.power_grids[id]
	if(!grid)
		return
	var/now = power_problem(id)
	if(now != grid[PGRID_PROBLEM_SHOWN])
		grid[PGRID_PROBLEM_SHOWN] = now
		power_grid_changed(id, CHANGE_POWER_GRID_STATE)

// ---- reads ------------------------------------------------------------------

/proc/power_avail(id)
	var/list/grid = power_grid(id)
	return grid ? grid[PGRID_AVAIL] : 0

/proc/power_load(id)
	var/list/grid = power_grid(id)
	return grid ? grid[PGRID_LOAD] : 0

/// Supply minus load at the last step (may be negative when overdrawn).
/proc/power_netexcess(id)
	var/list/grid = power_grid(id)
	return grid ? grid[PGRID_AVAIL] - grid[PGRID_LOAD] : 0

/// Spare power right now, never negative.
/proc/power_surplus(id)
	return max(power_netexcess(id), 0)

/// What a monitor shows for supply: the raw ledger value (the UI eases it client-side).
/proc/power_view_avail(id)
	return power_avail(id)

/// What a monitor shows for load: the raw ledger value.
/proc/power_view_load(id)
	return power_load(id)

/proc/power_brownout(id)
	var/list/grid = power_grid(id)
	return grid ? grid[PGRID_BROWNOUT] : FALSE

/// TRUE while power monitors should show a warning for region `id`.
/proc/power_problem(id)
	var/list/grid = power_grid(id)
	if(!grid)
		return FALSE
	return grid[PGRID_MATERIAL_PROBLEM] || grid[PGRID_PROBLEM_TIMED]

/// The machines bound to region `id` (do not modify).
/proc/power_grid_nodes(id)
	RETURN_TYPE(/list)
	var/list/grid = power_grid(id)
	return grid ? grid[PGRID_NODES] : list()

/// Any one machine on region `id` (a key to watch it by), or null.
/proc/power_grid_any_node(id)
	var/list/nodes = power_grid_nodes(id)
	return length(nodes) ? nodes[1] : null

/proc/power_percent_load(id, smes_only = FALSE)
	var/load = power_load(id)
	if(smes_only)
		// SMES output is not reported per tick any more; nothing is available from storage here.
		return 0
	var/avail = power_avail(id)
	if(!load || !avail)
		return 0
	return between(0, (load / avail) * 100, 100)

/proc/power_electrocute_damage(id)
	// Logarithmic damage scaling:
	// 1kW=5, 10kW=24, 100kW=45, 250kW=53, 1MW=66, 10MW=88, 100MW=110, 1GW=132
	var/avail = power_avail(id)
	if(avail >= 1000)
		var/damage = log(1.1, avail)
		damage = damage - (log(1.1, damage) * 1.5)
		return round(damage)
	return 0

// ---- writes -----------------------------------------------------------------

/// Draws from region `id` for `consumer` (or anonymously). Returns what was
/// delivered; never more than the spare supply this step.
/proc/power_draw(id, amount, atom/consumer)
	var/list/grid = power_grid(id)
	if(!grid || amount <= 0)
		return 0
	var/datum/material_power_overlay/overlay = SSmachines.power_material_overlays[id]
	var/efficiency = 1
	if(consumer && overlay?.material_graph)
		efficiency = overlay.material_graph.efficiency_for(consumer)
	var/drawn
	if(id < 0)
		drawn = between(0, amount / efficiency, grid[PGRID_AVAIL] - grid[PGRID_LOAD])
	else
		drawn = vg_power_region_draw(id, amount / efficiency)
	grid[PGRID_LOAD] += drawn
	var/delivered = drawn * efficiency
	if(consumer && overlay?.material_graph)
		overlay.add_material_consumption(consumer, delivered)
	return delivered

/// Flags a problem visible on power monitors for `duration` deciseconds.
/proc/power_warn(id, duration = 2 SECONDS)
	var/list/grid = power_grid(id)
	if(!grid)
		return
	grid[PGRID_PROBLEM_TIMED] = TRUE
	after(null, max(duration, 0.1 SECONDS), GLOBAL_PROC_REF(power_warn_expire), key = "power_warn:[id]", with = list(id))
	power_grid_sync_problem(id)

/// Ends a timed power_warn() on region `id` once its duration has run out.
/proc/power_warn_expire(id)
	var/list/grid = SSmachines.power_grids[id]
	if(!grid)
		return
	grid[PGRID_PROBLEM_TIMED] = FALSE
	power_grid_sync_problem(id)

/proc/power_set_material_warning(id, active)
	var/list/grid = power_grid(id)
	if(!grid || grid[PGRID_MATERIAL_PROBLEM] == !!active)
		return
	grid[PGRID_MATERIAL_PROBLEM] = !!active
	power_grid_sync_problem(id)

/// Binds `M` onto region `new_id` (0 = none), leaving its old one.
/proc/power_grid_move_node(obj/machinery/power/M, old_id, new_id)
	var/list/old_grid = old_id ? SSmachines.power_grids[old_id] : null
	if(old_grid)
		old_grid[PGRID_NODES] -= M
		power_grid_changed(old_id, CHANGE_POWER_GRID_TOPOLOGY)
	var/list/new_grid = power_grid(new_id)
	if(new_grid)
		new_grid[PGRID_NODES] |= M
		power_grid_changed(new_id, CHANGE_POWER_GRID_TOPOLOGY)
	var/datum/material_power_overlay/overlay = SSmachines.power_material_overlays[old_id]
	overlay?.material_cache_dirty = TRUE
	overlay = SSmachines.power_material_overlays[new_id]
	overlay?.material_cache_dirty = TRUE

// ---- detached test grids ----------------------------------------------------

/// A detached grid holding `avail` W that Rust never sees (tests). Returns its id.
/proc/power_test_grid(avail = 0)
	var/id = --SSmachines.power_test_grid_serial
	var/list/grid = power_grid(id)
	grid[PGRID_AVAIL] = avail
	return id

/proc/power_test_set_avail(id, avail)
	var/list/grid = power_grid(id)
	grid[PGRID_AVAIL] = avail
	power_grid_changed(id, CHANGE_POWER_GRID_RATE)

/proc/power_test_set_brownout(id, value)
	var/list/grid = power_grid(id)
	grid[PGRID_BROWNOUT] = !!value
	power_grid_changed(id, CHANGE_POWER_GRID_STATE)

/// Puts `M` on detached grid `id` without a Rust node.
/proc/power_test_join(id, obj/machinery/power/M)
	var/old = M.power_region
	M.power_region = id
	power_grid_move_node(M, old, id)

/proc/power_test_drop_grid(id)
	var/list/nodes = power_grid_nodes(id)
	for(var/obj/machinery/power/M as anything in nodes.Copy())
		if(M.power_region == id)
			M.power_region = 0
	SSmachines.power_grids -= id

// ---- material overlay -------------------------------------------------------
// The CG voltage solver (material_power.rs) runs only for regions holding an
// engineered conductor. Member cables point at the overlay while it owns them.

/datum/material_power_overlay
	/// The region this overlays (0 for a detached test overlay).
	var/region_id = 0
	/// Member cables (two-sided with each cable's material_overlay), rebuilt with the material graph.
	var/list/obj/structure/cable/cables
	var/material_cache_dirty = TRUE
	var/datum/material_power_graph/material_graph
	/// Demand this interval: vertex index -> watts (material_graph.vertex_for()).
	var/alist/material_consumers
	var/material_loss_watts = 0
	var/material_pending_heat = 0
	var/material_pending_heat_elapsed = 0
	EXPIRY_DECLARE(last_material_process)

CAPABILITIES(/datum/material_power_overlay)
	owns_one(nameof(material_graph), /datum/material_power_graph)

/datum/material_power_overlay/New(id)
	region_id = id
	..()


/datum/material_power_overlay/lifecycle_unbind()
	. = ..()
	if(region_id && SSmachines.power_material_overlays[region_id] == src)
		SSmachines.power_material_overlays -= region_id

/datum/material_power_overlay/proc/add_cable(obj/structure/cable/C)
	rel_add(src, nameof(cables), C) // two-sided: sets C.material_overlay
	invalidate_material_cache()

/datum/material_power_overlay/proc/remove_cable(obj/structure/cable/C)
	rel_remove(src, nameof(cables), C)
	invalidate_material_cache()

/// Books `watts` delivered to `consumer` this interval, at its vertex.
/datum/material_power_overlay/proc/add_material_consumption(atom/consumer, watts)
	var/index = material_graph?.vertex_for(consumer)
	if(!index)
		return
	if(!material_consumers)
		material_consumers = alist()
	material_consumers[index] += watts

/datum/material_power_overlay/proc/invalidate_material_cache()
	material_cache_dirty = TRUE

/datum/material_power_overlay/proc/release_material_cables()
	rel_clear(src, nameof(cables)) // two-sided: each cable's material_overlay lets go

/datum/material_power_overlay/proc/rebuild_material_cache()
	material_cache_dirty = FALSE
	if(region_id)
		release_material_cables()
		for(var/entity in vg_power_region_members(region_id))
			var/obj/structure/cable/C = SSvg.entity_lookup(entity)
			if(istype(C) && C.power_entity == entity)
				rel_add(src, nameof(cables), C)
	// Demand booked so far is keyed by the old graph's vertices: it can't carry over.
	material_consumers = null
	rel_set(src, nameof(material_graph), new /datum/material_power_graph)
	material_graph.build(cables, region_id)

/// Supply by vertex for the solver: each bound machine's registered rate, at its vertex.
/datum/material_power_overlay/proc/material_sources()
	var/alist/sources = alist()
	for(var/obj/machinery/power/M as anything in power_grid_nodes(region_id))
		if(M.power_supply_rate > 0)
			var/index = material_graph?.vertex_for(M)
			if(index)
				sources[index] += M.power_supply_rate
	return sources

/// One overlay step: settle heat for the last interval, solve, and pay the
/// resistive loss from the grid. FALSE when the region holds no engineered
/// conductor any more (the caller drops the overlay).
/datum/material_power_overlay/proc/process_material_network()
	var/elapsed_seconds = last_material_process ? max((world.time - last_material_process) / 10, 0.1) : 1
	EXPIRY_STAMP(src, last_material_process, CLOCK_WORLD)
	if(material_cache_dirty)
		rebuild_material_cache()
	if(!material_graph?.has_custom_conductors && !material_graph?.has_superconductors)
		power_set_material_warning(region_id, FALSE)
		return FALSE
	for(var/obj/machinery/power/terminal/T in power_grid_nodes(region_id))
		var/obj/machinery/power/apc/A = T.master()
		if(istype(A))
			add_material_consumption(T, A.channel_load_total())

	material_pending_heat += material_loss_watts * elapsed_seconds
	material_pending_heat_elapsed += elapsed_seconds
	if(material_cache_dirty || material_graph.has_superconductors || material_pending_heat_elapsed >= MATERIAL_POWER_HEAT_SETTLEMENT_INTERVAL)
		material_graph.deposit_losses(material_pending_heat, material_pending_heat_elapsed)
		material_pending_heat = 0
		material_pending_heat_elapsed = 0
	material_graph.resolve_loads(material_sources(), material_consumers)
	material_loss_watts = material_graph.loss_watts
	material_consumers = null
	var/list/grid = region_id ? power_grid(region_id) : null
	if(material_loss_watts > 0 && grid)
		grid[PGRID_LOAD] += vg_power_region_draw(region_id, material_loss_watts)
	power_set_material_warning(region_id, material_loss_watts > max((grid ? grid[PGRID_LOAD] : 0) * 0.1, 1000))
	return TRUE

#undef PGRID_AVAIL
#undef PGRID_LOAD
#undef PGRID_BROWNOUT
#undef PGRID_PROBLEM_TIMED
#undef PGRID_MATERIAL_PROBLEM
#undef PGRID_PROBLEM_SHOWN
#undef PGRID_NODES
#undef PGRID_FIELDS

////////////////////////////////////////////////
// Misc.
///////////////////////////////////////////////

// return a knot cable (O-X) if one is present in the turf, null otherwise.
/turf/proc/get_cable_node()
	for(var/obj/structure/cable/C in turf_contents_of_type(src, /obj/structure/cable))
		if(C.d1 == 0)
			return C
	return null

/area/proc/get_apc()
	return apc
