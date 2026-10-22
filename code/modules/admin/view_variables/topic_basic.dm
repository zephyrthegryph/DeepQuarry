// Basic VV actions on any datum or client, handled by the admin's client (not the target's type)
// so they keep working when the target's own code is broken.

/client/proc/vv_topic_basic_edit(mob/user, href_target, href_targetvar)
	var/datum/target = href_target
	var/target_var = href_targetvar
	if(!target_var)
		return
	modify_variables(target, target_var, 1, TRUE)
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
	ask_admin(/datum/ask_sequence/admin/vv_value, target, null, PROC_REF(vv_expose_picked), list("pick_params" = list("class" = VV_CLIENT)))
	return TRUE

/client/proc/vv_expose_picked(datum/ask_sequence/admin/vv_value/asked)
	var/mob/user = asked.actor()
	var/list/value = asked.get("picked")
	if (value["class"] != VV_CLIENT)
		return
	var/client/C = value["value"]
	if (!C)
		return
	var/datum/target = asked.subject()
	if(!target)
		to_chat(user, span_warning("The object you tried to expose to [C] no longer exists (nulled or hard-deled)"), confidential = TRUE)
		return
	message_admins("[key_name_admin(user)] Showed [key_name_admin(C)] a <a href='byond://?_src_=vars;[HrefToken(TRUE)];Vars=[REF(target)]'>VV window</a>")
	log_admin("Admin [key_name(user)] Showed [key_name(C)] a VV window of a [target]")
	to_chat(C, "[holder.fakekey ? "an Administrator" : "[key]"] has granted you access to view a View Variables window", confidential = TRUE)
	C.debug_variables(target, user)

/client/proc/vv_topic_delete(mob/user, href_target)
	var/datum/target = href_target
	admin_delete(target, user)
	if (isturf(target)) // the turf's window opens as the question does, answered or cancelled
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
	ask_admin(/datum/ask_sequence/admin, target, list(
		question_step("capability", /datum/prompt/choice, question = "Choose a capability to grant", title = "Grant Capability", choices = names)),
		PROC_REF(vv_capability_chosen))
	return TRUE

/client/proc/vv_capability_chosen(datum/ask_sequence/admin/asked)
	var/mob/user = asked.actor()
	var/result = asked.get("capability")
	var/datum/target = asked.subject()
	if(isnull(result) || !user)
		return
	if(!target || QDELETED(target))
		to_chat(user, "That thing doesn't exist anymore!", confidential = TRUE)
		return
	if(!grant(target, result, SRC_VV))
		to_chat(user, "[result] could not be granted to [target] (see the runtime log).", confidential = TRUE)
		return
	log_admin("[key_name(user)] has granted capability [result] to [key_name(target)].")
	message_admins(span_notice("[key_name_admin(user)] has granted capability [result] to [key_name_admin(target)]."))

/client/proc/vv_topic_remove_behaviour(mob/user, href_target)
	return vv_remove_behaviour(user, href_target, FALSE)

/client/proc/vv_topic_mass_remove_behaviour(mob/user, href_target)
	return vv_remove_behaviour(user, href_target, TRUE)

/// Revoking a capability granted through VV, from one datum or (`mass`) from every one of its type.
/datum/ask_sequence/admin/vv_revoke
	var/include_subtypes = FALSE
	var/mass = FALSE

/client/proc/vv_remove_behaviour(mob/user, datum/target, mass_remove)
	var/list/names = list()
	for(var/datum/activation/A as anything in target.rx?.activations)
		if(!A.dead && A.source == SRC_VV)
			names |= A.def.type
	if(!length(names))
		to_chat(user, "[target] has no capabilities granted through VV.")
		return
	var/list/steps = list(question_step("capability", /datum/prompt/choice, question = "Choose a capability to revoke", title = "Revoke Capability", choices = names))
	if(mass_remove)
		steps += TYPE_PROC_REF(/client, vv_revoke_ask_subtypes)
		steps += TYPE_PROC_REF(/client, vv_revoke_ask_mass)
	ask_admin(/datum/ask_sequence/admin/vv_revoke, target, steps, PROC_REF(vv_capability_revoked), list("mass" = mass_remove))
	return TRUE

/client/proc/vv_revoke_ask_subtypes(datum/ask_sequence/admin/vv_revoke/asked)
	var/datum/target = asked.subject()
	if(!target || QDELETED(target))
		return ASK_STOP
	return asked.ask_child(/datum/ask_sequence/picker/subtype_pick, "include_subtypes", list("target_type" = target.type))

/client/proc/vv_revoke_ask_mass(datum/ask_sequence/admin/vv_revoke/asked)
	var/datum/target = asked.subject()
	if(!target || QDELETED(target))
		return ASK_STOP
	return question_step("mass_confirm", /datum/prompt/choice, question = "Are you sure you want to mass-revoke [asked.get("capability")] on [target.type]?", title = "Mass Revoke Confirmation", choices = list("Yes", "No"), buttons = TRUE)

/client/proc/vv_capability_revoked(datum/ask_sequence/admin/vv_revoke/asked)
	var/mob/user = asked.actor()
	var/path = asked.get("capability")
	var/datum/target = asked.subject()
	if(isnull(path) || !user)
		return
	if(!target || QDELETED(target))
		to_chat(user, "That thing doesn't exist anymore!")
		return
	var/list/targets_to_remove_from = list(target)
	if(asked.mass)
		if(asked.get("mass_confirm") != "Yes")
			return
		targets_to_remove_from = get_all_of_type(target.type, asked.include_subtypes)
	for(var/datum/target_to_remove_from as anything in targets_to_remove_from)
		revoke(target_to_remove_from, path, SRC_VV)
	message_admins(span_notice("[key_name_admin(user)] has [asked.mass ? "mass " : ""]revoked capability [path] from [asked.mass ? target.type : key_name_admin(target)]."))

/client/proc/vv_topic_call_proc(mob/user, href_target)
	return SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/call_proc_datum, href_target)
