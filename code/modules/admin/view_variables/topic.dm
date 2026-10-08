// The View Variables href entry (doc/rewrite/final_api.html section 13, namespaces in code/__defines/vv.dm).
// Per-type actions are ops of the VV'd datum in the VV_TOPIC namespace (topic_in(VV_TOPIC, key)), beside the type's vv_get_dropdown(); the admin
// client's own VV actions (here, topic_basic.dm, topic_list.dm) are ops of the admin holder in VV_ADMIN_TOPIC, whose handler is a /datum/admins proc
// that calls the /client proc of the same name, which takes the link's values as typed parameters.

/// Every `_src_=vars` href, and server-side callers opening VV (`trusted`: a tgui panel's own
/// act, which carries no href token). Its questions re-run it (prompt_flow(), prompt_helpers.dm).
/client/proc/vv_topic(list/href_list, trusted = FALSE)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(vv_topic), args)
	if(!href_list || !check_rights_for(src, R_VAREDIT))
		return
	if(!trusted && !holder.CheckAdminHref(null, href_list, mob))
		return
	return topic_dispatch_vv(src, href_list)

/// Dispatches a VV href for admin client `C`: the VV_TOPIC ops of the `target` datum first, then the admin holder's VV_ADMIN_TOPIC ops. Neither runs the
/// target's own gate: VV is gated by vv_topic() (R_VAREDIT + href token) and each op's req_rights().
/proc/topic_dispatch_vv(client/C, list/href_list)
	var/mob/user = C.mob
	var/raw_target = href_list[VV_HK_TARGET]
	if(!isnull(raw_target))
		var/datum/target = topic_resolve_ref(C, raw_target, /datum, TOPIC_ANY)
		if(target?.vv_topic_allowed(user))
			var/datum/op_result/on_target = op_topic_href(user, target, href_list, namespace = VV_TOPIC)
			if(on_target)
				return on_target
	return op_topic_href(user, admin_holder_of(C), href_list, namespace = VV_ADMIN_TOPIC)

/// The handlers of the VV_ADMIN_TOPIC ops: the admin's own client does the work, in the /client proc of the same name (topic.dm, topic_basic.dm,
/// topic_list.dm), with the link's values as parameters.
/datum/admins/proc/vv_topic_vars(datum/act/op/A, href_vars, href_special_varname)
	owner()?.vv_topic_vars(A.actor, href_vars, href_special_varname)

/datum/admins/proc/vv_topic_rotate_left(datum/act/op/A, href_rotatedatum)
	owner()?.vv_topic_rotate_left(A.actor, href_rotatedatum)

/datum/admins/proc/vv_topic_rotate_right(datum/act/op/A, href_rotatedatum)
	owner()?.vv_topic_rotate_right(A.actor, href_rotatedatum)

/datum/admins/proc/vv_topic_adjust_body(datum/act/op/A, href_mobtodamage, href_adjustbody)
	owner()?.vv_topic_adjust_body(A.actor, href_mobtodamage, href_adjustbody)

/datum/admins/proc/vv_topic_basic_edit(datum/act/op/A, href_target, href_targetvar)
	owner()?.vv_topic_basic_edit(A.actor, href_target, href_targetvar)

/datum/admins/proc/vv_topic_basic_change(datum/act/op/A, href_target, href_targetvar)
	owner()?.vv_topic_basic_change(A.actor, href_target, href_targetvar)

/datum/admins/proc/vv_topic_basic_massedit(datum/act/op/A, href_target, href_targetvar)
	owner()?.vv_topic_basic_massedit(A.actor, href_target, href_targetvar)

/datum/admins/proc/vv_topic_expose(datum/act/op/A, href_target)
	owner()?.vv_topic_expose(A.actor, href_target)

/datum/admins/proc/vv_topic_delete(datum/act/op/A, href_target)
	owner()?.vv_topic_delete(A.actor, href_target)

/datum/admins/proc/vv_topic_mark(datum/act/op/A, href_target)
	owner()?.vv_topic_mark(A.actor, href_target)

/datum/admins/proc/vv_topic_tag(datum/act/op/A, href_target)
	owner()?.vv_topic_tag(A.actor, href_target)

