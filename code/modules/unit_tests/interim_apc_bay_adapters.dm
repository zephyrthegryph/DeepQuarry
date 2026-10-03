/// Test adapter for the migrated APC bay's actual public op. It selects the insert operation explicitly so an occupied bay tests insertion rather than click priority.
/proc/interim_apc_insert(obj/machinery/power/apc/apc, obj/item/cell/cell, mob/user)
	var/datum/op_result/result = perform_op(user, apc, "cell_bay.cell.insert", cell, origin = ORIGIN_SYSTEM)
	return result?.outcome == ACT_COMMITTED

/// The actual public take op still handles full hands by releasing the original cell to the floor. Optional dropping is a real subsequent inventory operation.
/proc/interim_apc_take(obj/machinery/power/apc/apc, mob/user, drop = FALSE)
	var/obj/item/cell/original = apc.cell
	var/datum/op_result/result = perform_op(user, apc, "cell_bay.cell.take", origin = ORIGIN_SYSTEM)
	if(result?.outcome != ACT_COMMITTED)
		return null
	if(drop && original.loc == user)
		if(!user.drop_from_inventory(original))
			return null
	return original

/// A real completed APC, with its initialized spillable cell tracked and the pre-existing area's channel values restored after teardown.
/datum/unit_test/proc/interim_apc_make(turf/T)
	var/area/powered_area = get_area(T)
	var/obj/machinery/power/apc/previous_apc = powered_area.apc
	set_var(powered_area, nameof(powered_area.power_light), powered_area.power_light)
	set_var(powered_area, nameof(powered_area.power_equip), powered_area.power_equip)
	set_var(powered_area, nameof(powered_area.power_environ), powered_area.power_environ)
	var/obj/machinery/power/apc/apc = allocate(/obj/machinery/power/apc, T)
	own(apc.cell)
	own(apc.terminal)
	defer_cleanup(src, PROC_REF(interim_apc_cleanup), apc, powered_area, previous_apc)
	return apc

/// Delete the fixture through its actual lifecycle before restoring the area's original APC relation. Saved channel vars restore after allocated objects are deleted.
/datum/unit_test/proc/interim_apc_cleanup(obj/machinery/power/apc/apc, area/powered_area, obj/machinery/power/apc/previous_apc)
	if(!QDELETED(apc))
		qdel(apc)
	if(!powered_area)
		return
	if(previous_apc && !QDELETED(previous_apc))
		rel_set(powered_area, nameof(powered_area.apc), previous_apc)
	else
		rel_clear(powered_area, nameof(powered_area.apc))
