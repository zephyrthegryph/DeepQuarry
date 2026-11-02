// Character setup batch: the migrations and rules of the identity tab .

/// Loads the fixture save with character1's keys overridden.
/proc/dq_test_load_character(list/overrides)
	var/path = dq_test_write_character_save(overrides)
	var/datum/preferences/dq_test_stub/P = new()
	P.load_and_save = TRUE
	P.path = path
	P.load_savefile()
	P.load_character(1)
	fdel(path)
	return P

/// An old {key: language} save keeps its keys, every other known language has its own default, and a key already held is refused.
/datum/unit_test/dq_language_keys_migrate_and_conflict

/datum/unit_test/dq_language_keys_migrate_and_conflict/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "language" = list(LANGUAGE_UNATHI), "language_custom_keys" = list("q" = LANGUAGE_UNATHI), "language_prefixes" = list("+", "#", ",")))
	var/list/map = P.language_key_map()
	TEST_ASSERT_EQUAL(map[LANGUAGE_UNATHI], ",q", "the saved custom key is kept, now as a whole prefix")
	var/species_lang = P.species_language_name()
	var/datum/language/own = GLOB.all_languages[species_lang]
	TEST_ASSERT_EQUAL(map[species_lang], language_default_prefix(own), "a language without a saved key uses its own")
	TEST_ASSERT_NOTNULL(P.language_key_problem(species_lang, ",q"), "a held key is a conflict")
	TEST_ASSERT_NOTNULL(P.language_key_problem(species_lang, ":x"), "radio syntax is refused")
	TEST_ASSERT_NOTNULL(P.language_key_problem(species_lang, "ab"), "a word is refused")
	TEST_ASSERT_NOTNULL(P.language_key_problem(LANGUAGE_SIIK, ",w"), "an unknown language is refused")
	TEST_ASSERT_NULL(P.set_language_key(LANGUAGE_UNATHI, ",7"), "a free prefix is taken")
	TEST_ASSERT_EQUAL(P.language_key_map()[LANGUAGE_UNATHI], ",7", "the new key replaces the old")
	var/list/custom = P.read_preference(/datum/preference/language_custom_keys)
	TEST_ASSERT(!(",q" in custom), "the old key is freed")

/// The old default ("common", not a language) and a language the character does not know resolve to the species language; the editor refuses unknowns.
/datum/unit_test/dq_preferred_language_rules

/datum/unit_test/dq_preferred_language_rules/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "language" = list(LANGUAGE_UNATHI)))
	var/datum/preference/text/human/preferred_language/pref = GLOB.preference_entries[/datum/preference/text/human/preferred_language]
	TEST_ASSERT_EQUAL(pref.sanitize("common", P), P.species_language_name(), "the old default falls back to the species language")
	var/datum/preference_editor/language/editor = GLOB.preference_editors_by_key["language"]
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_preferred", list("language" = LANGUAGE_SIIK), null), PREF_UPDATE_REJECTED, "an unknown language cannot be preferred")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_preferred", list("language" = LANGUAGE_UNATHI), null), PREF_UPDATE_ACCEPTED, "a known one can")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "remove_language", list("language" = LANGUAGE_UNATHI), null), PREF_UPDATE_ACCEPTED, "the language can be removed")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/text/human/preferred_language), P.species_language_name(), "removing the preferred language falls back to the species language")

/// What a spawn runs on the mob: the keys reach mob.language_keys, the preferred language becomes the default, and parsing honours the key.
/datum/unit_test/dq_language_prefs_reach_the_mob

/datum/unit_test/dq_language_prefs_reach_the_mob/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "language" = list(LANGUAGE_UNATHI), "language_custom_keys" = list("q" = LANGUAGE_UNATHI), "preflang" = LANGUAGE_UNATHI))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.add_language(LANGUAGE_UNATHI)
	H.apply_language_prefs(P)
	var/datum/language/unathi = GLOB.all_languages[LANGUAGE_UNATHI]
	TEST_ASSERT_EQUAL(H.language_keys[",q"], unathi, "the key is bound on the mob")
	TEST_ASSERT_EQUAL(H.get_default_language(), unathi, "the preferred language is the default")
	var/list/pieces = H.parse_languages(",q hello")
	var/datum/multilingual_say_piece/piece = pieces[1]
	TEST_ASSERT_EQUAL(piece.speaking, unathi, "typing the prefix speaks the language")

/// The nine old zones land in General, Face and Body with no text lost; loading the result again changes nothing.
/datum/unit_test/dq_flavor_zone_migration

