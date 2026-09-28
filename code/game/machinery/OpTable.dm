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
	var/mob/living/carbon/human/victim = null
	var/strapped = 0.0
	var/obj/machinery/computer/operating/computer = null

/obj/machinery/optable/Initialize(mapload)
	. = ..()
	for(var/direction in list(NORTH,EAST,SOUTH,WEST))
		computer = locate(/obj/machinery/computer/operating, get_step(src, direction))
		if(computer)
			computer.table = src
			break

/obj/machinery/optable/ex_act(severity)
	if(severity == 3 && prob(25))
		density = FALSE
	return ..()

EXTEND_INTERACTIONS(/obj/machinery/optable, \
	INTERACT_HAND_UNGATED(null, PROC_REF(optable_interaction_hand)), \
	INTERACT_DRAG("Lay on table", PROC_REF(optable_interaction_drag)), \
	INTERACT_ITEM(null, PROC_REF(optable_interaction_item)), \
	INTERACT_VERB("Climb On Table", PROC_REF(optable_climb_onto)), \
)

/// Old attack_hand (it never reached the machinery gate).
/obj/machinery/optable/proc/optable_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.has_mutation(HULK))
		visible_message(span_danger("\The [user] destroys \the [src]!"))
		density = FALSE
		qdel(src)
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
			victim = M
			if(M.pulse)
				if(M.stat)
					icon_state = "table2-sleep"
				else
					icon_state = "table2-active"
			else
				icon_state = "table2-dead"
			return 1
	victim = null
	icon_state = "table2-idle"
	return 0

/obj/machinery/optable/machine_step()
	if(!check_victim())
		return PROCESS_KILL
	if(computer)
		MACHINE_WAKE(computer)

/obj/machinery/optable/proc/take_victim(mob/living/carbon/C, mob/living/carbon/user as mob)
	if(C == user)
		user.visible_message("[user] climbs on \the [src].","You climb on \the [src].")
	else
		visible_message(span_notice("\The [C] has been laid on \the [src] by [user]."))
	var/mob/puller = C?.pulled_by_mob()
	if(puller)
		puller.stop_pulling()
	C.resting = 1
	C.update_canmove() // Sync `lying` now so check_victim() does not race the next Life() tick.
	C.forceMove(get_turf(src))
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/O in contents_of(src)) // ALLOW(latent): materialized above
		O.forceMove(src.loc)
	add_fingerprint(user)
	if(ishuman(C))
		var/mob/living/carbon/human/H = C
		victim = H
		MACHINE_WAKE(src)
		if(computer)
			MACHINE_WAKE(computer)
		icon_state = H.pulse ? "table2-active" : "table2-idle"
	else
		icon_state = "table2-idle"

/// Old MouseDrop_T.
/obj/machinery/optable/proc/optable_interaction_drag(mob/living/user, mob/living/carbon/target, datum/interaction/interaction)
	if(!istype(target) || !istype(user))
		return FALSE

	if(!Adjacent(target) || !Adjacent(user))
		return FALSE

	if(user.incapacitated() || !check_table(target, user))
		return FALSE

	take_victim(target, user)
	return TRUE

/// Old verb "Climb On Table".
/obj/machinery/optable/proc/optable_climb_onto(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!istype(user) || user.incapacitated() || !check_table(user, user))
		return

	take_victim(user, user)

/// Old attackby. It never called ..(), so every item stops here.
/obj/machinery/optable/proc/optable_interaction_item(mob/living/carbon/user, obj/item/W, datum/interaction/interaction)
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

DECLARE_REF(/obj/machinery/optable, "victim", HELD, null)
DECLARE_REF(/obj/machinery/optable, "computer", PAIR, "table")
