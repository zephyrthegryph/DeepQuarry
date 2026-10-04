/// Real native mode cycling preserves each tool's actual advertised tool quality.
/datum/unit_test/round2_transforming_tools_native
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_transforming_tools_native/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/completed = 0
	for(var/tool_type in list(/obj/item/tool/transforming/jawsoflife, /obj/item/tool/transforming/powerdrill, /obj/item/tool/transforming/altevian))
		var/obj/item/tool/transforming/tool = allocate(tool_type, T)
		TEST_ASSERT_EQUAL(tool.current_tooltype, 1, "actual constructor starts at first mode")
		TEST_ASSERT(tool.has_tool_quality(tool.possible_tooltypes[1]), "actual constructor exposes first mode quality")
		TEST_ASSERT(user.put_in_active_hand(tool), "actual actor holds original transforming tool")
		var/obj/item/weldingtool/original_welder = tool.welder
		var/first_icon = tool.icon_state
		var/first_description = tool.desc
		for(var/index = 2, index <= length(tool.possible_tooltypes), index++)
			test_click(user, tool, tool)
			test_time(1 SECOND)
			TEST_ASSERT_EQUAL(tool.current_tooltype, index, "actual native input advances exact original mode")
			TEST_ASSERT(tool.has_tool_quality(tool.possible_tooltypes[index]), "actual subtype exposes the newly selected quality")
			TEST_ASSERT_EQUAL(length(tool.tool_qualities), 1, "actual switch advertises only its selected quality")
			TEST_ASSERT_EQUAL(user.get_active_hand(), tool, "actual switch preserves exact actor hand")
			TEST_ASSERT_EQUAL(tool.welder, original_welder, "actual switch retains exact original internal welder")
		if(tool_type == /obj/item/tool/transforming/altevian)
			TEST_ASSERT_EQUAL(original_welder?.type, /obj/item/weldingtool/dummy/altevian, "real Altevian constructor creates its actual internal welder")
			TEST_ASSERT_EQUAL(tool.get_welder(), original_welder, "actual final welding mode resolves original welder")
			TEST_ASSERT_EQUAL(original_welder.loc, tool, "actual internal welder stays physically in original owner")
		test_click(user, tool, tool)
		test_time(1 SECOND)
		TEST_ASSERT_EQUAL(tool.current_tooltype, 1, "actual final native input wraps back to first mode")
		TEST_ASSERT(tool.has_tool_quality(tool.possible_tooltypes[1]), "actual wrap restores first tool quality")
		TEST_ASSERT_EQUAL(tool.icon_state, first_icon, "actual roundtrip restores original subtype icon")
		TEST_ASSERT_EQUAL(tool.desc, first_description, "actual roundtrip restores original subtype description")
		TEST_ASSERT_EQUAL(tool.welder, original_welder, "actual roundtrip preserves internal welder identity")
		TEST_ASSERT(user.unEquip(tool), "actual actor releases completed transforming tool")
		completed++
	TEST_ASSERT_EQUAL(completed, 3, "all three real transforming constructors completed")
