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

CAPABILITIES(/obj/structure/portal_event)
	ref_one(nameof(target), /obj)
	op("portal_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_hand)))
	op("portal_event_ghost_use", observer(), priority(OP_PRIORITY_NORMAL + 1), label("Portal"), when(req_empty(nameof(target)), req_rights(R_HOLDER)), asks(/datum/prompt/choice, fields = list("question" = "You appear to be staff. This portal has no exit point. If you want to make one, move to where you want it to go, and click the appropriate option, otherwise click 'Cancel'. Selecting 'Portal Here' will create and link a portal at your location, while 'Target Here' will create an object that is only visible to ghosts which will act as the target, again at your location. Each option will give you the ability to change portal types, but for all options except 'Select Type' you only get one shot at it, so be sure to experiment with 'Select Type' first if you're not familiar with them.", "title" = "Unbound Portal", "choices" = list("Cancel", "Portal Here", "Target Here", "Select Type"), "buttons" = TRUE, "timeout" = 0), step = "k36"), asks(/datum/prompt/choice, fields = list("question" = "Would you like to select a different portal type for these portals?", "title" = "Change portal", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "k41", when = PROC_REF(portal_here)), asks(/datum/prompt/choice, fields = list("question" = "What kind of portal would you like it to be?", "title" = "Type Selection", "choices" = list("Tech (Default)", "Star", "Weird Green", "Pulsing"), "buttons" = TRUE, "timeout" = 0), step = "k64a", when = PROC_REF(types_a)), asks(/datum/prompt/choice, fields = list("question" = "Which subtype would you prefer?", "title" = "Subtype Selection", "choices" = list("Blue", "Blue Pulse", "Blue Unstable", "Red", "Red Unstable"), "buttons" = TRUE, "timeout" = 0), step = "k69a", when = PROC_REF(star_a)), asks(/datum/prompt/choice, fields = list("question" = "Which subtype would you prefer?", "title" = "Subtype Selection", "choices" = list("Blue", "Red", "Blue/Red Mix", "Yellow", "White"), "buttons" = TRUE, "timeout" = 0), step = "k83a", when = PROC_REF(pulsing_a)), asks(/datum/prompt/choice, fields = list("question" = "Would you like to select a different portal type?", "title" = "Change portal", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "k50", when = PROC_REF(target_here)), asks(/datum/prompt/choice, fields = list("question" = "What kind of portal would you like it to be?", "title" = "Type Selection", "choices" = list("Tech (Default)", "Star", "Weird Green", "Pulsing"), "buttons" = TRUE, "timeout" = 0), step = "k64b", when = PROC_REF(types_b)), asks(/datum/prompt/choice, fields = list("question" = "Which subtype would you prefer?", "title" = "Subtype Selection", "choices" = list("Blue", "Blue Pulse", "Blue Unstable", "Red", "Red Unstable"), "buttons" = TRUE, "timeout" = 0), step = "k69b", when = PROC_REF(star_b)), asks(/datum/prompt/choice, fields = list("question" = "Which subtype would you prefer?", "title" = "Subtype Selection", "choices" = list("Blue", "Red", "Blue/Red Mix", "Yellow", "White"), "buttons" = TRUE, "timeout" = 0), step = "k83b", when = PROC_REF(pulsing_b)), asks(/datum/prompt/choice, fields = list("question" = "What kind of portal would you like it to be?", "title" = "Type Selection", "choices" = list("Tech (Default)", "Star", "Weird Green", "Pulsing"), "buttons" = TRUE, "timeout" = 0), step = "k64c", when = PROC_REF(types_c)), asks(/datum/prompt/choice, fields = list("question" = "Which subtype would you prefer?", "title" = "Subtype Selection", "choices" = list("Blue", "Blue Pulse", "Blue Unstable", "Red", "Red Unstable"), "buttons" = TRUE, "timeout" = 0), step = "k69c", when = PROC_REF(star_c)), asks(/datum/prompt/choice, fields = list("question" = "Which subtype would you prefer?", "title" = "Subtype Selection", "choices" = list("Blue", "Red", "Blue/Red Mix", "Yellow", "White"), "buttons" = TRUE, "timeout" = 0), step = "k83c", when = PROC_REF(pulsing_c)), then(PROC_REF(portal_event_ghost_use)))
	op("portal_staff_use", observer(), needs(req_full(nameof(target)), req_rights(R_HOLDER)), then(PROC_REF(portal_staff_use)))
	op("portal_ghost_nothing", observer(), priority(OP_PRIORITY_DEFAULT - 1), then(TYPE_PROC_REF(/atom, op_swallow)))

/// Old attack_hand.
/obj/structure/portal_event/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(!istype(user))
		return OP_OK
	if(!target)
		if(isliving(user))
			to_chat(user, span_notice("Your hand scatters \the [src]..."))
			spent(src, user)	//Delete portals which aren't set that people mess with.
		else return OP_OK
	else if(isliving(user) || isobserver(user) && check_rights_for(user?.client, R_HOLDER))	//unless they're staff
		teleport(user)
	return OP_OK

/obj/structure/portal_event/proc/portal_here(datum/act/op/A)
	return A.step_value("k36") == "Portal Here"

/obj/structure/portal_event/proc/target_here(datum/act/op/A)
	return A.step_value("k36") == "Target Here"

/// The type questions of a context (a: after Portal Here, b: after Target Here, c: Select Type) are asked after a Yes there.
/obj/structure/portal_event/proc/asks_type_a(datum/act/op/A)
	return portal_here(A) && A.step_value("k41") == "Yes"

/obj/structure/portal_event/proc/asks_type_b(datum/act/op/A)
	return target_here(A) && A.step_value("k50") == "Yes"

/obj/structure/portal_event/proc/asks_type_c(datum/act/op/A)
	return A.step_value("k36") == "Select Type"

/obj/structure/portal_event/proc/types_a(datum/act/op/A)
	return asks_type_a(A)

/obj/structure/portal_event/proc/star_a(datum/act/op/A)
	return asks_type_a(A) && A.step_value("k64a") == "Star"

/obj/structure/portal_event/proc/pulsing_a(datum/act/op/A)
	return asks_type_a(A) && A.step_value("k64a") == "Pulsing"

/obj/structure/portal_event/proc/types_b(datum/act/op/A)
	return asks_type_b(A)

/obj/structure/portal_event/proc/star_b(datum/act/op/A)
	return asks_type_b(A) && A.step_value("k64b") == "Star"

/obj/structure/portal_event/proc/pulsing_b(datum/act/op/A)
	return asks_type_b(A) && A.step_value("k64b") == "Pulsing"

/obj/structure/portal_event/proc/types_c(datum/act/op/A)
	return asks_type_c(A)

/obj/structure/portal_event/proc/star_c(datum/act/op/A)
	return asks_type_c(A) && A.step_value("k64c") == "Star"

/obj/structure/portal_event/proc/pulsing_c(datum/act/op/A)
	return asks_type_c(A) && A.step_value("k64c") == "Pulsing"

/// Old attack_ghost: staff bind an unbound portal, or travel through a bound one. Never fell through.
/obj/structure/portal_event/proc/portal_event_ghost_use(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	var/response = A.step_value("k36")
	if(isnull(response))
		return OP_OK
	if(response == "Portal Here")
		rel_set(src, nameof(target), new type(get_turf(user), src))
		rel_set(target, nameof(/obj/singularity/::target), src)
		target.icon_state = icon_state
		var/letsportal = A.step_value("k41")
		if(isnull(letsportal))
			return OP_OK
		if(letsportal == "Yes")
			var/portal_icon_selection = chosen_portal_icon(A, "a")
			icon_state = portal_icon_selection
			target.icon_state = portal_icon_selection
	if(response == "Target Here")
		var/obj/structure/portal_target/newtarg = new(get_turf(user))
		rel_set(src, nameof(target), newtarg)
		rel_set(newtarg, nameof(newtarg.target), src)
		var/letsportal = A.step_value("k50")
		if(isnull(letsportal))
			return OP_OK
		if(letsportal == "Yes")
			user.forceMove(src)
			icon_state = chosen_portal_icon(A, "b")
	if(response == "Select Type")
		icon_state = chosen_portal_icon(A, "c")
		return OP_OK
	if(target)
		message_admins("The [src]([x],[y],[z]) was given [target]([target.x],[target.y],[target.z]) as a target, and should be ready to use.")
	return OP_OK

/// Old attack_ghost: staff travel through a bound portal.
/obj/structure/portal_event/proc/portal_staff_use(datum/act/op/A)
	src.teleport(A.actor)
	return OP_OK

/// The icon the type questions of a context picked.
/obj/structure/portal_event/proc/chosen_portal_icon(datum/act/op/A, context)
	var/portal_type = A.step_value("k64[context]")
	if(isnull(portal_type))
		return
	var/portal_icon_selection = "type-d-portal"
	if(portal_type == "Tech (Default)")
		portal_icon_selection = "type-d-portal"
	if(portal_type == "Star")
		var/portal_subtype = A.step_value("k69[context]")
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
		var/portal_subtype = A.step_value("k83[context]")
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
	status_at_least(STAT_PARALYZED, 10)
	status_at_least(STAT_SLEEPING, 10)
	src << 'sound/effects/bamf.ogg'
	to_chat(src, span_warning("You're starting to come to. You feel like you've been out for a few minutes, at least..."))

/// A portal's other end goes with it: the two ends name each other through relation views (the
/// framework clears them), and deleting one end deletes the other.
/obj/structure/portal_event/on_destroy(force)
	var/obj/other = target
	..()
	if(other && !QDELETED(other))
		ended_with(other, src)
