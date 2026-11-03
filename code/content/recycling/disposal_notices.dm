// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// Called when a disposal connected object attempts to link to a trunk: (/obj/structure/disposalpipe/trunk)
ACTION(disposal_link, trunk, FIXED, notice = /datum/notice/disposal_link)

/// Called when a disposal connected object recieves an object from it's connected trunk
ACTION(disposal_receive, items, gas, FIXED, notice = /datum/notice/disposal_receive)

/// Called when a disposal connected object should unlink from a trunk it's attached to.
ACTION(disposal_unlink, FIXED, notice = /datum/notice/disposal_unlink)