/datum/unit_test/dq_flavor_zone_migration/Run()
	var/list/old = list("general" = "G", "head" = "H", "face" = "F", "eyes" = "E", "torso" = "T", "arms" = "A", "hands" = "Ha", "legs" = "L", "feet" = "Fe")
	var/list/migrated = dq_migrate_flavor_zones(old)
	TEST_ASSERT_EQUAL(length(migrated), 3, "three entries")
	TEST_ASSERT_EQUAL(migrated["general"], "G", "general stays")
	TEST_ASSERT_EQUAL(migrated["face"], "Face: F\n\nHead: H\n\nEyes: E", "face, head and eyes join under labels")
	TEST_ASSERT_EQUAL(migrated["body"], "Torso: T\n\nArms: A\n\nHands: Ha\n\nLegs: L\n\nFeet: Fe", "the body zones join under labels")
	var/list/again = dq_migrate_flavor_zones(migrated)
	TEST_ASSERT_EQUAL(again["face"], migrated["face"], "migrating twice changes nothing")
	var/list/single = dq_migrate_flavor_zones(list("legs" = "Long legs"))
	TEST_ASSERT_EQUAL(single["body"], "Long legs", "a lone zone moves without a label")
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("flavor_texts" = list("eyes" = "Green", "arms" = "Strong")))
	var/list/loaded = P.read_preference(/datum/preference/flavor_texts)
	TEST_ASSERT_EQUAL(loaded["face"], "Green", "a loaded save is migrated")
	TEST_ASSERT_EQUAL(loaded["body"], "Strong", "a loaded save is migrated")

/// General always shows; Face hides under a mask; Body hides only when everything worn covers the whole body, with real equipment.
/datum/unit_test/dq_flavor_hidden_entries

/datum/unit_test/dq_flavor_hidden_entries/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bio.flavor_texts = list("general" = "GEN", "face" = "FACE", "body" = "BODY")
	TEST_ASSERT(("face" in H.visible_flavor_zones()) && ("body" in H.visible_flavor_zones()), "a bare body shows every entry")
	var/obj/item/clothing/under/color/grey/uniform = allocate(/obj/item/clothing/under/color/grey)
	TEST_ASSERT(worn_of(uniform).covers & UPPER_TORSO, "a jumpsuit covers the torso")
	TEST_ASSERT(H.equip_to_slot(uniform, SLOT_ID_UNIFORM), "the uniform is worn")
	TEST_ASSERT("body" in H.visible_flavor_zones(), "a jumpsuit alone shows Body")
	var/obj/item/clothing/shoes/black/shoes = allocate(/obj/item/clothing/shoes/black)
	var/obj/item/clothing/gloves/black/gloves = allocate(/obj/item/clothing/gloves/black)
	TEST_ASSERT(H.equip_to_slot(shoes, SLOT_ID_SHOES), "shoes are worn")
	TEST_ASSERT(H.equip_to_slot(gloves, SLOT_ID_GLOVES), "gloves are worn")
	TEST_ASSERT("body" in H.visible_flavor_zones(), "partial gear shows Body")
	var/obj/item/clothing/head/helmet/space/helmet = allocate(/obj/item/clothing/head/helmet/space)
	TEST_ASSERT(H.equip_to_slot(helmet, SLOT_ID_HEAD), "the helmet is worn")
	TEST_ASSERT(!("body" in H.visible_flavor_zones()), "a head-to-toe outfit hides Body")
	TEST_ASSERT(!("face" in H.visible_flavor_zones()), "and the helmet hides Face")
	TEST_ASSERT("general" in H.visible_flavor_zones(), "General always shows")
	H.print_flavor_text(0)
	TEST_ASSERT(!findtext(H.bio.flavor_text, "BODY"), "a hidden entry is not printed")
	TEST_ASSERT(findtext(H.bio.flavor_text, "GEN"), "General prints")
	TEST_ASSERT(H.drop_from_inventory(gloves), "the gloves come off")
	TEST_ASSERT("body" in H.visible_flavor_zones(), "bare hands show Body again")
	TEST_ASSERT(H.equip_to_slot(gloves, SLOT_ID_GLOVES), "the gloves go back on")
	TEST_ASSERT(!("body" in H.visible_flavor_zones()), "covered again")
	TEST_ASSERT(H.drop_from_inventory(helmet), "the helmet comes off")
	TEST_ASSERT("body" in H.visible_flavor_zones(), "a bare head shows Body again")
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas)
	TEST_ASSERT(H.equip_to_slot(mask, SLOT_ID_MASK), "the mask is worn")
	TEST_ASSERT(!("face" in H.visible_flavor_zones()), "a gas mask hides Face")
	TEST_ASSERT("body" in H.visible_flavor_zones(), "a gas mask leaves the head, so Body shows")

