// Orbiting: one atom circling another (ghost follow, tesla miniballs, admin
// orbit, the toilet gag). Replaces the old orbiter component: the orbit IS an
// edge of /datum/om/relation/orbiting (orbiter -> center), read through
// ORBIT_TARGET()/ORBITERS() (om.dm). Nothing about it is stored on either
// atom; the orbiter's pre-orbit transform rides on the edge's `data`.
//
// The relation singleton is also the movement listener: it watches the
// orbiters, the centers and whatever holds a center (a bag, a mob), and
// keeps every orbiter on its center's turf.

/datum/om/relation/orbiting
	name = "orbit"
	source_single = TRUE

/datum/om/relation/orbiting/on_link(atom/movable/source, atom/target, datum/om/edge/edge)
	if(!istype(source) || !istype(target))
		return
	watch(source)
	if(ismovable(target))
		watch(target)
		watch_holders(target)

/datum/om/relation/orbiting/on_unlink(atom/movable/source, atom/target, datum/om/edge/edge)
	if(istype(source) && !QDELETED(source))
		source.SpinAnimation(0, 0)
		var/matrix/saved = edge.data?["transform"]
		if(istype(saved))
			source.transform = saved
	if(istype(source))
		source.orbit_ended(target)
	maybe_unwatch(source)
	if(ismovable(target))
		maybe_unwatch(target)

/datum/om/relation/orbiting/proc/watch(atom/movable/AM)
	if(!QDELETED(AM))
		observe(AM, /datum/notice/moved, src, then(PROC_REF(on_moved)))

/datum/om/relation/orbiting/proc/watch_holders(atom/movable/center)
	var/atom/movable/holder = center.loc
	var/depth = 0
	while(ismovable(holder) && depth++ < 16)
		watch(holder)
		holder = holder.loc

/// Stops listening to `AM` once it neither orbits nor is orbited. Holders are
/// dropped lazily, the next time they move with no center inside.
/datum/om/relation/orbiting/proc/maybe_unwatch(atom/movable/AM)
	if(QDELETED(AM))
		return
	if(AM?.orbit_target() || LAZYLEN(AM?.orbiter_list()))
		return
	unobserve(AM, /datum/notice/moved, src)

/datum/om/relation/orbiting/proc/on_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/movable/mover = A.target
	var/involved = FALSE
	// An orbiter that left its center's turf stops orbiting.
	var/atom/center = mover?.orbit_target()
	if(center)
		involved = TRUE
		if(mover.loc != get_turf(center))
			om_unlink(mover, center, /datum/om/relation/orbiting)
	// A center (or something holding one) moved: bring its orbiters along.
	if(LAZYLEN(mover?.orbiter_list()))
		involved = TRUE
		follow(mover)
	for(var/atom/movable/inner in mover.get_all_contents())
		if(inner != mover && LAZYLEN(inner?.orbiter_list()))
			involved = TRUE
			follow(inner)
	if(!involved)
		unobserve(mover, /datum/notice/moved, src)

/datum/om/relation/orbiting/proc/follow(atom/movable/center)
	var/turf/T = get_turf(center)
	for(var/atom/movable/orbiter as anything in center?.orbiter_list())
		if(!T)
			om_unlink(orbiter, center, /datum/om/relation/orbiting)
			continue
		if(!QDELETED(orbiter) && orbiter.loc != T)
			orbiter.forceMove(T, movetime = MOVE_GLIDE_CALC(center.glide_size, 0))
	if(T)
		watch_holders(center)

// ---------------------------------------------------------------- atom API

//radius: range to orbit at, radius of the circle formed by orbiting (in pixels)
//clockwise: whether you orbit clockwise or anti clockwise
//rotation_speed: how fast to rotate (how many ds should it take for a rotation to complete)
//rotation_segments: the resolution of the orbit circle, less = a more block circle, this can be used to produce hexagons (6 segments) triangles (3 segments), and so on, 36 is the best default.
//pre_rotation: Chooses to rotate src 90 degress towards the orbit dir (clockwise/anticlockwise), useful for things to go "head first" like ghosts
/atom/movable/proc/orbit(atom/A, radius = 10, clockwise = FALSE, rotation_speed = 20, rotation_segments = 36, pre_rotation = TRUE)
	if(!istype(A) || !get_turf(A) || A == src)
		return
	// Re-orbiting the same center restarts it with the new parameters.
	stop_orbit()
	var/datum/om/edge/edge = om_link(src, A, /datum/om/relation/orbiting)
	if(!istype(edge))
		return
	edge.data = list("transform" = matrix(transform))

	// Head first!
	if(pre_rotation)
		var/matrix/M = matrix(transform)
		M.Turn(clockwise ? 90 : -90)
		transform = M

	var/matrix/shift = matrix(transform)
	shift.Translate(0, radius)
	transform = shift

	SpinAnimation(rotation_speed, -1, clockwise, rotation_segments)

	forceMove(get_turf(A))
	to_chat(src, span_notice("Now orbiting [A]."))
	return edge

/// Ends this atom's orbit, if any.
/atom/movable/proc/stop_orbit()
	var/atom/center = src?.orbit_target()
	if(center)
		om_unlink(src, center, /datum/om/relation/orbiting)

/// Hook: this atom's orbit around `center` just ended (the edge is gone).
/atom/movable/proc/orbit_ended(atom/center)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// Ends every orbit around this atom.
/atom/movable/proc/stop_orbiters()
	for(var/atom/movable/orbiter as anything in orbiter_list())
		om_unlink(orbiter, src, /datum/om/relation/orbiting)
