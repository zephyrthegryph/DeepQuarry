// Behaviour pins for the timed actions of code/game/objects/items (round 3, group C), recorded on the legacy task_timed / task_start forms before they
// became ops with wait(). Same harness as dq_timed_pin_w8_behaviour.dm: every pin drives the real click path (or the proc the engine hook calls) and records
// the duration (not done a second before, done a second after), the start message, what a move, a dropped held item or a lost target does, and what
// completion does. A conversion keeps every assertion; a difference is a documented class in doc/rewrite/intended_changes.md.
//
// Not pinned, because the legacy form cannot be driven by the test driver (a legacy attack()/afterattack() reached only through a real client, a
// prompt chain, or state the test floor cannot give): the leash, nanopaste, the sandbag fill (needs an outdoor floor), the stack recipe build, the
// law board, the RCD / RMS / RPD, the inducer, the implanter, the kitchen utensil force feed, the material repair, the medigun and the UAV radial.

/datum/unit_test/dq_timed_pin_w11C
	abstract_type = /datum/unit_test/dq_timed_pin_w11C
	parent_type = /datum/unit_test/dq_timed_pin_w8

// ---- Soap: scrubs a decal out, 3.5 seconds ----

/datum/unit_test/dq_timed_pin_w11C/soap_scrub_decal
	duration = 3.5 SECONDS
	began = "You begin to scrub"
	drop_cancels = TRUE
	legacy_click = TRUE

/datum/unit_test/dq_timed_pin_w11C/soap_scrub_decal/setup_scene()
	user = person()
	target = allocate(/obj/effect/decal/cleanable/dirt, get_step(user, NORTH))
	held = hold(/obj/item/soap)

/datum/unit_test/dq_timed_pin_w11C/soap_scrub_decal/is_done()
	return QDELETED(target)

// ---- Handcuffs: put on yourself, three seconds ----

/datum/unit_test/dq_timed_pin_w11C/handcuffs_self
	duration = 3 SECONDS
	drop_cancels = TRUE
	loss_cancels = FALSE // the cuffed are the actor

/datum/unit_test/dq_timed_pin_w11C/handcuffs_self/setup_scene()
	user = person()
	target = user
	held = hold(/obj/item/handcuffs)

/datum/unit_test/dq_timed_pin_w11C/handcuffs_self/start_click()
	test_chat_clear()
	var/obj/item/handcuffs/cuffs = held
	cuffs.attempt_to_cuff(user, user)

/datum/unit_test/dq_timed_pin_w11C/handcuffs_self/is_done()
	return !isnull(user.get_equipped_item(SLOT_ID_HANDCUFFED))

/datum/unit_test/dq_timed_pin_w11C/handcuffs_self/clear_scene()
	tidy()
	if(user && user.get_equipped_item(SLOT_ID_HANDCUFFED))
		user.drop_from_inventory(user.get_equipped_item(SLOT_ID_HANDCUFFED))
	target = null

// ---- A splint on somebody else's arm, five seconds ----

/datum/unit_test/dq_timed_pin_w11C/splint_other
	duration = 5 SECONDS
	drop_cancels = TRUE
	legacy_click = TRUE

/datum/unit_test/dq_timed_pin_w11C/splint_other/setup_scene()
	user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = BP_L_ARM
	target = person(get_step(user, NORTH))
	held = hold(/obj/item/stack/medical/splint)

/datum/unit_test/dq_timed_pin_w11C/splint_other/is_done()
	var/mob/living/carbon/human/patient = target
	var/obj/item/organ/external/arm = patient?.get_organ(BP_L_ARM)
	return !QDELETED(patient) && arm?.splinted

// ---- Ointment on a burned arm, one second ----

/datum/unit_test/dq_timed_pin_w11C/ointment_burn
	duration = 1 SECOND
	drop_cancels = TRUE
	legacy_click = TRUE

/datum/unit_test/dq_timed_pin_w11C/ointment_burn/setup_scene()
	user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = BP_L_ARM
	var/mob/living/carbon/human/patient = person(get_step(user, NORTH))
	patient.injure(INJURY_BURN, 15, BP_L_ARM)
	target = patient
	held = hold(/obj/item/stack/medical/ointment)