/// Uniform coverage: the base declares the torso; what is not worn over it stays off it.
/datum/unit_test/dq_uniform_coverage

/datum/unit_test/dq_uniform_coverage/Run()
	TEST_ASSERT_EQUAL(worn_of_type(/obj/item/clothing/under).covers, CHEST|ARMS|LEGS, "the base uniform")
	TEST_ASSERT_EQUAL(worn_of_type(/obj/item/clothing/under/swimsuit/black).covers, CHEST, "a swimsuit is the torso alone")
	TEST_ASSERT_EQUAL(worn_of_type(/obj/item/clothing/under/shorts/red).covers, LOWER_TORSO, "shorts keep their own")
	TEST_ASSERT_EQUAL(worn_of_type(/obj/item/clothing/under/pants/black).covers, LOWER_TORSO|LEGS, "pants keep their own")
	TEST_ASSERT_EQUAL(worn_of_type(/obj/item/clothing/under/skirt/red).covers, LOWER_TORSO, "skirts keep their own")

/// None and invalid saved dates become real ones; the editor takes only real dates.
/datum/unit_test/dq_birthday_only_real_dates

/datum/unit_test/dq_birthday_only_real_dates/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("bday_month" = 0, "bday_day" = 0))
	var/month = P.read_preference(/datum/preference/numeric/human/bday_month)
	var/day = P.read_preference(/datum/preference/numeric/human/bday_day)
	TEST_ASSERT(month >= 1 && month <= 12, "an unset month becomes a month ([month])")
	TEST_ASSERT(day >= 1 && day <= birth_month_days(month), "an unset day becomes a day of it ([day])")
	P = dq_test_load_character(list("bday_month" = 2, "bday_day" = 31))
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/numeric/human/bday_month), 2, "a real month is kept")
	TEST_ASSERT(P.read_preference(/datum/preference/numeric/human/bday_day) <= 29, "February 31st is not kept")
	P = dq_test_load_character(list("bday_month" = 3, "bday_day" = 5))
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/numeric/human/bday_day), 5, "a real date is kept")
	var/datum/preference_editor/birthday/editor = GLOB.preference_editors_by_key["birthday"]
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_month", list("value" = "0"), null), PREF_UPDATE_REJECTED, "no month is refused")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_day", list("value" = "0"), null), PREF_UPDATE_REJECTED, "no day is refused")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_day", list("value" = "31"), null), PREF_UPDATE_ACCEPTED, "March 31st exists")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_month", list("value" = "2"), null), PREF_UPDATE_ACCEPTED, "February is taken")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/numeric/human/bday_day), 29, "the day follows the shorter month")
	TEST_ASSERT_EQUAL(editor.handle_action(P, "set_day", list("value" = "30"), null), PREF_UPDATE_REJECTED, "February 30th is refused")

/// Old levels map to Default at that level; a named hiss applies on another species; Default follows the species; tooltips come from the maps.
/datum/unit_test/dq_autohiss_exact_types

/datum/unit_test/dq_autohiss_exact_types/Run()
	var/datum/preference/text/human/autohiss/pref = GLOB.preference_entries[/datum/preference/text/human/autohiss]
	TEST_ASSERT_EQUAL(pref.pref_deserialize("Full", null), "Default (Full)", "old Full")
	TEST_ASSERT_EQUAL(pref.pref_deserialize("Basic", null), "Default (Basic)", "old Basic")
	TEST_ASSERT_EQUAL(pref.pref_deserialize("Off", null), "Off", "Off stays")
	TEST_ASSERT_EQUAL(pref.pref_deserialize("Tajaran r-roll", null), "Tajaran r-roll", "a chosen type stays")
	TEST_ASSERT_EQUAL(pref.pref_deserialize("junk", null), "Default (Full)", "junk is the default")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/language/common = GLOB.all_languages[LANGUAGE_GALCOM]
	TEST_ASSERT_EQUAL(H.autohiss_by_choice("sir", common, "Off"), "sir", "Off changes nothing")
	TEST_ASSERT_EQUAL(H.autohiss_by_choice("sir", common, "Default (Full)"), "sir", "a human has no hiss of its own")
	TEST_ASSERT(findtext(H.autohiss_by_choice("sir", common, "Unathi hiss (Basic)"), "ss"), "the Unathi hiss applies on a human")
	TEST_ASSERT(findtext(H.autohiss_by_choice("sir", common, "Tajaran r-roll"), "rr"), "the r-roll applies on a human")
	TEST_ASSERT_EQUAL(H.autohiss_by_choice("sir", GLOB.all_languages[LANGUAGE_UNATHI], "Unathi hiss (Basic)"), "sir", "its own language is exempt")
	TEST_ASSERT_EQUAL(H.autohiss_by_choice("x", common, "Unathi hiss (Basic)"), "x", "Basic leaves the extra map out")
	TEST_ASSERT(findtext(H.autohiss_by_choice("x", common, "Unathi hiss (Full)"), "ks"), "Full has it")
	TEST_ASSERT_NOTEQUAL(H.autohiss_by_choice("the", common, "Yingish lisp (Full)"), "the", "a several-letter key applies")
	TEST_ASSERT_EQUAL(H.autohiss_by_choice("the", common, "Yingish lisp (Full)"), "z", "and replaces all its letters")
	H.set_species(SPECIES_UNATHI)
	TEST_ASSERT(findtext(H.autohiss_by_choice("sir", common, "Default (Basic)"), "ss"), "Default is the species' hiss")
	TEST_ASSERT(findtext(autohiss_choice_tooltips()["Unathi hiss (Basic)"], "s becomes ss, sss or ssss"), "the tooltip is generated from the map")
	TEST_ASSERT(!GLOB.autohiss_choices["Tajaran r-roll (Full)"], "a hiss without an extra map has one level")
	for(var/choice in GLOB.autohiss_choices)
		TEST_ASSERT(autohiss_choice_tooltips()[choice], "[choice] has a tooltip")

