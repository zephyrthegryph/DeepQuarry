// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// A closet or crate closed (published by /obj/structure/closet/close()).
ACTION(closet_closed, FIXED, notice = /datum/notice/closet_closed)
