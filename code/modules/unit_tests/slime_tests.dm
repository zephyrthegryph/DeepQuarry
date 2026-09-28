/datum/unit_test/all_slimes_must_have_research_values

/datum/unit_test/all_slimes_must_have_research_values/Run()
	var/failed = FALSE

	for(var/slime in subtypesof(/obj/item/slime_extract))
		if(!(slime in GLOB.research_service.techweb_point_items))
			TEST_NOTICE(src, "Slimes - [slime] type did not have a GLOB.research_service.techweb_point_items value associated with it.")
			failed = TRUE

	if(failed)
		TEST_FAIL("All xenobio slimes must have a research point value")
