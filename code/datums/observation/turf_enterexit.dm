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
	// Only build the weakref when something listens: test and bench builds
	// evaluate signal arguments eagerly (SIGNAL_ARG_CHECKS), and every mapped
	// object entering its turf at init made one (65 k weakrefs, 3-7 s of REF()).
	if(_listen_lookup?[COMSIG_OBSERVER_TURF_ENTERED])
		SEND_SIGNAL(src, COMSIG_OBSERVER_TURF_ENTERED, WEAKREF(am), old_loc)

/turf/Exited(atom/movable/am, atom/new_loc)
	. = ..()
