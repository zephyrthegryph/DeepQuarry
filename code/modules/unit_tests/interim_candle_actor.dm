/// Keep the actual ignition effect while recording the actor at its boundary.
/obj/item/flame/candle/interim_actor_probe
	var/light_actor_ref

/obj/item/flame/candle/interim_actor_probe/light(flavor_text, mob/user)
	light_actor_ref = user ? REF(user) : null
	return ..(flavor_text, user)

/datum/unit_test/interim_candle_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/flame/candle/interim_actor_probe/candle = allocate(/obj/item/flame/candle/interim_actor_probe, T)
	var/list/source_types = list(/obj/item/flame/lighter, /obj/item/flame/match, /obj/item/flame/candle)
	for(var/source_type in source_types)
		var/obj/item/flame/source = allocate(source_type, T)
		TEST_ASSERT(!source.lit, "the ignition source begins unlit")
		candle.interaction_item(user, source, null)
		TEST_ASSERT(!candle.lit, "an unlit source cannot ignite the candle")
		source.set_lit(TRUE)
		var/wax_before = candle.wax
		candle.interaction_item(user, source, null)
		TEST_ASSERT(candle.lit, "a lit source ignites the actual candle")
		TEST_ASSERT_EQUAL(candle.light_range, CANDLE_LUM, "ignition enables the candle's actual light")
		TEST_ASSERT_EQUAL(candle.light_actor_ref, REF(user), "the ignition helper receives the explicit actor")
		TEST_ASSERT_EQUAL(candle.wax, wax_before, "ignition preserves the remaining wax")
		candle.interaction_item(user, source, null)
		TEST_ASSERT_EQUAL(candle.wax, wax_before, "lighting an already lit candle preserves its wax")
		candle.interaction_self(user, null, null)
		TEST_ASSERT(!candle.lit, "self interaction extinguishes the actual candle")
		TEST_ASSERT_EQUAL(candle.light_range, 0, "extinguishing clears the candle's actual light")
		source.set_lit(FALSE)
