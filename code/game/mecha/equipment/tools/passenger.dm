/obj/item/mecha_parts/mecha_equipment/tool/passenger
	name = "passenger compartment"
	desc = "A mountable passenger compartment for exosuits. Rather cramped."
	icon_state = "mecha_passenger"
	energy_drain = 10
	range = MECH_MELEE
	equip_cooldown = 20
	var/door_locked = 1
	salvageable = 0
	allow_duplicate = TRUE
	equip_type = EQUIP_HULL

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3).
/datum/om/relation/slot/occupant/mecha_passenger
	holder = /obj/item/mecha_parts/mecha_equipment/tool/passenger
	slot_id = OCCUPANT_SLOT_MECHA_PASSENGER
	name = "passenger compartment"


/obj/item/mecha_parts/mecha_equipment/tool/passenger/destroy()
	for(var/atom/movable/AM in contents_of(src))
		AM.forceMove(get_turf(src))
		to_chat(AM, span_danger("You tumble out of the destroyed [src.name]!"))
	return ..()

/obj/item/mecha_parts/mecha_equipment/tool/passenger/Exit(atom/movable/O)
	return 0

/obj/item/mecha_parts/mecha_equipment/tool/passenger/proc/move_inside(mob/user)
	if (chassis)
		act_message(user, chassis, others = span_notice("%U% starts to climb into %T%."))

	task_start(/datum/task/timed/passenger_boarded, user, src, receiver = src)

/obj/item/mecha_parts/mecha_equipment/tool/passenger/proc/forced_out(mob/user, mob/passenger_occupant)
	act_message(user, src, MSG_SELF(span_notice("You open the hatch on %T% and remove [passenger_occupant]!")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " opens the hatch on %T% and removes [passenger_occupant]!")))
	go_out()
	mecha_log_message("[passenger_occupant] was removed.")

/datum/task/timed/passenger_boarded
	duration = 4 SECONDS
	complete_proc = /obj/item/mecha_parts/mecha_equipment/tool/passenger/proc/boarded
	fail_message = span_info("You stop entering the exosuit.")

/obj/item/mecha_parts/mecha_equipment/tool/passenger/proc/boarded(datum/task/timed/passenger_boarded/task)
	var/mob/user = task.actor
	if(!src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER))
		if(!move_into(src, OCCUPANT_SLOT_MECHA_PASSENGER, user))
			return
		src.mecha_log_message("[user] boarded.")
		occupant_message("[user] boarded.")
	else if(src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER) != user)
		to_chat(user, span_warning("[src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)] was faster. Try harder next time, loser."))

/obj/item/mecha_parts/mecha_equipment/tool/passenger/container_resist(mob/living)
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)
	if(occupant == living)
		eject()

/obj/item/mecha_parts/mecha_equipment/tool/passenger/verb/eject()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)
	set name = "Eject"
	set category = VERB_CAT_EXOSUIT_INTERFACE
	set src = usr.loc
	set popup_menu = 0

	if(usr != occupant)
		return
	if(door_locked)
		to_chat(occupant, span_notice("\The [src] is locked! You begin operating the emergency unlock mechanism. This will take one minute."))
		after(src, 1 MINUTE, PROC_REF(emergency_unlocked), with = list(occupant))
		return
	passenger_disembark(occupant)

/obj/item/mecha_parts/mecha_equipment/tool/passenger/proc/emergency_unlocked(mob/living/carbon/occupant)
	if(occupant != src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)) //Check if someone's released/replaced/bombed him already
		return
	if(door_locked)
		door_locked = FALSE
		occupant_message("Passenger compartment hatch unlocked.")
		if (chassis)
			chassis.visible_message(span_infoplain("The hatch on \the [chassis] unlocks."), span_hear("You hear something latching."))
	passenger_disembark(occupant)

