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

/turf/Entered(atom/movable/am, atom/old_loc)
	. = ..()
	SEND_SIGNAL(src, COMSIG_OBSERVER_TURF_ENTERED, WEAKREF(am), old_loc)

/turf/Exited(atom/movable/am, atom/new_loc)
	. = ..()
