/obj/machinery/optable
	name = "Operating Table"
	desc = "Used for advanced medical procedures."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "table2-idle"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 1
	active_power_usage = 5
	surgery_cleanliness = 100
	throwpass = 1
	var/strapped = 0.0
	var/obj/machinery/computer/operating/computer = null

/// The patient lying on it; the table checks on them every machine frame while there is one.
/obj/machinery/optable/var/mob/living/carbon/human/victim
/obj/machinery/optable/Initialize(mapload)
	. = ..()
	for(var/direction in list(NORTH,EAST,SOUTH,WEST))
		rel_set(src, nameof(computer), locate(/obj/machinery/computer/operating, get_step(src, direction)))
		if(computer)
			rel_set(computer, nameof(computer.table), src)
			break

CAPABILITIES(/obj/machinery/optable)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(victim), wakes_on = list(nameof(victim)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(optable_blast))))
	op("optable_interaction_hand", hand(), ungated(), then(PROC_REF(optable_interaction_hand)))
	op("optable_interaction_drag", item(/mob/living/carbon), gesture(GESTURE_DRAG), label("Lay on table"), then(PROC_REF(optable_interaction_drag)))
	op("optable_interaction_item", item(/obj/item), then(PROC_REF(optable_interaction_item)))
	op("optable_climb_onto", menu(), label("Climb On Table"), then(PROC_REF(optable_climb_onto)))

/// A light blast may knock the table flat.
/obj/machinery/optable/proc/optable_blast(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	if(packet.severity == 3 && prob(25))
		set_density(FALSE)
	return HOOK_DECLINE

/// Old attack_hand (it never reached the machinery gate).
/obj/machinery/optable/proc/optable_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.has_mutation(HULK))
		act_message(user, src, others = span_danger("%U% destroys %T%!"))
		set_density(FALSE)
		spent(src)
	return TRUE

/obj/machinery/optable/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	return FALSE

/obj/machinery/optable/proc/check_victim()
	if(locate(/mob/living/carbon/human, src.loc))
		var/mob/living/carbon/human/M = locate(/mob/living/carbon/human, src.loc)
		// `lying` is only recomputed by update_canmove(); a patient just laid
		// down via take_victim() has resting set but may not be lying yet.
		if(M.lying || M.resting)
			rel_set(src, nameof(victim), M)
			if(M.pulse)
				if(M.stat)
					icon_state = "table2-sleep"
				else
					icon_state = "table2-active"
			else
				icon_state = "table2-dead"
			return 1
	rel_clear(src, nameof(victim))
	icon_state = "table2-idle"
	return 0

/obj/machinery/optable/proc/work_step(datum/act/timer/A)
	if(!check_victim())
		return // check_victim() cleared the victim, which ends the declared work
	if(computer)
		work_start(computer)

/obj/machinery/optable/proc/take_victim(mob/living/carbon/C, mob/living/carbon/user as mob)
	if(C == user)
		act_message(user, src, MSG_SELF("You climb on %T%."), MSG_OTHERS("%U% climbs on %T%."))
	else
		act_message(C, user, others = span_notice("%U% has been laid on \the [src] by %T%."))
	var/mob/puller = C?.pulled_by_mob()
	if(puller)
		puller.stop_pulling()
	C.set_resting(1)
	C.update_canmove() // Sync `lying` now so check_victim() does not race the next Life() tick.
	C.forceMove(get_turf(src))
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/O in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		O.forceMove(src.loc)
	add_fingerprint(user)
	if(ishuman(C))
		var/mob/living/carbon/human/H = C
		rel_set(src, nameof(victim), H)
		if(computer)
			work_start(computer)
		icon_state = H.pulse ? "table2-active" : "table2-idle"
	else
		icon_state = "table2-idle"

/// Old MouseDrop_T.
/obj/machinery/optable/proc/optable_interaction_drag(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/carbon/target = A.held
	if(!istype(target) || !istype(user))
		return OP_DECLINE

	if(!Adjacent(target) || !Adjacent(user))
		return OP_DECLINE

	if(user.incapacitated() || !check_table(target, user))
		return OP_DECLINE

	take_victim(target, user)
	return TRUE

/// Old verb "Climb On Table".
/obj/machinery/optable/proc/optable_climb_onto(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!istype(user) || user.incapacitated() || !check_table(user, user))
		return

	take_victim(user, user)

/// Old attackby. It never called ..(), so every item stops here.
/obj/machinery/optable/proc/optable_interaction_item(datum/act/op/A)
	var/mob/living/carbon/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/grab))
		var/obj/item/grab/G = W
		if(iscarbon(G?.grab_target()) && check_table(G?.grab_target(), user))
			take_victim(G?.grab_target(), user)
			consume(W, user)
	return TRUE

/obj/machinery/optable/proc/check_table(mob/living/carbon/patient, mob/living/user)
	check_victim()
	if(victim && get_turf(victim) == get_turf(src) && (victim.lying || victim.resting))
		to_chat(user, span_warning("\The [src] is already occupied!"))
		return 0
	if(patient?.buckled_to())
		to_chat(user, span_notice("Unbuckle \the [patient] first!"))
		return 0
	return 1

/obj/machinery/optable/relations()
	. = ..()
	. += rel_one(nameof(computer), back = nameof(/obj/machinery/computer/operating::table))
