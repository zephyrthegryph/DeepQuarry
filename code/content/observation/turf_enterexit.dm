//	Observer Pattern Implementation: Turf Entered/Exited
//		Registration type: /turf
//
//		Raised when: A /turf has a new item in contents, or an item has left it's contents
//
//		Arguments that the called proc should expect:
//			/turf: The turf that was entered/exited
//			/atom/movable/moving_instance: The instance that entered/exited
// 			/atom/old_loc / /atom/new_loc: The previous/new loc of the mover

//Deprecated in favor of Comsigs

/********************
* Movement Handling *
********************/

/// A thing entered this turf: arrived, from old_loc.
ACTION(observer_turf_entered, atom/movable/arrived, atom/old_loc, FIXED, notice = /datum/notice/observer_turf_entered)

/turf/Entered(atom/movable/am, atom/old_loc)
	. = ..()
	// WANTS first: PUBLISH evaluates its arguments, and every mapped object entering its turf at init would otherwise call it.
	if(WANTS(src, /datum/notice/observer_turf_entered))
		PUBLISH(src, observer_turf_entered, arrived = am, old_loc = old_loc)

/turf/Exited(atom/movable/am, atom/new_loc)
	. = ..()
