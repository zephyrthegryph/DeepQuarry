//	Observer Pattern Implementation: Shuttle Added
//		Registration type: /datum/shuttle (register for the global event only)
//
//		Raised when: After a shuttle is initialized.
//
//		Arguments that the called proc should expect:
//			/datum/shuttle/shuttle: the new shuttle
//Deprecated in favor of comsigs

/*****************************
*  Shuttle Added Handling *
*****************************/

/datum/controller/subsystem/shuttles/initialize_shuttle()
	. = ..()
	if(.)
		OM_EMIT(SSshuttles, /datum/om/event/observer_shuttle_added, .)
