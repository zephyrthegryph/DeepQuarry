/client/proc/admin_delete(datum/D, mob/actor)
	if(!GLOB.prompt_flow) // its questions re-run it (prompt_flow(), prompt_helpers.dm)
		return prompt_flow(src, PROC_REF(admin_delete), args)
	var/atom/A = D
	var/coords = ""
	var/jmp_coords = ""
	if(istype(A))
		var/turf/T = get_turf(A)
		if(T)
			var/atom/a_loc = A.loc
			var/is_turf = isturf(a_loc)
			coords = "[is_turf ? "at" : "from [a_loc] at"] [AREACOORD(T)]"
			jmp_coords = "[is_turf ? "at" : "from [a_loc] at"] [ADMIN_VERBOSEJMP(T)]"
		else
			jmp_coords = coords = "in nullspace"

	if (flow_ask(mob, "delete", /datum/prompt/choice, question = "Are you sure you want to delete:\n[D]\n[coords]?", title = "Confirmation", choices = list("Yes", "No"), buttons = TRUE) == "Yes")
		log_admin("[key_name(actor)] deleted [D] [coords]")
		message_admins("[key_name_admin(actor)] deleted [D] [jmp_coords]")
		feedback_add_details("admin_verb","ADEL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		if(isturf(D))
			var/turf/T = D
			T.ChangeTurf(world.turf)
		else
			vv_update_display(D, "deleted", VV_MSG_DELETED)
			spent(D, actor)
			if(!QDELETED(D))
				vv_update_display(D, "deleted", "")
