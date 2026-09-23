// The spatial API (doc/rewrite/containment.md §2a): tile queries, as opposed
// to a holder's own contents (which go through the ledger read API in
// api.dm/latent.dm). A turf's contents are engine-maintained -- BYOND updates
// them on every move and nothing here can intercept that -- so this is one
// central, typed wrapper over the existing turf contents list, not a
// ledger-backed structure. Centralizing call sites here means the
// implementation can change later (e.g. to consult a Rust-side spatial index
// for a hot query) without touching every call site again.

/// Every atom of `type` (and subtypes) on turf `T`, as a new list. Equivalent
/// to `for(var/type/A in T)`, named so the spatial lint can count and convert
/// call sites instead of matching bare loops.
///
/// # Examples
///
/// ```
/// var/list/obj/machinery/door/doors = turf_contents_of_type(T, /obj/machinery/door)
/// ```
/proc/turf_contents_of_type(turf/T, type)
	. = list()
	if(!T)
		return
	for(var/atom/movable/AM in T)
		if(istype(AM, type))
			. += AM

/// The first atom of `type` on turf `T`, or null. Equivalent to
/// `locate(type) in T`.
/proc/locate_on(turf/T, type)
	if(!T)
		return null
	return locate(type) in T

/// Calls `callback` (a `/datum/callback` from `CALLBACK()`) once per atom of
/// `type` on turf `T`, without allocating a list. For hot paths (radiation,
/// EMP, explosion falloff) that only need a side effect per atom and would
/// otherwise build a list with `turf_contents_of_type()` and throw it away.
/// Returns the number of atoms visited.
/proc/turf_each(turf/T, type, datum/callback/callback)
	. = 0
	if(!T || !callback)
		return
	for(var/atom/movable/AM in T)
		if(!istype(AM, type))
			continue
		. += 1
		callback.Invoke(AM)
