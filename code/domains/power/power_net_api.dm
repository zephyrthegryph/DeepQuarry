// The power domain's calls into the native power network, for content: machines bind into its grid by their entity and tile, the grid is
// committed once their binds are in, and a region's size and state are read back through these. Content does not call the vg_ binds.

/// Binds the machine entity `entity` at (x, y, z) into the native grid.
/proc/power_net_bind_machine(entity, x, y, z)
	return vg_power_bind_machine(entity, x, y, z)

/// `power_net_bind_machine()` for many: `entities` and the flat `coords` list (x, y, z per entity).
/proc/power_net_bind_machine_list(list/entities, list/coords)
	return vg_power_bind_machine_list(entities, coords)

/// Removes the node `entity` from the native grid.
/proc/power_net_unbind_node(entity)
	return vg_power_unbind_node(entity)

/// Commits the grid's pending binds.
/proc/power_net_commit()
	return vg_power_commit()

/// The region `entity` is in (its id plus one; 0 is none).
/proc/power_net_region_of(entity)
	return vg_power_region_of(entity)

/// How many nodes region `region` holds.
/proc/power_net_region_size(region)
	return vg_power_region_size(region)

/// Region `region`'s state as the native network last stepped it.
/proc/power_net_region_read(region)
	return vg_power_region_read(region)
