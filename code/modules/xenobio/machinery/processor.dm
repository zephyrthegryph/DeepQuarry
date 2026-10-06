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
	/// Recycled bodies per monkey cube pressed.
	var/monkeys_per_cube = 4

/obj/item/circuitboard/processor
	name = T_BOARD("slime processor")
	build_path = /obj/machinery/processor

EXTEND_INTERACTIONS(/obj/machinery/processor, \
	INTERACT_HAND_UNGATED("Start", PROC_REF(interaction_start), REQ_FIELD_NOT("processing", "the processor is in the process of processing")), \
	INTERACT_VERB("Eject Processor", PROC_REF(interaction_eject), REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now")), \
	INTERACT_DRAG("Insert", PROC_REF(interaction_insert)), \
)

/obj/machinery/processor/proc/interaction_start(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(length(to_be_processed))
		after(src, 0.1 SECONDS, PROC_REF(begin_processing))
	else
		to_chat(user, span_warning("The processor is empty."))
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
		return TRUE
	return TRUE

// Verb to remove everything.
/obj/machinery/processor/proc/interaction_eject(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || !user.canmove || user.restrained())
		return TRUE
	empty()
	add_fingerprint(user)
	return TRUE

// Ejects all the things out of the machine.
/obj/machinery/processor/proc/empty()
	for(var/atom/movable/AM in to_be_processed)
		rel_remove(src, nameof(to_be_processed), AM)
		AM.forceMove(get_turf(src))

// Ejects all the things out of the machine.
/obj/machinery/processor/proc/insert(atom/movable/AM, mob/living/user)
	if(!Adjacent(AM))
		return
	if(!can_insert(AM))
		to_chat(user, span_warning("\The [src] cannot process \the [AM] at this time."))
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
		return
	rel_add(src, nameof(to_be_processed), AM)
	AM.forceMove(src)
	act_message(user, AM, others = span_infoplain(span_bold("%U%") + " places %T% inside \the [src]."))

/obj/machinery/processor/proc/begin_processing()
	if(processing)
		return // Already doing it.
	processing = TRUE
	play_sfx(src, SFX_MACHINES_JUICER, 2)
	om_task_start(/datum/om/task/slime_processing, src)

/// The processor at work: one thing a second (a core out of a slime, a body processed, or a
/// monkey cube pressed from the recycled bodies) until it is empty.
/datum/om/task/slime_processing
	name = "slime processing"
	steps = list(/obj/machinery/processor/proc/processing_step = 0)
	complete_proc = /obj/machinery/processor/proc/processing_done
	cancel_proc = /obj/machinery/processor/proc/processing_done

/obj/machinery/processor/proc/processing_step(datum/om/task/T)
	var/atom/movable/AM = LAZYACCESS(to_be_processed, 1)
	if(istype(AM, /mob/living/simple_mob/slime))
		var/mob/living/simple_mob/slime/S = AM
		if(S.cores)
			new S.coretype(get_turf(src))
			play_sfx(src, SFX_EFFECTS_SPLAT)
			S.cores--
			return STEP_REPEAT(1 SECOND)
		rel_remove(src, nameof(to_be_processed), S)
		consumed(S, src)
		return STEP_REPEAT(1 SECOND)
	if(ishuman(AM))
		play_sfx(src, SFX_EFFECTS_SPLAT)
		rel_remove(src, nameof(to_be_processed), AM)
		consumed(AM, src)
		monkeys_recycled++
		return STEP_REPEAT(1 SECOND)
	if(AM)
		rel_remove(src, nameof(to_be_processed), AM)
		return STEP_REPEAT(0)
	if(monkeys_recycled >= monkeys_per_cube)
		new /obj/item/reagent_containers/food/snacks/monkeycube(get_turf(src))
		play_sfx(src, SFX_EFFECTS_SPLAT)
		monkeys_recycled -= monkeys_per_cube
		return STEP_REPEAT(1 SECOND)
	return STEP_DONE

/obj/machinery/processor/proc/processing_done(datum/om/task/T)
	processing = FALSE
	play_sfx(src, SFX_MACHINES_DING)

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

/obj/machinery/processor/proc/interaction_insert(mob/living/user, atom/movable/dropping, datum/interaction/interaction)
	var/atom/movable/AM = dropping
	if(user.stat || user.incapacitated(INCAPACITATION_DISABLED) || !istype(user))
		return TRUE
	insert(AM, user)
	return TRUE
