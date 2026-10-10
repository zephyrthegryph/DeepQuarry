// Behaviour pins for the timed actions of group A of round 3 (rewrite/timed3-A): the machinery, mecha, turf and antagonist-ability sites that were
// task_timed / task_start calls and are now ops with wait(). Same harness as dq_timed_pin_w8_behaviour.dm. They were written from the pre-conversion
// code and are meant to hold on the legacy form and on the ops. Sites whose starter is a legacy attack()/afterattack()/ability verb or a prompt answer
// (the changeling absorb, the cult spells and tome, the malf hacks, the mecha equipment, the kiosk's service answer, the pod's consent) cannot be
// started from test_click and are not pinned here.

// ---- A suit cycler: a grabbed victim is put in, two seconds, the grab is spent ----

/datum/unit_test/dq_timed_pin_w8/a_cycler_insert_grab
	duration = 2 SECONDS
	drop_cancels = TRUE
	menu_key = "cycler_insert_grab"

/datum/unit_test/dq_timed_pin_w8/a_cycler_insert_grab/setup_scene()
	user = person()
	var/mob/living/carbon/human/victim = person(get_step(user, NORTH))
	var/obj/machinery/suit_cycler/cycler = allocate(/obj/machinery/suit_cycler, get_step(user, EAST))
	cycler.set_grid_power(TRUE)
	cycler.set_broken_condition(FALSE)
	cycler.set_locked(FALSE)
	var/obj/item/grab/G = allocate(/obj/item/grab, user, victim)
	if(user.get_active_hand() != G)
		user.put_in_active_hand(G)
	target = cycler
	held = G

/datum/unit_test/dq_timed_pin_w8/a_cycler_insert_grab/is_done()
	var/obj/machinery/suit_cycler/cycler = target
	return !QDELETED(cycler) && !isnull(cycler.slot_item(OCCUPANT_SLOT_SUIT_CYCLER))

// ---- The mecha climb in, four seconds: a move cancels, the pilot ends in the pilot slot ----
// (started by the Enter Exosuit menu entry; the item in hand does not matter)

/datum/unit_test/dq_timed_pin_w8/a_mecha_climb_in
	duration = 4 SECONDS
	menu_key = "mecha_enter"

/datum/unit_test/dq_timed_pin_w8/a_mecha_climb_in/setup_scene()
	user = person()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, get_step(user, NORTH))
	target = mech
	held = null

/datum/unit_test/dq_timed_pin_w8/a_mecha_climb_in/is_done()
	var/obj/mecha/mech = target
	return !QDELETED(mech) && mech.slot_item(MECHA_SLOT_PILOT) == user

// ---- A grave: a shovel in grave mode digs a hole, five seconds at normal tool speed ----

/datum/unit_test/dq_timed_pin_w8/a_dig_grave
	duration = 5 SECONDS
	drop_cancels = TRUE
	loss_cancels = FALSE // the turf is the target and cannot be deleted

/datum/unit_test/dq_timed_pin_w8/a_dig_grave/setup_scene()
	user = person()
	var/obj/item/shovel/dig = hold(/obj/item/shovel)
	dig.grave_mode = TRUE
	dig.toolspeed = 1
	target = get_step(user, NORTH)
	held = dig

/datum/unit_test/dq_timed_pin_w8/a_dig_grave/is_done()
	return !isnull(locate(/obj/structure/closet/grave/dirthole) in target)

/datum/unit_test/dq_timed_pin_w8/a_dig_grave/clear_scene()
	tidy()
	for(var/obj/structure/closet/grave/dirthole/hole in target)
		qdel(hole)
	target = null
