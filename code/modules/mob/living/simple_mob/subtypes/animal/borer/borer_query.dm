/mob/living/simple_mob/animal/borer
	var/datum/ghost_query/ghost_check // Used to unregister our signal

CAPABILITIES(/mob/living/simple_mob/animal/borer)
	immune_to_incapacitation()
	after_init(0, then(PROC_REF(find_player)))
	owns_one(nameof(ghost_check), /datum/ghost_query)
	owns_one(nameof(host_brain), /mob/living/captive_brain)
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)

/mob/living/simple_mob/animal/borer/proc/request_player()
	rel_set(src, nameof(ghost_check), new /datum/ghost_query/borer())
	global.observe(ghost_check, /datum/notice/ghost_query_complete, src, then(PROC_REF(get_winner)))
	ghost_check.query() // This will sleep the proc for awhile.

/mob/living/simple_mob/animal/borer/proc/get_winner(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if(ghost_check && ghost_check.candidates.len) //ghost_check should NEVER get deleted but...whatever, sanity.
		var/mob/observer/dead/D = ghost_check.candidates[1]
		transfer_personality(D)
	unobserve(ghost_check, /datum/notice/ghost_query_complete, src)
	rel_clear(src, nameof(ghost_check)) //get rid of the query

