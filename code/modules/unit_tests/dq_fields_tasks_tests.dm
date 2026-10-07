// Behaviour of the slow work that used to be om_task_periodic()/periodic_step(): each type's work starts when
// its trigger happens, runs on its interval, and stops itself when there is nothing left to do.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A cyborg hypospray's refill work stops by itself when every reagent is full.
/datum/unit_test/dq_fields_borghypo_refill_stops_when_full

/datum/unit_test/dq_fields_borghypo_refill_stops_when_full/Run()
	test_driver_begin()
	var/obj/item/reagent_containers/borghypo/B = allocate(/obj/item/reagent_containers/borghypo)
	B.set_refilling(TRUE)
	TEST_ASSERT(B.refilling, "a started refill is not running")
	test_time(2 SECONDS + 1)
	TEST_ASSERT(!B.refilling, "a full hypospray kept refilling")
	var/id = REAGENT_ID_TRICORDRAZINE
	B.reagent_volumes[id] = 0
	B.set_refilling(TRUE)
	test_time(2 SECONDS + 1)
	TEST_ASSERT(B.refilling, "a short hypospray with no cyborg to draw from stopped refilling")
	test_driver_end()

/// A cyborg package dispenser gains a sheet every 12 s while short, and stops at full.
/datum/unit_test/dq_fields_borg_wrap_refills

/datum/unit_test/dq_fields_borg_wrap_refills/Run()
	test_driver_begin()
	var/obj/item/packageWrap/borg/W = allocate(/obj/item/packageWrap/borg)
	var/full = initial(W.amount)
	W.amount = full - 1
	W.wrap_used()
	TEST_ASSERT(W.refilling, "using the wrap did not start the refill")
	test_time(30 SECONDS)
	TEST_ASSERT_EQUAL(W.amount, full, "the dispenser did not refill")
	test_time(2 SECONDS + 1)
	TEST_ASSERT(!W.refilling, "a full dispenser kept refilling")
	test_driver_end()

/// An egg that was started on the growth work grows while on the floor and hatches into a chick.
/datum/unit_test/dq_fields_egg_hatches

/datum/unit_test/dq_fields_egg_hatches/Run()
	test_driver_begin()
	var/obj/item/reagent_containers/food/snacks/egg/E = allocate(/obj/item/reagent_containers/food/snacks/egg)
	TEST_ASSERT(!E.growing, "an egg grows before it is started")
	E.set_growing(TRUE)
	test_time(2 SECONDS + 1)
	TEST_ASSERT(E.amount_grown > 0, "a started egg did not grow")
	E.amount_grown = 99
	var/turf/T = get_turf(E)
	test_time(2 SECONDS + 1)
	TEST_ASSERT(QDELETED(E), "a grown egg did not hatch")
	var/found = FALSE
	for(var/mob/living/simple_mob/animal/passive/chick/C in contents_of(T))
		found = TRUE
		own(C)
	TEST_ASSERT(found, "no chick where the egg was")
	test_driver_end()

/// An egg picked up stops growing.
/datum/unit_test/dq_fields_egg_in_hand_stops

/datum/unit_test/dq_fields_egg_in_hand_stops/Run()
	test_driver_begin()
	var/obj/item/reagent_containers/food/snacks/egg/E = allocate(/obj/item/reagent_containers/food/snacks/egg)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	E.set_growing(TRUE)
	E.forceMove(H)
	test_time(2 SECONDS + 1)
	TEST_ASSERT(!E.growing, "a carried egg kept growing")
	test_driver_end()

/// The AI detector senses while carried; set down, its work stops.
/datum/unit_test/dq_fields_ai_detector_senses_while_carried

/datum/unit_test/dq_fields_ai_detector_senses_while_carried/Run()
	test_driver_begin()
	var/obj/item/multitool/ai_detector/D = allocate(/obj/item/multitool/ai_detector)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!D.sensing, "an uncarried detector senses")
	D.forceMove(H)
	D.equipped(H, SLOT_ID_HAND_L)
	TEST_ASSERT(D.sensing, "picking the detector up did not start it")
	test_time(2 SECONDS + 1)
	TEST_ASSERT(D.sensing, "a carried detector stopped")
	D.forceMove(get_turf(H))
	test_time(2 SECONDS + 1)
	TEST_ASSERT(!D.sensing, "a set-down detector kept sensing")
	test_driver_end()

