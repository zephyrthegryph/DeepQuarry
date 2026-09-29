REGISTRY_MEMBERSHIP(/obj/effect/portal, REGISTRY_PORTALS)

/obj/effect/portal
	name = "portal"
	desc = "Looks unstable. Best to test it with the clown."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "portal"
	density = TRUE
	unacidable = TRUE//Can't destroy energy portals.
	var/failchance = 5
	var/obj/item/target
	var/creator = null
	anchored = TRUE
	var/event = FALSE

/obj/effect/portal/Bumped(mob/M as mob|obj)
	if(ismob(M) && !(isliving(M)))
		return	//do not send ghosts, zshadows, ai eyes, etc
	teleport(M)
	return

/obj/effect/portal/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		if(!event)
			return
		if(isliving(AM))
			var/mob/living/L = AM
			var/datum/shadekin/SK = L.get_shadekin_state()
			if(SK)
				SK.attack_dephase(null, src)
	if(ismob(AM) && !(isliving(AM)))
		return	//do not send ghosts, zshadows, ai eyes, etc
	teleport(AM)
	return

EXTEND_INTERACTIONS(/obj/effect/portal, \
	INTERACT_HAND("Enter", PROC_REF(interaction_enter_portal)), \
	INTERACT_OBSERVER("Go through", PROC_REF(portal_ghost_follow)), \
)

/// Old attack_hand: step through the portal.
/obj/effect/portal/proc/interaction_enter_portal(mob/user, obj/item/held, datum/interaction/interaction)
	if(istype(user) && !(isliving(user)))
		return TRUE	//do not send ghosts, zshadows, ai eyes, etc
	teleport(user)
	return TRUE

/obj/effect/portal/Initialize(mapload)
	. = ..()
	expire(30 SECONDS)

/obj/effect/portal/proc/teleport(atom/movable/M as mob|obj)
	if(istype(M, /obj/effect)) //sparks don't teleport
		return
	if (M.anchored&&istype(M, /obj/mecha))
		return
	if (icon_state == "portal1")
		return
	if (!( target_ref() ))
		qdel(src)
		return
	if (istype(M, /atom/movable))
		// ition Start: Prevent taurriding abuse
		if(isliving(M))
			var/mob/living/L = M
			if(LAZYLEN(L?.buckled_mob_list()))
				var/datum/riding/R = L.riding_datum
				for(var/rider in L?.buckled_mob_list())
					R.force_dismount(rider)
		// ition End: Prevent taurriding abuse
		if(isbelly(target_ref()))
			if(target_ref() == M)
				return
			if(istype(M, /mob/living))
				var/mob/living/L = M
				if(L.can_be_drop_prey && L.devourable)
					do_teleport(M, target_ref())
					return
		if(prob(failchance)) //oh dear a problem, put em in deep space
			src.icon_state = "portal1"
			do_teleport(M, locate(rand(5, world.maxx - 5), rand(5, world.maxy -5), 3), 0)
		else
			do_teleport(M, target_ref(), 1) ///You will appear adjacent to the beacon

/// LC-refs: target -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/effect/portal/proc/target_ref() as /obj/item
	return target
