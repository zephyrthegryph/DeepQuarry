/client/proc/mark_datum(datum/D)
	holder?.mark_datum_for(D)

/// `D` becomes this admin's marked datum; the one marked before loses its VV marker.
/datum/admins/proc/mark_datum_for(datum/D)
	if(marked_datum())
		owner()?.vv_update_display(marked_datum(), "marked", "")
	// A relation view: it reads null once the marked datum is deleted, so no QDELETING registration.
	rel_set(src, nameof(marked_datum), D)
	owner()?.vv_update_display(D, "marked", VV_MSG_MARKED)

ADMIN_VERB_ONLY_CONTEXT_MENU(mark_datum, R_HOLDER, "Mark Object", datum/target as mob|obj|turf|area in view())
	user.mark_datum(target)
