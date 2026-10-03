/// Literal biological-disguise protection preserves the actual EMP refusal and the parent's choice-table construction.
/datum/unit_test/interim_changeling_clothing_emp_data
	var/parent_item_type = /obj/item/clothing/head/chameleon
	var/protected_item_type = /obj/item/clothing/head/chameleon/changeling

/datum/unit_test/interim_changeling_clothing_emp_data/suit
	parent_item_type = /obj/item/clothing/suit/chameleon
	protected_item_type = /obj/item/clothing/suit/chameleon/changeling

/datum/unit_test/interim_changeling_clothing_emp_data/shoes
	parent_item_type = /obj/item/clothing/shoes/chameleon
	protected_item_type = /obj/item/clothing/shoes/chameleon/changeling

/datum/unit_test/interim_changeling_clothing_emp_data/backpack
	parent_item_type = /obj/item/storage/backpack/chameleon
	protected_item_type = /obj/item/storage/backpack/chameleon/changeling

/datum/unit_test/interim_changeling_clothing_emp_data/gloves
	parent_item_type = /obj/item/clothing/gloves/chameleon
	protected_item_type = /obj/item/clothing/gloves/chameleon/changeling

/datum/unit_test/interim_changeling_clothing_emp_data/mask
	parent_item_type = /obj/item/clothing/mask/chameleon
	protected_item_type = /obj/item/clothing/mask/chameleon/changeling

/datum/unit_test/interim_changeling_clothing_emp_data/glasses
	parent_item_type = /obj/item/clothing/glasses/chameleon
	protected_item_type = /obj/item/clothing/glasses/chameleon/changeling

/datum/unit_test/interim_changeling_clothing_emp_data/belt
	parent_item_type = /obj/item/storage/belt/chameleon
	protected_item_type = /obj/item/storage/belt/chameleon/changeling

/datum/unit_test/interim_changeling_clothing_emp_data/Run()
	var/turf/T = test_floor()
	var/obj/item/biological = allocate(protected_item_type, T)
	var/obj/item/control = allocate(parent_item_type, T)
	TEST_ASSERT_EQUAL(biological.emp_protection_flags, EMP_PROTECT_SELF, "Actual fabricated clothing retains only the original self-protection bit")
	TEST_ASSERT_EQUAL(control.emp_protection_flags, NONE, "The actual parent control has no biological EMP protection")
	TEST_ASSERT(!biological.canremove, "The actual fabricated subtype retains its biological removal restriction")
	var/list/choices
	switch(parent_item_type)
		if(/obj/item/clothing/head/chameleon)
			choices = GLOB.chamelion_head_choices
		if(/obj/item/clothing/suit/chameleon)
			choices = GLOB.chamelion_suit_choices
		if(/obj/item/clothing/shoes/chameleon)
			choices = GLOB.chamelion_shoe_choices
		if(/obj/item/storage/backpack/chameleon)
			choices = GLOB.chamelion_back_choices
		if(/obj/item/clothing/gloves/chameleon)
			choices = GLOB.chamelion_glove_choices
		if(/obj/item/clothing/mask/chameleon)
			choices = GLOB.chamelion_mask_choices
		if(/obj/item/clothing/glasses/chameleon)
			var/obj/item/clothing/glasses/chameleon/glasses = biological
			TEST_ASSERT_EQUAL(glasses.type, /obj/item/clothing/glasses/chameleon/changeling, "The real glasses choice-table fixture uses the exact biological subtype")
			choices = glasses.clothing_choices
		if(/obj/item/storage/belt/chameleon)
			choices = GLOB.chamelion_belt_choices
	TEST_ASSERT(length(choices) > 0, "The real inherited constructor supplies a nonempty chameleon appearance table")
	for(var/choice in choices)
		TEST_ASSERT(ispath(choices[choice], /obj/item), "Actual parent appearance choices identify real item types")
	var/original_name = biological.name
	var/original_desc = biological.desc
	var/original_state = biological.icon_state
	// A renamed real parent item makes its actual reveal falsifiable, including backpack and belt whose default names already match the reveal.
	control.name = "Unrevealed test disguise"
	biological.emp_act(1)
	control.emp_act(1)
	TEST_ASSERT_EQUAL(biological.name, original_name, "Actual EMP preserves the protected biological disguise name")
	TEST_ASSERT_EQUAL(biological.desc, original_desc, "Actual EMP preserves the protected biological disguise description")
	TEST_ASSERT_EQUAL(biological.icon_state, original_state, "Actual EMP preserves the protected biological disguise icon")
	TEST_ASSERT(control.name != "Unrevealed test disguise", "The same real EMP runs the unprotected parent's actual reveal reaction")
	TEST_ASSERT_EQUAL(biological.loc, T, "Actual protected EMP preserves the original item location")
	TEST_ASSERT_EQUAL(control.loc, T, "Actual control reveal preserves the original item location")
	TEST_ASSERT(!QDELETED(biological) && !QDELETED(control), "Actual protected and control EMP preserve both original item identities")
