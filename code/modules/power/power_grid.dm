READ_LOOKUP(/proc/power_grid_lookup, registry = GLOBAL_PROC_REF(power_grid_registry), key = GLOBAL_PROC_REF(power_grid_identity_key), argument = 1, result = /datum/power_grid)

// DM state for the Rust domain's numeric cable-region identities. Real field
// setters publish once on the region datum; numeric lookup dependencies bind
// the registry identity key and the selected datum, including empty regions.
// Negative identities remain detached test ledgers and are never sent to Rust.

/datum/power_grid
	var/avail = 0
	var/load = 0
	var/brownout = FALSE
	var/problem_timed = FALSE
	var/material_problem = FALSE
	var/list/nodes


CAPABILITIES(/datum/power_grid)
	ref_many(nameof(nodes), /obj/machinery/power)

/datum/power_grid/lifecycle_unbind()
	var/datum/power_grid_registry/registry = owner_of(src)
	if(istype(registry))
		registry.forget(src)
	. = ..()

/datum/power_grid_registry
	/// Numeric identities are alist keys, never ordinary list indices.
	var/alist/by_id
	var/list/owned_grids

CAPABILITIES(/datum/power_grid_registry)
	owns_many(nameof(owned_grids), /datum/power_grid)

/proc/power_grid_registry()
	RETURN_TYPE(/datum/power_grid_registry)
	return SSmachines.power_grid_registry()

/// A pure lookup: a requirement or draw does not create simulation state.
/proc/power_grid_lookup(id)
	RETURN_TYPE(/datum/power_grid)
	return id ? power_grid_registry()?.lookup(id) : null

/proc/power_grid_identity_key(id)
	return "power_grid:[num2text(id, 20)]"

/datum/power_grid_registry/proc/lookup(id)
	RETURN_TYPE(/datum/power_grid)
	return by_id?[id]

/datum/power_grid_registry/proc/ids()
	return by_id ? by_id.Copy() : alist()

/// Actual lookup consumers may warm a Rust-only numeric ID before DM custody exists.
/// The system's write step synchronizes those real watched identities; pure reads never do.
/datum/power_grid_registry/proc/watched_native_ids()
	. = list()
	for(var/key in lookup_registry_watched_keys(src))
		if(findtext(key, "power_grid:") != 1)
			continue
		var/id = text2num(copytext(key, 12))
		if(id > 0)
			. |= list(id)

/datum/power_grid_registry/proc/put(id, datum/power_grid/grid)
	if(!id || !grid || lookup(id) == grid)
		return
	if(lookup(id))
		drop(id)
	if(!by_id)
		by_id = alist()
	rel_add(src, nameof(owned_grids), grid)
	by_id[id] = grid
	tracked_changed(src, power_grid_identity_key(id))

/datum/power_grid_registry/proc/drop(id)
	var/datum/power_grid/grid = lookup(id)
	if(!grid)
		return
	by_id -= id
	tracked_changed(src, power_grid_identity_key(id))
	rel_take(src, nameof(owned_grids), grid)
	lifeform_end(grid, END_SCOPE)

/// A grid ended externally: remove its actual identity while it still has an owner.
/datum/power_grid_registry/proc/forget(datum/power_grid/grid)
	for(var/id in ids())
		if(lookup(id) != grid)
			continue
		by_id -= id
		tracked_changed(src, power_grid_identity_key(id))
		rel_take(src, nameof(owned_grids), grid)

/datum/power_grid_registry/proc/clear()
	for(var/id in ids())
		drop(id)

/// Explicit ensure for writers and network binding, not a requirement read.
/proc/power_grid(id)
	RETURN_TYPE(/datum/power_grid)
	if(!id)
		return null
	var/datum/power_grid/grid = power_grid_lookup(id)
	if(grid)
		return grid
	grid = new
	// Readers warmed against Rust already see the real native values. Hydrate
	// before identity publication so adopting the record cannot expose zero defaults.
	grid.poll_native(id)
	power_grid_registry().put(id, grid)
	return grid

/// Poll the real region fields once per power step. No per-machine relay.
/proc/power_grid_refresh(id)
	if(id <= 0)
		return TRUE
	var/datum/power_grid/grid = power_grid_lookup(id)
	return grid ? grid.poll_native(id) : FALSE

/// The same real native poll fills an unpublished new record and updates a live one.
/datum/power_grid/proc/poll_native(id)
	if(id <= 0)
		return TRUE // detached ledgers retain their real tracked values
	var/list/info = vg_power_region_read(id)
	if(!info)
		return FALSE
	return apply_native_sample(info)

/// A Rust ledger sample is one coherent state: every field is set before any
/// observer rechecks, with each actual changed key published once afterward.
/datum/power_grid/proc/apply_native_sample(list/info)
	return state_batch(src, PROC_REF(write_native_sample), list(info))

/datum/power_grid/proc/write_native_sample(list/info)
	set_avail(info[1])
	set_load(info[2])
	set_brownout(!!info[3])
	return TRUE

// ---- reads ------------------------------------------------------------------

