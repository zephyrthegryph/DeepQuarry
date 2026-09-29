/obj/machinery/door/airlock/lift
	name = "Elevator Door"
	desc = "Ding."
	req_access = list(ACCESS_MAINT_TUNNELS)
	unacidable = TRUE
	opacity = 0
	autoclose = 0
	glass = 1
	icon = 'icons/obj/doors/doorlift.dmi'

	var/tmp/datum/turbolift/lift
	var/tmp/datum/turbolift_floor/floor

// Leaves its lift's and floor's door lists.

/obj/machinery/door/airlock/lift/bumpopen(mob/user)
	return // No accidental sprinting into open elevator shafts.

/obj/machinery/door/airlock/lift/allowed(mob/M)
	return FALSE //only the lift machinery is allowed to operate this door

/obj/machinery/door/airlock/lift/close(forced=0)
	if(!safe)
		return ..()
	for(var/turf/turf in locs)
		for(var/mob/living/LM in turf)
			if(LM.mob_size <= MOB_TINY)
				var/moved = 0
				for(dir in shuffle(GLOB.cardinal.Copy()))
					var/dest = get_step(LM,dir)
					if(!(locate_within(dest, /obj/machinery/door/airlock/lift)))
						if(LM.Move(dest))
							moved = 1
							act_message(LM, null, others = "%U% scurries away from the closing doors.")
							break
				if(!moved) // nowhere to go....
					LM.gib()
			else // the mob is too big to just move, so we need to give up what we're doing
				audible_message("\The [src]'s motors grind as they quickly reverse direction, unable to safely close.", runemessage = "WRRRRR")
				set_cur_command(null) // the door will just keep trying otherwise
				return 0
	return ..()

// Vore specific code for /obj/machinery/door/airlock/lift

/obj/machinery/door/airlock/lift/emag_act(uses_left, mob/user)
	to_chat(user, span_danger("This door is internally controlled."))
	return 0 // Prevents the cryptographic sequencer from using a charge fruitlessly

/// the lift this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/door/airlock/lift/proc/lift() as /datum/turbolift
	return lift

/// the floor this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/door/airlock/lift/proc/lift_floor() as /datum/turbolift_floor
	return floor

// Interior doors: two-sided with the lift's doors list.
REL_PAIR(/obj/machinery/door/airlock/lift, lift, doors)
REL_PAIR_LIST(/datum/turbolift, doors, lift)
// Exterior doors: a floor lists its doors (airlocks and firedoors) in a one-sided REL_LIST
// (turbolift_floor.dm), and each door names its floor in a one-sided view.
