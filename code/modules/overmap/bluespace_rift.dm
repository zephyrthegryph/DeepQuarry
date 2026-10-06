/obj/effect/overmap/bluespace_rift
	name = "bluespace rift"
	desc = "Some sort of bluespace rift. Who knows where it leads?"
	icon = 'icons/obj/overmap_vr.dmi'
	icon_state = "portal"
	color = "#2288FF"
	scannable = TRUE       //if set to TRUE will show up on ship sensors for detailed scans

	var/obj/effect/overmap/bluespace_rift/partner
	var/paused

/// The rift this one is made paired with (its constructor param).
/obj/effect/overmap/bluespace_rift/var/tmp/obj/effect/overmap/bluespace_rift/pair_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/overmap/bluespace_rift/proc/pair_made(obj/effect/overmap/bluespace_rift/new_partner)
	if(new_partner)
		pair(new_partner)

CAPABILITIES(/obj/effect/overmap/bluespace_rift)
	links(/obj/effect/overmap/bluespace_rift::partner, /obj/effect/overmap/bluespace_rift::partner)
	param(nameof(pair_at_make), pos = 1, apply = PROC_REF(pair_made), keep = FALSE)

/obj/effect/overmap/bluespace_rift/proc/pair(obj/effect/overmap/bluespace_rift/new_partner)
	if(istype(new_partner))
		rel_set(src, nameof(partner), new_partner) // rel_one(back =): the partner names us back

/obj/effect/overmap/bluespace_rift/proc/take_this(atom/movable/AM)
	paused = TRUE
	AM.forceMove(get_turf(src))
	paused = FALSE

/obj/effect/overmap/bluespace_rift/Crossed(atom/movable/AM)
	if(istype(AM, /obj/effect/overmap/visitable/ship) && !paused && partner)
		partner.take_this(AM)
	else
		return ..()

EXTEND_INTERACTIONS(/obj/effect/overmap/bluespace_rift, INTERACT_OBSERVER("Travel", PROC_REF(bluespace_rift_ghost_use)))

/// Old attack_ghost: staff make a partner rift, or the ghost travels through; else the default.
/obj/effect/overmap/bluespace_rift/proc/bluespace_rift_ghost_use(mob/observer/dead/user, obj/item/held, datum/interaction/interaction)
	if(!partner && check_rights_for(user?.client, R_HOLDER))
		var/response = rerun_ask(user, "k42", PROC_REF(bluespace_rift_ghost_use), args, /datum/om/prompt/choice/alert, message = "You appear to be staff. This rift has no exit point. If you want to make one, move to where you want it to go, and click 'Make Here', otherwise click 'Cancel'", title = "Bluespace Rift", choices = list("Cancel","Make Here"))
		if(isnull(response))
			return TRUE
		if(response == "Make Here")
			new type(get_turf(user), src)
		return TRUE
	else if(partner)
		user.forceMove(get_turf(partner))
		to_chat(user, span_notice("Your ghostly form is pulled through the rift!"))
		return TRUE
	return FALSE
