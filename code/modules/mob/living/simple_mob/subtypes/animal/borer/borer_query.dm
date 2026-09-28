/mob/living/simple_mob/animal/borer
	var/datum/ghost_query/ghost_check // Used to unregister our signal

/mob/living/simple_mob/animal/borer/proc/request_player()
	ghost_check = new /datum/ghost_query/borer()
	om_hook(ghost_check, /datum/om/event/ghost_query_complete, src, PROC_REF(get_winner))
	ghost_check.query() // This will sleep the proc for awhile.

/mob/living/simple_mob/animal/borer/proc/get_winner(datum/source, datum/om/event/ghost_query_complete/event)
	EVENT_HANDLER
	if(ghost_check && ghost_check.candidates.len) //ghost_check should NEVER get deleted but...whatever, sanity.
		var/mob/observer/dead/D = ghost_check.candidates[1]
		transfer_personality(D)
	om_unhook(ghost_check, /datum/om/event/ghost_query_complete, src)
	QDEL_NULL(ghost_check) //get rid of the query

DECLARE_REF(/mob/living/simple_mob/animal/borer, "ghost_check", OWNED, null)
