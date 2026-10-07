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
	READS_FROM() // what stands on a tile is asked when a choice is made, never cached
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
/proc/turf_each(turf/T, type, datum/actor_callback/callback)
	. = 0
	if(!T || !callback)
		return
	for(var/atom/movable/AM in T)
		if(!istype(AM, type))
			continue
		. += 1
		callback.invoke_actor(AM)

/// Every atom of `type` (and subtypes) anywhere in area `A`, as a new list.
/// Equivalent to `for(var/type/A in Area)`, one level up from
/// `turf_contents_of_type()`. `type` can be a movable type (BYOND yields the
/// area's movable atoms) or a turf type (BYOND yields the area's own member
/// turfs) -- both are `/atom`, so one generic loop covers both shapes.
///
/// # Examples
///
/// ```
/// var/list/obj/machinery/light/L = area_contents_of_type(A, /obj/machinery/light)
/// var/list/turf/simulated/floor/floors = area_contents_of_type(A, /turf/simulated/floor)
/// ```
/proc/area_contents_of_type(area/A, type)
	. = list()
	if(!A)
		return
	for(var/atom/AT in A)
		if(istype(AT, type))
			. += AT

/// The first atom of `type` anywhere in area `A`, or null. Equivalent to
/// `locate(type) in A`.
/proc/locate_in_area(area/A, type)
	if(!A)
		return null
	return locate(type) in A

// Generic reads (C11): the named replacements for raw `in X.contents` loops,
// implicit `for(var/T/A in holder)` loops, `X.contents.len` and `locate() in`
// over an arbitrary list. They work on any atom (turf, mob, obj, area), so a
// call site does not have to care whether its holder is ledger-tracked.

/// A copy of `A`'s direct contents, filtered to `type` when given. Iterating
/// it is exactly the old `for(var/type/X in A)` (DM copies contents for a
/// for-in anyway), and nothing breaks when the loop body moves things.
///
/// # Examples
///
/// ```
/// for(var/obj/item/I in contents_of(src))
/// var/list/obj/item/cell/cells = contents_of(holder, /obj/item/cell)
/// ```
/proc/contents_of(atom/A, type)
	RETURN_TYPE(/list)
	READS_FROM() // what a thing holds is asked when a choice is made, never cached
	if(!A)
		return list()
	if(!type)
		return A.contents.Copy()
	. = list()
	for(var/atom/X as anything in A.contents)
		if(istype(X, type))
			. += X

/// The first direct content of `A` that is a `type`, or null. Equivalent to
/// `locate(type) in A` (or `in A.contents`) for any atom, turf or not.
/proc/locate_within(atom/A, type)
	READS_FROM() // what a thing holds is asked when a choice is made, never cached
	if(!A)
		return null
	return locate(type) in A.contents

/// How many things `A` directly contains. Equivalent to `A.contents.len`.
/proc/contents_count(atom/A)
	return A ? length(A.contents) : 0

/// `locate(what) in L` over a plain list (a registry, a view() result, a
/// Topic() whitelist): `what` is a type, a ref string or an instance.
/// Returns null for a null list.
/proc/locate_in_list(list/L, what)
	if(!L)
		return null
	return locate(what) in L

/// Anchor an /image (not a movable: it has no ledger entry and no Move())
/// to `A`, or detach it with null. The one place an image's loc is written,
/// so the containment lint can ban raw `loc =` everywhere else.
/proc/image_anchor(image/I, atom/A)
	if(!I)
		return
	I.loc = A // ALLOW(containment): images are not movables; this is their only anchor