/datum/admins/proc/vv_topic_add_behaviour(datum/act/op/A, href_target)
	owner()?.vv_topic_add_behaviour(A.actor, href_target)

/datum/admins/proc/vv_topic_remove_behaviour(datum/act/op/A, href_target)
	owner()?.vv_topic_remove_behaviour(A.actor, href_target)

/datum/admins/proc/vv_topic_mass_remove_behaviour(datum/act/op/A, href_target)
	owner()?.vv_topic_mass_remove_behaviour(A.actor, href_target)

/datum/admins/proc/vv_topic_call_proc(datum/act/op/A, href_target)
	owner()?.vv_topic_call_proc(A.actor, href_target)

/datum/admins/proc/vv_topic_list_edit(datum/act/op/A, href_target, href_targetvar)
	owner()?.vv_topic_list_edit(A.actor, href_target, href_targetvar)

/datum/admins/proc/vv_topic_list_change(datum/act/op/A, href_target, href_targetvar)
	owner()?.vv_topic_list_change(A.actor, href_target, href_targetvar)

/datum/admins/proc/vv_topic_list_remove(datum/act/op/A, href_target, href_targetvar)
	owner()?.vv_topic_list_remove(A.actor, href_target, href_targetvar)

/datum/admins/proc/vv_topic_list_add(datum/act/op/A, href_target)
	owner()?.vv_topic_list_add(A.actor, href_target)

/datum/admins/proc/vv_topic_list_dupes(datum/act/op/A, href_target)
	owner()?.vv_topic_list_dupes(A.actor, href_target)

/datum/admins/proc/vv_topic_list_nulls(datum/act/op/A, href_target)
	owner()?.vv_topic_list_nulls(A.actor, href_target)

/datum/admins/proc/vv_topic_list_length(datum/act/op/A, href_target)
	owner()?.vv_topic_list_length(A.actor, href_target)

/datum/admins/proc/vv_topic_list_shuffle(datum/act/op/A, href_target)
	owner()?.vv_topic_list_shuffle(A.actor, href_target)

/// Whether this datum's VV_TOPIC ops may run for `user` (the admin holder's ops always may).
/datum/proc/vv_topic_allowed(mob/user)
	return TRUE

// Opens VV on a ref. Some special vars can't be located even with their ref: those links name
// the owner and the var instead.

/client/proc/vv_topic_vars(mob/user, href_vars, href_special_varname)
	var/vars_target = href_vars
	var/special = href_special_varname
	if(special)
		var/datum/owner = vars_target
		if(!isdatum(owner) || !(special in owner.vars))
			return
		vars_target = owner.vars[special]
	debug_variables(vars_target)
	return TRUE


/client/proc/vv_topic_rotate_left(mob/user, href_rotatedatum)
	return vv_rotate(href_rotatedatum, 45)

/client/proc/vv_topic_rotate_right(mob/user, href_rotatedatum)
	return vv_rotate(href_rotatedatum, -45)

/client/proc/vv_rotate(atom/A, angle)
	if(!A)
		return
	A.set_dir(turn(A.dir, angle))
	vv_update_display(A, "dir", dir2text(A.dir))
	return TRUE

// The VV body editor (/mob/living/vv_get_header(), vv_adjust_body()).

/client/proc/vv_topic_adjust_body(mob/user, href_mobtodamage, href_adjustbody)
	var/mob/living/L = href_mobtodamage
	if(!L?.body)
		return
	var/log_msg = L.vv_adjust_body(src, href_adjustbody)
	if(!log_msg)
		return
	if(QDELETED(L))
		to_chat(user, "Mob doesn't exist anymore", confidential = TRUE)
		return
	log_msg = "[key_name(user)] [log_msg] on [key_name(L)]"
	message_admins("[log_msg] ([ADMIN_LOOKUPFLW(L)])")
	log_admin(log_msg)
	admin_ticket_log(L, "<font color='blue'>[log_msg]</font>")
	vv_update_display(L, "vitality", "[round(L.vitality() * 100)]%")
	vv_update_display(L, "afflictions", "[LAZYLEN(L.body?.afflictions)]")
	vv_update_display(L, "oxygen_debt", "[round(L.oxygen_debt(), 0.1)]")
	return TRUE
