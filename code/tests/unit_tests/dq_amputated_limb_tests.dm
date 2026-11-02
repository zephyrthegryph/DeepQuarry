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