/proc/power_avail(id)
	var/datum/power_grid/grid = power_grid_lookup(id)
	if(grid)
		return grid.avail
	var/list/info = id > 0 ? vg_power_region_read(id) : null
	return info ? info[1] : 0

/proc/power_load(id)
	var/datum/power_grid/grid = power_grid_lookup(id)
	if(grid)
		return grid.load
	var/list/info = id > 0 ? vg_power_region_read(id) : null
	return info ? info[2] : 0

/// Supply minus load at the last step (may be negative when overdrawn).
/proc/power_netexcess(id)
	var/datum/power_grid/grid = power_grid_lookup(id)
	if(grid)
		return grid.avail - grid.load
	var/list/info = id > 0 ? vg_power_region_read(id) : null
	return info ? info[1] - info[2] : 0

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
	var/datum/power_grid/grid = power_grid_lookup(id)
	if(grid)
		return grid.brownout
	var/list/info = id > 0 ? vg_power_region_read(id) : null
	return info ? !!info[3] : FALSE

/// TRUE while power monitors should show a warning for region `id`.
/proc/power_problem(id)
	var/datum/power_grid/grid = power_grid_lookup(id)
	if(!grid)
		return FALSE
	return grid.material_problem || grid.problem_timed

/// The machines bound to region `id` (do not modify).
/proc/power_grid_nodes(id)
	RETURN_TYPE(/list)
	var/datum/power_grid/grid = power_grid_lookup(id)
	return grid?.nodes || list()

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
	var/datum/power_grid/grid = power_grid(id)
	if(!grid || amount <= 0)
		return 0
	var/datum/material_power_overlay/overlay = SSmachines.power_material_overlays[id]
	var/efficiency = 1
	if(consumer && overlay?.material_graph)
		efficiency = overlay.material_graph.efficiency_for(consumer)
	var/drawn
	if(id < 0)
		drawn = between(0, amount / efficiency, grid.avail - grid.load)
	else
		drawn = vg_power_region_draw(id, amount / efficiency)
	grid.set_load(grid.load + drawn)
	var/delivered = drawn * efficiency
	if(consumer && overlay?.material_graph)
		overlay.add_material_consumption(consumer, delivered)
	return delivered

/// Flags a problem visible on power monitors for `duration` deciseconds.
/proc/power_warn(id, duration = 2 SECONDS)
	var/datum/power_grid/grid = power_grid(id)
	if(!grid)
		return
	grid.set_problem_timed(TRUE)
	after(null, max(duration, 0.1 SECONDS), GLOBAL_PROC_REF(power_warn_expire), key = "power_warn:[id]", with = list(id))

/// Ends a timed power_warn() on region `id` once its duration has run out.
/proc/power_warn_expire(id)
	var/datum/power_grid/grid = power_grid_lookup(id)
	if(!grid)
		return
	grid.set_problem_timed(FALSE)

/proc/power_set_material_warning(id, active)
	var/datum/power_grid/grid = power_grid(id)
	if(!grid || grid.material_problem == !!active)
		return
	grid.set_material_problem(!!active)

/// Binds `M` onto region `new_id` (0 = none), leaving its old one.
/proc/power_grid_move_node(obj/machinery/power/M, old_id, new_id)
	var/datum/power_grid/old_grid = power_grid_lookup(old_id)
	if(old_grid)
		rel_remove(old_grid, nameof(old_grid.nodes), M)
	var/datum/power_grid/new_grid = power_grid(new_id)
	if(new_grid)
		rel_add(new_grid, nameof(new_grid.nodes), M)
	var/datum/material_power_overlay/overlay = SSmachines.power_material_overlays[old_id]
	overlay?.material_cache_dirty = TRUE
	overlay = SSmachines.power_material_overlays[new_id]
	overlay?.material_cache_dirty = TRUE

// ---- detached test grids ----------------------------------------------------

/// A detached grid holding `avail` W that Rust never sees (tests). Returns its id.
/proc/power_test_grid(avail = 0)
	var/id = --SSmachines.power_test_grid_serial
	var/datum/power_grid/grid = power_grid(id)
	grid.set_avail(avail)
	return id

/proc/power_test_set_avail(id, avail)
	var/datum/power_grid/grid = power_grid(id)
	grid.set_avail(avail)

/proc/power_test_set_brownout(id, value)
	var/datum/power_grid/grid = power_grid(id)
	grid.set_brownout(!!value)

/// Puts `M` on detached grid `id` without a Rust node.
/proc/power_test_join(id, obj/machinery/power/M)
	var/old = M.power_region
	M.set_power_region(id)
	power_grid_move_node(M, old, id)

/proc/power_test_drop_grid(id)
	var/list/nodes = power_grid_nodes(id)
	for(var/obj/machinery/power/M as anything in nodes.Copy())
		if(M.power_region == id)
			M.set_power_region(0)
	power_grid_registry().drop(id)

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
	var/datum/power_grid/grid = region_id ? power_grid(region_id) : null
	if(material_loss_watts > 0 && grid)
		grid.set_load(grid.load + vg_power_region_draw(region_id, material_loss_watts))
	power_set_material_warning(region_id, material_loss_watts > max((grid ? grid.load : 0) * 0.1, 1000))
	return TRUE


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
