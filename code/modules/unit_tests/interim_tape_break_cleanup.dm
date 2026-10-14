/datum/unit_test/interim_tape_break_cleanup
	var/stance = I_HURT

/datum/unit_test/interim_tape_break_cleanup/help
	stance = I_HELP

/datum/unit_test/interim_tape_break_cleanup/Run()
	var/turf/T = get_step(test_floor(), EAST)
	var/turf/west = get_step(T, WEST)
	var/turf/east = get_step(T, EAST)
	TEST_ASSERT(isfloorturf(T) && isfloorturf(west) && isfloorturf(east), "The real tape line uses three original room floors")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(actor.put_in_active_hand(pen), "The actual actor holds the original unrelated pen")
	var/obj/item/tape/source = allocate(/obj/item/tape, T)
	var/obj/item/tape/left = allocate(/obj/item/tape, west)
	var/obj/item/tape/right = allocate(/obj/item/tape, east)
	var/obj/item/tape/unconnected = allocate(/obj/item/tape, east)
	source.set_tape_dir(EAST | WEST)
	left.set_tape_dir(EAST)
	right.set_tape_dir(WEST)
	unconnected.set_tape_dir(NORTH)
	var/list/line = source.gettapeline()
	TEST_ASSERT(left in line, "The actual tape line discovers its original western segment")
	TEST_ASSERT(right in line, "The actual tape line discovers its original eastern segment")
	TEST_ASSERT(unconnected in line, "The actual line includes the neighboring unconnected tape before checking its direction")
	source.breaktape(actor, stance)
	if(stance == I_HELP)
		TEST_ASSERT(!QDELETED(source) && source.loc == T, "Actual help intent refuses to break the original source")
		TEST_ASSERT(!QDELETED(left) && left.loc == west, "Actual help refusal preserves the original western segment")
		TEST_ASSERT(!QDELETED(right) && right.loc == east, "Actual help refusal preserves the original eastern segment")
	else
		TEST_ASSERT(QDELETED(source), "Actual breaking consumes the exact original source")
		TEST_ASSERT(QDELETED(left), "Actual breaking deletes the original segment connected from the west")
		TEST_ASSERT(QDELETED(right), "Actual breaking deletes the original segment connected from the east")
	TEST_ASSERT(!QDELETED(unconnected) && unconnected.loc == east, "Actual tape handling preserves the exact neighboring tape not directed toward its source")
	TEST_ASSERT_EQUAL(unconnected.tape_dir, NORTH, "Actual tape handling preserves the unrelated original tape direction")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), pen, "Actual tape handling preserves the unrelated original held pen")
	TEST_ASSERT(!QDELETED(actor) && actor.loc == T, "Actual tape handling preserves the original actor and floor")
