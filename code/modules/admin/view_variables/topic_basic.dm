// Basic VV actions on any datum or client, handled by the admin's client (not the target's type)
// so they keep working when the target's own code is broken.

/client/proc/vv_topic_basic_edit(mob/user, href_target, href_targetvar)
	var/datum/target = href_target
	var/target_var = href_targetvar
	if(!target_var || !modify_variables(target, target_var, 1))
		return
	switch(target_var)
		if("name")
			vv_update_display(target, "name", "[target]")
		if("dir")
			var/atom/A = target
			if(istype(A))
				vv_update_display(target, "dir", dir2text(A.dir) || A.dir)
		if("ckey")
			var/mob/living/L = target
			if(istype(L))
				vv_update_display(target, "ckey", L.ckey || "No ckey")
		if("real_name")
			var/mob/living/L = target
			if(istype(L))
				vv_update_display(target, "real_name", L.real_name || "No real name")
	return TRUE

/client/proc/vv_topic_basic_change(mob/user, href_target, href_targetvar)
	if(!href_targetvar)
		return
	modify_variables(href_target, href_targetvar, 0)
	return TRUE

/client/proc/vv_topic_basic_massedit(mob/user, href_target, href_targetvar)
	if(!href_targetvar)
		return
	cmd_mass_modify_object_variables(href_target, href_targetvar)
	return TRUE

/client/proc/vv_topic_expose(mob/user, href_target)
	var/datum/target = href_target
	var/value = vv_get_value(VV_CLIENT, key = "expose")
	if (value["class"] != VV_CLIENT)
		return
	var/client/C = value["value"]
	if (!C)
		return
	if(!target)
		to_chat(user, span_warning("The object you tried to expose to [C] no longer exists (nulled or hard-deled)"), confidential = TRUE)
		return
	message_admins("[key_name_admin(user)] Showed [key_name_admin(C)] a <a href='byond://?_src_=vars;[HrefToken(TRUE)];Vars=[REF(target)]'>VV window</a>")
	log_admin("Admin [key_name(user)] Showed [key_name(C)] a VV window of a [target]")
	to_chat(C, "[holder.fakekey ? "an Administrator" : "[key]"] has granted you access to view a View Variables window", confidential = TRUE)
	C.debug_variables(target, user)
	return TRUE

/client/proc/vv_topic_delete(mob/user, href_target)
	var/datum/target = href_target
	admin_delete(target, user)
	if (isturf(target)) // show the turf that took its place
		debug_variables(target)
	return TRUE

/client/proc/vv_topic_mark(mob/user, href_target)
	mark_datum(href_target)
	return TRUE

/client/proc/vv_topic_tag(mob/user, href_target)
	tag_datum(href_target)
	return TRUE

/client/proc/vv_topic_add_behaviour(mob/user, href_target)
	var/datum/target = href_target
	var/list/names = sortList(subtypesof(/datum/capability), GLOBAL_PROC_REF(cmp_typepaths_asc))
	var/result = flow_ask(mob, "behaviour:add", /datum/prompt/choice, question = "Choose a capability to grant", title = "Grant Capability", choices = names)
	if(isnull(result) || !user)
		return
	if(QDELETED(target))
		to_chat(user, "That thing doesn't exist anymore!", confidential = TRUE)
		return
	if(!grant(target, result, SRC_VV))
		to_chat(user, "[result] could not be granted to [target] (see the runtime log).", confidential = TRUE)
		return
	log_admin("[key_name(user)] has granted capability [result] to [key_name(target)].")
	message_admins(span_notice("[key_name_admin(user)] has granted capability [result] to [key_name_admin(target)]."))
	return TRUE

/client/proc/vv_topic_remove_behaviour(mob/user, href_target)
	return vv_remove_behaviour(user, href_target, FALSE)

/client/proc/vv_topic_mass_remove_behaviour(mob/user, href_target)
	return vv_remove_behaviour(user, href_target, TRUE)

/client/proc/vv_remove_behaviour(mob/user, datum/target, mass_remove)
	var/list/names = list()
	for(var/datum/activation/A as anything in target.rx?.activations)
		if(!A.dead && A.source == SRC_VV)
			names |= A.def.type
	if(!length(names))
		to_chat(user, "[target] has no capabilities granted through VV.")
		return
	var/path = flow_ask(mob, "behaviour:remove", /datum/prompt/choice, question = "Choose a capability to revoke", title = "Revoke Capability", choices = names)
	if(isnull(path) || !user)
		return
	if(QDELETED(target))
		to_chat(user, "That thing doesn't exist anymore!")
		return
	var/list/targets_to_remove_from = list(target)
	if(mass_remove)
		var/method = vv_subtype_prompt(target.type, "behaviour")
		if(isnull(method))
			return
		if(flow_ask(mob, "behaviour:mass", /datum/prompt/choice, question = "Are you sure you want to mass-revoke [path] on [target.type]?", title = "Mass Revoke Confirmation", choices = list("Yes", "No"), buttons = TRUE) != "Yes")
			return
		targets_to_remove_from = get_all_of_type(target.type, method)
	for(var/datum/target_to_remove_from as anything in targets_to_remove_from)
		revoke(target_to_remove_from, path, SRC_VV)
	message_admins(span_notice("[key_name_admin(user)] has [mass_remove ? "mass " : ""]revoked capability [path] from [mass_remove ? target.type : key_name_admin(target)]."))
	return TRUE

/client/proc/vv_topic_call_proc(mob/user, href_target)
	return SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/call_proc_datum, href_target)
