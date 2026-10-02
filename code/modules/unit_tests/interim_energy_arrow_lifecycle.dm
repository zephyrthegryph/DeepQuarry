/// Real hardlight arrows dissipate through the actual inventory equip boundary, including sticky arrows.
/datum/unit_test/interim_energy_arrow_equip_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	for(var/sticky in list(FALSE, TRUE))
		var/obj/item/arrow/energy/arrow = allocate(/obj/item/arrow/energy, T)
		if(sticky)
			add_trait(arrow, TRAIT_NODROP, "interim_energy_arrow_equip")
		user.put_in_active_hand(arrow)
		TEST_ASSERT(QDELETED(arrow), "the actual equip callback dissipates the hardlight arrow even when sticky")
		TEST_ASSERT_NULL(user.get_active_hand(), "the compulsory drop vacates the actual inventory hand")
		TEST_ASSERT_NULL(locate_within(T, /obj/item/arrow/energy), "equipping leaves no spent hardlight arrow on the floor")

/// A real nonliving throw impact consumes the spent hardlight projectile through its parent impact path.
/datum/unit_test/interim_energy_arrow_impact_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/arrow/energy/arrow = allocate(/obj/item/arrow/energy, T)
	var/obj/item/pen/obstacle = allocate(/obj/item/pen, T)
	arrow.throw_impact(obstacle)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(arrow), "the actual obstacle impact consumes the spent hardlight arrow")
	TEST_ASSERT_NULL(locate_within(T, /obj/item/arrow/energy), "impact leaves no spent hardlight projectile on the floor")
	TEST_ASSERT(!QDELETED(obstacle), "the actual parent impact preserves this nonliving obstacle")
