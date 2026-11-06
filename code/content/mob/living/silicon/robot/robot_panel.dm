// The silicon panel: a cyborg's or drone's commands (what the Abilities.Silicon verbs were) in one command panel
// (code/library/ui/command_panel.dm). A subsystem is listed while the silicon has it (silicon_subsystems), the shell commands while the
// cyborg is an AI shell or has an AI deployed in it.

GLOBAL_LIST_INIT(robot_panel_commands, list(
	panel_command("state_laws", "State Laws", "Choose which laws to state aloud.", "Commands", TYPE_PROC_REF(/mob/living/silicon/robot, robot_checklaws), TYPE_PROC_REF(/mob/living/silicon/robot, robot_command_shown)),
	panel_command("reset_codes", "Reset Identity Codes", "Scrambles your security and identification codes and resets your current buffers. Unlocks you and permenantly severs you from your AI and the robotics console and will deactivate your camera system.", "Commands", TYPE_PROC_REF(/mob/living/silicon/robot, ResetSecurityCodes), TYPE_PROC_REF(/mob/living/silicon/robot, robot_command_shown)),
	panel_command("transfer_shell", "Transfer to Shell", "Move yourself to another AI shell.", "Commands", TYPE_PROC_REF(/mob/living/silicon/robot, transfer_shell_act), TYPE_PROC_REF(/mob/living/silicon/robot, robot_command_shown)),
	panel_command("release_control", "Release Control", "Release control of a remote drone.", "Commands", TYPE_PROC_REF(/mob/living/silicon/robot, undeploy_act), TYPE_PROC_REF(/mob/living/silicon/robot, robot_command_shown)),
	panel_command("take_image", "Take Image", "Use your camera.", "Camera", TYPE_PROC_REF(/mob/living/silicon/robot, take_image), TYPE_PROC_REF(/mob/living/silicon/robot, robot_command_shown)),
	panel_command("view_images", "View Images", "Look at the pictures you took.", "Camera", TYPE_PROC_REF(/mob/living/silicon/robot, view_images), TYPE_PROC_REF(/mob/living/silicon/robot, robot_command_shown)),
	panel_command("delete_images", "Delete Image", "Delete a picture you took.", "Camera", TYPE_PROC_REF(/mob/living/silicon/robot, delete_images), TYPE_PROC_REF(/mob/living/silicon/robot, robot_command_shown)),
	panel_command("alarm_monitor", "Alarm Monitor", "Open the alarm monitor.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_alarm_monitor), TYPE_PROC_REF(/mob/living/silicon, silicon_subsystem_shown)),
	panel_command("atmos_control", "Atmospherics Control", "Open the atmospherics control.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_atmos_control), TYPE_PROC_REF(/mob/living/silicon, silicon_subsystem_shown)),
	panel_command("crew_manifest", "Crew Manifest", "Open the crew manifest.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_crew_manifest), TYPE_PROC_REF(/mob/living/silicon, silicon_subsystem_shown)),
	panel_command("crew_monitor", "Crew Monitor", "Open the crew monitor.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_crew_monitor), TYPE_PROC_REF(/mob/living/silicon, silicon_subsystem_shown)),
	panel_command("law_manager", "Law Manager", "Open the law manager.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_law_manager), TYPE_PROC_REF(/mob/living/silicon, silicon_subsystem_shown)),
	panel_command("power_monitor", "Power Monitor", "Open the power monitor.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_power_monitor), TYPE_PROC_REF(/mob/living/silicon, silicon_subsystem_shown)),
	panel_command("rcon", "RCON", "Open the remote power control.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_rcon), TYPE_PROC_REF(/mob/living/silicon, silicon_subsystem_shown)),
))

/// The one cyborg verb: opens the silicon panel.
/mob/living/silicon/robot/proc/robot_panel()
	set name = "Silicon Panel"
	set desc = "Every cyborg command and subsystem in one window."
	set category = VERB_CAT_ABILITIES_SILICON

	command_panel_open(src, "robot", "Silicon Panel", GLOB.robot_panel_commands, TYPE_PROC_REF(/mob/living/silicon/robot, robot_panel_blocked))

/// Why the commands cannot be used: a dead cyborg has none.
/mob/living/silicon/robot/proc/robot_panel_blocked()
	if(stat == DEAD)
		return "You are dead."
	return null

/// Is this cyborg command listed? The drone has none of the cyborg's own commands but the identity reset; a shell has the transfer and a
/// deployed one the release.
/mob/living/silicon/robot/proc/robot_command_shown(id)
	switch(id)
		if("reset_codes")
			return TRUE
		if("transfer_shell")
			return shell && !istype(src, /mob/living/silicon/robot/drone)
		if("release_control")
			return deployed
	return !istype(src, /mob/living/silicon/robot/drone)

/// Does this silicon have the subsystem with this id (the ids are the ends of the subsystem proc names)?
/mob/living/silicon/proc/silicon_subsystem_shown(id)
	var/wanted = "/mob/living/silicon/proc/subsystem_[id]"
	for(var/path in silicon_subsystems)
		if("[path]" == wanted)
			return TRUE
	return FALSE
