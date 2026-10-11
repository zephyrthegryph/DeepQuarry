// Placed children and neighbour discovery (doc/rewrite/final_api.html section 6, "Lifecycle forms").
//
//	CAPABILITIES(/obj/effect/fusion_em_field)
//		spawns_many(nameof(particle_catchers), /obj/effect/fusion_particle_catcher, at = list(list(0, 0, 1), list(-1, 0, 3), ...),
//			back = nameof(/obj/effect/fusion_particle_catcher::parent), each = PROC_REF(catcher_placed), only_if = nameof(owned_core))
//
//	CAPABILITIES(/obj/machinery/teleport/station)
//		finds(nameof(com), /obj/machinery/teleport/hub, near = NEAR_CARDINAL)
//
// spawns_many() builds one `type` per offset in `at` (list(dx, dy, extra...), relative to the holder's turf; on another z or off the map the
// offset is skipped; `at` may be a PROC_REF answering the list, such as a TYPE_TABLE), adds each to the holder's owns_many list `var`, writes the holder into the child's `back` var, and calls the holder's
// each(child, offset) to configure it (the extra values ride in `offset`). It runs in the capability init (phase 2 of the init contract), and
// only when `only_if` (a holder var) is truthy then. The list var must be owns_many-declared, so the children go with the holder.
//
// finds() writes into the holder's `var` the first `type` found next to it (NEAR_CARDINAL: the four cardinal neighbour turfs, in
// GLOB.cardinal order; NEAR_AROUND: the eight around it) when its init is complete (after_init timing: every map-loaded neighbour exists and has
// initialized), and, with `back =`, writes the holder into the found thing's `back` var. Nothing found leaves the var as it was.


CAPABILITY_TYPE(spawns_many, CAP_SPAWNS_MANY, /datum/capability/lib/spawns_many, key = NONE, var_name = null, kind = null, at = null, back = null, each = null, only_if = null)

/datum/capability/lib/spawns_many
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/spawns_many/on_holder_init(datum/act/eval/A)
	var/atom/holder = A.holder
	if(!isatom(holder) || !ispath(kind))
		return
	if(only_if && !holder.vars[only_if])
		return
	var/turf/origin = get_turf(holder)
	if(!origin)
		return
	var/list/offsets = istext(at) ? call(holder, at)() : at // a PROC_REF answering the layout (a TYPE_TABLE), or the list itself
	for(var/list/offset as anything in offsets)
		var/turf/place = locate(origin.x + offset[1], origin.y + offset[2], origin.z)
		if(!place)
			continue
		var/datum/child = new kind(place)
		if(back)
			rel_set(child, back, holder)
		if(each)
			call(holder, each)(child, offset)
		rel_add(holder, var_name, child)

CAPABILITY_TYPE(finds, CAP_FINDS, /datum/capability/lib/finds, key = NONE, var_name = null, kind = null, near = NEAR_CARDINAL, back = null)

/datum/capability/lib/finds/entries()
	return list(after_init(0, then(CAP_PROC(look_around))))

/datum/capability/lib/finds/proc/look_around(datum/act/timer/A)
	var/atom/holder = A.holder
	var/turf/origin = get_turf(holder)
	if(!origin)
		return
	var/list/dirs = near == NEAR_AROUND ? GLOB.alldirs : GLOB.cardinal
	for(var/direction in dirs)
		var/atom/found = locate(kind) in get_step(origin, direction)
		if(!found)
			continue
		rel_set(holder, var_name, found)
		if(back)
			rel_set(found, back, holder)
		return
