// Behaviour pins for the timed actions converted in round 2 of the timed-action lane (rewrite/timed), on the harness of
// dq_timed_pin_w8_behaviour.dm (base type /datum/unit_test/dq_timed_pin_w8). The scenes are written from the pre-conversion code
// (git show 1d164d2693 for the file) and run against the ops that replaced it.

// ---- A pAI card: a screwdriver opens the panel, three seconds ----

/datum/unit_test/dq_timed_pin_w8/paicard_open_panel
	duration = 3 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/paicard_open_panel/setup_scene()
	user = person()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, get_step(user, NORTH))
	allocate(/mob/living/silicon/pai, card)
	target = card
	held = hold(/obj/item/tool/screwdriver)

/datum/unit_test/dq_timed_pin_w8/paicard_open_panel/is_done()
	var/obj/item/paicard/card = target
	return !QDELETED(card) && card.panel_open

// ---- A pAI card: a missing power cell is installed from the hand, three seconds ----

/datum/unit_test/dq_timed_pin_w8/paicard_install_cell
	duration = 3 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/paicard_install_cell/setup_scene()
	user = person()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, get_step(user, NORTH))
	card.set_cell(PP_MISSING)
	target = card
	held = hold(/obj/item/paiparts/cell)

/datum/unit_test/dq_timed_pin_w8/paicard_install_cell/is_done()
	var/obj/item/paicard/card = target
	return !QDELETED(card) && card.cell == PP_FUNCTIONAL

/datum/unit_test/dq_timed_pin_w8/paicard_install_cell/extra_pin()
	// a socket that is already filled refuses and nothing starts
	setup_scene()
	var/obj/item/paicard/card = target
	card.set_cell(PP_FUNCTIONAL)
	refused("remove the installed")
	clear_scene()

// ---- A ghost trap: set up from the hand, six seconds ----

/datum/unit_test/dq_timed_pin_w8/ghost_trap_deploy
	duration = 6 SECONDS
	began = "You begin deploying"
	finished = "You have deployed"
	drop_cancels = FALSE // the trap is the target and the held item both; dropping it loses the target

/datum/unit_test/dq_timed_pin_w8/ghost_trap_deploy/setup_scene()
	user = person()
	var/obj/item/ghost_trap/trap = allocate(/obj/item/ghost_trap, run_loc_floor_bottom_left)
	user.put_in_active_hand(trap)
	target = trap
	held = trap

/datum/unit_test/dq_timed_pin_w8/ghost_trap_deploy/is_done()
	var/obj/item/ghost_trap/trap = target
	return !QDELETED(trap) && trap.deployed

// ---- A ghost trap: a deployed trap is deactivated by hand, six seconds ----

/datum/unit_test/dq_timed_pin_w8/ghost_trap_deactivate
	duration = 6 SECONDS
	began = "You begin deactivate"
	finished = "You have deactivated"

/datum/unit_test/dq_timed_pin_w8/ghost_trap_deactivate/setup_scene()
	user = person()
	var/obj/item/ghost_trap/trap = allocate(/obj/item/ghost_trap, get_step(user, NORTH))
	trap.set_deployed(TRUE)
	target = trap
	held = null

/datum/unit_test/dq_timed_pin_w8/ghost_trap_deactivate/is_done()
	var/obj/item/ghost_trap/trap = target
	return !QDELETED(trap) && !trap.deployed
