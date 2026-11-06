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
