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

TRACKED(/obj/machinery/processor, processing)

CAPABILITIES(/obj/machinery/processor)
	every(1 SECOND, then(PROC_REF(processing_step)), when = nameof(processing))
	op("start", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Start"), needs(req_is(nameof(processing), FALSE, because = MSG(processor/processing))), then(PROC_REF(interaction_start)))
	op("eject", menu(), label("Eject Processor"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_eject)))
	op("insert", item(/atom/movable), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Insert"), then(PROC_REF(interaction_insert)))

MSG_DEF_SELF(processor/processing, "the processor is in the process of processing")

/obj/machinery/processor/proc/interaction_start(datum/act/op/A)
	var/mob/living/user = A.actor
	if(length(to_be_processed))
		after(src, 0.1 SECONDS, PROC_REF(begin_processing))
	else
		to_chat(user, span_warning("The processor is empty."))
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
		return OP_OK
	return OP_OK

// Verb to remove everything.
/obj/machinery/processor/proc/interaction_eject(datum/act/op/A)
	var/mob/user = A.actor
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
	set_processing(TRUE)
	play_sfx(src, SFX_MACHINES_JUICER, 2)
	log_game("slime processor [src] ([x],[y],[z]) starts with [length(to_be_processed)] things inside")
	processing_step() // the first step is at once; every() (the block above) does the rest, a second apart

/// The processor at work: one thing a second (a core out of a slime, a body processed, or a
/// monkey cube pressed from the recycled bodies) until it is empty.
/obj/machinery/processor/proc/processing_step(datum/act/timer/A)
	while(processing)
		var/atom/movable/AM = LAZYACCESS(to_be_processed, 1)
		if(istype(AM, /mob/living/simple_mob/slime))
			var/mob/living/simple_mob/slime/S = AM
			if(S.cores)
				new S.coretype(get_turf(src))
				play_sfx(src, SFX_EFFECTS_SPLAT)
				S.cores--
				return
			rel_remove(src, nameof(to_be_processed), S)
			consumed(S, src)
			return
		if(ishuman(AM))
			play_sfx(src, SFX_EFFECTS_SPLAT)
			rel_remove(src, nameof(to_be_processed), AM)
			consumed(AM, src)
			monkeys_recycled++
			return
		if(AM)
			rel_remove(src, nameof(to_be_processed), AM)
			continue // not a body: dropped at once, the next thing is looked at in the same step
		if(monkeys_recycled >= monkeys_per_cube)
			new /obj/item/reagent_containers/food/snacks/monkeycube(get_turf(src))
			play_sfx(src, SFX_EFFECTS_SPLAT)
			monkeys_recycled -= monkeys_per_cube
			return
		processing_done()
		return

/obj/machinery/processor/proc/processing_done()
	set_processing(FALSE)
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

/obj/machinery/processor/proc/interaction_insert(datum/act/op/A)
	var/mob/living/user = A.actor
	var/atom/movable/dropping = A.held
	var/atom/movable/AM = dropping
	if(user.stat || user.incapacitated(INCAPACITATION_DISABLED) || !istype(user))
		return OP_OK
	insert(AM, user)
	return OP_OK