/datum/unit_test/dq_timed_pin_w11C/ointment_burn/is_done()
	var/mob/living/carbon/human/patient = target
	var/obj/item/organ/external/arm = patient?.get_organ(BP_L_ARM)
	return !QDELETED(patient) && arm?.is_salved()

// ---- A plushie with something stitched inside: any touch takes a second to find it ----

/datum/unit_test/dq_timed_pin_w11C/plushie_find_inside
	duration = 1 SECOND

/datum/unit_test/dq_timed_pin_w11C/plushie_find_inside/setup_scene()
	user = person()
	var/obj/structure/plushie/P = allocate(/obj/structure/plushie, get_step(user, NORTH))
	P.opened = TRUE
	var/obj/item/pen/hidden = allocate(/obj/item/pen, P.loc)
	move_into(P, nameof(P.stored_item), hidden)
	target = P

/datum/unit_test/dq_timed_pin_w11C/plushie_find_inside/is_done()
	var/obj/structure/plushie/P = target
	return !QDELETED(P) && isnull(P.stored_item)

/datum/unit_test/dq_timed_pin_w11C/plushie_find_inside/extra_pin()
	// a second touch while it works does not start a second search
	setup_scene()
	start_click()
	test_click(user, target, null)
	TEST_ASSERT_EQUAL(running_count(user), 1, "a second touch while it works starts nothing more")
	test_time(duration + 2 SECONDS)
	clear_scene()

// ---- A vore egg: whoever is inside pushes out for five seconds ----

/datum/unit_test/dq_timed_pin_w11C/egg_hatch
	duration = 5 SECONDS
	var/obj/item/pen/inside

/datum/unit_test/dq_timed_pin_w11C/egg_hatch/setup_scene()
	user = person()
	var/obj/item/storage/vore_egg/egg = allocate(/obj/item/storage/vore_egg, get_step(user, NORTH))
	inside = allocate(/obj/item/pen, egg.loc)
	inside.forceMove(egg)
	target = egg

/datum/unit_test/dq_timed_pin_w11C/egg_hatch/start_click()
	test_chat_clear()
	var/obj/item/storage/vore_egg/egg = target
	egg.hatch(user)

/datum/unit_test/dq_timed_pin_w11C/egg_hatch/is_done()
	return !QDELETED(inside) && inside.loc != target

// ---- A crayon: a letter takes five seconds, standing still ----

/datum/unit_test/dq_timed_pin_w11C/crayon_letter

/datum/unit_test/dq_timed_pin_w11C/crayon_letter/run_pin()
	var/turf/simulated/floor/surface = test_floor()
	user = person(surface)
	var/obj/item/pen/crayon/crayon = allocate(/obj/item/pen/crayon, surface)
	TEST_ASSERT(user.put_in_hands(crayon), "the drawer holds the crayon")
	crayon.instant = FALSE
	draw_letter(crayon, surface)
	TEST_ASSERT(!isnull(running(user)), "answering the second question starts the drawing")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(new_decals(surface), 0, "nothing is drawn after four seconds")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(new_decals(surface), 1, "the letter is drawn after six")
	own_turf_contents(surface)
	// walking away ends it
	draw_letter(crayon, surface)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a second drawing starts")
	test_time(2 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(new_decals(surface), 1, "moving cancels the second drawing: no more decals")
	TEST_ASSERT(was_cancelled(T, user), "and it ends cancelled")
	own_turf_contents(surface)

/datum/unit_test/dq_timed_pin_w11C/crayon_letter/proc/draw_letter(obj/item/pen/crayon/crayon, turf/simulated/floor/surface)
	crayon.afterattack(surface, user, TRUE, "icon-x=16;icon-y=16")
	test_answer(user, "letter")
	test_time(0.1 SECONDS)
	test_answer(user, "a")
	test_time(0.1 SECONDS)

/datum/unit_test/dq_timed_pin_w11C/crayon_letter/proc/new_decals(turf/surface)
	var/count = 0
	for(var/obj/effect/decal/cleanable/crayon/drawn in surface)
		count++
	return count
