#define MAX_THROWING_DIST 1280 // 5 z-levels on default width
#define MAX_TICKS_TO_MAKE_UP 3 //how many missed ticks will we attempt to make up for this run.

// A throw in flight (fold wave F3; SSthrowing is gone). Each /datum/thrownthing runs on the
// continuous throwing lane (PERIODIC_THROWING, code/datums/om/periodic.dm): throw_at() starts it,
// periodic_step() moves it once per server tick, and it parks when it lands (finalize() deletes it).

/// A throw in flight -> the movable being thrown (which holds it as `throwing`). Read with
/// throw_subject(). Deleting the movable deletes the throw; the unlink clears its `throwing`.
/datum/om/relation/throw_of
	name = "throw"
	source_single = TRUE
	target_single = TRUE
	on_target_delete = OM_END_DELETE_OTHER

/datum/om/relation/throw_of/on_unlink(datum/thrownthing/source, atom/movable/target, datum/om/edge/edge)
	om_unhook(target, /datum/om/event/before/living_turf_collision, source)
	if(target.throwing == source)
		rel_clear(target, "throwing")

/datum/thrownthing
	///OM handle to the original intended target of the throw, to prevent hardDels
	var/initial_target
	///OM handle to the turf that the target was on, if it's not a turf itself.
	var/target_turf
	///OM handle to the turf that we were thrown from.
	var/starting_turf
	///If the target happens to be a carbon and that carbon has a body zone aimed at, this is carried on here.
	var/target_zone
	///The initial direction of the thrower of the thrownthing for building the trajectory of the throw.
	var/init_dir
	///The maximum number of turfs that the thrownthing will travel to reach its target.
	var/maxrange
	///Turfs to travel per tick
	var/speed
	///If a mob is the one who has thrown the object, then it's moved here. This can be null and must be null checked before trying to use it.
	var/thrower
	///A variable that helps in describing objects thrown at an angle, if it should be moved diagonally first or last.
	var/diagonals_first
	///Set to TRUE if the throw is exclusively diagonal (45 Degree angle throws for example)
	var/pure_diagonal
	///Tracks how far a thrownthing has traveled mid-throw for the purposes of maxrange
	var/dist_travelled = 0
	///The start_time obtained via world.time for the purposes of tiles moved/tick.
	var/start_time
	///Distance to travel in the X axis/direction.
	var/dist_x
	///Distance to travel in the y axis/direction.
	var/dist_y
	///The Horizontal direction we're traveling (EAST or WEST)
	var/dx
	///The VERTICAL direction we're traveling (NORTH or SOUTH)
	var/dy
	///The movement force provided to a given object in transit. More info on these in move_force.dm
	var/force = 1
	///If the throw is gentle, then the thrownthing is harmless on impact.
	var/gentle = FALSE
	///How many tiles that need to be moved in order to travel to the target.
	var/diagonal_error
	///If a thrown thing has a callback, it can be invoked here within thrownthing. Owned: it goes with the throw.
	var/datum/callback/callback
	///Mainly exists for things that would freeze a thrown object in place, like a timestop'd tile. Or a Tractor Beam.
	var/paused = FALSE
	///How long an object has been paused for, to be added to the travel time.
	var/delayed_time = 0
	///The last world.time value stored when the thrownthing was moving.
	var/last_move = 0
	/// If our thrownthing has been blocked
	var/blocked = FALSE

/datum/thrownthing/New(atom/movable/thrownthing, atom/target, init_dir, maxrange, speed, mob/thrower, diagonals_first, force, gentle, callback, target_zone)
	. = ..()
	om_link(src, thrownthing, /datum/om/relation/throw_of)
	om_hook(thrownthing, /datum/om/event/before/living_turf_collision, src, PROC_REF(hit_atom))
	src.starting_turf = om_handle(get_turf(thrownthing))
	var/turf/target_turf = get_turf(target)
	src.target_turf = om_handle(target_turf)
	if(target_turf != target)
		src.initial_target = om_handle(target)
	src.init_dir = init_dir
	src.maxrange = maxrange
	src.speed = speed
	if(thrower)
		src.thrower = om_handle(thrower)
	src.diagonals_first = diagonals_first
	src.force = force
	src.gentle = gentle
	own_set(src, "callback", callback)
	src.target_zone = target_zone
	if(!QDELETED(thrower) && ismob(thrower))
		src.target_zone = thrower.zone_sel ? thrower.zone_sel.selecting : null

	dist_x = abs(target.x - thrownthing.x)
	dist_y = abs(target.y - thrownthing.y)
	dx = (target.x > thrownthing.x) ? EAST : WEST
	dy = (target.y > thrownthing.y) ? NORTH : SOUTH//same up to here

	if (dist_x == dist_y)
		pure_diagonal = TRUE

	else if(dist_x <= dist_y)
		var/olddist_x = dist_x
		var/olddx = dx
		dist_x = dist_y
		dist_y = olddist_x
		dx = dy
		dy = olddx

	diagonal_error = dist_x/2 - dist_y

	start_time = world.time


