/client/proc/mark_datum(datum/D)
	if(!holder)
		return
	if(holder.marked_datum())
		vv_update_display(holder.marked_datum(), "marked", "")
	// An OM handle: it reads null once the marked datum is deleted, so no QDELETING registration.
	holder.marked_datum_handle = om_handle(D)
	vv_update_display(D, "marked", VV_MSG_MARKED)

ADMIN_VERB_ONLY_CONTEXT_MENU(mark_datum, R_HOLDER, "Mark Object", datum/target as mob|obj|turf|area in view())
	user.mark_datum(target)
