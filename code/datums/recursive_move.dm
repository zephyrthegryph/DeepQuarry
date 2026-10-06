/**
 * Recursive move relay
 * Attach with dq_add_recursive_move(AM) to anything where /datum/om/event/movable_attempted_move
 * should also be emitted when a container it is inside (at any depth) moves.
 * Previously there was a system where moves were always recursively propagated, but that was unnecessary bloat.
 *
 * An owned plain datum held in /atom/movable/var/recursive_move (deleted with its holder).
 * Adding it again to a movable that already has one just rebuilds the container chain.
 */
/datum/recursive_move
	/// The movable we relay container moves to.
	var/atom/movable/holder
	var/list/parents
	var/noparents = FALSE

/atom/movable
	/// The recursive move relay (dq_add_recursive_move()), or null.
	var/tmp/datum/recursive_move/recursive_move


/// Gives `AM` a recursive move relay, or rebuilds the container chain of the one it has.
/proc/dq_add_recursive_move(atom/movable/AM)
	if(!istype(AM) || QDELETED(AM))
		return null
	if(AM.recursive_move)
		AM.recursive_move.reset_parents()
		AM.recursive_move.setup_parents()
		return AM.recursive_move
	rel_set(AM, nameof(AM.recursive_move), new /datum/recursive_move(AM))
	return AM.recursive_move

/datum/recursive_move/New(atom/movable/new_holder)
	..()
	rel_set(src, nameof(holder), new_holder)
	after(src, 0, PROC_REF(setup_parents)) // Delayed action if our holder is spawned in nullspace and then loc = target, hopefully this catches it. VV Add item does this, for example.

/datum/recursive_move/proc/setup_parents()
	if(QDELETED(src) || QDELETED(holder))
		return
	if(length(parents)) // safety check just incase this was called without clearing
		reset_parents()
	var/atom/movable/cur_parent = holder.loc // first loc could be null
	var/recursion = 0 // safety check - max iterations
	while(istype(cur_parent) && (recursion < 64))
		if(cur_parent == cur_parent.loc) //safety check incase a thing is somehow inside itself, cancel
			log_runtime("RECURSIVE_MOVE: Parent is inside itself. ([holder]) ([holder.type])")
			reset_parents()
			break
		if(cur_parent in parents) //safety check incase of circular contents. (A inside B, B inside C, C inside A), cancel
			log_runtime("RECURSIVE_MOVE: Parent is inside a circular inventory. ([holder]) ([holder.type])")
			reset_parents()
			break
		recursion++
		rel_add(src, nameof(parents), cur_parent)
		observe(cur_parent, /datum/notice/atom_exited, src, then(PROC_REF(on_parent_exited)))
		observe(cur_parent, /datum/notice/qdeleting, src, then(PROC_REF(on_qdel)))
		// Because the turf is not considered to be in the heirarchy by the relay, picking
		// up a bag with an recursive item inside it will not rebuild the heirarchy when it
		// enters the mob unless we fire this. Can't use pickup event as it happens too early...
		observe(cur_parent, /datum/notice/item_equipped, src, then(PROC_REF(on_parent_equipped)))
		cur_parent = cur_parent.loc

	if(recursion >= 64) // If we escaped due to iteration limit, cancel
		log_runtime("RECURSIVE_MOVE: Parent hit recursion limit. ([holder]) ([holder.type])")
		reset_parents()
		rel_clear(src, nameof(parents))

	if(length(parents))
		//Only need to watch top parent for movement. Everything is covered by Exited
		observe(parents[length(parents)], /datum/notice/atom_entering, src, then(PROC_REF(top_moved)))

	//If we have no parents of type atom/movable then we wait to see if that changes, checking every time our holder moves.
	if(!length(parents) && !noparents)
		noparents = TRUE
		observe(holder, /datum/notice/atom_entering, src, then(PROC_REF(on_holder_entering)))

	if(length(parents) && noparents)
		noparents = FALSE
		unobserve(holder, /datum/notice/atom_entering, src)

/datum/recursive_move/proc/on_holder_entering(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	setup_parents()

/datum/recursive_move/proc/unregister_hooks()
	if(noparents) // safety check
		noparents = FALSE
		if(holder)
			unobserve(holder, /datum/notice/atom_entering, src)
	if(!length(parents))
		return
	for(var/atom/movable/cur_parent in parents)
		unobserve(cur_parent, /datum/notice/qdeleting, src)
		unobserve(cur_parent, /datum/notice/atom_exited, src)
		unobserve(cur_parent, /datum/notice/item_equipped, src)

	if(length(parents))
		unobserve(parents[length(parents)], /datum/notice/atom_entering, src)

//Parent at top of heirarchy moved.
/datum/recursive_move/proc/top_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/atom_entering/event = A
	PUBLISH_LEGACY(holder, /datum/notice/movable_attempted_move, event.old_loc, event.destination)

//One of the parents other than the top parent moved.
/datum/recursive_move/proc/on_parent_exited(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/old_loc = A.target
	var/datum/notice/atom_exited/event = A
	heirarchy_changed(old_loc, event.new_loc)

/datum/recursive_move/proc/on_parent_equipped(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/old_loc = A.target
	var/datum/notice/item_equipped/event = A
	// As before: the equip signal's second argument (the slot) stood in for the new loc.
	heirarchy_changed(old_loc, event.slot)

/datum/recursive_move/proc/heirarchy_changed(atom/old_loc, atom/new_loc)
	PUBLISH_LEGACY(holder, /datum/notice/movable_attempted_move, old_loc, new_loc)
	//Rebuild our list of parents
	reset_parents()
	setup_parents()

//Some things will move their contents on qdel so we should prepare ourselves to be moved.
//If this qdel does destroy our holder, the holder deletes us (we are owned).
/datum/recursive_move/proc/on_qdel(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	reset_parents()
	noparents = TRUE
	if(holder)
		observe(holder, /datum/notice/atom_entering, src, then(PROC_REF(on_holder_entering)))

/datum/recursive_move/proc/reset_parents()
	unregister_hooks()
	rel_clear(src, nameof(parents))

//the banana peel of testing stays
/obj/item/bananapeel/test
	name = "banana peel of testing"
	desc = "spams world log with debugging information"

/obj/item/bananapeel/test/proc/shmove(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/source = A.target
	var/datum/notice/movable_attempted_move/event = A
	var/atom/old_loc = event.old_loc
	var/atom/new_loc = event.new_loc
	world.log << "the [source] moved from [old_loc]([old_loc.x],[old_loc.y],[old_loc.z]) to [new_loc]([new_loc.x],[new_loc.y],[new_loc.z])"

/obj/item/bananapeel/test/Initialize(mapload)
	. = ..()
	dq_add_recursive_move(src)
	observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(shmove)))
