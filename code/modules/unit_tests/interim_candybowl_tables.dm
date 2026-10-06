/// Exact department tables and real task cancellation without manufacturing a keyed client.
/// Completed keyed-player candy selection is not exercised by this clientless fixture.
/datum/unit_test/interim_candybowl_tables
	var/bowl_type = /obj/structure/candybowl
	var/list/additions

/datum/unit_test/interim_candybowl_tables/medical
	bowl_type = /obj/structure/candybowl/medical
	additions = list(/obj/item/clothing/mask/chewable/candy/lolli, /obj/item/reagent_containers/food/snacks/organ, /obj/item/storage/box/shrimpsandbananas)

/datum/unit_test/interim_candybowl_tables/engineering
	bowl_type = /obj/structure/candybowl/engineering
	additions = list(/obj/item/reagent_containers/food/snacks/welders_original, /obj/item/reagent_containers/food/snacks/butterscotch, /obj/item/reagent_containers/food/snacks/chocolatepiece)

/datum/unit_test/interim_candybowl_tables/cargo
	bowl_type = /obj/structure/candybowl/cargo
	additions = list(/obj/item/reagent_containers/food/snacks/butterscotch, /obj/item/reagent_containers/food/snacks/honey_candy, /obj/item/storage/box/winegum)

/datum/unit_test/interim_candybowl_tables/science
	bowl_type = /obj/structure/candybowl/science
	additions = list(/obj/item/reagent_containers/food/snacks/reishicup, /obj/item/reagent_containers/food/snacks/antball, /obj/item/storage/box/winegum, /obj/item/reagent_containers/food/snacks/chocolatepiece/truffle)

/datum/unit_test/interim_candybowl_tables/security
	bowl_type = /obj/structure/candybowl/security
	additions = list(/obj/item/reagent_containers/food/snacks/spicy_boys, /obj/item/reagent_containers/food/snacks/chocolatepiece/white, /obj/item/reagent_containers/food/snacks/candy_corn)

/datum/unit_test/interim_candybowl_tables/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/candybowl/bowl = allocate(bowl_type, T)
	var/obj/structure/candybowl/other = allocate(bowl_type, T)
	var/obj/structure/candybowl/base = allocate(/obj/structure/candybowl, T)
	var/list/base_choices = list(
		/obj/item/reagent_containers/food/snacks/cb01,
		/obj/item/reagent_containers/food/snacks/cb02,
		/obj/item/reagent_containers/food/snacks/cb03,
		/obj/item/reagent_containers/food/snacks/cb04,
		/obj/item/reagent_containers/food/snacks/cb05,
		/obj/item/reagent_containers/food/snacks/cb06,
		/obj/item/reagent_containers/food/snacks/cb07,
		/obj/item/reagent_containers/food/snacks/cb08,
		/obj/item/reagent_containers/food/snacks/cb09,
		/obj/item/reagent_containers/food/snacks/cb10,
		/obj/item/reagent_containers/food/snacks/candy_corn,
		/obj/item/reagent_containers/food/snacks/triton,
		/obj/item/reagent_containers/food/snacks/saturn,
		/obj/item/reagent_containers/food/snacks/jupiter,
		/obj/item/reagent_containers/food/snacks/pluto,
		/obj/item/reagent_containers/food/snacks/mars,
		/obj/item/reagent_containers/food/snacks/venus,
		/obj/item/reagent_containers/food/snacks/oort
	)
	var/list/expected = base_choices.Copy()
	if(additions)
		expected += additions
	var/list/choices = TYPE_TABLE_GET(bowl, candy_choices)
	var/list/other_choices = TYPE_TABLE_GET(other, candy_choices)
	var/list/actual_base = TYPE_TABLE_GET(base, candy_choices)
	TEST_ASSERT_EQUAL(length(choices), length(expected), "actual departmental choices retain exact count including duplicate weights")
	TEST_ASSERT_EQUAL(length(actual_base), length(base_choices), "actual base choices retain their exact original count")
	for(var/i in 1 to length(expected))
		TEST_ASSERT_EQUAL(choices[i], expected[i], "actual departmental choices preserve exact parent and appended order")
		TEST_ASSERT_EQUAL(other_choices[i], expected[i], "another actual bowl has the same exact department choices")
	for(var/i in 1 to length(base_choices))
		TEST_ASSERT_EQUAL(actual_base[i], base_choices[i], "actual parent choices remain unchanged by department additions")
	var/list/private_choices = TYPE_TABLE_COPY(bowl, candy_choices)
	private_choices.Cut()
	TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(bowl, candy_choices)), length(expected), "mutating a supported private copy preserves actual department choices")
	TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(other, candy_choices)), length(expected), "private copy mutation preserves another actual bowl")
	TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(base, candy_choices)), length(base_choices), "private copy mutation preserves actual parent choices")
	TEST_ASSERT(bowl.has_candy, "actual initialized bowl contains candy")
	TEST_ASSERT_NULL(user.get_active_hand(), "actual search fixture begins with an empty active hand")
	TEST_ASSERT_EQUAL(bowl.can_search(user, bowl, null), TRUE, "actual full idle bowl permits searching")
	TEST_ASSERT_EQUAL(bowl.interaction_hand(user, null, null), TRUE, "actual hand entry starts the real timed search")
	TEST_ASSERT(task_busy(bowl), "actual search claims its bowl while the task runs")
	test_time(4 SECONDS)
	TEST_ASSERT_NULL(user.get_active_hand(), "actual search creates no candy before its five-second deadline")
	var/turf/away = get_step(get_step(T, EAST), EAST)
	TEST_ASSERT(away, "actual cancellation fixture has a floor outside bowl reach")
	user.forceMove(away)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(user.get_active_hand(), "actual movement cancellation prevents a candy product at the deadline")
	TEST_ASSERT(!task_busy(bowl), "actual canceled search releases its bowl claim")
	TEST_ASSERT(bowl.has_candy && !QDELETED(bowl), "actual canceled search preserves the full bowl")
	TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(bowl, candy_choices)), length(expected), "actual cancellation leaves shared choices unchanged")
	TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(other, candy_choices)), length(expected), "actual cancellation preserves another bowl choices")
	bowl.empty()
	TEST_ASSERT(!bowl.has_candy, "actual empty operation marks the bowl empty")
	TEST_ASSERT_EQUAL(bowl.can_search(user, bowl, null), "there is no candy, someone took too many", "actual empty bowl refuses another search")
	TEST_ASSERT(other.has_candy, "emptying an actual bowl preserves another instance")
	bowl.fill()
	TEST_ASSERT_EQUAL(bowl.can_search(user, bowl, null), TRUE, "actual refill restores search availability")
	TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(bowl, candy_choices)), length(expected), "actual empty and refill preserve exact department choices")
