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
	op("bluespace_rift_ghost_use", observer(), label("Travel"), asks(/datum/prompt/choice, fields = list("question" = "You appear to be staff. This rift has no exit point. If you want to make one, move to where you want it to go, and click 'Make Here', otherwise click 'Cancel'", "title" = "Bluespace Rift", "choices" = list("Cancel", "Make Here"), "buttons" = TRUE, "timeout" = 0), step = "k42", when = PROC_REF(staff_may_make_exit)), then(PROC_REF(bluespace_rift_ghost_use)))

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

/// Staff at a rift with no exit are asked whether to make one.
/obj/effect/overmap/bluespace_rift/proc/staff_may_make_exit(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	return !partner && check_rights_for(user?.client, R_HOLDER)

/// Old attack_ghost: staff make a partner rift, or the ghost travels through; else the default.
/obj/effect/overmap/bluespace_rift/proc/bluespace_rift_ghost_use(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	if(!partner && check_rights_for(user?.client, R_HOLDER))
		var/response = A.step_value("k42")
		if(response == "Make Here")
			new type(get_turf(user), src)
		return OP_OK
	else if(partner)
		user.forceMove(get_turf(partner))
		to_chat(user, span_notice("Your ghostly form is pulled through the rift!"))
		return OP_OK
	return OP_DECLINE
