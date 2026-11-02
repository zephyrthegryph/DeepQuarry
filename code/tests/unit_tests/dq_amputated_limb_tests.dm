// A limb whose parent is amputated goes with it: greyed in the window, refused by the editor, its saved setting kept but not applied.

/datum/unit_test/dq_amputated_parent_takes_children

/datum/unit_test/dq_amputated_parent_takes_children/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/list/organ_data = P.read_preference(/datum/preference/organ_data) || list()
	organ_data[BP_L_ARM] = "amputated"
	organ_data[BP_L_HAND] = "cyborg"
	organ_data[BP_R_HAND] = "cyborg"
	P.update_preference_by_type(/datum/preference/organ_data, organ_data)

	TEST_ASSERT_EQUAL(dq_limb_lost_through(organ_data, BP_L_HAND), BP_L_ARM, "a hand goes with its arm")
	TEST_ASSERT_NULL(dq_limb_lost_through(organ_data, BP_R_HAND), "the other hand does not")
	TEST_ASSERT_NULL(dq_limb_lost_through(organ_data, BP_L_ARM), "the amputated limb is not lost through itself")

	var/datum/preference_editor/organs/editor = new
	var/list/data = editor.build_ui_data(P)
	var/list/externals = data["externals"]
	TEST_ASSERT_EQUAL(externals[BP_L_HAND]["lost_via"], BP_L_ARM, "the window greys the hand")
	TEST_ASSERT_EQUAL(externals[BP_L_HAND]["status"], "cyborg", "and still knows its saved setting")
	TEST_ASSERT_EQUAL(editor.ui_act_set_external_status(null, list("limb" = BP_L_HAND, "status" = "normal"), P, null, null), PREF_UPDATE_REJECTED, "a lost limb's setting is refused")
	TEST_ASSERT_EQUAL(editor.ui_act_set_external_model(null, list("limb" = BP_L_HAND, "model" = GLOB.all_robolimbs[1]), P, null, null), PREF_UPDATE_REJECTED, "a lost limb's manufacturer is refused")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_HUMAN)
	var/datum/preference_apply_hook/organs/hook = new
	hook.apply(H, P)
	var/obj/item/organ/external/left = H.organs_by_name[BP_L_HAND]
	TEST_ASSERT(!left || left.is_stump() || !left.robotic, "the saved cybernetic hand does not apply")
	var/obj/item/organ/external/right = H.organs_by_name[BP_R_HAND]
	TEST_ASSERT(right?.robotic, "the hand on an intact arm does")
	fdel(P.path)

/// A save from before the toggle was removed loads without its key.
/datum/unit_test/dq_synth_markings_key_dropped

/datum/unit_test/dq_synth_markings_key_dropped/Run()
	var/list/raw = json_decode(file2text("code/tests/unit_tests/data/profile_saves/headless_preferences.json"))
	TEST_ASSERT("synth_markings" in raw["character1"], "the fixture is an old save with the key")
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/list/save_data = P.get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	TEST_ASSERT(!("synth_markings" in save_data), "loading drops it")
	fdel(P.path)

/// A cybernetic limb takes its children with it: Normal is refused below it, Amputated is not.
/datum/unit_test/dq_cybernetic_parent_moves_children

/datum/unit_test/dq_cybernetic_parent_moves_children/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/datum/preference_editor/organs/editor = new
	TEST_ASSERT_EQUAL(editor.ui_act_set_external_status(null, list("limb" = BP_R_ARM, "status" = "cyborg"), P, null, null), PREF_UPDATE_ACCEPTED, "the arm goes cybernetic")
	var/list/organ_data = P.read_preference(/datum/preference/organ_data)
	TEST_ASSERT_EQUAL(organ_data[BP_R_HAND], "cyborg", "the hand moves with it")
	TEST_ASSERT_EQUAL(editor.ui_act_set_external_status(null, list("limb" = BP_R_HAND, "status" = "normal"), P, null, null), PREF_UPDATE_REJECTED, "the hand cannot be Normal")
	TEST_ASSERT_EQUAL(editor.ui_act_set_external_status(null, list("limb" = BP_R_HAND, "status" = "amputated"), P, null, null), PREF_UPDATE_ACCEPTED, "the hand can be amputated")
	fdel(P.path)

/// A skin colour differing from Primary becomes Primary, and what was linked to Primary keeps the colour it showed.
/datum/unit_test/dq_skin_eyes_follow_slots

/datum/unit_test/dq_skin_eyes_follow_slots/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs(list("palette_linked" = TRUE, "palette_primary" = "#111111", "skin_color" = "#222222", "tail_color1" = "primary"))
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/skin_color), "primary", "skin links to Primary")
	TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/skin_color)), "#222222", "and keeps its colour")
	TEST_ASSERT_EQUAL(lowertext(P.read_preference(/datum/preference/color/human/color_slot/primary)), "#222222", "Primary took the skin colour")
	TEST_ASSERT_EQUAL(lowertext(P.read_preference_raw(/datum/preference/color/human/tail_color1)), "#111111", "the tail keeps the colour it showed")
	TEST_ASSERT_EQUAL(P.read_preference_raw(/datum/preference/color/human/eyes_color), "tertiary", "eyes link to Tertiary")
	fdel(P.path)

/// A Kitsuhana body with no ear style takes the ear style that replaced its built-in ears, once.
/datum/unit_test/dq_robotic_ears_are_a_style

/datum/unit_test/dq_robotic_ears_are_a_style/Run()
	TEST_ASSERT(GLOB.ear_styles_list[/datum/sprite_accessory/ears/kitsuhana], "the ears are an ordinary style")
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs(list("organ_data" = list(BP_TORSO = "cyborg"), "rlimb_data" = list(BP_TORSO = "Kitsuhana"), "ear_style" = null, "ear_secondary_style" = null))
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/text/human/ear_style), "Kitsuhana cybernetic ears", "the save migrates")
	P.update_preference_by_type(/datum/preference/text/human/ear_style, "")
	P.migrate_robotic_ears()
	TEST_ASSERT(!P.read_preference(/datum/preference/text/human/ear_style), "and None then stays None")
	fdel(P.path)

/// The Body table reads each style's channels and whether a tail style is a taur from its thumbnail data.
/datum/unit_test/dq_style_thumbs_carry_channels

/datum/unit_test/dq_style_thumbs_carry_channels/Run()
	var/list/thumbs = sprite_accessory_thumbs(GLOB.tail_styles_list)
	var/datum/sprite_accessory/tail/taur/wolf/wolf = GLOB.tail_styles_list[/datum/sprite_accessory/tail/taur/wolf/wolf_2c]
	TEST_ASSERT(thumbs[wolf.name]["taur"], "a taur tail says so")
	TEST_ASSERT_EQUAL(thumbs[wolf.name]["channels"], wolf.get_color_channel_count(), "and its channels")
	TEST_ASSERT(wolf.get_color_channel_count() >= 2, "a two colour taur counts its overlay")
