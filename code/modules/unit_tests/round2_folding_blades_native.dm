/// Actual native held inputs retain each blade subtype's existing equipment transformations.
/datum/unit_test/round2_folding_blades_native
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_folding_blades_native/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/completed = 0
	for(var/blade_type in list(/obj/item/material/butterfly, /obj/item/material/butterfly/switchblade, /obj/item/material/butterfly/boxcutter, /obj/item/material/butterfly/saw))
		var/obj/item/material/butterfly/blade = allocate(blade_type, T, MAT_STEEL)
		TEST_ASSERT_EQUAL(blade.active, 0, "actual constructor starts blade folded")
		TEST_ASSERT_EQUAL(blade.force, 3, "actual folded blade has existing blunt force")
		TEST_ASSERT(!blade.edge && !blade.sharp, "actual folded blade is not cutting")
		var/folded_size = blade.w_class
		var/folded_icon = blade.icon_state
		var/datum/material/original_material = blade.material
		TEST_ASSERT(user.put_in_active_hand(blade), "actual actor holds original material blade")
		test_click(user, blade, blade)
		test_time(1 SECOND)
		TEST_ASSERT_EQUAL(blade.active, 1, "actual native held input opens original blade")
		TEST_ASSERT(blade.edge && blade.sharp, "actual native opening creates original cutting edges")
		TEST_ASSERT(blade.force > 3, "actual steel opening increases cutting force above folded blunt force")
		TEST_ASSERT_EQUAL(blade.hitsound, SFX_WEAPONS_BLADESLICE, "actual opening selects original blade sound")
		TEST_ASSERT_EQUAL(user.get_active_hand(), blade, "actual opening preserves exact original actor hand")
		TEST_ASSERT_EQUAL(blade.material, original_material, "actual opening preserves exact original material")
		if(istype(blade, /obj/item/material/butterfly/saw))
			TEST_ASSERT_EQUAL(blade.can_cleave, 1, "actual saw subtype parent chain enables cleaving")
			TEST_ASSERT_EQUAL(blade.item_state, "cleaving_saw_open", "actual saw subtype retains its distinct held appearance")
		test_click(user, blade, blade)
		test_time(1 SECOND)
		TEST_ASSERT_EQUAL(blade.active, 0, "actual second native input folds original blade")
		TEST_ASSERT_EQUAL(blade.force, 3, "actual folding restores original blunt force")
		TEST_ASSERT(!blade.edge && !blade.sharp, "actual folding removes original cutting edges")
		TEST_ASSERT_EQUAL(blade.w_class, folded_size, "actual folding restores original subtype size")
		TEST_ASSERT_EQUAL(blade.icon_state, folded_icon, "actual folding restores original subtype icon")
		TEST_ASSERT_EQUAL(blade.material, original_material, "actual roundtrip preserves original material")
		TEST_ASSERT_EQUAL(user.get_active_hand(), blade, "actual roundtrip preserves original actor hand")
		TEST_ASSERT(user.unEquip(blade), "actual actor releases completed blade")
		completed++
	TEST_ASSERT_EQUAL(completed, 4, "all four real folding blade constructors completed")
