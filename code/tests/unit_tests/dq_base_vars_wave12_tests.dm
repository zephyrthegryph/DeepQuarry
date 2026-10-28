// base_vars wave 12: the datums a base type held in a var of its own that became sparse links (turfslip, the setup HUD button, the faction ledger, the default
// attack, the disposal connection ...), the weak slots (throw_source, armor_override), losebreath moved onto the physiology, the voice name moved into the
// mob_kind trait, and traumatic_shock deleted (it mirrored current_pain()).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// losebreath is the physiology's: no var and no slot on the mob, 0 for a mob without a physiology, and the breath adjusters clamp it.
/datum/unit_test/dq_base_vars_wave12_losebreath

/datum/unit_test/dq_base_vars_wave12_losebreath/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/physiology/P = H.body?.physiology
	TEST_ASSERT_NOTNULL(P, "a human body has a physiology")
	TEST_ASSERT(!("losebreath" in H.vars), "losebreath is not a var of the mob")
	TEST_ASSERT_EQUAL(H.losebreath(), 0, "a mob breathes normally at first")
	H.set_losebreath(5)
	TEST_ASSERT_EQUAL(P.losebreath, 5, "the value is the physiology's field")
	TEST_ASSERT_EQUAL(H.losebreath(), 5, "the mob reads it from there")
	H.AdjustLosebreath(100)
	TEST_ASSERT_EQUAL(H.losebreath(), 25, "the adjuster clamps it to 25")
	H.set_losebreath(0)
	TEST_ASSERT_NULL(H.sparse_slots, "no slot is left behind")

/// The weak slots: where a thrown thing came from and an instance's own armour, read back while the datum lives.
/datum/unit_test/dq_base_vars_wave12_weak_slots

/datum/unit_test/dq_base_vars_wave12_weak_slots/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/clothing/suit/armor/vest/thing = allocate(/obj/item/clothing/suit/armor/vest, T)
	TEST_ASSERT(!("throw_source" in thing.vars), "throw_source is not a var")
	TEST_ASSERT(!("armor_override" in thing.vars), "armor_override is not a var")
	TEST_ASSERT_NULL(movable_throw_source(thing), "nothing was thrown from anywhere")
	sparse_ref_set(thing, throw_source, T)
	TEST_ASSERT_EQUAL(movable_throw_source(thing), T, "the throw source reads back")
	sparse_ref_set(thing, throw_source, null)
	TEST_ASSERT_NULL(movable_throw_source(thing), "and clears")
	var/datum/armor/plate = dq_armor(list(MELEE = 33))
	thing.set_armor(plate)
	TEST_ASSERT_EQUAL(atom_armor_override(thing), plate, "the instance's armour is its override")
	thing.set_armor(null)
	TEST_ASSERT_NULL(atom_armor_override(thing), "set_armor(null) drops the override")

/// The owned helper datums of a living mob are sparse links that go with it.
/datum/unit_test/dq_base_vars_wave12_owned_links

/datum/unit_test/dq_base_vars_wave12_owned_links/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	for(var/name in list("turfslip", "character_setup_button", "vore_panel_button", "vorePanel", "belly_overlay_tgui", "machine_shim", "inventory_panel", "faction_reputation", "default_attack", "traumatic_shock", "voice_name", "firesoundloop"))
		TEST_ASSERT(!(name in H.vars), "[name] is no longer a var of [H.type]")
	TEST_ASSERT_NULL(H.current_turfslip(), "no slide at first")
	var/datum/turfslip/slide = H.get_or_start_turfslip()
	TEST_ASSERT_EQUAL(H.current_turfslip(), slide, "the slide is the mob's")
	TEST_ASSERT_EQUAL(H.get_or_start_turfslip(), slide, "asking again gives the same slide")
	var/datum/character_setup_button/button = H.add_character_setup_button()
	TEST_ASSERT_EQUAL(H.character_setup_button(), button, "the setup button is the mob's")
	TEST_ASSERT_EQUAL(H.add_character_setup_button(), button, "it is made once")
	var/datum/faction_reputation_ledger/ledger = H.ensure_faction_reputation()
	TEST_ASSERT_EQUAL(H.faction_reputation(), ledger, "the ledger is the mob's")
	var/datum/unarmed_attack/attack = H.species.unarmed_attacks[1]
	TEST_ASSERT_NULL(H.default_attack(), "no default attack is chosen")
	H.set_default_attack(attack)
	TEST_ASSERT_EQUAL(H.default_attack(), attack, "the chosen attack reads back")
	H.set_default_attack(null)
	TEST_ASSERT_NULL(H.default_attack(), "choosing none clears it")
	H.set_default_attack(attack)
	qdel(H)
	TEST_ASSERT(QDELETED(slide), "the slide goes with its mob")
	TEST_ASSERT(QDELETED(button), "the setup button goes with its mob")
	TEST_ASSERT(!QDELETED(attack), "a shared attack outlives the mob that chose it")

/// A retired slide takes its link with it.
/datum/unit_test/dq_base_vars_wave12_slide_ends

/datum/unit_test/dq_base_vars_wave12_slide_ends/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/turfslip/slide = H.get_or_start_turfslip()
	slide.end_slip()
	TEST_ASSERT(QDELETED(slide), "the slide ended")
	TEST_ASSERT_NULL(H.current_turfslip(), "the mob has no slide after it")
	TEST_ASSERT_EQUAL(link_count(H, LK_TURFSLIP), 0, "and no link to it")

/// The voice name is the mob_kind trait: a type's default, the mob's own copy once set, and the type default untouched.
/datum/unit_test/dq_base_vars_wave12_voice_name

/datum/unit_test/dq_base_vars_wave12_voice_name/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_EQUAL(kind_of(H).voice_name, "unknown", "a human's voice is unknown")
	TEST_ASSERT_EQUAL(kind_of_type(/mob/living/silicon/robot).voice_name, "synthesized voice", "a silicon's is synthesized")
	TEST_ASSERT_EQUAL(kind_of_type(/mob/living/carbon/alien/diona).voice_name, "diona nymph", "a nymph's is its own")
	TEST_ASSERT_EQUAL(kind_of_type(/mob/living/simple_mob).voice_name, "unidentifiable voice", "everything else is unidentifiable")
	H.set_voice_name("Nobody")
	TEST_ASSERT_EQUAL(kind_of(H).voice_name, "Nobody", "the mob's own copy changed")
	TEST_ASSERT_EQUAL(kind_of_type(H.type).voice_name, "unknown", "the type's default did not")

/// A replaced disposal connection is retired and the object reads the new one.
/datum/unit_test/dq_base_vars_wave12_disposal_connection

/datum/unit_test/dq_base_vars_wave12_disposal_connection/Run()
	var/obj/structure/toilet/toilet = allocate(/obj/structure/toilet, test_floor())
	TEST_ASSERT(!("disposal_connection" in toilet.vars), "disposal_connection is not a var")
	var/datum/disposal_system_connection/first = toilet.disposal_connection()
	TEST_ASSERT_NOTNULL(first, "the toilet has its connection")
	var/datum/disposal_system_connection/second = toilet.add_disposal_connection()
	TEST_ASSERT(QDELETED(first), "the replaced connection is retired")
	TEST_ASSERT_EQUAL(toilet.disposal_connection(), second, "the object reads the new one")
	qdel(toilet)
	TEST_ASSERT(QDELETED(second), "the connection goes with its object")

#endif
