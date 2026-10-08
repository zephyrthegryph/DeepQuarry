// Behaviour-preservation tests for the rag (phase 2, reagent containers, step 8): soaking it, wiping with it, wringing it out, smothering somebody and
// setting it alight. They use the base and the click helpers of dq_p2_reagent_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Fixtures and adapters
// ---------------------------------------------------------------------------------------------------------------------

/// Something that counts how often it was wiped.
/obj/item/p2_wipeable
	name = "dirty thing"
	w_class = ITEMSIZE_SMALL
	var/wiped = 0

/obj/item/p2_wipeable/on_rag_wipe(obj/item/reagent_containers/glass/rag/R)
	wiped++

/// The rag's name now (dry, damp or burning).
/proc/rc_rag_name(obj/item/reagent_containers/glass/rag/R)
	return R.name

/// Whether the rag burns.
/proc/rc_rag_lit(obj/item/reagent_containers/glass/rag/R)
	return !!R.rag_lit

/// A rag holding `amount` units of `id` (a fresh dry one for 0).
/datum/unit_test/dq_p2_reagents/proc/rc_rag(amount = 0, id = REAGENT_ID_WATER)
	var/obj/item/reagent_containers/glass/rag/R = allocate(/obj/item/reagent_containers/glass/rag)
	if(amount > 0)
		R.reagents.add_reagent(id, amount)
	R.update_name()
	return R

// ---------------------------------------------------------------------------------------------------------------------
// What it is
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/rags_start_as_declared

/datum/unit_test/dq_p2_reagents/rags_start_as_declared/run_gate()
	var/obj/item/reagent_containers/glass/rag/R = rc_rag()
	TEST_ASSERT_EQUAL(rc_capacity(R), 10, "a rag holds 10")
	TEST_ASSERT_EQUAL(rc_rag_name(R), "dry rag", "a new one is dry")
	TEST_ASSERT(!rc_rag_lit(R), "and does not burn")
	var/obj/item/reagent_containers/glass/rag/damp = rc_rag(5)
	TEST_ASSERT_EQUAL(rc_rag_name(damp), "damp rag", "one with water in it is damp")

// ---------------------------------------------------------------------------------------------------------------------
// Soaking
// ---------------------------------------------------------------------------------------------------------------------

/// A rag soaks up from a tank, a bucket or a mop bucket as much as it holds; a soaked one says so and takes no more.
/datum/unit_test/dq_p2_reagents/rag_soaks_from_a_tank

/datum/unit_test/dq_p2_reagents/rag_soaks_from_a_tank/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/rag/R = rc_rag()
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	var/before = rc_units(tank)
	rc_click(H, tank, R)
	TEST_ASSERT_EQUAL(rc_units(R), 10, "the rag is soaked")
	TEST_ASSERT_EQUAL(rc_units(tank), before - 10, "from the tank")
	TEST_ASSERT_EQUAL(rc_rag_name(R), "damp rag", "and is damp")
	rc_click(H, tank, R)
	TEST_ASSERT_EQUAL(rc_units(tank), before - 10, "a soaked rag takes no more")
	var/obj/item/reagent_containers/glass/bucket/bucket = rc_filled(/obj/item/reagent_containers/glass/bucket, 100)
	var/obj/item/reagent_containers/glass/rag/R2 = rc_rag()
	rc_click(H, bucket, R2)
	TEST_ASSERT_EQUAL(rc_units(R2), 10, "a bucket soaks it too")

// ---------------------------------------------------------------------------------------------------------------------
// Wiping
// ---------------------------------------------------------------------------------------------------------------------

/// A damp rag wipes a thing in three seconds; a dry one does not.
/datum/unit_test/dq_p2_reagents/rag_wipes_after_a_wait

/datum/unit_test/dq_p2_reagents/rag_wipes_after_a_wait/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/p2_wipeable/thing = allocate(/obj/item/p2_wipeable)
	var/obj/item/reagent_containers/glass/rag/dry = rc_rag()
	rc_click(H, thing, dry)
	TEST_ASSERT_EQUAL(thing.wiped, 0, "a dry rag wipes nothing")
	var/obj/item/reagent_containers/glass/rag/R = rc_rag(5)
	rc_click(H, thing, R, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(thing.wiped, 0, "nothing at once")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(thing.wiped, 0, "nor after a second")
	rc_settle()
	TEST_ASSERT_EQUAL(thing.wiped, 1, "after the wait it is wiped")

// ---------------------------------------------------------------------------------------------------------------------
// Wringing out
// ---------------------------------------------------------------------------------------------------------------------

/// Using a damp rag in hand wrings it out over the floor: five deciseconds a unit, then it is dry.
/datum/unit_test/dq_p2_reagents/rag_is_wrung_out_in_hand

/datum/unit_test/dq_p2_reagents/rag_is_wrung_out_in_hand/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/rag/R = rc_rag(10)
	rc_click(H, R, R, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(R), 10, "nothing at once")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(R), 10, "nor after two seconds")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(R), 0, "after ten units' worth of wringing it is dry")
	TEST_ASSERT_EQUAL(rc_rag_name(R), "dry rag", "and named so")

