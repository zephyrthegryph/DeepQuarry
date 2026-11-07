// The pet customize panel (code/content/mob/living/simple_mob/pet_customize_panel.dm): the settings verbs of a simple mob in one window.

/// The ids of the settings a pet panel lists now.
/datum/unit_test/proc/dq_pet_setting_ids(datum/pet_panel/panel)
	var/list/ids = list()
	for(var/list/row as anything in panel.ui_data(null)["settings"])
		ids[row["id"]] = row
	return ids

/// The panel lists the settings the pet was granted, runs them for the pet alone, and the Abilities panel lists its Customize command.
/datum/unit_test/dq_pet_panel_lists_granted_settings

/datum/unit_test/dq_pet_panel_lists_granted_settings/Run()
	var/mob/living/simple_mob/animal/passive/mouse/pet = allocate(/mob/living/simple_mob/animal/passive/mouse, test_floor())
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	var/datum/pet_panel/panel = new(pet)
	var/datum/command_panel/abilities = new(pet, "abilities", "Abilities", GLOB.ability_panel_commands)
	TEST_ASSERT(!dq_panel_ids(abilities)["pet_customize"], "a pet with no customize setting granted has no Customize command")
	TEST_ASSERT(!length(dq_pet_setting_ids(panel)), "and the window lists nothing")
	grant(pet, granted_verb(/mob/living/simple_mob/proc/set_name), pet)
	grant(pet, granted_verb(/mob/living/simple_mob/proc/choose_gender), pet)
	var/list/ids = dq_pet_setting_ids(panel)
	TEST_ASSERT(ids[PET_SET_NAME] && ids[PET_SET_GENDER], "the granted settings are listed")
	TEST_ASSERT(!ids[PET_SET_SIZE] && !ids[PET_SET_COLOR], "the ones not granted are not")
	TEST_ASSERT_EQUAL(ids[PET_SET_GENDER]["value"], "[pet.gender]", "a setting shows its present value")
	TEST_ASSERT_EQUAL(dq_panel_ids(abilities)["pet_customize"], "Settings", "the Abilities panel lists Customize under Settings")
	TEST_ASSERT(!panel.run_action(other, PET_SET_NAME), "another mob cannot press the pet's buttons")
	TEST_ASSERT(!panel.run_action(pet, PET_SET_SIZE), "a setting that was not granted is refused")
	TEST_ASSERT(!panel.run_action(pet, "no_such_setting"), "an unknown setting is refused")
	TEST_ASSERT(panel.run_action(pet, PET_SET_NAME), "the pet can rename itself")
	var/datum/prompt/text/ask = SSrequests.open_for(pet)
	TEST_ASSERT(istype(ask), "pressing Rename asks for the new name")
	request_answer(pet, "Test Fluffy")
	TEST_ASSERT_EQUAL(pet.name, "Test Fluffy", "the answer renames the pet")
	TEST_ASSERT_EQUAL(ids[PET_SET_NAME]["enabled"], TRUE, "the name could be set before")
	var/list/after = dq_pet_setting_ids(panel)
	TEST_ASSERT_EQUAL(after[PET_SET_NAME]["value"], "Test Fluffy", "the window shows the new name")
	TEST_ASSERT_EQUAL(!!after[PET_SET_NAME]["enabled"], !pet.limit_renames, "a pet that may rename once has used it up")
	qdel(abilities)
	qdel(panel)
	var/datum/command_panel/human_panel = new(other, "abilities", "Abilities", GLOB.ability_panel_commands)
	TEST_ASSERT(!dq_panel_ids(human_panel)["pet_customize"], "a human has no Customize command")
	qdel(human_panel)

/// The settings that are used up say why, and the size of a mob immune to resizing is refused.
/datum/unit_test/dq_pet_panel_refuses_used_settings

/datum/unit_test/dq_pet_panel_refuses_used_settings/Run()
	var/mob/living/simple_mob/animal/passive/mouse/pet = allocate(/mob/living/simple_mob/animal/passive/mouse, test_floor())
	var/datum/pet_panel/panel = new(pet)
	grant(pet, granted_verb(/mob/living/simple_mob/proc/pick_color), pet)
	grant(pet, granted_verb(/mob/living/simple_mob/proc/ColorMate), pet)
	var/list/ids = dq_pet_setting_ids(panel)
	TEST_ASSERT(ids[PET_SET_COLOR]["enabled"], "an unused colour setting can be pressed")
	pet.set_picked_color(TRUE)
	pet.set_has_recoloured(TRUE)
	var/list/used = dq_pet_setting_ids(panel)
	TEST_ASSERT(!used[PET_SET_COLOR]["enabled"] && used[PET_SET_COLOR]["why"], "a colour already picked says why it cannot be picked again")
	TEST_ASSERT(!used[PET_SET_RECOLOUR]["enabled"] && used[PET_SET_RECOLOUR]["why"], "so does the recolour")
	TEST_ASSERT(!panel.run_action(pet, PET_SET_COLOR), "and pressing it does nothing")
	TEST_ASSERT(!SSrequests.open_for(pet), "no question was asked")
	qdel(panel)
