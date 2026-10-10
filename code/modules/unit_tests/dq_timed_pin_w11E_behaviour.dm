// Behaviour pins for the timed actions converted in round 3 (rewrite/timed3-E), on the harness of dq_timed_pin_w8_behaviour.dm
// (base type /datum/unit_test/dq_timed_pin_w8). The scenes are written from the pre-conversion code and run against the ops that
// replaced it. The legacy attack()/afterattack() entries (the detective scanner, the glass straw's old afterattack) are not
// reached by test_click, so what they started is pinned only where a click reaches the op.

// ---- A hide: a knife scrapes one hide every two and a half seconds ----

/datum/unit_test/dq_timed_pin_w8/hide_scrape
	duration = 2.5 SECONDS
	finished = "You scrape the hair off"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/hide_scrape/setup_scene()
	user = person()
	var/obj/item/stack/animalhide/hide = allocate(/obj/item/stack/animalhide, user.loc)
	hide.set_amount(1)
	target = hide
	held = hold(/obj/item/material/knife)

/datum/unit_test/dq_timed_pin_w8/hide_scrape/is_done()
	return !!locate(/obj/item/stack/hairlesshide) in user.loc

// ---- Nail polish: painting someone else's nails takes two seconds and both must stay still ----

/datum/unit_test/dq_timed_pin_w8/nailpolish_paint_other
	duration = 2 SECONDS
	drop_cancels = TRUE
	finished = "nails with"

/datum/unit_test/dq_timed_pin_w8/nailpolish_paint_other/setup_scene()
	user = person()
	dq_give_zone_sel(user)
	user.zone_sel.set_selecting(BP_R_HAND)
	var/mob/living/carbon/human/patient = other()
	var/obj/item/nailpolish/polish = hold(/obj/item/nailpolish)
	polish.set_open(TRUE)
	target = patient
	held = polish

/datum/unit_test/dq_timed_pin_w8/nailpolish_paint_other/is_done()
	var/mob/living/carbon/human/patient = target
	var/obj/item/organ/external/hand = patient.get_organ(BP_R_HAND)
	return !!hand?.nail_polish

/datum/unit_test/dq_timed_pin_w8/nailpolish_paint_other/extra_pin()
	// a closed bottle does nothing
	setup_scene()
	var/obj/item/nailpolish/polish = held
	polish.set_open(FALSE)
	start_click()
	TEST_ASSERT_NULL(running(user), "a closed bottle starts nothing")
	clear_scene()