/// A damp rag clicked on an open container wrings into it.
/datum/unit_test/dq_p2_reagents/rag_wrings_into_a_container

/datum/unit_test/dq_p2_reagents/rag_wrings_into_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/rag/R = rc_rag(10)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, R)
	TEST_ASSERT_EQUAL(rc_units(R), 0, "the rag is wrung out")
	TEST_ASSERT_EQUAL(rc_units(B), 10, "into the beaker")

// ---------------------------------------------------------------------------------------------------------------------
// Smothering
// ---------------------------------------------------------------------------------------------------------------------

/// Aiming at the mouth, a damp rag smothers: one transfer into the blood. A dry one, a covered face and a non-human refuse.
/datum/unit_test/dq_p2_reagents/rag_smothers_a_person

/datum/unit_test/dq_p2_reagents/rag_smothers_a_person/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	H.zone_sel.set_selecting(O_MOUTH)
	var/obj/item/reagent_containers/glass/rag/R = rc_rag(10)
	var/before = rc_blood_units(patient)
	rc_click(H, patient, R, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(R), 5, "one transfer left the rag")
	TEST_ASSERT(rc_blood_units(patient) > before, "and is in the patient")
	var/obj/item/reagent_containers/glass/rag/dry = rc_rag()
	var/blood = rc_blood_units(patient)
	rc_click(H, patient, dry, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_blood_units(patient), blood, "a dry rag smothers nobody")
	var/obj/item/clothing/head/helmet/helmet = allocate(/obj/item/clothing/head/helmet)
	if(patient.equip_to_slot_if_possible(helmet, SLOT_ID_HEAD) && (helmet.body_parts_covered & FACE))
		rc_click(H, patient, R, I_HELP, FALSE)
		TEST_ASSERT_EQUAL(rc_units(R), 5, "a covered face is refused")
	H.zone_sel.set_selecting(BP_TORSO)

// ---------------------------------------------------------------------------------------------------------------------
// Fire
// ---------------------------------------------------------------------------------------------------------------------

/// A rag soaked in spirits is lit by a flame; using it in hand stamps it out.
/datum/unit_test/dq_p2_reagents/rag_is_lit_and_stamped_out

/datum/unit_test/dq_p2_reagents/rag_is_lit_and_stamped_out/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/rag/R = rc_rag(10, REAGENT_ID_ETHANOL)
	var/obj/item/flame/lighter/L = allocate(/obj/item/flame/lighter)
	L.set_lit(TRUE)
	rc_click(H, R, L)
	TEST_ASSERT(rc_rag_lit(R), "a lit flame sets a spirit-soaked rag alight")
	TEST_ASSERT_EQUAL(rc_rag_name(R), "burning rag", "and it is named so")
	rc_use(H, R)
	TEST_ASSERT(!rc_rag_lit(R) || QDELETED(R), "using it in hand puts it out")
	var/obj/item/reagent_containers/glass/rag/water = rc_rag(10)
	rc_click(H, water, L)
	TEST_ASSERT(!rc_rag_lit(water), "a rag soaked in water does not light")

/// A rag stuffed in a bottle is lit by a flame held to the bottle (a fire bomb).
/datum/unit_test/dq_p2_reagents/rag_in_a_bottle_is_lit

/datum/unit_test/dq_p2_reagents/rag_in_a_bottle_is_lit/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/rag/R = rc_rag(10, REAGENT_ID_ETHANOL)
	var/obj/item/reagent_containers/food/drinks/bottle/bottle = allocate(/obj/item/reagent_containers/food/drinks/bottle)
	bottle.insert_rag(R, H)
	TEST_ASSERT(bottle.rag == R, "the rag is in the bottle")
	var/obj/item/flame/lighter/L = allocate(/obj/item/flame/lighter)
	L.set_lit(TRUE)
	rc_click(H, bottle, L)
	TEST_ASSERT(rc_rag_lit(R), "the flame lit the rag in the bottle")
