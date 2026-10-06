/obj/structure/portal_event
	name = "portal"
	desc = "It leads to someplace else!"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "type-d-portal"
	density = TRUE
	unacidable = TRUE//Can't destroy energy portals.
	var/failchance = 0
	anchored = TRUE
	/// Relation view: the far end (another portal or a ghost-only portal_target).
	var/obj/target

/obj/structure/portal_event/Bumped(mob/M as mob|obj)
	if(ismob(M) && !(isliving(M)))
		return	//do not send ghosts, zshadows, ai eyes, etc
	teleport(M)

/obj/structure/portal_event/Crossed(AM as mob|obj)
	if(ismob(AM) && !(isliving(AM)))
		return	//do not send ghosts, zshadows, ai eyes, etc
	teleport(AM)

DECLARE_INTERACTIONS(/obj/structure/portal_event, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_OBSERVER("Portal", PROC_REF(portal_event_ghost_use)), \
)

/// Old attack_hand.
/obj/structure/portal_event/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(user))
		return TRUE
	if(!target)
		if(isliving(user))
			to_chat(user, span_notice("Your hand scatters \the [src]..."))
			spent(src, user)	//Delete portals which aren't set that people mess with.
		else return TRUE
	else if(isliving(user) || isobserver(user) && check_rights_for(user?.client, R_HOLDER))	//unless they're staff
		teleport(user)
	return TRUE

/// Old attack_ghost: staff bind an unbound portal, or travel through a bound one. Never fell through.
/obj/structure/portal_event/proc/portal_event_ghost_use(mob/observer/dead/user, obj/item/held, datum/interaction/interaction)
	if(!target && check_rights_for(user?.client, R_HOLDER))
		to_chat(user, span_notice("Selecting 'Portal Here' will create and link a portal at your location, while 'Target Here' will create an object that is only visible to ghosts which will act as the target, again at your location. Each option will give you the ability to change portal types, but for all options except 'Select Type' you only get one shot at it, so be sure to experiment with 'Select Type' first if you're not familiar with them."))
		var/response = rerun_ask(user, "k36", PROC_REF(portal_event_ghost_use), args, /datum/om/prompt/choice/alert, message = "You appear to be staff. This portal has no exit point. If you want to make one, move to where you want it to go, and click the appropriate option, see chat for more info, otherwise click 'Cancel'", title = "Unbound Portal", choices = list("Cancel","Portal Here","Target Here", "Select Type"))
		if(isnull(response))
			return TRUE
		if(response == "Portal Here")
			rel_set(src, nameof(target), new type(get_turf(user), src))
			rel_set(target, nameof(/obj/singularity/::target), src)
			target.icon_state = icon_state
			var/letsportal = rerun_ask(user, "k41", PROC_REF(portal_event_ghost_use), args, /datum/om/prompt/choice/alert, message = "Would you like to select a different portal type for these portals?", title = "Change portal", choices = list("No","Yes"))
			if(isnull(letsportal))
				return TRUE
			if(letsportal == "Yes")
				var/portal_icon_selection = select_portal_subtype(user)
				icon_state = portal_icon_selection
				target.icon_state = portal_icon_selection
		if(response == "Target Here")
			var/obj/structure/portal_target/newtarg = new(get_turf(user))
			rel_set(src, nameof(target), newtarg)
			rel_set(newtarg, nameof(newtarg.target), src)
			var/letsportal = rerun_ask(user, "k50", PROC_REF(portal_event_ghost_use), args, /datum/om/prompt/choice/alert, message = "Would you like to select a different portal type?", title = "Change portal", choices = list("No","Yes"))
			if(isnull(letsportal))
				return TRUE
			if(letsportal == "Yes")
				user.forceMove(src)
				icon_state = select_portal_subtype(user)
		if(response == "Select Type")
			icon_state = select_portal_subtype(user)
			return TRUE
		if(target)
			message_admins("The [src]([x],[y],[z]) was given [target]([target.x],[target.y],[target.z]) as a target, and should be ready to use.")
	else if(check_rights_for(user?.client, R_HOLDER))
		src.teleport(user)
	return TRUE

/obj/structure/portal_event/proc/select_portal_subtype(user)
	var/portal_type = rerun_ask(user, "k64", PROC_REF(select_portal_subtype), args, /datum/om/prompt/choice/alert, message = "What kind of portal would you like it to be?", title = "Type Selection", choices = list("Tech (Default)","Star","Weird Green","Pulsing"))
	if(isnull(portal_type))
		return
	var/portal_icon_selection = "type-d-portal"
	if(portal_type == "Tech (Default)")
		portal_icon_selection = "type-d-portal"
	if(portal_type == "Star")
		var/portal_subtype = rerun_ask(user, "k69", PROC_REF(select_portal_subtype), args, /datum/om/prompt/choice/alert, message = "Which subtype would you prefer?", title = "Subtype Selection", choices = list("Blue","Blue Pulse","Blue Unstable","Red","Red Unstable"))
		if(isnull(portal_subtype))
			return
		if(portal_subtype == "Blue")
			portal_icon_selection = "type-a-blue-portal"
		if(portal_subtype == "Blue Pulse")
			portal_icon_selection = "type-a-blue-portal-b"
		if(portal_subtype == "Blue Unstable")
			portal_icon_selection = "type-a-blue-portal-c"
		if(portal_subtype == "Red")
			portal_icon_selection = "type-a-red-portal"
		if(portal_subtype == "Red Unstable")
			portal_icon_selection = "type-a-red-portal-b"
	if(portal_type == "Weird Green")
		portal_icon_selection = "type-b-portal"
	if(portal_type == "Pulsing")
		var/portal_subtype = rerun_ask(user, "k83", PROC_REF(select_portal_subtype), args, /datum/om/prompt/choice/alert, message = "Which subtype would you prefer?", title = "Subtype Selection", choices = list("Blue","Red","Blue/Red Mix", "Yellow", "White"))
		if(isnull(portal_subtype))
			return
		if(portal_subtype == "Blue")
			portal_icon_selection = "type-c-blue-portal"
		if(portal_subtype == "Red")
			portal_icon_selection = "type-c-red-portal"
		if(portal_subtype == "Blue/Red Mix")
			portal_icon_selection = "type-c-mix-portal"
		if(portal_subtype == "Yellow")
			portal_icon_selection = "type-c-yellow-portal"
		if(portal_subtype == "White")
			portal_icon_selection = "type-c-white-portal"
	return portal_icon_selection

