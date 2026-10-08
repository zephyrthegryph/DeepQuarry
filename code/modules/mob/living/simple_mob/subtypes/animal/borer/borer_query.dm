/// The name of the borer's host var (the reverse-index key borer_of() reads).
#define BORER_HOST_VAR "borer_host_mob"

/mob/living/simple_mob/animal/borer
	var/datum/ghost_query/ghost_check // Used to unregister our signal
	/// The human this borer has infested (a reference, cleared when the host is deleted). Read with borer_host().
	var/mob/living/carbon/human/borer_host_mob

CAPABILITIES(/mob/living/simple_mob/animal/borer)
	ref_one(nameof(borer_host_mob), /mob/living/carbon/human, on_unlink = PROC_REF(host_lost))
	immune_to_incapacitation()
	after_init(0, then(PROC_REF(find_player)))
	owns_one(nameof(ghost_check), /datum/ghost_query)
	owns_one(nameof(host_brain), /mob/living/captive_brain)
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)

/// The human this borer has infested, or null.
/mob/living/simple_mob/animal/borer/proc/borer_host() as /mob/living/carbon/human
	return borer_host_mob

/// The borer infesting this human, or null.
/mob/living/carbon/human/proc/borer_of() as /mob/living/simple_mob/animal/borer
	var/list/borers = rel_sources_via(src, BORER_HOST_VAR)
	return length(borers) ? borers[1] : null

/// The borer infests `new_host`: linked, and listed in the head organ's implants so every teardown path agrees (detatch(), leave_host(), the organ
/// being removed, either end deleted).
/mob/living/simple_mob/animal/borer/proc/take_host(mob/living/carbon/human/new_host)
	rel_set(src, nameof(borer_host_mob), new_host)
	if(borer_host_mob != new_host)
		return FALSE
	var/obj/item/organ/external/head = new_host.get_organ(BP_HEAD)
	if(head)
		rel_add(head, nameof(head.implants), src)
	return TRUE

/// The host link went (the borer left, or the host was deleted): the borer leaves the head's implants.
/mob/living/simple_mob/animal/borer/proc/host_lost(mob/living/carbon/human/old_host)
	var/obj/item/organ/external/head = old_host.get_organ(BP_HEAD)
	if(head)
		rel_remove(head, nameof(head.implants), src)

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

