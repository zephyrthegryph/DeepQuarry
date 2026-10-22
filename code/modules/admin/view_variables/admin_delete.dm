/// Asks for a confirmation, then deletes `D`. `view_turf`: a deleted turf's replacement is opened in View Variables afterwards.
/client/proc/admin_delete(datum/D, mob/actor, view_turf = FALSE)
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

	ask_admin(/datum/ask_sequence/admin, D, list(
		question_step("confirm", /datum/prompt/choice, question = "Are you sure you want to delete:\n[D]\n[coords]?", title = "Confirmation", choices = list("Yes", "No"), buttons = TRUE)),
		PROC_REF(admin_delete_answered), null, list("coords" = coords, "jmp_coords" = jmp_coords, "view_turf" = view_turf))

/client/proc/admin_delete_answered(datum/ask_sequence/admin/asked)
	var/datum/D = asked.subject()
	if(!D)
		return
	var/mob/actor = asked.actor()
	if(asked.get("confirm") == "Yes")
		log_admin("[key_name(actor)] deleted [D] [asked.kept["coords"]]")
		message_admins("[key_name_admin(actor)] deleted [D] [asked.kept["jmp_coords"]]")
		feedback_add_details("admin_verb","ADEL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		if(isturf(D))
			var/turf/T = D
			T.ChangeTurf(world.turf)
		else
			vv_update_display(D, "deleted", VV_MSG_DELETED)
			spent(D, actor)
			if(!QDELETED(D))
				vv_update_display(D, "deleted", "")
	if(asked.kept["view_turf"] && isturf(D)) // show the turf that took its place
		debug_variables(D)
