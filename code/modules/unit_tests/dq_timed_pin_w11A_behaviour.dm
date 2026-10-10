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

// (the mecha climb-in is not pinned: moved_inside() needs a pilot with a client, which the test world has none of)

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

/// The test floor does not carry TURF_CAN_DIG_SHOVEL, so the click cannot reach the dig: the grave step the dig calls is started directly.
/datum/unit_test/dq_timed_pin_w8/a_dig_grave/start_click()
	test_chat_clear()
	var/turf/T = target
	T.shovel_dig_grave(user, held)

/datum/unit_test/dq_timed_pin_w8/a_dig_grave/is_done()
	return !isnull(locate(/obj/structure/closet/grave/dirthole) in target)

/datum/unit_test/dq_timed_pin_w8/a_dig_grave/clear_scene()
	tidy()
	for(var/obj/structure/closet/grave/dirthole/hole in target)
		qdel(hole)
	target = null
