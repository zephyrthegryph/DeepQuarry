// The command panel (code/library/ui/command_panel.dm) and the panels built on it: the AI, malfunction and silicon verb tabs are windows now.

/// The ids a panel lists, by group.
/datum/unit_test/proc/dq_panel_ids(datum/command_panel/panel)
	var/list/ids = list()
	for(var/list/group as anything in panel.ui_data(null)["groups"])
		for(var/list/command as anything in group["commands"])
			ids[command["id"]] = group["title"]
	return ids

/// The AI panel lists its camera, command, station and settings commands, and only the AI itself can press them.
/datum/unit_test/dq_command_panel_ai_lists_its_commands

/datum/unit_test/dq_command_panel_ai_lists_its_commands/Run()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, test_floor(), null, null, null, TRUE)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	var/datum/command_panel/panel = new(AI, "ai", "AI Panel", GLOB.ai_panel_commands, TYPE_PROC_REF(/mob/living/silicon/ai, ai_panel_blocked))
	var/list/ids = dq_panel_ids(panel)
	TEST_ASSERT_EQUAL(ids["camera_list"], "Camera Control", "the camera list is under Camera Control")
	TEST_ASSERT_EQUAL(ids["announcement"], "Station Commands", "the announcement is a station command")
	TEST_ASSERT_EQUAL(ids["show_laws"], "Commands", "the laws are a command")
	TEST_ASSERT_EQUAL(ids["status"], "Settings", "the status display is a setting")
	TEST_ASSERT_EQUAL(ids["rcon"], "Subsystems", "the AI has the power control subsystem")
	TEST_ASSERT(!panel.run_command(other, "show_laws"), "another mob cannot press the AI's buttons")
	TEST_ASSERT(!panel.run_command(AI, "no_such_command"), "an unknown command is refused")
	TEST_ASSERT_NULL(panel.blocked_reason(), "a live AI can use its commands")
	qdel(panel)

/// A malfunctioning AI lists the always-on hardware commands and nothing it has not earned.
/datum/unit_test/dq_command_panel_malf_lists_what_the_ai_has

/datum/unit_test/dq_command_panel_malf_lists_what_the_ai_has/Run()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, test_floor(), null, null, null, TRUE)
	var/datum/command_panel/panel = new(AI, "malf", "Malfunction Panel", GLOB.malf_panel_commands, TYPE_PROC_REF(/mob/living/silicon/ai, malf_panel_blocked))
	TEST_ASSERT(panel.blocked_reason(), "an AI that does not malfunction has no malfunction commands")
	AI.malfunctioning = 1
	TEST_ASSERT_NULL(panel.blocked_reason(), "a malfunctioning one does")
	var/list/ids = dq_panel_ids(panel)
	TEST_ASSERT(ids["ai_select_hardware"] && ids["ai_select_research"] && ids["ai_help"], "the hardware, research and help commands are always listed")
	TEST_ASSERT(!ids["hack_cyborg"], "a software command not researched is not listed")
	TEST_ASSERT(!ids["ai_destroy_station"], "Destroy Station waits for the system override")
	TEST_ASSERT(!ids["ai_self_destruct"], "the core bomb needs its hardware")
	qdel(panel)

/// A cyborg lists its own commands, a drone only the identity reset and its subsystems.
/datum/unit_test/dq_command_panel_robot_commands

/datum/unit_test/dq_command_panel_robot_commands/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	var/datum/command_panel/panel = new(R, "robot", "Silicon Panel", GLOB.robot_panel_commands, TYPE_PROC_REF(/mob/living/silicon/robot, robot_panel_blocked))
	var/list/ids = dq_panel_ids(panel)
	TEST_ASSERT(ids["state_laws"] && ids["reset_codes"] && ids["take_image"], "a cyborg lists its laws, identity reset and camera")
	TEST_ASSERT(!ids["transfer_shell"] && !ids["release_control"], "and the shell commands only for a shell")
	TEST_ASSERT(ids["law_manager"], "and the law manager subsystem")
	qdel(panel)
	var/mob/living/silicon/robot/drone/D = allocate(/mob/living/silicon/robot/drone, test_floor())
	var/datum/command_panel/drone_panel = new(D, "robot", "Silicon Panel", GLOB.robot_panel_commands, TYPE_PROC_REF(/mob/living/silicon/robot, robot_panel_blocked))
	var/list/drone_ids = dq_panel_ids(drone_panel)
	TEST_ASSERT(drone_ids["reset_codes"], "a drone can reset its identity codes")
	TEST_ASSERT(!drone_ids["state_laws"] && !drone_ids["take_image"], "but has no cyborg commands")
	qdel(drone_panel)

/// The abilities panel lists what a mob has been granted, and the abilities are no verb panel entries.
/datum/unit_test/dq_command_panel_abilities_follow_the_grants

