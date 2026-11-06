// The AI panel: the AI's camera, station and settings commands (what the AI.* verb tabs were) in one command panel
// (code/library/ui/command_panel.dm). A command that used to take a verb argument asks for it with a typed prompt here and then calls the
// same proc the HUD buttons call.

GLOBAL_LIST_INIT(ai_panel_commands, list(
	panel_command("camera_list", "Show Camera List", "Pick a camera to look through.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, panel_camera_list)),
	panel_command("store_location", "Store Camera Location", "Stores your current camera location by the given name.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, panel_store_location)),
	panel_command("goto_location", "Goto Camera Location", "Returns to the selected camera location.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, panel_goto_location)),
	panel_command("remove_location", "Delete Camera Location", "Deletes the selected camera location.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, panel_remove_location)),
	panel_command("camera_track", "Follow With Camera", "Select who you would like to track.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, panel_camera_track)),
	panel_command("cancel_camera", "Cancel Camera View", "Go back to your core.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, panel_cancel_camera)),
	panel_command("network_change", "Jump To Network", "Switch to another camera network.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, panel_network_change)),
	panel_command("camera_light", "Toggle Camera Light", "Toggles the light on the camera you are looking through.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, toggle_camera_light)),
	panel_command("multicam", "Toggle Multicam", "Look through several cameras at once.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, toggle_multicam_verb)),
	panel_command("multicam_add", "Add Multicam Viewport", "Add one more viewport to the multicam.", "Camera Control", TYPE_PROC_REF(/mob/living/silicon/ai, add_multicam_verb)),
	panel_command("deploy_shell", "Deploy to Shell", "Take control of an AI shell.", "Commands", TYPE_PROC_REF(/mob/living/silicon/ai, deploy_to_shell_act)),
	panel_command("show_laws", "Show Laws", "Read your laws.", "Commands", TYPE_PROC_REF(/mob/living/silicon/ai, show_laws_verb)),
	panel_command("state_laws", "State Laws", "Choose which laws to state aloud.", "Commands", TYPE_PROC_REF(/mob/living/silicon/ai, ai_checklaws)),
	panel_command("take_image", "Take Image", "Use your camera.", "Commands", TYPE_PROC_REF(/mob/living/silicon/ai, take_image)),
	panel_command("view_images", "View Images", "Look at the pictures you took.", "Commands", TYPE_PROC_REF(/mob/living/silicon/ai, view_images)),
	panel_command("delete_images", "Delete Image", "Delete a picture you took.", "Commands", TYPE_PROC_REF(/mob/living/silicon/ai, delete_images)),
	panel_command("announcement", "Make Station Announcement", "Announce something to the whole station.", "Station Commands", TYPE_PROC_REF(/mob/living/silicon/ai, ai_announcement)),
	panel_command("call_shuttle", "Call Emergency Shuttle", "Call the emergency shuttle.", "Station Commands", TYPE_PROC_REF(/mob/living/silicon/ai, ai_call_shuttle)),
	panel_command("emergency_message", "Send Emergency Message", "Send an emergency message to CentCom.", "Station Commands", TYPE_PROC_REF(/mob/living/silicon/ai, ai_emergency_message)),
	panel_command("camera_acceleration", "Toggle Camera Acceleration", "Make the camera eye speed up as it moves.", "Settings", TYPE_PROC_REF(/mob/living/silicon/ai, toggle_acceleration)),
	panel_command("core_display", "Set AI Core Display", "Pick how your core looks.", "Settings", TYPE_PROC_REF(/mob/living/silicon/ai, pick_icon)),
	panel_command("status", "AI Status", "Pick what the status displays show.", "Settings", TYPE_PROC_REF(/mob/living/silicon/ai, ai_statuschange)),
	panel_command("hologram", "Change Hologram", "Change the default hologram available to you to something else.", "Settings", TYPE_PROC_REF(/mob/living/silicon/ai, ai_hologram_change)),
	panel_command("radio", "Radio Settings", "Allows you to change settings of your radio.", "Settings", TYPE_PROC_REF(/mob/living/silicon/ai, control_integrated_radio)),
	panel_command("sensor_mode", "Toggle Sensor Augmentation", "Toggle the sensor augmentation of your camera.", "Settings", TYPE_PROC_REF(/mob/living/silicon/ai, sensor_mode)),
	panel_command("hologram_movement", "Toggle Hologram Movement", "Toggle whether your hologram can move.", "Settings", TYPE_PROC_REF(/mob/living/silicon/ai, toggle_hologram_movement)),
	panel_command("alarm_monitor", "Alarm Monitor", "Open the alarm monitor.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_alarm_monitor)),
	panel_command("atmos_control", "Atmospherics Control", "Open the atmospherics control.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_atmos_control)),
	panel_command("crew_manifest", "Crew Manifest", "Open the crew manifest.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_crew_manifest)),
	panel_command("crew_monitor", "Crew Monitor", "Open the crew monitor.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_crew_monitor)),
	panel_command("law_manager", "Law Manager", "Open the law manager.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_law_manager)),
	panel_command("power_monitor", "Power Monitor", "Open the power monitor.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_power_monitor)),
	panel_command("rcon", "RCON", "Open the remote power control.", "Subsystems", TYPE_PROC_REF(/mob/living/silicon, subsystem_rcon)),
))

/// The one AI verb: opens the AI panel.
/mob/living/silicon/ai/proc/ai_panel()
	set name = "AI Panel"
	set desc = "Every AI command in one window: cameras, station commands, settings and subsystems."
	set category = VERB_CAT_AI_COMMANDS

	command_panel_open(src, "ai", "AI Panel", GLOB.ai_panel_commands, TYPE_PROC_REF(/mob/living/silicon/ai, ai_panel_blocked))

/// Why the panel's commands cannot be used: a dead AI has none.
/mob/living/silicon/ai/proc/ai_panel_blocked()
	if(stat == DEAD)
		return "You are dead."
	return null

// ---- the commands that asked for a verb argument ----

/mob/living/silicon/ai/proc/panel_cancel_camera()
	cancel_camera()

/mob/living/silicon/ai/proc/panel_camera_list()
	if(check_unable())
		return
	var/list/cameras = get_camera_list()
	if(!length(cameras))
		to_chat(src, span_warning("There are no cameras to look through."))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(panel_camera_list_chosen), answerer = src, question = "Pick Camera:", title = "Camera Choice", choices = cameras, timeout = 0)

/mob/living/silicon/ai/proc/panel_camera_list_chosen(datum/act/request/A)
	if(!A.answer)
		return
	ai_camera_list(A.answer.value)

/mob/living/silicon/ai/proc/panel_store_location()
	open_request(src, /datum/prompt/text, PROC_REF(panel_store_location_named), answerer = src, title = "Camera Location", question = "Name this camera location:", max_len = MAX_NAME_LEN, encode = FALSE, timeout = 0)

/mob/living/silicon/ai/proc/panel_store_location_named(datum/act/request/A)
	if(!A.answer)
		return
	ai_store_location(A.answer.value)

/mob/living/silicon/ai/proc/panel_goto_location()
	var/list/locations = sorted_stored_locations()
	if(!length(locations))
		to_chat(src, span_warning("You have not stored any camera locations."))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(panel_goto_location_chosen), answerer = src, question = "Go to which location?", title = "Camera Location", choices = locations, timeout = 0)

/mob/living/silicon/ai/proc/panel_goto_location_chosen(datum/act/request/A)
	if(!A.answer)
		return
	ai_goto_location(A.answer.value)

/mob/living/silicon/ai/proc/panel_remove_location()
	var/list/locations = sorted_stored_locations()
	if(!length(locations))
		to_chat(src, span_warning("You have not stored any camera locations."))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(panel_remove_location_chosen), answerer = src, question = "Delete which location?", title = "Camera Location", choices = locations, timeout = 0)

/mob/living/silicon/ai/proc/panel_remove_location_chosen(datum/act/request/A)
	if(!A.answer)
		return
	ai_remove_location(A.answer.value)

/mob/living/silicon/ai/proc/panel_camera_track()
	if(stat == DEAD)
		to_chat(src, "You can't follow anyone with cameras because you are dead!")
		return
	var/list/targets = trackable_mobs()
	if(!length(targets))
		to_chat(src, span_warning("There is nobody to follow."))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(panel_camera_track_chosen), answerer = src, question = "Pick Mob:", title = "Mob Choice", choices = targets, timeout = 0)

/mob/living/silicon/ai/proc/panel_camera_track_chosen(datum/act/request/A)
	if(!A.answer)
		return
	ai_camera_track(A.answer.value)

/mob/living/silicon/ai/proc/panel_network_change()
	var/list/networks = get_camera_network_list()
	if(!length(networks))
		to_chat(src, span_warning("There are no camera networks to jump to."))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(panel_network_change_chosen), answerer = src, question = "Jump to which network?", title = "Camera Network", choices = networks, timeout = 0)

/mob/living/silicon/ai/proc/panel_network_change_chosen(datum/act/request/A)
	if(!A.answer)
		return
	ai_network_change(A.answer.value)
