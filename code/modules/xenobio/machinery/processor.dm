// This is specifically for slimes since we don't have a 'normal' processor now.
// Feel free to rename it if that ever changes.

/obj/machinery/processor
	name = "slime processor"
	desc = "An industrial grinder used to automate the process of slime core extraction.  It can also recycle biomatter."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "processor1"
	density = TRUE
	anchored = TRUE
	var/processing = FALSE // So I heard you like processing.
	var/list/to_be_processed
	var/monkeys_recycled = 0

/obj/item/circuitboard/processor
	name = T_BOARD("slime processor")
	build_path = /obj/machinery/processor

/obj/machinery/processor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/processor_start,
		/datum/interaction/machine_verb/processor_eject,
		/datum/interaction/machine_drag/processor_insert,
	)
	..()

/datum/interaction/machine_hand/ungated/processor_start
	id = "processor_start"
	name = "Start"
	effect = /obj/machinery/processor/proc/interaction_start

/obj/machinery/processor/proc/interaction_start(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(processing)
		to_chat(user, span_warning("The processor is in the process of processing!"))
		return TRUE
	if(length(to_be_processed))
		spawn(1)
			begin_processing()
	else
		to_chat(user, span_warning("The processor is empty."))
		playsound(src, 'sound/machines/buzz-sigh.ogg', 50, 1)
		return TRUE
	return TRUE

// Verb to remove everything.
/datum/interaction/machine_verb/processor_eject
	id = "processor_eject"
	name = "Eject Processor"
	category = INTERACTION_CAT_EJECT
	requires = list(REQ_INTERACTION_REACH, REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now"))
	effect = /obj/machinery/processor/proc/interaction_eject

/obj/machinery/processor/proc/interaction_eject(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || !user.canmove || user.restrained())
		return TRUE
	empty()
	add_fingerprint(user)
	return TRUE

// Ejects all the things out of the machine.
/obj/machinery/processor/proc/empty()
	for(var/atom/movable/AM in to_be_processed)
		LAZYREMOVE(to_be_processed, AM)
		AM.forceMove(get_turf(src))

// Ejects all the things out of the machine.
/obj/machinery/processor/proc/insert(atom/movable/AM, mob/living/user)
	if(!Adjacent(AM))
		return
	if(!can_insert(AM))
		to_chat(user, span_warning("\The [src] cannot process \the [AM] at this time."))
		playsound(src, 'sound/machines/buzz-sigh.ogg', 50, 1)
		return
	LAZYADD(to_be_processed, AM)
	AM.forceMove(src)
	visible_message(span_infoplain(span_bold("\The [user]") + " places [AM] inside \the [src]."))

/obj/machinery/processor/proc/begin_processing()
	if(processing)
		return // Already doing it.
	processing = TRUE
	playsound(src, 'sound/machines/juicer.ogg', 50, 1)
	for(var/atom/movable/AM in to_be_processed)
		extract(AM)
		sleep(1 SECONDS)

	while(monkeys_recycled >= 4)
		new /obj/item/reagent_containers/food/snacks/monkeycube(get_turf(src))
		playsound(src, 'sound/effects/splat.ogg', 50, 1)
		monkeys_recycled -= 4
		sleep(1 SECOND)

	processing = FALSE
	playsound(src, 'sound/machines/ding.ogg', 50, 1)

/obj/machinery/processor/proc/extract(atom/movable/AM)
	if(istype(AM, /mob/living/simple_mob/slime))
		var/mob/living/simple_mob/slime/S = AM
		while(S.cores)
			var/atom/new_core = new S.coretype(get_turf(src))
			playsound(src, 'sound/effects/splat.ogg', 50, 1)
			S.cores--
			sleep(1 SECOND)
		LAZYREMOVE(to_be_processed, S)
		qdel(S)

	if(ishuman(AM))
		var/mob/living/carbon/human/M = AM
		playsound(src, 'sound/effects/splat.ogg', 50, 1)
		LAZYREMOVE(to_be_processed, M)
		qdel(M)
		monkeys_recycled++
		sleep(1 SECOND)

/obj/machinery/processor/proc/can_insert(atom/movable/AM)
	if(istype(AM, /mob/living/simple_mob/slime))
		var/mob/living/simple_mob/slime/S = AM
		if(S.stat != DEAD)
			return FALSE
		return TRUE
	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		if(!istype(H.species, /datum/species/monkey))
			return FALSE
		if(H.stat != DEAD)
			return FALSE
		return TRUE
	return FALSE

/datum/interaction/machine_drag/processor_insert
	id = "processor_insert"
	name = "Insert"
	effect = /obj/machinery/processor/proc/interaction_insert

/obj/machinery/processor/proc/interaction_insert(mob/living/user, atom/movable/dropping, datum/interaction/interaction)
	var/atom/movable/AM = dropping
	if(user.stat || user.incapacitated(INCAPACITATION_DISABLED) || !istype(user))
		return TRUE
	insert(AM, user)
	return TRUE
