// The View Variables href entry (doc/rewrite/systems.md §20, macros in code/__defines/vv.dm).
// Per-type actions are VV_TOPIC_ACTION rows beside their type's vv_get_dropdown(); the admin
// client's own VV actions are VV_ADMIN_TOPIC_ACTION rows (here, topic_basic.dm, topic_list.dm).

/// Every `_src_=vars` href, and server-side callers opening VV (`trusted`: a tgui panel's own
/// act, which carries no href token). Its questions re-run it (prompt_flow(), prompt_helpers.dm).
/client/proc/vv_topic(list/href_list, trusted = FALSE)
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(vv_topic), args)
	if(!href_list || !check_rights_for(src, R_VAREDIT))
		return
	if(!trusted && !holder.CheckAdminHref(null, href_list))
		return
	return topic_dispatch_vv(src, href_list)

/// Dispatches a VV href for admin client `C`: the VV_TOPIC rows of the `target` datum's type
/// first, then the client's VV_ADMIN_TOPIC rows. Neither runs the target's topic_allowed(): VV
/// is gated by vv_topic() (R_VAREDIT + href token) and each row's TOPIC_RIGHTS.
/proc/topic_dispatch_vv(client/C, list/href_list)
	var/mob/user = C.mob
	var/list/row
	var/raw_target = href_list[VV_HK_TARGET]
	if(!isnull(raw_target))
		var/datum/target = topic_resolve_ref(C, raw_target, /datum, TOPIC_ANY)
		if(target?.vv_topic_allowed(user))
			row = topic_find_row(target, href_list, VV_TOPIC)
			if(row)
				return topic_run(target, user, href_list, row, FALSE)
	row = topic_find_row(C, href_list, VV_ADMIN_TOPIC)
	if(row)
		return topic_run(C, user, href_list, row, FALSE)
	return null

/// Whether this datum's VV_TOPIC rows may run for `user` (the admin client's rows always may).
/datum/proc/vv_topic_allowed(mob/user)
	return TRUE

// Opens VV on a ref. Some special vars can't be located even with their ref: those links name
// the owner and the var instead.
VV_ADMIN_TOPIC_ACTION("Vars", PROC_REF(vv_topic_vars), TOPIC_REF("Vars", null, TOPIC_ANY), TOPIC_TEXT("special_varname"))

/client/proc/vv_topic_vars(mob/user, list/args)
	var/vars_target = args["Vars"]
	var/special = args["special_varname"]
	if(special)
		var/datum/owner = vars_target
		if(!isdatum(owner) || !(special in owner.vars))
			return
		vars_target = owner.vars[special]
	debug_variables(vars_target)
	return TRUE

VV_ADMIN_TOPIC_ACTION("rotatedir=left", PROC_REF(vv_topic_rotate_left), TOPIC_REF("rotatedatum", /atom, TOPIC_ANY))
VV_ADMIN_TOPIC_ACTION("rotatedir=right", PROC_REF(vv_topic_rotate_right), TOPIC_REF("rotatedatum", /atom, TOPIC_ANY))

/client/proc/vv_topic_rotate_left(mob/user, list/args)
	return vv_rotate(args["rotatedatum"], 45)

/client/proc/vv_topic_rotate_right(mob/user, list/args)
	return vv_rotate(args["rotatedatum"], -45)

/client/proc/vv_rotate(atom/A, angle)
	if(!A)
		return
	A.set_dir(turn(A.dir, angle))
	vv_update_display(A, "dir", dir2text(A.dir))
	return TRUE

// The VV body editor (/mob/living/vv_get_header(), vv_adjust_body()).
VV_ADMIN_TOPIC_ACTION("adjustBody", PROC_REF(vv_topic_adjust_body), TOPIC_REF("mobToDamage", /mob/living, TOPIC_IN_MOBS), TOPIC_TEXT("adjustBody", 16))

/client/proc/vv_topic_adjust_body(mob/user, list/args)
	var/mob/living/L = args["mobToDamage"]
	if(!L?.body)
		return
	var/log_msg = L.vv_adjust_body(src, args["adjustBody"])
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