/datum/unit_test/dq_command_panel_abilities_follow_the_grants/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/command_panel/panel = new(H, "abilities", "Abilities", GLOB.ability_panel_commands)
	var/list/before = dq_panel_ids(panel)
	TEST_ASSERT(!before["mob.living.carbon.human.proc.reconstitute_form"], "an ability the mob was not granted is not listed")
	grant(H, granted_verb(/mob/living/carbon/human/proc/reconstitute_form), H)
	var/list/after = dq_panel_ids(panel)
	TEST_ASSERT_EQUAL(after["mob.living.carbon.human.proc.reconstitute_form"], "Xenochimera", "a granted ability is listed under its group")
	revoke(H, granted_verb(/mob/living/carbon/human/proc/reconstitute_form), H)
	TEST_ASSERT(!dq_panel_ids(panel)["mob.living.carbon.human.proc.reconstitute_form"], "and goes when the grant does")
	TEST_ASSERT(!verb_panel_listed(/mob/living/carbon/human/proc/reconstitute_form), "the ability has no tab of its own")
	TEST_ASSERT(dq_vmo_row(H, H, "abilities_panel"), "every living mob has the Abilities entry in its own menu")
	qdel(panel)

/// An ability that needs a target asks for it in the panel, then runs on the one picked.
/datum/unit_test/dq_command_panel_target_ability_asks_for_its_target

/datum/unit_test/dq_command_panel_target_ability_asks_for_its_target/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	grant(H, granted_verb(/mob/living/carbon/human/proc/psychic_whisper), H)
	var/datum/command_panel/panel = new(H, "abilities", "Abilities", GLOB.ability_panel_commands)
	TEST_ASSERT(panel.run_command(H, "mob.living.carbon.human.proc.psychic_whisper"), "the granted ability can be pressed")
	var/datum/prompt/choice/panel_target/pick = SSrequests.open_for(H)
	TEST_ASSERT(istype(pick), "pressing it asks who to use it on")
	TEST_ASSERT(("[other.name]" in pick.choices), "the other mob in view is offered by name")
	TEST_ASSERT(!(H.name in pick.choices) || H.name == other.name, "and the owner is not")
	request_answer(H, "[other.name]")
	var/datum/prompt/text/telepathy/whisper = SSrequests.open_for(H)
	TEST_ASSERT(istype(whisper), "the answer runs the ability, which asks what to whisper")
	TEST_ASSERT_EQUAL(whisper.recipient, other, "to the one picked")
	request_answer(H, null, REQ_CANCELLED)
	qdel(panel)

/// The abilities that took a target argument, and the verbs that had a tab of their own, are no tab entries now.
/datum/unit_test/dq_command_panel_target_abilities_have_no_tab

/datum/unit_test/dq_command_panel_target_abilities_have_no_tab/Run()
	var/list/paths = list(
		/mob/living/proc/convert_to_rev, /mob/living/proc/convert_to_loyalist, /mob/living/carbon/human/proc/psychic_whisper,
		/mob/living/carbon/human/proc/telepathy, /mob/living/carbon/human/proc/check_plasma_amount, /mob/living/carbon/human/proc/transfer_plasma,
		/mob/living/carbon/human/proc/corrosive_acid, /mob/living/carbon/human/proc/lick_wounds, /mob/living/carbon/human/proc/taur_mount,
		/mob/living/simple_mob/proc/corrosive_acid, /mob/living/simple_mob/proc/speen, /mob/living/simple_mob/proc/animal_nom,
		/mob/living/simple_mob/proc/animal_mount, /mob/living/silicon/pai/proc/pai_nom, /mob/living/carbon/alien/proc/evolve,
		/mob/living/simple_mob/animal/passive/mouse/proc/set_mouse_colour, /mob/living/simple_mob/vore/blaidd/proc/blaidd_invis,
		/mob/living/proc/polymorph, /mob/living/proc/glamour_invisibility)
	for(var/path in paths)
		TEST_ASSERT(!verb_panel_listed(path), "[path] has no tab of its own")
	var/list/ids = list()
	for(var/list/row as anything in GLOB.ability_panel_commands)
		ids += row["id"]
	for(var/path in paths)
		TEST_ASSERT(("[path]" in dotted_ability_ids(ids)), "[path] is a command of the abilities panel")

/// The ids of the panel rows as the paths they name.
/datum/unit_test/proc/dotted_ability_ids(list/ids)
	var/list/paths = list()
	for(var/id in ids)
		paths += "/[replacetext(id, ".", "/")]"
	return paths

/// A silicon lists its integrated communicator and PDA in its panel and uses them from there.
/datum/unit_test/dq_command_panel_silicon_lists_its_communicator_and_pda

/datum/unit_test/dq_command_panel_silicon_lists_its_communicator_and_pda/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/command_panel/panel = new(R, "robot", "Silicon Panel", GLOB.robot_panel_commands, TYPE_PROC_REF(/mob/living/silicon/robot, robot_panel_blocked))
	var/list/ids = dq_panel_ids(panel)
	TEST_ASSERT(ids["integrated_communicator"] && ids["integrated_pda"], "a cyborg lists its communicator and PDA")
	qdel(panel)
	var/datum/command_panel/human_panel = new(H, "abilities", "Abilities", GLOB.ability_panel_commands)
	var/list/human_ids = dq_panel_ids(human_panel)
	TEST_ASSERT(!human_ids["integrated_communicator"] && !human_ids["integrated_pda"], "a human has neither")
	qdel(human_panel)
