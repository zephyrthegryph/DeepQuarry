// Orbiting: one atom circling another (ghost follow, tesla miniballs, admin
// orbit, the toilet gag). The orbit IS a sparse declared link (links() in
// CAPABILITIES(/atom/movable), code/engine/declare/link_state.dm): LK_ORBITING on
// the orbiter, LK_ORBITERS on the centre, which may be any atom (a turf too).
// Nothing about it is stored on either atom; the orbiter's pre-orbit transform
// rides on the link (link_data_set).
//
// One listener, /datum/orbit_watcher, watches the move notices of the orbiters,
// the centres and whatever holds a centre (a bag, a mob), and keeps every
// orbiter on its centre's turf.

/datum/orbit_watcher

GLOBAL_DATUM_INIT(orbit_watcher, /datum/orbit_watcher, new)

/datum/orbit_watcher/proc/watch(atom/movable/AM)
	if(!QDELETED(AM))
		observe(AM, /datum/notice/moved, src, then(PROC_REF(on_moved)))

/datum/orbit_watcher/proc/watch_holders(atom/movable/center)
	var/atom/movable/holder = center.loc
	var/depth = 0
	while(ismovable(holder) && depth++ < 16)
		watch(holder)
		holder = holder.loc

/// Stops listening to `AM` once it neither orbits nor is orbited. Holders are
/// dropped lazily, the next time they move with no centre inside.
/datum/orbit_watcher/proc/maybe_unwatch(atom/movable/AM)
	if(QDELETED(AM))
		return
	if(AM?.orbit_target() || LAZYLEN(AM?.orbiter_list()))
		return
	unobserve(AM, /datum/notice/moved, src)

/datum/orbit_watcher/proc/on_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/movable/mover = A.target
	var/involved = FALSE
	// An orbiter that left its centre's turf stops orbiting.
	var/atom/center = mover?.orbit_target()
	if(center)
		involved = TRUE
		if(mover.loc != get_turf(center))
			link_break(mover, LK_ORBITING, center)
	// A centre (or something holding one) moved: bring its orbiters along.
	if(LAZYLEN(mover?.orbiter_list()))
		involved = TRUE
		follow(mover)
	for(var/atom/movable/inner in mover.get_all_contents())
		if(inner != mover && LAZYLEN(inner?.orbiter_list()))
			involved = TRUE
			follow(inner)
	if(!involved)
		unobserve(mover, /datum/notice/moved, src)

/datum/orbit_watcher/proc/follow(atom/movable/center)
	var/turf/T = get_turf(center)
	for(var/atom/movable/orbiter as anything in center?.orbiter_list())
		if(!T)
			link_break(orbiter, LK_ORBITING, center)
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
	if(!link_make(src, LK_ORBITING, A))
		return
	link_data_set(src, LK_ORBITING, "transform", matrix(transform))
	GLOB.orbit_watcher.watch(src)
	if(ismovable(A))
		var/atom/movable/center = A
		GLOB.orbit_watcher.watch(center)
		GLOB.orbit_watcher.watch_holders(center)

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
	return TRUE

/// Ends this atom's orbit, if any.
/atom/movable/proc/stop_orbit()
	var/atom/center = src?.orbit_target()
	if(center)
		link_break(src, LK_ORBITING, center)

/// The orbit link broke (its a_on_unlink hook): the spin stops, the transform it saved comes back and the watcher lets go of what no longer orbits.
/atom/movable/proc/orbit_released(atom/center)
	SpinAnimation(0, 0)
	var/matrix/saved = link_data_get(src, LK_ORBITING, "transform")
	if(istype(saved))
		transform = saved
	orbit_ended(center)
	GLOB.orbit_watcher.maybe_unwatch(src)
	if(ismovable(center))
		GLOB.orbit_watcher.maybe_unwatch(center)

/// Hook: this atom's orbit around `center` just ended (the link is gone).
/atom/movable/proc/orbit_ended(atom/center)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// Ends every orbit around this atom.
/atom/movable/proc/stop_orbiters()
	for(var/atom/movable/orbiter as anything in orbiter_list())
		link_break(orbiter, LK_ORBITING, src)
