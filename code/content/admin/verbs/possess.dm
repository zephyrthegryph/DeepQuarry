/// The object an admin mob possesses, or null: a sparse link (LK_POSSESSING), not a var on /mob.
/proc/possessed_obj_of(mob/M) as /obj
	return link_get(M, LK_POSSESSING)

/// Possesses object O, or releases it with null.
/proc/set_possessed_obj(mob/M, obj/O)
	return link_set_one(M, LK_POSSESSING, O)

ADMIN_VERB_AND_CONTEXT_MENU(possess, R_POSSESS, "Possess Obj", "Possess an object.", ADMIN_CATEGORY_OBJECT, obj/O as obj in world)
	if(istype(O,/obj/singularity))
		if(CONFIG_GET(flag/forbid_singulo_possession))
			to_chat(user, "It is forbidden to possess singularities.")
			return

	var/turf/T = get_turf(O)

	if(T)
		log_admin("[key_name(user)] has possessed [O] ([O.type]) at ([T.x], [T.y], [T.z])")
		message_admins("[key_name(user)] has possessed [O] ([O.type]) at ([T.x], [T.y], [T.z])", 1)
	else
		log_admin("[key_name(user)] has possessed [O] ([O.type]) at an unknown location")
		message_admins("[key_name(user)] has possessed [O] ([O.type]) at an unknown location", 1)

	if(!possessed_obj_of(user.mob)) //If you're not already possessing something...
		sparse_set(user.mob, name_archive, user.mob.real_name)

	user.mob.forceMove(O)
	user.mob.set_real_name(O.name)
	user.mob.name = O.name
	user.eye = O
	set_possessed_obj(user.mob, O)
	feedback_add_details("admin_verb","PO") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(release, R_POSSESS, "Release Object", "Stop possessing an object.", ADMIN_CATEGORY_OBJECT, obj/O as obj in world)
	if(possessed_obj_of(user.mob) && sparse_get(user.mob, name_archive)) //if you have a name archived and if you are actually relassing an object
		user.mob.set_real_name(sparse_get(user.mob, name_archive))
		user.mob.name = user.mob.real_name
		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			H.name = H.get_visible_name()

	user.mob.forceMove(O.loc) // Appear where the object you were controlling is -- TLE
	user.eye = user
	set_possessed_obj(user.mob, null)
	feedback_add_details("admin_verb","RO") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
