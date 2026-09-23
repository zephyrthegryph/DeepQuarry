//	Observer Pattern Implementation: Moved
//		Registration type: /atom/movable
//
//		Raised when: An /atom/movable instance has moved using Move() or forceMove().
//
//		Arguments that the called proc should expect:
//			/atom/movable/moving_instance: The instance that moved
//			/atom/old_loc: The loc before the move.
//			/atom/new_loc: The loc after the move.

//Deprecated in favor of comsigs

/********************
* Movement Handling *
********************/
// Entered() typically lifts the moved event, but in the case of null-space we'll have to handle it.
/atom/movable/Move()
	var/old_loc = loc
	. = ..()
	if(. && !loc)
		SEND_SIGNAL(src,COMSIG_MOVABLE_ATTEMPTED_MOVE, old_loc, null)

/atom/movable/forceMove(atom/destination, direction, movetime) // pass movetime through
	var/old_loc = loc
	. = ..()
	if(. && !loc)
		SEND_SIGNAL(src,COMSIG_MOVABLE_ATTEMPTED_MOVE, old_loc, null)
