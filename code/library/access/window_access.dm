// Window and silicon access (doc/rewrite/final_api.html, section 11 "The library", section 13 "Window access is a requirement").
//
// Two requirements every machine with a control window shares, so no machine writes its own "can this mob use me" proc:
//
//   req_window_usable(remote = PROC_REF(x))
//        The actor can work the holder's window now. An admin ghost always can. Anyone else must be conscious, able to use tools, free and standing;
//        by hand they must be beside the holder; over a silicon's link (AUTH_REMOTE_ACCESS) the distance does not matter and the holder's own
//        `remote` proc decides instead: x(datum/act/op/A) returns null to let the link in or a /datum/msg reason (the AI-control wire, a hacker).
//   req_silicon_or_admin()
//        The actor works the holder over a silicon's link the holder lets in (remote_link_allowed(): the AI, a cyborg with access on its own ID
//        card) or is an admin ghost: the window an AI owns (an airlock's), the buttons only a silicon has (an APC's overload), and the lock's own
//        exemption (lock(), code/library/access/lock.dm).
//
// Typical use, on a machine whose every window button answers the same people:
//
//   extend(TAG_UI, needs(req_window_usable(remote = PROC_REF(ai_control_refusal))))
//   op("overload", ui_act(), needs(req_silicon_or_admin()), ...)

MSG_DEF_SELF(window/cant_use, "You can't use that right now.")
MSG_DEF_SELF(window/silicons_only, "Only a silicon can do that.")

/// Is the actor of `A` working the holder over a silicon's link the holder lets in, or an admin ghost that may interact? A condition.
/proc/silicon_or_admin(datum/act/op/A)
	READS_FROM(A)
	var/mob/user = A?.actor
	if(!user)
		return FALSE
	var/obj/holder = A.holder
	if(istype(holder) && holder.remote_link_allowed(A))
		return TRUE
	return is_admin_ghost(user)

/// An admin's ghost that may interact with the world.
/proc/is_admin_ghost(mob/user)
	READS_FROM()
	if(!isobserver(user))
		return FALSE
	var/mob/observer/dead/D = user
	return D.can_admin_interact()

// ---- req_silicon_or_admin ----

/// req_silicon_or_admin(because =, id =): the actor works the holder over a link it lets in, or is an admin ghost.
/proc/req_silicon_or_admin(because = null, id = null)
	return part_make(/datum/entry/part/req/silicon_or_admin, list("because" = because, "id" = id))

/datum/entry/part/req/silicon_or_admin
	part_name = "req_silicon_or_admin"
	default_reason = /datum/msg/window/silicons_only

/datum/entry/part/req/silicon_or_admin/holds(datum/act/op/A)
	return silicon_or_admin(A)

// ---- req_window_usable ----

/// req_window_usable(remote =, because =, id =): the actor can work the holder's window now (see the top of the file). `remote` names a proc of the
/// holder deciding a remote user's access: x(datum/act/op/A) returns null to allow, or a /datum/msg reason.
/proc/req_window_usable(remote = null, because = null, id = null)
	return part_make(/datum/entry/part/req/window_usable, list("remote" = remote, "because" = because, "id" = id))

/datum/entry/part/req/window_usable
	part_name = "req_window_usable"
	default_reason = /datum/msg/window/cant_use

/datum/entry/part/req/window_usable/holds(datum/act/op/A)
	return isnull(window_refusal(A))

/datum/entry/part/req/window_usable/refusal(datum/act/op/A)
	var/because = src.args["because"]
	if(ispath(because, /datum/msg))
		return because
	return window_refusal(A) || default_reason

/// Why the actor of `A` can't work the holder's window now, or null.
/datum/entry/part/req/window_usable/proc/window_refusal(datum/act/op/A)
	var/mob/user = A.actor
	if(!user)
		return /datum/msg/window/cant_use
	if(is_admin_ghost(user))
		return null
	if(user.stat)
		return /datum/msg/window/cant_use
	if(!user.IsAdvancedToolUser() || user.restrained() || user.lying) // ALLOW(reads): a mob lying down is legacy mob state, tracked in the mob conversion; the check runs when a window button is pressed, never from a cached menu
		return /datum/msg/window/cant_use
	if(A.authority & AUTH_REMOTE_ACCESS) // over a link: the holder decides, not the distance
		var/remote = src.args["remote"]
		return remote ? op_call(A, remote) : null
	var/atom/holder = A.holder
	if(!istype(holder) || get_dist(holder, user) > 1)
		return /datum/msg/window/cant_use
	return null
