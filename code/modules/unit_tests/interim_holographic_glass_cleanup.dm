/// Actual holographic glass fades on destructive damage without returning physical glass parts.
/datum/unit_test/interim_holographic_glass_cleanup
	var/windoor = FALSE

/datum/unit_test/interim_holographic_glass_cleanup/windoor
	windoor = TRUE

/datum/unit_test/interim_holographic_glass_cleanup/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/glass = allocate(windoor ? /obj/machinery/door/window/holowindoor : /obj/structure/window/reinforced/holowindow, T)
	TEST_ASSERT(!QDELETED(glass), "actual holographic glass initializes alive")
	TEST_ASSERT(glass.get_integrity() > 0, "actual holographic glass starts with real integrity")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/material/shard)), 0, "actual holographic fixture starts without physical glass shards")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/cable_coil)), 0, "actual holographic fixture starts without physical cable parts")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/airlock_electronics)), 0, "actual holographic fixture starts without physical electronics")
	if(!windoor)
		var/obj/structure/window/reinforced/holowindow/window = glass
		TEST_ASSERT_EQUAL(window.interaction_tool_act(user, wrench, TOOL_WRENCH), ITEM_INTERACT_BLOCKING, "actual holographic window refuses physical disassembly")
		TEST_ASSERT(!QDELETED(window), "actual disassembly refusal preserves the holographic window")
	glass.take_damage(0, BRUTE, MELEE, sound_effect = FALSE)
	TEST_ASSERT(!QDELETED(glass), "actual zero-damage hit preserves holographic glass")
	glass.take_damage(glass.max_integrity * 3, BRUTE, MELEE, sound_effect = FALSE)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(glass), "actual destructive damage shatters and consumes the original holographic glass")
	if(windoor)
		TEST_ASSERT(!glass.density, "actual holographic windoor clears blocking density before fading")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/material/shard)), 0, "actual holographic shattering returns no physical glass shards")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/cable_coil)), 0, "actual holographic shattering returns no physical cable parts")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/airlock_electronics)), 0, "actual holographic shattering returns no physical electronics")
	TEST_ASSERT(!QDELETED(user) && !QDELETED(wrench), "actual holographic cleanup preserves the actor and its tool")
