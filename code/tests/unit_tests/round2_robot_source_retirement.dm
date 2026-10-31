/// Exercise the actual source-selection helper; UI authorization/delivery is outside this test.
/datum/unit_test/round2_robot_source_retirement/Run()
	var/datum/eventkit/modify_robot/model = allocate(/datum/eventkit/modify_robot)
	var/selection
	for(var/key in GLOB.robot_modules)
		if(GLOB.robot_modules[key] == /obj/item/robot_module/robot/standard)
			selection = key
			break
	TEST_ASSERT_NOTNULL(selection, "the current real registry contains the standard module selection")
	model.ui_act_select_source(null, selection)
	var/mob/living/silicon/robot/original = model.source
	TEST_ASSERT_NOTNULL(original, "actual source selection creates its real nullspace robot")
	TEST_ASSERT(!QDELETED(original), "the original owned source is alive before replacement")
	TEST_ASSERT_EQUAL(original.type, /mob/living/silicon/robot, "standard selection constructs the ordinary real robot type")
	TEST_ASSERT_EQUAL(original.modtype, selection, "original source records the actual registry label")
	var/obj/item/robot_module/original_module = original.module
	TEST_ASSERT(istype(original_module, /obj/item/robot_module/robot/standard), "actual module constructor installs the standard module")
	TEST_ASSERT_EQUAL(original_module.loc, original, "original module belongs physically to its exact source")
	model.ui_act_select_source(null, selection)
	var/mob/living/silicon/robot/replacement = model.source
	TEST_ASSERT_NOTNULL(replacement, "replacement source is created by the actual same helper")
	TEST_ASSERT(replacement != original && !QDELETED(replacement), "replacement is a distinct live real robot")
	TEST_ASSERT(QDELETED(original), "the exact original owned source is retired")
	TEST_ASSERT(QDELETED(original_module), "retiring the source disposes its original actual module")
	TEST_ASSERT_EQUAL(replacement.type, /mob/living/silicon/robot, "replacement preserves the selected real robot type")
	TEST_ASSERT_EQUAL(replacement.modtype, selection, "replacement retains the actual selected registry label")
	var/obj/item/robot_module/replacement_module = replacement.module
	TEST_ASSERT(istype(replacement_module, /obj/item/robot_module/robot/standard), "replacement has a fresh correctly installed standard module")
	TEST_ASSERT(replacement_module != original_module && !QDELETED(replacement_module), "replacement module is independent live state")
	TEST_ASSERT_EQUAL(replacement_module.loc, replacement, "replacement module belongs to its exact source")
	TEST_ASSERT(replacement.emag_items, "actual source-selection configuration remains enabled")