/// Name, gender and demographics are one section; robots still lose age and birthday.
/datum/unit_test/dq_identity_groups_merged

/datum/unit_test/dq_identity_groups_merged/Run()
	TEST_ASSERT_EQUAL(GLOB.dq_group_display_merge["gender"], "name", "gender joins name")
	TEST_ASSERT_EQUAL(GLOB.dq_group_display_merge["demographics"], "name", "demographics joins name")
	TEST_ASSERT("demographics" in GLOB.dq_robot_mode_hidden_groups, "gating still reads the real group")
	TEST_ASSERT(!("gender" in GLOB.dq_group_order["identity"]), "the merged groups are not ordered separately")

/// The loadout tab's preview wears the job outfit with both preview toggles off, and other tabs still honour them; no job set falls back to Intern.
/datum/unit_test/dq_loadout_tab_preview_dressed

/datum/unit_test/dq_loadout_tab_preview_dressed/Run()
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "preview_loadout" = 0, "preview_job" = 0))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	P.dress_preview_mob(H)
	TEST_ASSERT_NULL(H.get_equipped_item(SLOT_ID_UNIFORM), "with the toggles off another tab shows no outfit")
	H.delete_inventory(TRUE)
	P.dress_preview_mob(H, TRUE)
	TEST_ASSERT_NOTNULL(H.get_equipped_item(SLOT_ID_UNIFORM), "the loadout tab shows the job outfit anyway")

/// Voice settings are in Identity; the antag tab is admin-only and a clientless (player) prefs does not see it.
/datum/unit_test/dq_voice_in_identity_antag_hidden

/datum/unit_test/dq_voice_in_identity_antag_hidden/Run()
	var/datum/preference/voice = GLOB.preference_entries[/datum/preference/text/human/voice_sound]
	TEST_ASSERT_EQUAL(voice.get_category(null), "identity", "voice sound is in Identity")
	TEST_ASSERT("voice" in GLOB.dq_group_order["identity"], "and ordered there")
	TEST_ASSERT("antag" in GLOB.dq_admin_only_categories, "antag is admin-only")
	TEST_ASSERT(!dq_sees_admin_categories(new /datum/preferences/dq_test_stub), "a player does not see it")
	TEST_ASSERT("antag" in dq_character_category_index("human"), "the shared index still holds it for admins")

/// Size is part of Identity, and the flavor inspection is the examine's own text for this character.
/datum/unit_test/dq_size_in_identity_and_inspection

/datum/unit_test/dq_size_in_identity_and_inspection/Run()
	var/datum/preference/size = GLOB.preference_entries[/datum/preference/numeric/human/size_multiplier]
	TEST_ASSERT_EQUAL(size.get_category(null), "identity", "size is in Identity")
	TEST_ASSERT("size" in GLOB.dq_robot_mode_hidden_groups, "cyborgs still do not get size")
	var/datum/preferences/dq_test_stub/P = dq_test_load_character(list("species" = SPECIES_HUMAN, "flavor_texts" = list("general" = "A very tall person.")))
	var/text = P.dq_examine_profile_text()
	TEST_ASSERT(findtext(text, "A very tall person."), "the examine text carries the flavor: [text]")
