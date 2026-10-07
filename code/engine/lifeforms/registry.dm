// registry(REGISTRY_X, key = nameof(var), by = REG_Z | REG_AREA), registry_get(), registry_all() and radio_listen(freq =, filter =)
// (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 3).
//
//	CAPABILITIES(/obj/machinery/door/airlock)
//		registry(REGISTRY_AIRLOCKS, key = nameof(id_tag), by = REG_Z)
//		radio_listen(freq = nameof(frequency), filter = RADIO_AIRLOCK)
//
//	var/obj/machinery/door/airlock/A = registry_get(REGISTRY_AIRLOCKS, "engine_inner", z = T.z)
//	for(var/obj/machinery/door/airlock/door as anything in registry_all(REGISTRY_AIRLOCKS, "engine_inner"))
//
// A generalised membership(): the instance is in the registry from its init to its destruction, filed under the value of its `key` var (null:
// unkeyed), and, with `by =`, under its z-level and/or its area. A write of the key var re-files it (the var must publish its writes: TRACKED
// or a setter calling tracked_changed()); a move re-files it under its new z or area; its destruction removes it. Nothing is written by hand.
// The registry's plain member list (REGISTRY_MEMBERS(id)) holds it too, so a reader of the old form keeps working.
//
// radio_listen(freq = nameof(var), filter =) is the radio listener of the area air device (code/domains/atmos/area_air_device.dm) as a form:
// the instance listens on the frequency its var holds from init, retunes when the var is written, and stops listening when it is destroyed.
// `freq` may be a number for a fixed frequency; `filter` is a RADIO_* filter or PROC_REF(x) of the holder answering one.

/proc/registry(id, key = null, by = REG_GLOBAL, when = null)
	if(!istext(id))
		declare_report("registry(): the first argument is a REGISTRY_* id, got [id]")
		return null
	return entry_make(ENTRY_REGISTRY, "registry:[id]", list("id" = id, "key" = key, "by" = by, "when" = when))

/proc/radio_listen(freq, filter = null)
	return entry_make(ENTRY_RADIO_LISTEN, "radio_listen", list("freq" = freq, "filter" = filter))

/// The keyed index of one registry id.
/datum/lifeform_index
	var/id
	/// key -> members, in join order ("" holds the unkeyed).
	var/list/by_key = list() // ALLOW(instance_list, base_vars): one index per registry id, always filled
	/// z -> key -> members.
	var/list/by_z = list() // ALLOW(instance_list, base_vars): one index per registry id, always filled
	/// area -> key -> members.
	var/list/by_area = list() // ALLOW(instance_list, base_vars): one index per registry id, always filled
	/// member -> list(key, z, area) it is filed under.
	var/list/filed = list() // ALLOW(instance_list, base_vars): one index per registry id, always filled

GLOBAL_LIST_EMPTY(lifeform_indexes) // registry id -> /datum/lifeform_index

/proc/lifeform_index(id)
	RETURN_TYPE(/datum/lifeform_index)
	var/datum/lifeform_index/I = GLOB.lifeform_indexes[id]
	if(!I)
		I = new
		I.id = id
		GLOB.lifeform_indexes[id] = I
	return I

/// The first member of registry `id` filed under `key` (null: the unkeyed), on z-level `z` or in area `area` when given.
/proc/registry_get(id, key = null, z = null, area/area = null)
	var/list/found = registry_all(id, key, z, area)
	return length(found) ? found[1] : null

/// The members of registry `id` filed under `key`, on `z` or in `area` when given. With no key and no place, every member. Read-only.
/proc/registry_all(id, key = null, z = null, area/area = null)
	RETURN_TYPE(/list)
	var/datum/lifeform_index/I = GLOB.lifeform_indexes[id]
	if(!I)
		return list()
	var/k = isnull(key) ? "" : "[key]"
	if(!isnull(z) || area)
		var/list/place = !isnull(z) ? I.by_z["[z]"] : I.by_area[area]
		if(!place)
			return list()
		if(!isnull(key))
			return place[k] || list()
		var/list/everyone = list()
		for(var/each_key in place)
			everyone += place[each_key]
		return everyone
	if(isnull(key))
		var/list/all = list()
		for(var/member in I.filed)
			all += member
		return all
	return I.by_key[k] || list()

/proc/registry_init(datum/holder, datum/lifeform_plan/P)
	for(var/datum/centry/C as anything in P.registries)
		var/datum/entry/E = C.item
		if((C.whens && !op_whens_hold(holder, C.whens)) || (!isnull(E.args["when"]) && !condition_holds(holder, E.args["when"])))
			continue
		registry_file(holder, E)
		if(E.args["by"] && ismovable(holder))
			var/atom/movable/AM = holder
			AM.lifeform_moves |= LIFEFORM_MOVES_REGISTRY

/proc/registry_teardown(datum/holder, datum/lifeform_plan/P)
	for(var/datum/centry/C as anything in P.registries)
		var/datum/entry/E = C.item
		registry_unfile(holder, E.args["id"])

