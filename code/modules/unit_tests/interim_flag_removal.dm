/// Actual paired-flag removal deletes both panels and preserves the folded/ripped/burnt outcomes.
/datum/unit_test/interim_flag_removal
	var/torn = FALSE
	var/burn = FALSE

/datum/unit_test/interim_flag_removal/torn
	torn = TRUE

/datum/unit_test/interim_flag_removal/burn
	burn = TRUE

/datum/unit_test/interim_flag_removal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/sign/flag/blank/flag = allocate(/obj/structure/sign/flag/blank, T)
	var/obj/structure/sign/flag/blank/other = allocate(/obj/structure/sign/flag/blank, T)
	rel_set(flag, nameof(flag.linked_flag), other)
	TEST_ASSERT_EQUAL(flag.linked_flag, other, "the declared pair relates the original flag to its second panel")
	TEST_ASSERT_EQUAL(other.linked_flag, flag, "the actual reverse relation links the second panel back")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/decal/cleanable/ash)), 0, "the floor starts without ash")
	TEST_ASSERT_NULL(user.get_active_hand(), "the actor starts with an empty hand for a folded flag")
	if(torn)
		flag.rip()
		TEST_ASSERT(flag.ripped, "actual ripping marks the original panel torn")
		TEST_ASSERT(other.ripped, "actual ripping propagates to the paired panel")
	if(burn)
		TEST_ASSERT_EQUAL(test_op_handler(flag, "burnt_down", user), OP_OK, "actual burning completion reports success")
	else
		flag.unfasten(user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(flag), "actual removal consumes the original panel")
	TEST_ASSERT(QDELETED(other), "actual removal deletes its linked second panel")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/sign/flag), "removal leaves no duplicate wall flag")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/decal/cleanable/ash)), burn ? 1 : 0, "only burning creates exactly one ash decal")
	if(!torn && !burn)
		var/obj/item/flag/folded = user.get_active_hand()
		TEST_ASSERT(istype(folded), "actual unfastening places the original type's folded flag in the free hand")
		TEST_ASSERT_EQUAL(folded.type, /obj/item/flag, "the blank panel returns its declared actual boxed flag type")
		TEST_ASSERT_EQUAL(folded.loc, user, "the actual folded flag remains held by the actor")
		TEST_ASSERT_EQUAL(length(contents_of(user, /obj/item/flag)), 1, "unfastening returns exactly one folded flag for both panels")
	else
		TEST_ASSERT_NULL(user.get_active_hand(), "torn or burned removal creates no folded flag in the actor's hand")
		TEST_ASSERT_EQUAL(length(contents_of(user, /obj/item/flag)), 0, "torn or burned removal returns no folded flag")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/flag)), 0, "removal creates no extra folded flag on the floor")