/// Gloves of regeneration work only while worn, and stop when taken off.
/datum/unit_test/dq_fields_regen_gloves_follow_the_wearer

/datum/unit_test/dq_fields_regen_gloves_follow_the_wearer/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/gloves/regen/G = allocate(/obj/item/clothing/gloves/regen)
	TEST_ASSERT(!G.regenerating, "unworn gloves regenerate")
	TEST_ASSERT(H.equip_to_slot_if_possible(G, SLOT_ID_GLOVES), "the gloves did not go on")
	TEST_ASSERT(G.regenerating, "wearing the gloves did not start them")
	H.drop_from_inventory(G)
	test_time(2 SECONDS + 1)
	TEST_ASSERT(!G.regenerating, "gloves taken off kept working")
	test_driver_end()

/// Purging gloves work only while worn.
/datum/unit_test/dq_fields_purging_gloves_follow_the_wearer

/datum/unit_test/dq_fields_purging_gloves_follow_the_wearer/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/gloves/toxinregen/G = allocate(/obj/item/clothing/gloves/toxinregen)
	TEST_ASSERT(H.equip_to_slot_if_possible(G, SLOT_ID_GLOVES), "the gloves did not go on")
	TEST_ASSERT(G.purging, "wearing the gloves did not start them")
	H.drop_from_inventory(G)
	test_time(2 SECONDS + 1)
	TEST_ASSERT(!G.purging, "gloves taken off kept working")
	test_driver_end()

/// A slime extract told to emit starts its work; a green one radiates, any other stops at once.
/datum/unit_test/dq_fields_extract_emits_then_stops

/datum/unit_test/dq_fields_extract_emits_then_stops/Run()
	test_driver_begin()
	var/obj/item/slime_extract/grey/X = allocate(/obj/item/slime_extract/grey)
	slime_extract_start_emitting(X)
	TEST_ASSERT(X.emitting, "an extract told to emit did not start")
	test_time(2 SECONDS + 1)
	TEST_ASSERT(!X.emitting, "an extract with nothing to emit kept stepping")
	var/obj/item/slime_extract/green/G = allocate(/obj/item/slime_extract/green)
	slime_extract_start_emitting(G)
	test_time(2 SECONDS + 1)
	TEST_ASSERT(G.emitting, "a green extract stopped emitting")
	test_driver_end()

/// A shield projector regenerates after damage and stops when whole.
/datum/unit_test/dq_fields_shield_projector_regen_stops_when_whole

/datum/unit_test/dq_fields_shield_projector_regen_stops_when_whole/Run()
	test_driver_begin()
	var/obj/item/shield_projector/rectangle/P = allocate(/obj/item/shield_projector/rectangle)
	P.take_damage(10, BRUTE, null, FALSE)
	TEST_ASSERT(P.regenerating, "damage did not start the regeneration")
	COOLDOWN_RESET(P, regen_cooldown) // the delay counts world time, which the test clock does not advance
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(P.get_integrity(), P.max_integrity, "the projector did not regenerate")
	test_time(2 SECONDS + 1)
	TEST_ASSERT(!P.regenerating, "a whole projector kept its work")
	test_driver_end()

/// A spiderling scooped into a glass jar does not grow while it is inside.
/datum/unit_test/dq_fields_spiderling_does_not_grow_in_a_jar

/datum/unit_test/dq_fields_spiderling_does_not_grow_in_a_jar/Run()
	test_driver_begin()
	var/obj/item/glass_jar/jar = allocate(/obj/item/glass_jar)
	var/obj/effect/spider/spiderling/S = allocate(/obj/effect/spider/spiderling)
	S.amount_grown = 10
	S.forceMove(jar)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(S.amount_grown, 10, "a spiderling grew inside the jar")
	S.forceMove(get_turf(jar))
	test_time(10 SECONDS)
	TEST_ASSERT(S.amount_grown > 10, "a released spiderling did not grow")
	test_driver_end()

#endif
