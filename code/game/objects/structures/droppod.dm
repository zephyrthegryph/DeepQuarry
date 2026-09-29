/obj/structure/drop_pod
	name = "drop pod"
	desc = "Standard Commonwealth drop pod. There are file marks where the serial number should be, however."
	icon = 'icons/obj/structures/droppod.dmi'
	icon_state = "pod"
	density = TRUE
	anchored = TRUE

	var/polite = FALSE // polite ones don't violently murder everything
	var/finished = FALSE
	var/datum/gas_mixture/pod_air/air

/obj/structure/drop_pod/polite
	polite = TRUE

/obj/structure/drop_pod/Initialize(mapload, atom/movable/A, auto_open = FALSE)
	. = ..()
	if(A)
		A.forceMove(src) // helo
		podfall(auto_open)
	air = new

DECLARE_REF(/obj/structure/drop_pod, "air", OWNED, null)

/obj/structure/drop_pod/proc/podfall(auto_open)
	var/turf/T = get_turf(src)
	if(!T)
		WARNING("Drop pod wasn't spawned on a turf")
		return

	moveToNullspace()
	icon_state = "[initial(icon_state)]_falling"

	// Show warning on 3x3 area centred on our drop spot
	var/list/turfs_nearby = block(get_step(T, SOUTHWEST), get_step(T, NORTHEAST))
	for(var/turf/TN in turfs_nearby)
		new /obj/effect/temporary_effect/shuttle_landing(TN)

	om_after(src, 4 SECONDS, PROC_REF(do_fall), auto_open, T)

/obj/structure/drop_pod/proc/do_fall(auto_open, turf/T)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// Wheeeeeee
	plane = ABOVE_PLANE
	pixel_y = 300
	alpha = 0
	forceMove(T)
	play_sfx(T, SFX_EFFECTS_DROPPOD)
	animate(src, pixel_y = 0, time = 3 SECONDS, easing = SINE_EASING|EASE_OUT)
	animate(src, alpha = 255, time = 1 SECOND, flags = ANIMATION_PARALLEL)
	filters += filter(type="drop_shadow", x=-64, y=100, size=10)
	animate(filters[filters.len], x=0, y=0, size=0, time=3 SECONDS, flags=ANIMATION_PARALLEL, easing=SINE_EASING|EASE_OUT)
	om_after(src, 2 SECONDS, PROC_REF(after_fall), auto_open, T)

/obj/structure/drop_pod/proc/after_fall(auto_open, turf/T)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	new /obj/effect/effect/smoke(T)
	T.hotspot_expose(900)
	om_after(src, 1 SECOND, PROC_REF(on_impact), auto_open, T)

/obj/structure/drop_pod/proc/on_impact(auto_open, turf/T)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	filters = null

	// CRONCH
	play_sfx(src, SFX_EFFECTS_METEORIMPACT, 1.25)
	if(!polite)
		for(var/atom/A in view(1, T))
			if(A == src)
				continue
			A.ex_act(2)
	else
		for(var/turf/simulated/floor/F in view(1, T))
			F.burn_tile(900)

	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(O == src)
			continue
		qdel(O)
	for(var/mob/living/L in turf_contents_of_type(T, /mob/living))
		L.gib()

	// Landed! Simmer
	plane = initial(plane)
	icon_state = "[initial(icon_state)]"

	if(auto_open)
		om_after(src, 2 SECONDS, PROC_REF(open_pod), TRUE)
	else
		for(var/mob/M in contents_of(src))
			to_chat(M, span_danger("You've landed! Open the hatch if you think it's safe! \The [src] has enough air to last for a while..."))

/obj/structure/drop_pod/proc/open_pod(dropped)
	if(dropped)
		visible_message("\The [src] pops open!")
	if(finished)
		return
	icon_state = "[initial(icon_state)]_open"
	play_sfx(src, SFX_EFFECTS_MAGNETCLAMP)
	for(var/atom/movable/AM in contents_of(src))
		AM.forceMove(loc)
		AM.set_dir(SOUTH) // cus
	QDEL_NULL(air)
	finished = TRUE

/obj/structure/drop_pod/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/drop_pod_open,
	)
	..()

/// Old attack_hand: open the pod.
/datum/interaction/entry_hand/drop_pod_open
	id = "drop_pod_open"
	name = "Open"
	effect = /obj/structure/drop_pod/proc/interaction_open

/obj/structure/drop_pod/proc/interaction_open(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(istype(user) && (Adjacent(user) || (is_in_holder(user, src))) && !user.incapacitated())
		if(finished)
			to_chat(user, span_warning("Nothing left to do with it now. Maybe you can break it down into materials."))
		else
			open_pod()
			act_message(user, src, MSG_SELF(span_infoplain("You open %T%!")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " opens %T%!")))
	return TRUE

/obj/structure/drop_pod/wrench_act(mob/user, obj/item/O)
	if(!finished)
		to_chat(user, span_warning("\The [src] hasn't been opened yet. Do that first."))
		return TRUE
	to_chat(user, span_notice("You start breaking down \the [src]."))
	om_task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(wrench_act_timed_done), done_args = list(user, O))
	return TRUE

/obj/structure/drop_pod/proc/wrench_act_timed_done(mob/user, obj/item/O)
	playsound(user, O.usesound, 50, 1)
	replace_with(src, /obj/item/stack/material/plasteel, 10)

/obj/structure/drop_pod/return_air()
	return return_air_for_internal_lifeform()

/obj/structure/drop_pod/return_air_for_internal_lifeform()
	return air

// This is about 0.896m^3 of atmosphere, which is enough to last for quite a while.
// was XGM /datum/gas_mixture subtype with `total_moles =` and
// `gas = list(...)`. LINDA stores gases in `gases[/datum/gas/X][MOLES]` and
// total_moles is computed. Re-shape as adjust_gas calls in New().
/datum/gas_mixture/pod_air
	initial_volume = 2500

/datum/gas_mixture/pod_air/New()
	. = ..()
	set_temperature(T20C) // arena default is TCMB; set the intended initial temperature
	adjust_gas(GAS_O2, 21) // literal "oxygen" doesn't match LINDA gas IDs; GAS_O2 is "o2"
	adjust_gas(GAS_N2, 79)
