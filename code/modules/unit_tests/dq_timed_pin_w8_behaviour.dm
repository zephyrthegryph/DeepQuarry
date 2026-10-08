// Behaviour pins for the timed actions of code/game and code/modules (worker B, wave 3), recorded on the legacy task_timed / task_start forms before
// they become ops with wait(). Same harness as dq_timed_pin_w5_behaviour.dm: every pin drives the real click path and records the duration (not done a
// second before, done a second after), the start message, what a move, a dropped held item or a lost target does, what completion does and says, and
// a refusal. A conversion keeps every assertion; a difference is a documented class in doc/rewrite/intended_changes.md.

/datum/unit_test/dq_timed_pin_w8
	abstract_type = /datum/unit_test/dq_timed_pin_w8
	parent_type = /datum/unit_test/dq_timed_pin
	/// The actor of the current scene.
	var/mob/living/carbon/human/user
	/// The target of the current scene.
	var/atom/target
	/// What the actor holds in the current scene (null: a bare hand).
	var/obj/item/held
	/// The action's length in deciseconds.
	var/duration = 0
	/// A text the start message contains (null: it says nothing).
	var/began
	/// A text the finishing message contains (null: it says nothing).
	var/finished
	/// TRUE when dropping the held item cancels the action.
	var/drop_cancels = FALSE
	/// TRUE when deleting the target must be checked (its loss cancels).
	var/loss_cancels = TRUE
	/// The key of a context-menu op the scene starts (null: a click).
	var/menu_key

/// Builds a fresh actor, target and held item in `user`, `target` and `held`.
/datum/unit_test/dq_timed_pin_w8/proc/setup_scene()
	return

/// TRUE once the action has had its effect.
/datum/unit_test/dq_timed_pin_w8/proc/is_done()
	return FALSE

/// What an action leaves on the floor (its products) belongs to the test, so the leak check does not count it.
/datum/unit_test/dq_timed_pin_w8/proc/tidy()
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		own_turf_contents(T)
	forget_ghosts()

/// A mob that still has a ckey when it is deleted leaves an observer behind: take the ckeys off.
/datum/unit_test/dq_timed_pin_w8/proc/forget_ghosts()
	for(var/mob/living/carbon/human/H in range(3, run_loc_floor_bottom_left))
		H.ckey = null

/// Takes the scene down so the next one starts clean.
/datum/unit_test/dq_timed_pin_w8/proc/clear_scene()
	tidy()
	if(target && !QDELETED(target))
		qdel(target)
	target = null

/// Starts the action as the pin does: the held item (or a bare hand) clicked on the target, or the menu's op.
/datum/unit_test/dq_timed_pin_w8/proc/start_click()
	test_chat_clear()
	if(menu_key)
		test_menu(user, target, menu_key)
		return
	test_click(user, target, held)

/// The held item of the scene, put in the actor's active hand.
/datum/unit_test/dq_timed_pin_w8/proc/hold(path, ...)
	var/obj/item/I = allocate(path, run_loc_floor_bottom_left)
	user.put_in_active_hand(I)
	return I