/// Files `holder` in the entry's registry under its current key and place.
/proc/registry_file(datum/holder, datum/entry/E)
	var/id = E.args["id"]
	var/datum/lifeform_index/I = lifeform_index(id)
	if(I.filed[holder])
		registry_unfile(holder, id)
	var/key_var = E.args["key"]
	var/key = istext(key_var) && (key_var in holder.vars) ? holder.vars[key_var] : null
	var/k = isnull(key) ? "" : "[key]"
	var/z = null
	var/area/area = null
	var/by = E.args["by"]
	if(by && isatom(holder))
		var/turf/T = get_turf(holder)
		if(by & REG_Z)
			z = T ? "[T.z]" : null
		if(by & REG_AREA)
			area = T ? T.loc : null
	I.filed[holder] = list(k, z, area)
	LAZYADD(I.by_key[k], holder)
	if(z)
		LAZYINITLIST(I.by_z[z])
		LAZYADD(I.by_z[z][k], holder)
	if(area)
		LAZYINITLIST(I.by_area[area])
		LAZYADD(I.by_area[area][k], holder)
	holder.registry_mirror_join(id)

/proc/registry_unfile(datum/holder, id)
	var/datum/lifeform_index/I = GLOB.lifeform_indexes[id]
	var/list/at = I?.filed[holder]
	if(!at)
		return
	I.filed -= holder
	var/k = at[1]
	LAZYREMOVE(I.by_key[k], holder)
	if(at[2])
		LAZYREMOVE(I.by_z[at[2]]?[k], holder)
	if(at[3])
		LAZYREMOVE(I.by_area[at[3]]?[k], holder)
	holder.registry_mirror_leave(id)

/// The key var of a registry() entry was written: the holder is re-filed under the new key.
/proc/registry_rekey(datum/holder, datum/centry/C)
	var/datum/entry/E = C.item
	var/datum/lifeform_index/I = GLOB.lifeform_indexes[E.args["id"]]
	if(!I?.filed[holder])
		return
	registry_file(holder, E)

/// A movable filed by z or area moved: each such registry re-files it when its z or area changed.
/proc/registry_moved(atom/movable/holder)
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	var/turf/T = get_turf(holder)
	for(var/datum/centry/C as anything in P.registries)
		var/datum/entry/E = C.item
		var/by = E.args["by"]
		if(!by)
			continue
		var/datum/lifeform_index/I = GLOB.lifeform_indexes[E.args["id"]]
		var/list/at = I?.filed[holder]
		if(!at)
			continue
		var/z = (by & REG_Z) && T ? "[T.z]" : null
		var/area/area = (by & REG_AREA) && T ? T.loc : null
		if(z != at[2] || area != at[3])
			registry_file(holder, E)

// ---- radio_listen ----

GLOBAL_LIST_EMPTY(radio_listen_tuned) // holder -> the frequency it listens on now

/proc/radio_listen_init(datum/holder, datum/lifeform_plan/P)
	for(var/datum/centry/C as anything in P.radios)
		radio_listen_tune(holder, C)

/proc/radio_listen_teardown(datum/holder, datum/lifeform_plan/P)
	var/old = GLOB.radio_listen_tuned[holder]
	GLOB.radio_listen_tuned -= holder
	if(old)
		unregister_radio(holder, old)

/// Tunes `holder` to the frequency its declared var holds now (a retune leaves the old frequency first).
/proc/radio_listen_tune(datum/holder, datum/centry/C)
	var/datum/entry/E = C.item
	var/freq = E.args["freq"]
	if(istext(freq))
		freq = (freq in holder.vars) ? holder.vars[freq] : null
	var/filter = E.args["filter"]
	if(istext(filter) && hascall(holder, filter))
		filter = call(holder, filter)()
	var/old = GLOB.radio_listen_tuned[holder]
	if(old == freq && !isnull(old))
		return
	register_radio(holder, old, freq, filter)
	if(freq)
		GLOB.radio_listen_tuned[holder] = freq
	else
		GLOB.radio_listen_tuned -= holder

// ---- moves ----

/// What a movable's Moved() owes the lifecycle forms (LIFEFORM_MOVES_*, set at init): a movable that declares none pays one var read per move.
/atom/movable/var/tmp/lifeform_moves = 0 // ALLOW(base_vars): one bit field Moved() reads so a movable without a form that follows moves pays one var read

/// Called from /atom/movable/Moved() when lifeform_moves is set.
/proc/lifeform_moved(atom/movable/holder, atom/old_loc)
	if(holder.lifeform_moves & LIFEFORM_MOVES_REGISTRY)
		registry_moved(holder)
	if(holder.lifeform_moves & LIFEFORM_MOVES_ADJACENCY)
		adjacency_moved(holder, old_loc)

/// A downstream registry carrier may mirror membership in its own index.
/datum/proc/registry_mirror_join(id)
	return null

/datum/proc/registry_mirror_leave(id)
	return null