/obj/structure/portal_event/proc/teleport(atom/movable/M as mob|obj)
	if(istype(M, /obj/effect)) //sparks don't teleport
		return
	if (M.anchored&&istype(M, /obj/mecha))
		return
	if (!target)
		to_chat(M, span_notice("\The [src] scatters as you pass through it..."))
		spent(src, M)
		return
	if (!istype(M, /atom/movable))
		return
	var/turf/place
	if(isturf(target))
		place = src
	else
		place = target.loc
	var/portalfind = FALSE
	for(var/obj/structure/S in contents_of(place))
		if(istype(S, /obj/structure/portal_event))
			portalfind = TRUE
		else if (S.density)
			portalfind = TRUE
	var/temptarg
	if(portalfind)
		var/possible_turfs = place.AdjacentTurfs()
		if(isemptylist(possible_turfs))
			to_chat(M, span_notice("Something blocks your way."))
			return
		temptarg = pick(possible_turfs)
		do_teleport(M, temptarg)
	else if (istype(M, /atom/movable))
		do_teleport(M, target)

/obj/structure/portal_target
	name = "portal destination"
	desc = "you shouldn't see this unless you're a ghost"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "type-b-portal"
	density = 0
	alpha = 100
	invisibility = INVISIBILITY_OBSERVER
	/// Relation view: the portal that leads here.
	var/obj/target

/obj/structure/portal_gateway
	name = "portal"
	desc = "It leads to someplace else!"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "portalgateway"
	density = TRUE
	unacidable = TRUE//Can't destroy energy portals.
	anchored = TRUE

/obj/structure/portal_gateway/Bumped(mob/M as mob|obj)
	if(ismob(M) && !(isliving(M)))
		return	//do not send ghosts, zshadows, ai eyes, etc
	var/obj/effect/landmark/dest = pick(GLOB.eventdestinations)
	if(dest)
		M << 'sound/effects/phasein.ogg'
		play_sfx(src, SFX_EFFECTS_PHASEIN)
		M.forceMove(dest.loc)
		if(isliving(M) && dest.abductor)
			var/mob/living/L = M
			//Situations to get the mob out of
			if(L?.buckled_to())
				var/atom/movable/_tmp_buck_34 = L?.buckled_to()
				_tmp_buck_34.unbuckle_mob()
			if(istype(L.loc,/obj/mecha))
				var/obj/mecha/ME = L.loc
				ME.go_out()
			else if(occupant_pod_of(L.loc)) // a sleeper, a cryo cell, a scanner: any pod lets them out
				occupant_eject(L.loc)
			else if(istype(L.loc,/obj/machinery/recharge_station))
				var/obj/machinery/recharge_station/RS = L.loc
				RS.go_out()
			if(!issilicon(L)) //Don't drop borg modules...
				var/list/mob_contents = list() //Things which are actually drained as a result of the above not being null.
				mob_contents |= L // The recursive check below does not add the object being checked to its list.
				mob_contents |= recursive_content_check(L, mob_contents, recursion_limit = 3, client_check = 0, sight_check = 0, include_mobs = 1, include_objects = 1, ignore_show_messages = 1)
				for(var/obj/item/holder/I in mob_contents)
					var/obj/item/holder/H = I
					var/mob/living/MI = H.held_mob
					MI.forceMove(get_turf(H))
					if(!issilicon(MI)) //Don't drop borg modules...
						for(var/obj/item/II in MI)
							if(istype(II,/obj/item/implant) || istype(II,/obj/item/nif))
								continue
							MI.drop_from_inventory(II, dest.loc)
					var/obj/effect/landmark/finaldest = pick(GLOB.awayabductors)
					MI.forceMove(finaldest.loc)
					after(MI, 0.1 SECONDS, TYPE_PROC_REF(/mob/living, abduction_arrived))
				for(var/obj/item/I in L)
					if(istype(I,/obj/item/implant) || istype(I,/obj/item/nif))
						continue
					L.drop_from_inventory(I, dest.loc)
			var/obj/effect/landmark/finaldest = pick(GLOB.awayabductors)
			L.forceMove(finaldest.loc)
			after(L, 0.1 SECONDS, TYPE_PROC_REF(/mob/living, abduction_arrived))
	return

/// Knocked out on arrival from an abductor portal.
/mob/living/proc/abduction_arrived()
	status_at_least(EFFECT_PARALYZED, 10)
	status_at_least(EFFECT_SLEEPING, 10)
	src << 'sound/effects/bamf.ogg'
	to_chat(src, span_warning("You're starting to come to. You feel like you've been out for a few minutes, at least..."))

/// A portal's other end goes with it: the two ends name each other through relation views (the
/// framework clears them), and deleting one end deletes the other.
/obj/structure/portal_event/on_destroy(force)
	var/obj/other = target
	..()
	if(other && !QDELETED(other))
		ended_with(other, src)
