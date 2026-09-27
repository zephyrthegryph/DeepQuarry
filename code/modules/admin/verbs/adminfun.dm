ADMIN_VERB(admin_explosion, R_ADMIN|R_FUN, "Explosion", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, atom/orignator as obj|mob|turf)
	var/devastation = verb_prompt(user, "a1", list("kind" = "number", "message" = "Range of total devastation. -1 to none", "title" = text("Input"), "min" = -1), args)
	if(isnull(devastation))
		return
	if(devastation == null)
		return
	var/heavy = verb_prompt(user, "a2", list("kind" = "number", "message" = "Range of heavy impact. -1 to none", "title" = text("Input"), "min" = -1), args)
	if(isnull(heavy))
		return
	if(heavy == null)
		return
	var/light = verb_prompt(user, "a3", list("kind" = "number", "message" = "Range of light impact. -1 to none", "title" = text("Input"), "min" = -1), args)
	if(isnull(light))
		return
	if(light == null)
		return
	var/flash = verb_prompt(user, "a4", list("kind" = "number", "message" = "Range of flash. -1 to none", "title" = text("Input"), "min" = -1), args)
	if(isnull(flash))
		return
	if(flash == null)
		return

	if ((devastation != -1) || (heavy != -1) || (light != -1) || (flash != -1))
		if ((devastation > 20) || (heavy > 20) || (light > 20))
			var/_answer_a5 = verb_prompt(user, "a5", list("message" = "Are you sure you want to do this? It will laaag.", "title" = "Confirmation", "choices" = list("Yes", "No")), args)
			if(isnull(_answer_a5))
				return
			if (_answer_a5 != "Yes")
				return

		explosion(orignator, devastation, heavy, light, flash)
		log_admin("[key_name(user)] created an explosion ([devastation],[heavy],[light],[flash]) at ([orignator.x],[orignator.y],[orignator.z])")
		message_admins("[key_name_admin(user)] created an explosion ([devastation],[heavy],[light],[flash]) at ([orignator.x],[orignator.y],[orignator.z])", 1)
		feedback_add_details("admin_verb","EXPL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(admin_emp, R_ADMIN|R_FUN, "EM Pulse", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, atom/orignator as obj|mob|turf)
	var/heavy = verb_prompt(user, "a6", list("kind" = "number", "message" = "Range of heavy pulse.", "title" = text("Input")), args)
	if(isnull(heavy))
		return
	if(heavy == null)
		return
	var/med = verb_prompt(user, "a7", list("kind" = "number", "message" = "Range of medium pulse.", "title" = text("Input")), args)
	if(isnull(med))
		return
	if(med == null)
		return
	var/light = verb_prompt(user, "a8", list("kind" = "number", "message" = "Range of light pulse.", "title" = text("Input")), args)
	if(isnull(light))
		return
	if(light == null)
		return
	var/long = verb_prompt(user, "a9", list("kind" = "number", "message" = "Range of long pulse.", "title" = text("Input")), args)
	if(isnull(long))
		return
	if(long == null)
		return

	if (heavy || med || light || long)
		empulse(orignator, heavy, med, light, long)
		log_admin("[key_name(user)] created an EM Pulse ([heavy],[med],[light],[long]) at ([orignator.x],[orignator.y],[orignator.z])")
		message_admins("[key_name_admin(user)] created an EM PUlse ([heavy],[med],[light],[long]) at ([orignator.x],[orignator.y],[orignator.z])", 1)
		feedback_add_details("admin_verb","EMP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(gib_them, (R_ADMIN|R_FUN), "Gib", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, mob/victim in REGISTRY_MEMBERS(REGISTRY_MOBS))
	var/confirm = verb_prompt(user, "a10", list("message" = "You sure?", "title" = "Confirm", "choices" = list("Yes", "No")), args)
	if(isnull(confirm))
		return
	if(confirm != "Yes")
		return
	//Due to the delay here its easy for something to have happened to the mob
	if(!victim)
		return

	log_admin("[key_name(user)] has gibbed [key_name(victim)]")
	message_admins("[key_name_admin(user)] has gibbed [key_name_admin(victim)]", 1)

	if(isobserver(victim))
		gibs(victim.loc)
		return

	victim.gib()
	feedback_add_details("admin_verb","GIB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(gib_self, R_HOLDER, "Gibself", "Give yourself the same treatment you give others.", ADMIN_CATEGORY_FUN_DO_NOT)
	var/confirm = verb_prompt(user, "a11", list("message" = "You sure?", "title" = "Confirm", "choices" = list("Yes", "No")), args)
	if(isnull(confirm))
		return
	if(!confirm)
		return
	if(confirm == "Yes")
		if (isobserver(user.mob)) // so they don't spam gibs everywhere
			return
		else
			user.mob.gib()

		log_admin("[key_name(user)] used gibself.")
		message_admins(span_blue("[key_name_admin(user)] used gibself."), 1)
		feedback_add_details("admin_verb","GIBS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
