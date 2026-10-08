/// The person clicks `target` with `held` in hand and time passes.
/proc/interim_put_on(mob/living/carbon/human/user, atom/target, obj/item/held)
	user.next_click = 0
	test_click(user, target, held)
	test_time(10 SECONDS)

/// Hiding a real shard must respect inventory release without inventing ingredient ownership.
/datum/unit_test/interim_custom_sandwich_sticky_shard/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode() // the ten-second waits would leave a bare human unable to act
	var/obj/item/reagent_containers/food/snacks/csandwich/sandwich = allocate(/obj/item/reagent_containers/food/snacks/csandwich, T)
	var/obj/item/material/shard/shard = allocate(/obj/item/material/shard, T)
	TEST_ASSERT_EQUAL(contents_count(sandwich), 0, "the actual initialized sandwich starts without hidden objects")
	TEST_ASSERT(user.put_in_active_hand(shard), "the actor holds the exact original actual shard")
	add_trait(shard, TRAIT_NODROP, "interim_sandwich_shard_sticky")
	TEST_ASSERT(user.release_refusal(shard, user), "actual inventory refuses the sticky shard")
	interim_put_on(user, sandwich, shard)
	TEST_ASSERT_EQUAL(user.get_active_hand(), shard, "refused hiding preserves the exact source hand")
	TEST_ASSERT_EQUAL(shard.loc, user, "refused hiding preserves inventory containment")
	TEST_ASSERT_EQUAL(contents_count(sandwich), 0, "refused hiding contains no shard")
	TEST_ASSERT_EQUAL(LAZYLEN(sandwich.ingredients), 0, "refused hiding adds no food ingredient")
	remove_trait(shard, TRAIT_NODROP, "interim_sandwich_shard_sticky")
	interim_put_on(user, sandwich, shard)
	TEST_ASSERT_NULL(user.get_active_hand(), "allowed hiding clears the actual source hand")
	TEST_ASSERT_EQUAL(shard.loc, sandwich, "allowed hiding physically contains the exact original shard")
	TEST_ASSERT_EQUAL(contents_count(sandwich), 1, "allowed hiding adds exactly one original hidden object")
	TEST_ASSERT_EQUAL(LAZYLEN(sandwich.ingredients), 0, "a hidden shard retains its existing separation from food ingredients")
	TEST_ASSERT_NULL(owner_of(shard), "hiding preserves the original unowned shard containment policy")
	test_driver_end()