/// Phase 2: the throw leaves the throwing lane (the throw_of unlink clears the movable's `throwing`).
/datum/thrownthing/lifecycle_dematerialize()
	. = ..()
	om_task_periodic_stop(src)

/// One server tick of flight on the throwing lane (was SSthrowing.fire()).
/datum/thrownthing/periodic_step(delta)
	if(QDELETED(src) || QDELETED(throw_subject()))
		return PROCESS_KILL
	tick()
	if(QDELETED(src))
		return PROCESS_KILL

/// Returns the thrower, or null
/datum/thrownthing/proc/get_thrower()
	. = om_resolve(thrower)
	if(isnull(.))
		thrower = null

/datum/thrownthing/proc/tick()
	var/atom/movable/AM = throw_subject()
	if (!AM || !isturf(AM.loc) || !AM.throwing)
		finalize()
		return

	if(paused)
		delayed_time += world.time - last_move
		return

	if (dist_travelled && hitcheck(get_turf(AM))) //to catch sneaky things moving on our tile while we slept
		finalize()
		return

	var/area/A = get_area(AM.loc)
	var/atom/step

	last_move = world.time

	//calculate how many tiles to move, making up for any missed ticks.
	var/turf/target_turf = om_resolve(src.target_turf)
	var/tilestomove = CEILING(min(((((world.time+world.tick_lag) - start_time + delayed_time) * speed) - (dist_travelled ? dist_travelled : -1)), speed*MAX_TICKS_TO_MAKE_UP) * world.tick_lag, 1) // one lane step per server tick (SSthrowing.wait was 1 tick)
	while (tilestomove-- > 0)
		if ((dist_travelled >= maxrange || AM.loc == target_turf) && (A && A.get_gravity()))
			finalize()
			return

		if (dist_travelled <= max(dist_x, dist_y)) //if we haven't reached the target yet we home in on it, otherwise we use the initial direction
			step = get_step(AM, get_dir(AM, target_turf))
		else
			step = get_step(AM, init_dir)

		if (!pure_diagonal) // not a purely diagonal trajectory and we don't want all diagonal moves to be done first
			if (diagonal_error >= 0 && max(dist_x,dist_y) - dist_travelled != 1) //we do a step forward unless we're right before the target
				step = get_step(AM, dx)
			diagonal_error += (diagonal_error < 0) ? dist_x/2 : -dist_y

		if (!step) // going off the edge of the map makes get_step return null, don't let things go off the edge
			finalize()
			return

		if (hitcheck(step))
			finalize()
			return

		AM.Move(step, get_dir(AM, step))

		if (!AM)		// Us moving somehow destroyed us?
			return

		if (!AM.throwing) // we hit something during our move
			finalize(hit = TRUE)
			return

		dist_travelled++

		if (dist_travelled > MAX_THROWING_DIST)
			finalize()
			return

		A = get_area(AM.loc)

/datum/thrownthing/proc/finalize(hit = FALSE, t_target=null)
	//done throwing, either because it hit something or it finished moving
	var/atom/movable/thrownthing = throw_subject()
	if(QDELETED(thrownthing))
		return
	rel_clear(thrownthing, "throwing")
	if (!hit)
		var/atom/movable/actual_target = om_resolve(initial_target)
		for (var/thing in get_turf(thrownthing)) //looking for our target on the turf we land on.
			var/atom/A = thing
			if (A == actual_target)
				hit = TRUE
				thrownthing.throw_impact(A, src)
				break
		if (!hit)
			thrownthing.throw_impact(get_turf(thrownthing), src)  // we haven't hit something yet and we still must, let's hit the ground.

	if(ismob(thrownthing))
		var/mob/M = thrownthing
		M.inertia_dir = init_dir

	if(t_target && !QDELETED(thrownthing))
		thrownthing.throw_impact(t_target, src)

	if (callback)
		callback.Invoke()

	if (!QDELETED(thrownthing))
		thrownthing.fall()

	qdel(src)

/datum/thrownthing/proc/hit_atom(datum/source, datum/om/event/before/living_turf_collision/event)
	EVENT_HANDLER
	var/atom/A = source
	finalize(hit=TRUE, t_target=A)

/datum/thrownthing/proc/hitcheck(turf/T)
	var/atom/movable/hit_thing
	var/atom/movable/thrownthing = throw_subject()
	var/mob/thrower = get_thrower()
	for (var/thing in contents_of(T))
		var/atom/movable/AM = thing
		if (AM == thrownthing || (AM == thrower && !ismob(thrownthing)))
			continue
		if (!AM.density || AM.throwpass)//check if ATOM_FLAG_CHECKS_BORDER as an atom_flag is needed
			continue
		if (!hit_thing || AM.layer > hit_thing.layer)
			hit_thing = AM

	if(hit_thing)
		finalize(hit=TRUE, t_target=hit_thing)
		return TRUE

#undef MAX_THROWING_DIST
#undef MAX_TICKS_TO_MAKE_UP

/// LC-refs: throw source -- an OM handle (om_handle()); a global helper keeps the proc off the base type.
/proc/movable_throw_source(atom/movable/AM) as /turf
	return AM?.throw_source
