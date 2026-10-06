/// Real training-mine crossing and delayed-wire pulse each refund one casing and clear teardown state.
/datum/unit_test/interim_training_mine_end
	var/delayed = FALSE

/datum/unit_test/interim_training_mine_end/delayed
	delayed = TRUE

/datum/unit_test/interim_training_mine_end/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/effect/mine/training/mine = allocate(/obj/effect/mine/training, T)
	var/datum/wires_test_adapter/wires = wires_test(mine)
	TEST_ASSERT(wires, "the actual deployed training mine initializes its wire controller")
	TEST_ASSERT(mine in T.dangerous_objects, "actual initialization registers the training mine as a floor danger")
	TEST_ASSERT(!mine.triggered, "the real training mine starts untriggered")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/mine/training)), 0, "the floor starts without a refunded casing")
	if(delayed)
		TEST_ASSERT(!wires.is_cut(WIRE_EXPLODE_DELAY), "the actual delayed detonation wire starts intact")
		wires.pulse(WIRE_EXPLODE_DELAY, user)
		test_time(1 SECOND)
		TEST_ASSERT(!QDELETED(mine), "the actual delayed pulse preserves the mine before its deadline")
		TEST_ASSERT(!mine.triggered, "the real mine stays untriggered during the delay")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/mine/training)), 0, "the pending pulse refunds no casing early")
		test_time(1.5 SECONDS)
	else
		mine.Bumped(user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(mine), "actual crossing or scheduled detonation consumes the deployed mine")
	TEST_ASSERT(isnull(wiring_of(mine)), "actual consumption drops the mine's wire record")
	TEST_ASSERT(!(mine in T.dangerous_objects), "actual teardown removes the old mine from the floor danger index")
	TEST_ASSERT_NULL(locate_within(T, /obj/effect/mine/training), "the detonation leaves no duplicate deployed mine")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/mine/training)), 1, "actual training detonation refunds exactly one original-type casing")
	var/obj/item/mine/training/refund = locate_within(T, /obj/item/mine/training)
	TEST_ASSERT_EQUAL(refund.loc, T, "the actual training casing remains on the original floor")
	TEST_ASSERT_EQUAL(user.stat, CONSCIOUS, "the real training detonation leaves its actor alive and conscious")

/// Actual stun-mine crossing ignores a tiny mouse but stuns a full-size person before disappearing.
/datum/unit_test/interim_stun_mine_end/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/simple_mob/animal/passive/mouse/mouse = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	var/obj/effect/mine/stun/mine = allocate(/obj/effect/mine/stun, T)
	TEST_ASSERT(mouse.mob_size <= MOB_TINY, "the actual mouse meets the existing tiny-victim exemption")
	TEST_ASSERT(!user.has_status(STAT_STUNNED), "the actual person starts without stun")
	mine.Bumped(mouse)
	TEST_ASSERT(!QDELETED(mine), "the actual tiny-mouse crossing preserves the mine")
	TEST_ASSERT(!mine.triggered, "the tiny-mouse crossing does not trigger the mine")
	mine.Bumped(user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(mine), "the real full-size crossing consumes the stun mine")
	TEST_ASSERT(user.has_status(STAT_STUNNED), "the actual mine applies real stun to the full-size victim")
	TEST_ASSERT(user.status_units(STAT_STUNNED) > 0, "the actual stun has a positive remaining quantity")
	TEST_ASSERT(!QDELETED(mouse), "the tiny bystander survives the actual stun detonation")
	TEST_ASSERT(!(mine in T.dangerous_objects), "actual stun-mine teardown clears the floor danger index")
	TEST_ASSERT_NULL(locate_within(T, /obj/effect/mine/stun), "the real detonation leaves no duplicate stun mine")

/// Actual stripping-mine crossing drops both real held objects without destroying them.
/datum/unit_test/interim_stripping_mine_end/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/book/book = allocate(/obj/item/book, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(user.put_in_active_hand(book), "the actual victim holds the original book")
	TEST_ASSERT(user.put_in_inactive_hand(pen), "the actual victim holds the original pen in the other hand")
	var/obj/effect/mine/stripping/mine = allocate(/obj/effect/mine/stripping, T)
	mine.Bumped(user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(mine), "the actual crossing consumes the stripping mine")
	TEST_ASSERT_NULL(user.get_active_hand(), "the actual stripping effect clears the original active hand")
	TEST_ASSERT_NULL(user.get_inactive_hand(), "the actual stripping effect clears the original other hand")
	TEST_ASSERT(!QDELETED(book), "the original stripped book survives the effect")
	TEST_ASSERT(!QDELETED(pen), "the original stripped pen survives the effect")
	TEST_ASSERT_EQUAL(book.loc, T, "the actual stripping effect drops the same original book onto the floor")
	TEST_ASSERT_EQUAL(pen.loc, T, "the actual stripping effect drops the same original pen onto the floor")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/book)), 1, "the effect leaves exactly the original book")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/pen)), 1, "the effect leaves exactly the original pen")
	TEST_ASSERT(!(mine in T.dangerous_objects), "actual stripping-mine teardown clears the floor danger index")
	TEST_ASSERT_NULL(locate_within(T, /obj/effect/mine/stripping), "the actual detonation leaves no duplicate stripping mine")
