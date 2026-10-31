/// Actual token boundaries and parsed type selectors remain stable with an explicit actor.
/datum/unit_test/interim_sdql_tokenize_actor/Run()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/list/tokens = SDQL2_tokenize("SELECT /obj/item/pen WHERE name == 'O''Brien; pocket pen';", actor)
	TEST_ASSERT_EQUAL(length(tokens), 7, "the actual tokenizer preserves the quoted semicolon as part of one string token")
	TEST_ASSERT_EQUAL(tokens[1], "SELECT", "the actual tokenizer retains the command token")
	TEST_ASSERT_EQUAL(tokens[2], "/obj/item/pen", "the actual tokenizer retains the complete absolute type token")
	TEST_ASSERT_EQUAL(tokens[5], "==", "the actual tokenizer preserves the two-character comparison")
	TEST_ASSERT_EQUAL(tokens[6], "'O'Brien; pocket pen'", "the actual tokenizer unescapes a doubled apostrophe inside the quoted token")
	TEST_ASSERT_EQUAL(tokens[7], ";", "the actual tokenizer separates the final query delimiter")
	TEST_ASSERT_NULL(SDQL2_tokenize("SELECT /obj/item/pen WHERE name == 'unfinished", actor), "an unmatched quote makes the actual tokenizer refuse the query")
	TEST_ASSERT_NULL(SDQL2_tokenize("SELECT /obj/item/pen WHERE name == bad'quote'", actor), "an unexpected quote makes the actual tokenizer refuse the query")
	TEST_ASSERT_EQUAL(length(SDQL2_tokenize("SELECT /obj/item/pen", null)), 2, "a system caller can still tokenize a valid query without an actor")

/datum/unit_test/interim_sdql_parser_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/datum/SDQL_parser/parser = allocate(/datum/SDQL_parser, SDQL2_tokenize("SELECT /obj/item/pen", actor))
	var/list/tree = parser.parse(actor)
	TEST_ASSERT_EQUAL(parser.requester, actor, "the actual parser stores its explicit diagnostic actor")
	TEST_ASSERT(!parser.error, "the actual parser accepts the valid selector")
	var/list/selectors = tree["select"]
	TEST_ASSERT_NOTNULL(selectors, "the actual parsed query contains its select clause")
	TEST_ASSERT_EQUAL(selectors[1], /obj/item/pen, "the actual parser resolves the concrete absolute selected type")
	parser.parse(other)
	TEST_ASSERT_EQUAL(parser.requester, other, "the next actual parse replaces the previous diagnostic actor")
	parser.parse(null)
	TEST_ASSERT_NULL(parser.requester, "a system parse clears the previous actor relation")
	var/datum/SDQL_parser/invalid = allocate(/datum/SDQL_parser, SDQL2_tokenize("SELECT not_a_type", actor))
	TEST_ASSERT_EQUAL(length(invalid.parse(actor)), 0, "the actual parser refuses an invalid type selector")
	TEST_ASSERT(invalid.error, "the actual refused parse records its error state")
	TEST_ASSERT_EQUAL(invalid.requester, actor, "the actual refused parse retains its diagnostic actor")
	var/list/multiple = SDQL_parse(SDQL2_tokenize("SELECT /obj/item/pen; SELECT /obj/item/cell;", actor), actor)
	TEST_ASSERT_EQUAL(length(multiple), 2, "the actual batch parser keeps both valid query trees")
	var/list/first = multiple[1]
	var/list/second = multiple[2]
	var/list/first_select = first["select"]
	var/list/second_select = second["select"]
	TEST_ASSERT_EQUAL(first_select[1], /obj/item/pen, "the actual first query retains its selected type")
	TEST_ASSERT_EQUAL(second_select[1], /obj/item/cell, "the actual second query retains its distinct selected type")
