// A named HUD control asks its actor/provider to perform the controls it actually owns.
// Shared human/mob controls stay on the screen; unrecognized controls fall through unchanged.
/mob/proc/operate_hud_control(atom/movable/screen/button, location, control, params)
	return FALSE

/mob/living/silicon/operate_hud_control(atom/movable/screen/button, location, control, params)
	if(button.name == "set pose")
		pose()
		return TRUE
	return ..()

/mob/living/silicon/robot/operate_hud_control(atom/movable/screen/button, location, control, params)
	var/mob/living/silicon/robot/R = src
	switch(button.name)
		if("control_vtec")
			if(R.speed == 0 && R.vtec_active)
				R.speed = -0.5
				R.hud_used.control_vtec.icon_state = "speed_1"
			else if(R.speed == -0.5 && R.vtec_active)
				R.speed = -1
				R.hud_used.control_vtec.icon_state = "speed_2"
			else
				R.speed = 0
				R.hud_used.control_vtec.icon_state = "speed_0"
			return TRUE
		if("module")
			R.pick_module()
			return TRUE
		if("inventory")
			if(R.module)
				R.hud_used.toggle_show_robot_modules()
				return 1
			else
				to_chat(R, "You haven't selected a module yet.")
			return TRUE
		if("radio")
			R.radio_menu()
			return TRUE
		if("panel")
			R.installed_modules()
			return TRUE
		if("store")
			if(R.module)
				R.uneq_active()
			else
				to_chat(R, "You haven't selected a module yet.")
			return TRUE
		if("module1")
			R.toggle_module(1)
			return TRUE
		if("module2")
			R.toggle_module(2)
			return TRUE
		if("module3")
			R.toggle_module(3)
			return TRUE
	return ..()

/mob/living/silicon/ai/operate_hud_control(atom/movable/screen/button, location, control, params)
	var/mob/living/silicon/ai/ai_user = src
	var/mob/user = src
	switch(button.name)
		if("Show Camera List")
			inbox_menu(src, src, "hud_camera_list", button)
			return TRUE
		if("Track With Camera")
			inbox_menu(src, src, "hud_camera_track", button)
			return TRUE
		if("AI Core")
			ai_user.view_core()
			return TRUE
		if("Toggle Camera Light")
			ai_user.toggle_camera_light()
			return TRUE
		if("Crew Monitoring")
			ai_user.subsystem_crew_monitor()
			return TRUE
		if("Show Crew Manifest")
			ai_user.subsystem_crew_manifest()
			return TRUE
		if("Show Alerts")
			ai_user.subsystem_alarm_monitor()
			return TRUE
		if("Announcement")
			ai_user.ai_announcement()
			return TRUE
		if("Call Emergency Shuttle")
			ai_user.ai_call_shuttle()
			return TRUE
		if("State Laws")
			ai_user.ai_checklaws()
			return TRUE
		if("PDA - Messenger")
			ai_user.aiPDA.start_program(ai_user.aiPDA.find_program(/datum/data/pda/app/messenger))
			ai_user.aiPDA.cmd_pda_open_ui(user)
			return TRUE
		if("Take Image")
			ai_user.take_image()
			return TRUE
		if("View Images")
			ai_user.view_images()
			return TRUE
		if("Multicamera Mode")
			ai_user.toggle_multicam()
			return TRUE
		if("New Camera")
			ai_user.drop_new_multicam()
			return TRUE
	return ..()
