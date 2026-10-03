/// Real fixed manuals expose their original instructional HTML and metadata through the book UI.
/datum/unit_test/interim_fixed_manual_data/Run()
	var/static/list/cases = list(
		list(/obj/item/book/manual/cook_guide, "Food for Dummies 2", "Ali Big", "Dough Creation:", "add 10 units of Flour to create Dough"),
		list(/obj/item/book/manual/bar_guide, "How to Alcohol (And other Drinks)", "Ali Big", "drink making", "Recipes have been placed at the top"),
		list(/obj/item/book/manual/rotary_electric_generator, "Rotary Electric Generator Manual", "Engineering Encyclopedia", "Operator's Manual - Rotary Electric Generator, D-Type", "SETUP AND OPERATING PROCEDURES"),
		list(/obj/item/book/manual/synthetic_life, "Synthetics", "Pontifex Publishing", "Synthetic Life", "A comprehensive guide"),
	)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	for(var/list/entry as anything in cases)
		var/obj/item/book/manual/book = allocate(entry[1])
		TEST_ASSERT(!QDELETED(book), "the actual fixed manual initializes alive: [entry[1]]")
		TEST_ASSERT_EQUAL(book.unique, 1, "actual fixed manuals retain their editing restriction: [entry[1]]")
		TEST_ASSERT_EQUAL(book.ui_title(user), entry[2], "actual fixed manual UI retains its published title: [entry[1]]")
		var/list/data = book.ui_data_obj_item_book(user, null, null)
		TEST_ASSERT_EQUAL(data["title"], entry[2], "actual book UI receives the original manual title: [entry[1]]")
		TEST_ASSERT_EQUAL(data["author"], entry[3], "actual book UI receives the original attribution: [entry[1]]")
		TEST_ASSERT(istext(data["content"]) && length(data["content"]) > 1000, "actual book UI receives substantial instructional HTML: [entry[1]]")
		TEST_ASSERT(findtext(data["content"], entry[4]), "actual book UI retains the original manual subject: [entry[1]]")
		TEST_ASSERT(findtext(data["content"], entry[5]), "actual book UI retains the original instructional passage: [entry[1]]")
		TEST_ASSERT(findtext(data["content"], "<html") && findtext(data["content"], "</html>"), "actual book UI retains the complete manual HTML document: [entry[1]]")
		TEST_ASSERT_EQUAL(data["content"], book.dat, "actual book UI returns the exact initialized manual HTML")
