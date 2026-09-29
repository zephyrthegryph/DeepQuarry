/client/proc/mark_datum(datum/D)
	if(!holder)
		return
	if(holder.marked_datum())
		vv_update_display(holder.marked_datum(), "marked", "")
	// A relation view: it reads null once the marked datum is deleted, so no QDELETING registration.
	rel_set(holder, "marked_datum", D)
	vv_update_display(D, "marked", VV_MSG_MARKED)

ADMIN_VERB_ONLY_CONTEXT_MENU(mark_datum, R_HOLDER, "Mark Object", datum/target as mob|obj|turf|area in view())
	user.mark_datum(target)
