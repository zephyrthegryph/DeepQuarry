/datum/unit_test/interim_ant_structure_welder_cleanup
	var/structure_type = /obj/effect/ant_structure
	var/initial_integrity = 15

/datum/unit_test/interim_ant_structure_welder_cleanup/wall
	structure_type = /obj/effect/ant_structure/wall
	initial_integrity = 25

/datum/unit_test/interim_ant_structure_welder_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/effect/ant_structure/source = allocate(structure_type, T)
	var/obj/effect/ant_structure/neighbor = allocate(/obj/effect/ant_structure, T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	TEST_ASSERT(actor.put_in_active_hand(welder), "The actual actor holds its original real welding tool")
	TEST_ASSERT_EQUAL(source.get_integrity(), initial_integrity, "The actual canonical ant structure starts at its exact declared integrity")
	TEST_ASSERT(!welder.isOn(), "The actual original welding tool starts unlit")
	var/unlit_damage = round(welder.force / 4, DAMAGE_PRECISION)
	TEST_ASSERT(unlit_damage > 0 && unlit_damage < initial_integrity, "The actual unlit welder supplies a real nonlethal hit")
	TEST_ASSERT_EQUAL(test_op_handler(source, "interaction_hit_ant_structure", actor, welder), OP_PASS, "The actual unlit hit preserves its original handled result")
	TEST_ASSERT(!QDELETED(source) && source.loc == T, "The actual nonlethal unlit hit preserves its exact original source")
	TEST_ASSERT_EQUAL(source.get_integrity(), initial_integrity - unlit_damage, "The actual unlit hit applies its exact original quarter-force damage")
	TEST_ASSERT(test_op_handler(welder, "interaction_self", actor, welder), "The actual welding-tool self-use genuinely lights it")
	TEST_ASSERT(welder.isOn(), "The actual original welding tool is genuinely lit")
	var/fuel_before = welder.get_fuel()
	TEST_ASSERT_EQUAL(test_op_handler(source, "interaction_hit_ant_structure", actor, welder), OP_PASS, "The actual lit hit preserves its original handled result")
	if(initial_integrity > 15)
		TEST_ASSERT(!QDELETED(source), "The real thicker ant wall survives its original first fifteen-damage lit hit")
		TEST_ASSERT_EQUAL(source.get_integrity(), initial_integrity - unlit_damage - 15, "The real thicker ant wall loses exactly fifteen integrity from its first lit hit")
		TEST_ASSERT_EQUAL(test_op_handler(source, "interaction_hit_ant_structure", actor, welder), OP_PASS, "The real final wall hit preserves its original handled result")
	TEST_ASSERT(QDELETED(source), "Actual lethal welding damage consumes the exact original ant structure through its integrity destruction endpoint")
	TEST_ASSERT_EQUAL(welder.get_fuel(), fuel_before, "The real original ant-structure welding path retains its zero fuel charge")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), welder, "Actual ant cleanup preserves the exact original held welding tool")
	TEST_ASSERT(!QDELETED(actor) && !QDELETED(welder), "Actual ant cleanup preserves its original participants")
	TEST_ASSERT(!QDELETED(neighbor) && neighbor.loc == T, "Actual ant cleanup preserves its exact original neighboring structure")
	TEST_ASSERT_EQUAL(neighbor.get_integrity(), 15, "Actual ant cleanup preserves the original neighboring structure integrity")
	test_op_handler(welder, "interaction_self", actor, welder)
