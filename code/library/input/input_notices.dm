// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// From base of atom/Click(): (atom/location, control, params, mob/user)
ACTION(click, location, control, params, user, FIXED, notice = /datum/notice/click)

/// From /mob/proc/base_click_alt(): `mob` alt-clicked the atom. A listener handles the click: when one listens, the atom's own click_alt() and the loot panel do not run.
ACTION(click_alt, mob, FIXED, notice = /datum/notice/click_alt)

/// From base of client/Click(): (atom/target, atom/location, control, params, mob/user)
ACTION(client_click, target_, location, control, params, user, FIXED, notice = /datum/notice/client_click)