/// A second person on the actor's tile, for a patient or a victim.
/datum/unit_test/dq_timed_pin_w8/proc/other()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/datum/unit_test/dq_timed_pin_w8/run_pin()
	// the length, the start message and the finish
	setup_scene()
	start_click()
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	var/declared = declared_duration(T)
	TEST_ASSERT(isnull(declared) || declared == duration, "it lasts as long as it should")
	if(began)
		TEST_ASSERT(said(user, began), "it says it began")
	TEST_ASSERT(!is_done(), "nothing is done at the start")
	test_time(duration - 1 SECOND)
	TEST_ASSERT(!is_done(), "not done a second before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(is_done(), "done a second after the end")
	if(finished)
		TEST_ASSERT(said(user, finished), "it says it finished")
	clear_scene()
	// a move cancels
	setup_scene()
	start_click()
	T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action again")
	test_time(round(duration / 2))
	user.forceMove(get_step(user, EAST))
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(!is_done(), "moving cancels: nothing is done")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
	clear_scene()
	// a dropped held item cancels
	if(drop_cancels)
		setup_scene()
		start_click()
		T = running(user)
		TEST_ASSERT(!isnull(T), "the click starts a timed action a third time")
		user.drop_from_inventory(held)
		test_time(duration + 2 SECONDS)
		TEST_ASSERT(!is_done(), "dropping the held item cancels: nothing is done")
		TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
		clear_scene()
	// a lost target cancels
	if(loss_cancels)
		setup_scene()
		start_click()
		T = running(user)
		TEST_ASSERT(!isnull(T), "the click starts a timed action a last time")
		qdel(target)
		test_time(duration + 2 SECONDS)
		TEST_ASSERT(was_cancelled(T, user), "deleting the target cancels the action")
		clear_scene()
	extra_pin()
	tidy()

/// Pins of one type's own (a refusal, a second worker).
/datum/unit_test/dq_timed_pin_w8/proc/extra_pin()
	return

/// A click that must start nothing: checks it and that `needle` was said (when given).
/datum/unit_test/dq_timed_pin_w8/proc/refused(needle = null)
	start_click()
	TEST_ASSERT_NULL(running(user), "a refused click starts nothing")
	if(needle)
		TEST_ASSERT(said(user, needle), "and the actor is told so")

// ---- A DNA injector: used on somebody else, five seconds, the injector is spent ----

/datum/unit_test/dq_timed_pin_w8/dna_injector
	duration = 5 SECONDS
	drop_cancels = TRUE
	loss_cancels = FALSE // legacy: the injector was the task's target, so losing the patient cancelled nothing

/datum/unit_test/dq_timed_pin_w8/dna_injector/setup_scene()
	user = person()
	target = person(get_step(user, NORTH))
	held = hold(/obj/item/dnainjector)

/datum/unit_test/dq_timed_pin_w8/dna_injector/is_done()
	return QDELETED(held)

/datum/unit_test/dq_timed_pin_w8/dna_injector/extra_pin()
	setup_scene()
	start_click()
	test_click(user, target, held)
	TEST_ASSERT_EQUAL(running_count(user), 1, "a second click while it works starts nothing more")
	test_time(duration + 2 SECONDS)
	clear_scene()

// ---- A mop: a dirty tile cleaned with a wet mop ----

/datum/unit_test/dq_timed_pin_w8/mop_decal
	duration = 4 SECONDS
	drop_cancels = TRUE
	loss_cancels = FALSE // legacy: the task's target was the tile under the decal

/datum/unit_test/dq_timed_pin_w8/mop_decal/setup_scene()
	user = person()
	target = allocate(/obj/effect/decal/cleanable/dirt, run_loc_floor_bottom_left)
	held = hold(/obj/item/mop)
	held.reagents.add_reagent(REAGENT_ID_WATER, 10)

/datum/unit_test/dq_timed_pin_w8/mop_decal/is_done()
	return held.reagents.total_volume < 10 // one unit goes on the tile when it is washed

/datum/unit_test/dq_timed_pin_w8/mop_decal/extra_pin()
	// a dry mop starts nothing
	setup_scene()
	held.reagents.clear_reagents()
	refused()
	clear_scene()
	// the bare floor under the user is cleaned the same way
	setup_scene()
	target = get_turf(user)
	start_click()
	TEST_ASSERT(!isnull(running(user)), "the floor itself can be mopped")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(is_done(), "and one unit goes on it")
	target = null
	tidy()

// ---- Plastic explosive: planted on a structure ----

/datum/unit_test/dq_timed_pin_w8/plastique_plant
	duration = 5 SECONDS
	began = "Planting explosives"
	finished = "Bomb has been planted"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/plastique_plant/setup_scene()
	user = person()
	target = allocate(/obj/structure/girder, run_loc_floor_bottom_left)
	held = hold(/obj/item/plastique/wbt_probe)

/datum/unit_test/dq_timed_pin_w8/plastique_plant/is_done()
	return isnull(held.loc) // the charge leaves the hand for nullspace and waits on the target

/datum/unit_test/dq_timed_pin_w8/plastique_plant/extra_pin()
	// a person is not a place for it
	setup_scene()
	target = person(get_step(user, NORTH))
	refused()
	clear_scene()

// ---- Paper: wipes the lipstick off somebody else's mouth ----

/datum/unit_test/dq_timed_pin_w8/paper_wipe
	duration = 1 SECOND
	began = "You begin to wipe off"
	finished = "You wipe off"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/paper_wipe/setup_scene()
	user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = O_MOUTH
	var/mob/living/carbon/human/patient = person(get_step(user, NORTH))
	patient.set_lip_style("red")
	target = patient
	held = hold(/obj/item/paper)

/datum/unit_test/dq_timed_pin_w8/paper_wipe/is_done()
	var/mob/living/carbon/human/patient = target
	return !QDELETED(patient) && isnull(patient.lip_style)

/datum/unit_test/dq_timed_pin_w8/paper_wipe/extra_pin()
	// aimed at the eyes it only shows the paper, at once
	setup_scene()
	user.zone_sel.selecting = O_EYES
	refused()
	var/mob/living/carbon/human/patient = target
	TEST_ASSERT(!isnull(patient.lip_style), "and wipes nothing")
	clear_scene()

// ---- A ladder: deconstructed with a lit welder ----

/datum/unit_test/dq_timed_pin_w8/ladder_deconstruct
	duration = 2 SECONDS
	began = "You start to deconstruct"
	finished = "You deconstruct"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/ladder_deconstruct/setup_scene()
	user = person()
	target = allocate(/obj/structure/ladder, run_loc_floor_bottom_left)
	var/obj/item/weldingtool/W = hold(/obj/item/weldingtool)
	W.reagents.add_reagent(REAGENT_ID_FUEL, W.max_fuel)
	W.setWelding(TRUE)
	held = W

/datum/unit_test/dq_timed_pin_w8/ladder_deconstruct/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w8/ladder_deconstruct/extra_pin()
	// a welder that is not lit does nothing
	setup_scene()
	var/obj/item/weldingtool/W = held
	W.setWelding(FALSE)
	start_click()
	TEST_ASSERT_NULL(running(user), "an unlit welder starts nothing")
	clear_scene()

// ---- A maintenance panel: welded to or cut off the wall ----

/datum/unit_test/dq_timed_pin_w8/panel_weld
	duration = 2 SECONDS
	began = "You begin to cut"
	finished = "You cut the"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/panel_weld/setup_scene()
	user = person()
	target = allocate(/obj/structure/window/maintenance_panel, run_loc_floor_bottom_left)
	var/obj/item/weldingtool/W = hold(/obj/item/weldingtool)
	W.reagents.add_reagent(REAGENT_ID_FUEL, W.max_fuel)
	W.setWelding(TRUE)
	held = W

/datum/unit_test/dq_timed_pin_w8/panel_weld/is_done()
	var/obj/structure/window/maintenance_panel/P = target
	return !QDELETED(P) && !P.anchored

// ---- A smart magazine: a cell put in, and taken out by hand ----

/datum/unit_test/dq_timed_pin_w8/smartmag_cell_in
	duration = 2.5 SECONDS
	began = "You begin inserting"
	finished = "You install"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/smartmag_cell_in/setup_scene()
	user = person()
	target = allocate(/obj/item/ammo_magazine/smart, run_loc_floor_bottom_left)
	held = hold(/obj/item/cell/device)

/datum/unit_test/dq_timed_pin_w8/smartmag_cell_in/is_done()
	var/obj/item/ammo_magazine/smart/M = target
	return !QDELETED(M) && !isnull(M.attached_cell)

/datum/unit_test/dq_timed_pin_w8/smartmag_cell_in/extra_pin()
	// a magazine that has a cell takes no second one
	setup_scene()
	var/obj/item/ammo_magazine/smart/M = target
	var/obj/item/cell/device/C = allocate(/obj/item/cell/device, run_loc_floor_bottom_left)
	C.forceMove(M)
	rel_set(M, nameof(/obj/item/ammo_magazine/smart::attached_cell), C)
	refused("already has a")
	clear_scene()

/datum/unit_test/dq_timed_pin_w8/smartmag_cell_out
	duration = 4 SECONDS
	began = "You struggle to remove"
	finished = "You remove"

/datum/unit_test/dq_timed_pin_w8/smartmag_cell_out/setup_scene()
	user = person()
	var/obj/item/ammo_magazine/smart/M = allocate(/obj/item/ammo_magazine/smart, run_loc_floor_bottom_left)
	var/obj/item/cell/device/C = allocate(/obj/item/cell/device, run_loc_floor_bottom_left)
	C.forceMove(M)
	rel_set(M, nameof(/obj/item/ammo_magazine/smart::attached_cell), C)
	user.put_in_inactive_hand(M)
	target = M
	held = null

/datum/unit_test/dq_timed_pin_w8/smartmag_cell_out/is_done()
	var/obj/item/ammo_magazine/smart/M = target
	return !QDELETED(M) && isnull(M.attached_cell)

// ---- A hardsuit module: mended with cable (only a badly damaged one gets as far as the work, and the work does nothing) ----

/datum/unit_test/dq_timed_pin_w8/rig_module_cable
	duration = 3 SECONDS
	began = "You start mending"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/rig_module_cable/setup_scene()
	user = person()
	var/obj/item/rig_module/M = allocate(/obj/item/rig_module, run_loc_floor_bottom_left)
	M.damage = 1
	target = M
	var/obj/item/stack/cable_coil/C = hold(/obj/item/stack/cable_coil)
	C.amount = 10
	held = C

/datum/unit_test/dq_timed_pin_w8/rig_module_cable/is_done()
	// legacy: mend_with_cable only acts when damage != 1, so a module that got this far is not changed and the cable is not used
	var/obj/item/rig_module/M = target
	var/obj/item/stack/cable_coil/C = held
	return !QDELETED(M) && M.damage == 1 && C.get_amount() == 10

/datum/unit_test/dq_timed_pin_w8/rig_module_cable/extra_pin()
	setup_scene()
	var/obj/item/rig_module/M = target
	M.damage = 0
	refused("no damage to mend")
	M.damage = 2
	refused("crude tools")
	var/obj/item/stack/cable_coil/C = held
	C.amount = 3
	M.damage = 1
	refused("five units of cable")
	clear_scene()

// ---- A tape roll: eyes or mouth taped (here one's own: a firm grip is not needed on oneself) ----

/datum/unit_test/dq_timed_pin_w8/tape_eyes
	duration = 3 SECONDS
	drop_cancels = TRUE
	loss_cancels = FALSE // legacy: the task's target was the roll

/datum/unit_test/dq_timed_pin_w8/tape_eyes/setup_scene()
	user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = O_EYES
	user.set_use_stance(I_DISARM) // the roll refuses the help stance
	target = user
	held = hold(/obj/item/tape_roll)

/datum/unit_test/dq_timed_pin_w8/tape_eyes/is_done()
	return istype(user.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses/blindfold/tape)

/datum/unit_test/dq_timed_pin_w8/tape_eyes/extra_pin()
	// eyes that are already covered are told so
	setup_scene()
	var/obj/item/clothing/glasses/sunglasses/S = allocate(/obj/item/clothing/glasses/sunglasses, run_loc_floor_bottom_left)
	TEST_ASSERT(user.equip_to_slot_if_possible(S, SLOT_ID_EYES, disable_warning = TRUE), "the glasses go on")
	refused("already wearing something on their eyes")
	target = null
	tidy()

/datum/unit_test/dq_timed_pin_w8/tape_mouth
	duration = 3 SECONDS
	drop_cancels = TRUE
	loss_cancels = FALSE

/datum/unit_test/dq_timed_pin_w8/tape_mouth/setup_scene()
	user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = O_MOUTH
	user.set_use_stance(I_DISARM)
	target = user
	held = hold(/obj/item/tape_roll)

/datum/unit_test/dq_timed_pin_w8/tape_mouth/is_done()
	return istype(user.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/muzzle/tape)

/datum/unit_test/dq_timed_pin_w8/tape_mouth/extra_pin()
	setup_scene()
	var/obj/item/clothing/mask/gas/M = allocate(/obj/item/clothing/mask/gas, run_loc_floor_bottom_left)
	TEST_ASSERT(user.equip_to_slot_if_possible(M, SLOT_ID_MASK, disable_warning = TRUE), "the mask goes on")
	refused("already wearing a mask")
	target = null
	tidy()

// ---- Mail: a blank envelope sealed, opened and filled; a letter opened ----

/datum/unit_test/dq_timed_pin_w8/mail_blank_seal
	duration = 1.5 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/mail_blank_seal/setup_scene()
	user = person()
	held = hold(/obj/item/mail/blank)
	target = held

/datum/unit_test/dq_timed_pin_w8/mail_blank_seal/is_done()
	var/obj/item/mail/blank/E = held
	return !QDELETED(E) && E.sealed

/datum/unit_test/dq_timed_pin_w8/mail_blank_open
	duration = 1.5 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/mail_blank_open/setup_scene()
	user = person()
	var/obj/item/mail/blank/E = hold(/obj/item/mail/blank)
	E.set_sealed(TRUE)
	held = E
	target = E

/datum/unit_test/dq_timed_pin_w8/mail_blank_open/is_done()
	return QDELETED(held)

/datum/unit_test/dq_timed_pin_w8/mail_blank_open/extra_pin()
	setup_scene()
	start_click()
	test_click(user, target, held)
	TEST_ASSERT_EQUAL(running_count(user), 1, "a second click while it is opened starts nothing more")
	test_time(duration + 2 SECONDS)
	clear_scene()

/datum/unit_test/dq_timed_pin_w8/mail_letter_open
	duration = 1.5 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/mail_letter_open/setup_scene()
	user = person()
	held = hold(/obj/item/mail)
	target = held

/datum/unit_test/dq_timed_pin_w8/mail_letter_open/is_done()
	return QDELETED(held)

/datum/unit_test/dq_timed_pin_w8/mail_blank_fill
	duration = 1.5 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/mail_blank_fill/setup_scene()
	user = person()
	target = allocate(/obj/item/mail/blank, run_loc_floor_bottom_left)
	held = hold(/obj/item/tool/screwdriver)

/datum/unit_test/dq_timed_pin_w8/mail_blank_fill/is_done()
	return !QDELETED(held) && held.loc == target

/datum/unit_test/dq_timed_pin_w8/mail_blank_fill/extra_pin()
	// a sealed envelope takes nothing
	setup_scene()
	var/obj/item/mail/blank/E = target
	E.set_sealed(TRUE)
	refused()
	clear_scene()
