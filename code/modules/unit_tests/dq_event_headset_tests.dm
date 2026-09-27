// The event headset used to write H.species.item_slowdown_mod = 0 on equip and
// restore a saved value on unequip. /datum/species instances are shared
// singletons (GLOB.all_species) -- one per species, not per mob -- so this
// mutated every human of that species while any single wearer had the
// headset on, and a second wearer equipping/unequipping their own headset
// would stomp the first wearer's saved restore value. It should have used
// worn_factors (BF_SLOWDOWN), which the item already sets, and never touched
// the shared species datum at all.

/datum/unit_test/dq_event_headset_does_not_mutate_shared_species_datum

/datum/unit_test/dq_event_headset_does_not_mutate_shared_species_datum/Run()
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(wearer.species, bystander.species, "two default humans should share the same species singleton (precondition for this test)")

	var/baseline_mod = wearer.species.item_slowdown_mod
	var/obj/item/radio/headset/event/headset = allocate(/obj/item/radio/headset/event)
	headset.slowdown_to_set = 0.5

	TEST_ASSERT(wearer.equip_to_slot_if_possible(headset, slot_l_ear, disable_warning = TRUE), "the event headset should equip to an ear slot")

	TEST_ASSERT_EQUAL(wearer.species.item_slowdown_mod, baseline_mod, "equipping the event headset must not mutate the shared species datum's item_slowdown_mod")
	TEST_ASSERT_EQUAL(bystander.species.item_slowdown_mod, baseline_mod, "an unrelated human sharing the same species singleton must be unaffected by someone else's headset")

	// The intended effect (extra movement delay while worn) should still land,
	// just via the wearer's own worn_factors instead of the shared species var.
	TEST_ASSERT_EQUAL(headset.worn_factors[BF_SLOWDOWN], 0.5, "the headset should contribute its slowdown via worn_factors")
	TEST_ASSERT_EQUAL(wearer.factor(BF_SLOWDOWN), 0.5, "the wearer's own BF_SLOWDOWN factor should reflect the headset")
	TEST_ASSERT_EQUAL(bystander.factor(BF_SLOWDOWN), 0, "the bystander should be unaffected by the wearer's headset")

	wearer.drop_from_inventory(headset)
	TEST_ASSERT_EQUAL(wearer.species.item_slowdown_mod, baseline_mod, "unequipping the event headset must not mutate the shared species datum either")
	TEST_ASSERT_EQUAL(wearer.factor(BF_SLOWDOWN), 0, "taking the headset off should remove its slowdown")

/// The headset's spells list used to store spell paths as plain strings missing
/// their /datum/ prefix ("/spell/targeted/unrestricted/mend" instead of
/// /datum/spell/targeted/unrestricted/mend), so `new thing(H)` tried to
/// instantiate a null type and runtimed on equip. Now that spells holds real
/// typed path literals, equipping should actually grant the spells and
/// unequipping should remove them again.
/datum/unit_test/dq_event_headset_grants_and_removes_its_spells

/datum/unit_test/dq_event_headset_grants_and_removes_its_spells/Run()
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human)
	var/obj/item/radio/headset/event/headset = allocate(/obj/item/radio/headset/event)

	TEST_ASSERT(headset.spells.len, "precondition: the headset should have spells configured")
	for(var/spell_type in headset.spells)
		TEST_ASSERT(ispath(spell_type, /datum/spell), "[spell_type] should be a real /datum/spell type path, not a bare string")

	TEST_ASSERT(wearer.equip_to_slot_if_possible(headset, slot_l_ear, disable_warning = TRUE), "the event headset should equip to an ear slot")

	TEST_ASSERT_EQUAL(length(headset.remove_spells), length(headset.spells), "equipping should have instantiated and granted every configured spell")
	for(var/datum/spell/granted_spell in headset.remove_spells)
		TEST_ASSERT(granted_spell in wearer.spell_list, "[granted_spell.type] should have been granted to the wearer on equip")

	wearer.drop_from_inventory(headset)
	TEST_ASSERT(!length(wearer.spell_list), "unequipping the headset should remove every spell it granted")
