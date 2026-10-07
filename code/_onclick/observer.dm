// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/client/var/inquisitive_ghost = 1
/mob/observer/dead/verb/toggle_inquisition() // warning: unexpected inquisition
	set name = "Toggle Inquisitiveness"
	set desc = "Sets whether your ghost examines everything on click by default"
	set category = VERB_CAT_GHOST_SETTINGS
	if(!client) return
	client.inquisitive_ghost = !client.inquisitive_ghost
	if(client.inquisitive_ghost)
		to_chat(src, span_notice("You will now examine everything you click on."))
	else
		to_chat(src, span_notice("You will no longer examine things you click on."))

/mob/observer/dead/DblClickOn(atom/A, params)
	if(check_click_intercept(params,A))
		return
	if(client.buildmode)
		build_click(src, client.buildmode, params, A)
		return
	if(can_reenter_corpse && mind && mind.current)
		if(A == mind.current || (is_in_holder(mind.current, A))) // double click your corpse or whatever holds it
			reenter_corpse()						// (cloning scanner, body bag, closet, mech, etc)
			return
	if(isghosttrap(src.loc))
		return
	// Things you might plausibly want to follow
	if(istype(A,/atom/movable))
		ManualFollow(A)
	// Otherwise jump
	else
		if(src?.following_target())
			stop_following()
		forceMove(get_turf(A))

// Ghost clicks route through the input router: observer interactions (INTERACT_OBSERVER),
// then the ghost adapter's default (an object's UI to view, an inquisitive ghost's examine).

// ---------------------------------------
// And here are some good things for free:
// Now you can click through portals, wormholes, gateways, and teleporters while observing. -Sayu

EXTEND_INTERACTIONS(/obj/machinery/teleport/hub, INTERACT_OBSERVER("Follow the link", PROC_REF(hub_ghost_follow)))

/obj/machinery/teleport/hub/proc/hub_ghost_follow(mob/user, obj/item/held, datum/interaction/interaction)
	var/atom/l = loc
	var/obj/machinery/computer/teleporter/com = locate(/obj/machinery/computer/teleporter, locate(l.x - 2, l.y, l.z))
	if(!com?.teleport_control.locked())
		return FALSE
	user.forceMove(get_turf(com.teleport_control.locked()))
	return TRUE

/// Declared with the portal's other ops (portals.dm).
/obj/effect/portal/proc/portal_ghost_follow(datum/act/op/A)
	var/mob/user = A.actor
	if(!target_ref())
		return OP_DECLINE
	user.forceMove(get_turf(target_ref()))
	return OP_OK

// -------------------------------------------
// This was supposed to be used by adminghosts
// I think it is a *terrible* idea
// but I'm leaving it here anyway
// commented out, of course.
/*
/atom/proc/attack_admin(mob/user as mob)
	if(!user || !user.client || !check_rights_for(user.client, R_HOLDER))
		return
	attack_hand(user)

*/
