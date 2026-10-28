// The plain door (/obj/machinery/door), converted: touch, access, plasteel, repair, emag and the autoclose timer, as ops of the base door
// (code/game/machinery/doors/door.dm, code/library/machine/doors.dm). The airlock, firedoor, blast door and windoor answer these with their own until
// they convert; dq_p2_door_behaviour.dm pins what they do now.

/datum/unit_test/dq_p2_door/base_door_opens_and_closes_by_hand

/datum/unit_test/dq_p2_door/base_door_opens_and_closes_by_hand/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door)
	var/mob/living/carbon/human/H = make_person(null)
	TEST_ASSERT(D.density, "a door starts shut")
	click(H, D, null)
	TEST_ASSERT(!D.density, "a hand opens it")
	click(H, D, null)
	TEST_ASSERT(D.density, "and shuts it again")

/datum/unit_test/dq_p2_door/base_door_opens_for_any_item_in_hand

/datum/unit_test/dq_p2_door/base_door_opens_for_any_item_in_hand/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door)
	var/mob/living/carbon/human/H = make_person(null)
	click(H, D, give_item(H, /obj/item/pen))
	TEST_ASSERT(!D.density, "touching it with a pen opens it, as it always did")

/datum/unit_test/dq_p2_door/base_door_keeps_out_whoever_lacks_access

/datum/unit_test/dq_p2_door/base_door_keeps_out_whoever_lacks_access/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/stranger = make_person(null)
	var/mob/living/carbon/human/engineer = make_person(list(ACCESS_ENGINE), tile(1, 2))
	click(stranger, D, null)
	TEST_ASSERT(D.density, "no access, no entry")
	click(engineer, D, null)
	TEST_ASSERT(!D.density, "an engineer's ID opens it")

/datum/unit_test/dq_p2_door/base_door_without_power_does_not_answer

/datum/unit_test/dq_p2_door/base_door_without_power_does_not_answer/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door)
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_set_power(D, FALSE)
	click(H, D, null)
	TEST_ASSERT(D.density, "a door with no power does not open to a touch")

/datum/unit_test/dq_p2_door/base_door_autocloses

/datum/unit_test/dq_p2_door/base_door_autocloses/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door)
	var/mob/living/carbon/human/H = make_person(null)
	D.set_autoclose(TRUE)
	click(H, D, null)
	TEST_ASSERT(!D.density, "open")
	TEST_ASSERT(D.autoclose_pending(), "an autoclosing door waits to close")
	test_time(30 SECONDS)
	TEST_ASSERT(D.density, "and shuts itself")
	TEST_ASSERT(!D.autoclose_pending(), "with nothing left pending once it has")

/datum/unit_test/dq_p2_door/base_door_takes_plasteel_and_welds_it_in

/datum/unit_test/dq_p2_door/base_door_takes_plasteel_and_welds_it_in/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door)
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/stack/material/plasteel/sheets = give_item(H, /obj/item/stack/material/plasteel, 5)
	click(H, D, sheets)
	TEST_ASSERT_EQUAL(D.reinforcing, 2, "two sheets are fitted")
	TEST_ASSERT_EQUAL(sheets.get_amount(), 3, "and spent")
	click(H, D, give_welder(H))
	TEST_ASSERT(D.heat_proof, "welding them in reinforces the door")
	TEST_ASSERT_EQUAL(D.reinforcing, 0, "and nothing waits to be welded")

/datum/unit_test/dq_p2_door/base_door_gives_unwelded_plasteel_back_to_a_crowbar

/datum/unit_test/dq_p2_door/base_door_gives_unwelded_plasteel_back_to_a_crowbar/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door)
	var/mob/living/carbon/human/H = make_person(null)
	D.set_reinforcing(2)
	click(H, D, give_tool(H, /obj/item/tool/crowbar))
	TEST_ASSERT_EQUAL(D.reinforcing, 0, "a crowbar takes the unwelded plasteel back")
	TEST_ASSERT_EQUAL(sheets_on(tile(2, 2), /obj/item/stack/material/plasteel), 2, "onto the floor")
	tidy(tile(2, 2))

/datum/unit_test/dq_p2_door/base_door_welder_repairs_damage

/datum/unit_test/dq_p2_door/base_door_welder_repairs_damage/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door)
	var/mob/living/carbon/human/H = make_person(null)
	D.take_damage(D.max_integrity * 0.1, BRUTE, MELEE)
	TEST_ASSERT(D.get_integrity() < D.max_integrity, "damaged")
	p2_door_click(H, D, give_welder(H))
	test_time(60 SECONDS)
	TEST_ASSERT_EQUAL(D.get_integrity(), D.max_integrity, "a welder repairs it")

/datum/unit_test/dq_p2_door/base_door_emag_opens_it_for_good

/datum/unit_test/dq_p2_door/base_door_emag_opens_it_for_good/run_gate()
	var/obj/machinery/door/D = make_door(/obj/machinery/door, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/card/emag/emag = give_item(H, /obj/item/card/emag)
	var/uses = emag.uses
	click(H, D, emag)
	TEST_ASSERT(!D.density, "a sequencer opens it")
	TEST_ASSERT(p2_door_emagged(D), "and marks it emagged")
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "for one charge")
	click(H, D, emag)
	TEST_ASSERT_EQUAL(emag.uses, uses - 1, "an open door takes no second charge")
