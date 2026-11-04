// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// Signal that gets sent when a ghost query is completed
ACTION(ghost_query_complete, FIXED, notice = /datum/notice/ghost_query_complete)
