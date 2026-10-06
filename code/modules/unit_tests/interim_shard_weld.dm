/// Real shard welding consumes before returning a sheet and preserves the original product location.
/datum/unit_test/interim_shard_weld
	var/held = FALSE
	var/sticky = FALSE

/datum/unit_test/interim_shard_weld/held
	held = TRUE

/datum/unit_test/interim_shard_weld/sticky
	held = TRUE
	sticky = TRUE

/datum/unit_test/interim_shard_weld/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/material/shard/shard = allocate(/obj/item/material/shard, T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	TEST_ASSERT_EQUAL(shard.material.name, MAT_GLASS, "actual shard uses its declared glass material")
	TEST_ASSERT(user.put_in_active_hand(welder), "actor holds the actual welding tool")
	if(held)
		TEST_ASSERT(user.put_in_inactive_hand(shard), "actual shard occupies the other hand")
	var/atom/product_location = shard.loc
	TEST_ASSERT_EQUAL(length(contents_of(product_location, /obj/item/stack/material)), 0, "original product location starts without sheets")
	TEST_ASSERT_EQUAL(shard.welder_act(user, welder), TRUE, "unlit real welder preserves existing handled return")
	TEST_ASSERT(!QDELETED(shard), "unlit real welder preserves the original shard")
	TEST_ASSERT_EQUAL(length(contents_of(product_location, /obj/item/stack/material)), 0, "unlit attempt returns no sheets")
	TEST_ASSERT(test_op_handler(welder, "interaction_self", user, welder), "actual activation lights the welder")
	TEST_ASSERT(welder.isOn(), "real welding tool is lit")
	var/fuel_before = welder.get_fuel()
	if(sticky)
		add_trait(shard, TRAIT_NODROP, "interim_shard_weld")
		TEST_ASSERT(shard.loc.release_refusal(shard, user), "actual sticky shard refuses release")
		TEST_ASSERT_EQUAL(shard.welder_act(user, welder), TRUE, "refused welding still handles the tool action")
		TEST_ASSERT(!QDELETED(shard), "refused welding preserves the exact shard")
		TEST_ASSERT_EQUAL(user.get_inactive_hand(), shard, "refused welding preserves its hand slot")
		TEST_ASSERT_EQUAL(length(contents_of(product_location, /obj/item/stack/material)), 0, "refused welding creates no sheet")
		remove_trait(shard, TRAIT_NODROP, "interim_shard_weld")
	TEST_ASSERT_EQUAL(shard.welder_act(user, welder), TRUE, "actual welding handles successful recovery")
	test_op_handler(welder, "interaction_self", user, welder)
	own_turf_contents(T)
	for(var/obj/item/stack/material/sheet as anything in contents_of(user, /obj/item/stack/material))
		own(sheet)
	TEST_ASSERT_EQUAL(welder.get_fuel(), fuel_before, "actual shard welding keeps its declared zero fuel cost")
	TEST_ASSERT(QDELETED(shard), "successful actual welding consumes the original shard")
	if(held)
		TEST_ASSERT_NULL(user.get_inactive_hand(), "consumption vacates the original shard hand")
	var/list/sheets = contents_of(product_location, /obj/item/stack/material)
	TEST_ASSERT_EQUAL(length(sheets), 1, "successful welding returns exactly one actual sheet stack")
	var/obj/item/stack/material/product = sheets[1]
	TEST_ASSERT_EQUAL(product.get_material_name(), MAT_GLASS, "returned sheet preserves the shard material")
	TEST_ASSERT_EQUAL(product.get_amount(), 1, "returned stack contains exactly one sheet")
	TEST_ASSERT_EQUAL(product.loc, product_location, "returned sheet retains the exact original product location")
