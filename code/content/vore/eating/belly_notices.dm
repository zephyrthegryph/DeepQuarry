// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// From /obj/belly/HandleBellyReagents() and /obj/belly/update_internal_overlay()
ACTION(belly_update_vore_fx, volume, FIXED, notice = /datum/notice/belly_update_vore_fx)
