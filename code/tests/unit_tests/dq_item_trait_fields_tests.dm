// Per-type item constants moved off /obj/item into its type traits (doc/rewrite/proposals/base_vars.md): embed_chance, injury_kind and
// injury_kinds into item_combat(), digestable into item_rules().

/// A type's declaration is read through the trait, and a run-time write gives the item its own copy without touching the type.
/datum/unit_test/dq_item_trait_fields/Run()
	var/obj/item/ratvarian_spear/spear = allocate(/obj/item/ratvarian_spear)
	TEST_ASSERT_EQUAL(combat_of(spear).injury_kind, INJURY_CUT, "the spear's declared injury kind is read from item_combat")
	TEST_ASSERT_EQUAL(combat_of_type(/obj/item).injury_kind, INJURY_BLUNT, "the base default is blunt")
	TEST_ASSERT_EQUAL(combat_of_type(/obj/item).embed_chance, -1, "the base embed chance is the size default")
	spear.set_injury_kind(INJURY_BURN)
	TEST_ASSERT_EQUAL(combat_of(spear).injury_kind, INJURY_BURN, "a run-time write lands on the item")
	TEST_ASSERT_EQUAL(combat_of_type(/obj/item/ratvarian_spear).injury_kind, INJURY_CUT, "and leaves the type's declaration alone")
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	TEST_ASSERT(item_rules_of(pen).digestable, "items are digestable by default")
	pen.set_digestable(FALSE)
	TEST_ASSERT(!item_rules_of(pen).digestable, "the gear tweak's write turns it off for this item")
	TEST_ASSERT(!pen.digest_act(null, 0), "and an undigestable item refuses digestion")
