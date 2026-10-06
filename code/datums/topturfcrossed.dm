/// Forwards Crossed() from the topmost turf to a movable while it is inside
/// something (a bag, a mob), so it still reacts to things crossing where it is.
/// An owned plain datum: the owner holds it in a declared var and it goes with the owner.
/datum/topturfcrossed
	/// The movable we forward Crossed() to.
	var/atom/movable/owner
	var/turf/our_old_turf

/datum/topturfcrossed/New(atom/movable/new_owner)
	..()
	if(!ismovable(new_owner))
		log_runtime("TOPTURFCROSSED: attached to non-movable [new_owner] ([new_owner?.type])")
		return
	rel_set(src, nameof(owner), new_owner)
	dq_add_recursive_move(owner) // Required if we want to be useful at all
	observe(owner, /datum/notice/movable_attempted_move, src, then(PROC_REF(handle_location_change)))
	update_turf_hooks(get_turf(owner))

/datum/topturfcrossed/proc/handle_location_change(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/movable_attempted_move/event = A
	if(!owner)
		return
	update_turf_hooks(event.new_loc)

/// Updates the topmost turf we are hooked to when we are moved.
/datum/topturfcrossed/proc/update_turf_hooks(atom/new_loc)
	// Our turf is the exact same, don't change anything!
	if(new_loc && our_old_turf())
		var/turf/check_valid = isturf(new_loc) ? new_loc : get_turf(new_loc)
		if(check_valid == our_old_turf())
			return
	// Always remove the hook from our old turf when hooking the new one
	if(our_old_turf())
		unobserve(our_old_turf(), /datum/notice/observer_turf_entered, src)
		rel_clear(src, nameof(our_old_turf))
	// Only hook the turf if we are inside something, otherwise we'd get DOUBLECROSSED
	if(new_loc && !isturf(owner.loc))
		var/turf/find_new = isturf(new_loc) ? new_loc : get_turf(new_loc)
		if(find_new)
			observe(find_new, /datum/notice/observer_turf_entered, src, then(PROC_REF(handle_turf_entered)))
			rel_set(src, nameof(our_old_turf), find_new)

/// Forwards the Cross() call from the turf to the object hooked
/datum/topturfcrossed/proc/handle_turf_entered(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/observer_turf_entered/event = A
	var/atom/movable/crosser = event.arrived
	if(QDELETED(crosser) || QDELETED(owner))
		return
	if(isturf(owner.loc))
		return
	if(crosser == owner)
		return
	owner.Crossed(crosser)

/// The turf whose entries we watch (a relation view).
/datum/topturfcrossed/proc/our_old_turf() as /turf
	return our_old_turf


//the bikehorn of testing
/obj/item/bikehorn/topturf_testing
	name = "bikehorn of testing"
	desc = "honk if you're working correctly"
	var/tmp/datum/topturfcrossed/topturfcrossed


CAPABILITIES(/obj/item/bikehorn/topturf_testing)
	owns_one(nameof(topturfcrossed), starts = /datum/topturfcrossed)

/obj/item/bikehorn/topturf_testing/Crossed(atom/movable/AM)
	. = ..()
	to_chat(world, "[src] crossed by [AM], was inside [loc]")