/obj/item/mecha_parts/mecha_equipment/tool/passenger/proc/passenger_disembark(mob/living/carbon/occupant)
	to_chat(occupant, span_info("You climb out from \the [src]."))
	go_out()
	occupant_message("[occupant] disembarked.")
	src.mecha_log_message("[occupant] disembarked.")
	add_fingerprint(occupant)

/obj/item/mecha_parts/mecha_equipment/tool/passenger/proc/go_out()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)
	if(!occupant)
		return
	slot_remove(occupant, get_turf(src))
	return

/obj/item/mecha_parts/mecha_equipment/tool/passenger/attach()
	..()

/obj/item/mecha_parts/mecha_equipment/tool/passenger/detach()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)
	if(occupant)
		occupant_message("Unable to detach [src] - equipment occupied.")
		return

	..()

/obj/item/mecha_parts/mecha_equipment/tool/passenger/get_equip_info()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)
	return "[..()] <br />[occupant? "\[Occupant: [occupant]\]|" : ""]Exterior Hatch: <a href='byond://?src=\ref[src];toggle_lock=1'>Toggle Lock</a>"

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/passenger)
	op("toggle_lock", topic("toggle_lock"), then(PROC_REF(topic_toggle_lock)))

/obj/item/mecha_parts/mecha_equipment/tool/passenger/proc/topic_toggle_lock(datum/act/op/A)
	door_locked = !door_locked
	occupant_message("Passenger compartment hatch [door_locked? "locked" : "unlocked"].")
	if (chassis)
		chassis.visible_message("The hatch on \the [chassis] [door_locked? "locks" : "unlocks"].", "You hear something latching.")


#define LOCKED 1
#define OCCUPIED 2

/// Requirement for the mech's "Enter Passenger Compartment" Menu entry (old verbs |= on attach / -= on detach).
/obj/mecha/proc/pred_mecha_has_passenger_bay(mob/actor, atom/target, obj/item/held)
	return !!(locate(/obj/item/mecha_parts/mecha_equipment/tool/passenger) in slot_contents())

/// Requirement for climbing into a passenger compartment: TRUE, or why the user can't.
/obj/mecha/proc/can_enter_passenger(mob/user, atom/target, obj/item/held)
	if(user.stat || !ishuman(user) || !user.Adjacent(src))
		return TRUE // the effect declines these silently
	if(!isturf(user.loc))
		return "you can't reach the passenger compartment from here"
	if(iscarbon(user))
		var/mob/living/carbon/C = user
		if(C.get_equipped_item(SLOT_ID_HANDCUFFED))
			return "kinda hard to climb in while handcuffed, don't you think"
	if(isliving(user))
		var/mob/living/L = user
		if(L.has_buckled_mobs())
			return "you have other entities attached to yourself, remove them first"
	return TRUE

/// Old verb "Enter Passenger Compartment" (added to the chassis while a compartment was attached).
/obj/mecha/proc/move_inside_passenger(mob/user, obj/item/held, datum/interaction/interaction)

	//check that user can climb in
	if (user.stat || !ishuman(user))
		return

	if (!user.Adjacent(src))
		return

	//search for a valid passenger compartment
	var/feedback = 0 //for nicer user feedback
	for(var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P in contents_of(src))
		if (P?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER))
			feedback |= OCCUPIED
			continue
		if (P.door_locked)
			feedback |= LOCKED
			continue

		//found a boardable compartment
		P.move_inside(user)
		return

	//didn't find anything
	switch (feedback)
		if (OCCUPIED)
			to_chat(user, span_danger("The passenger compartment is already occupied!"))
		if (LOCKED)
			to_chat(user, span_warning("The passenger compartment hatch is locked!"))
		if (OCCUPIED|LOCKED)
			to_chat(user, span_danger("All of the passenger compartments are already occupied or locked!"))
		if (0)
			to_chat(user, span_warning("\The [src] doesn't have a passenger compartment."))

#undef LOCKED
#undef OCCUPIED
