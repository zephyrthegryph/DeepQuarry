// Robot decal and animation control
/datum/tgui_module/robot_ui_decals
	name = "Robot Decal & Animation Control"
	tgui_id = "RobotDecals"

/datum/tgui_module/robot_ui_decals/tgui_state(mob/user)
	return GLOB.tgui_self_state

/datum/tgui_module/robot_ui_decals/tgui_static_data()
	var/list/data = ..()

	var/mob/living/silicon/robot/R = host()

	if(!R.sprite_datum)
		return data

	data["all_decals"] = (R.sprite_datum.sprite_decals || list())
	data["all_animations"] = (R.sprite_datum.sprite_animations || list())

	return data

/datum/tgui_module/robot_ui_decals/tgui_data()
	var/list/data = ..()

	var/mob/living/silicon/robot/R = host()
	data["active_decals"] = (R.robotdecal_on || list())

	data["theme"] = R.get_ui_theme()

	return data

/datum/tgui_module/robot_ui_decals/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/mob/living/silicon/robot/R = host()
	if(!R.sprite_datum)
		return FALSE
	return TRUE

UI_ACT(/datum/tgui_module/robot_ui_decals, "toggle_decal", ui_act_toggle_decal, UI_ARG_TEXT("value"))
UI_ACT_PROC(/datum/tgui_module/robot_ui_decals, ui_act_toggle_decal)
	var/mob/living/silicon/robot/R = host()
	if(!LAZYLEN(R.sprite_datum.sprite_decals))
		return FALSE
	var/decal_to_toggle = lowertext(params["value"])
	if(!(decal_to_toggle in R.sprite_datum.sprite_decals))
		return FALSE
	if(decal_to_toggle in R.robotdecal_on)
		LAZYREMOVE(R.robotdecal_on, decal_to_toggle)
	else
		LAZYADD(R.robotdecal_on, decal_to_toggle)
	R.update_icon()
	. = TRUE

UI_ACT(/datum/tgui_module/robot_ui_decals, "flick_animation", ui_act_flick_animation, UI_ARG_TEXT("value"))
UI_ACT_PROC(/datum/tgui_module/robot_ui_decals, ui_act_flick_animation)
	var/mob/living/silicon/robot/R = host()
	if(!LAZYLEN(R.sprite_datum.sprite_animations))
		return FALSE
	var/animation_to_flick = lowertext(params["value"])
	if(!(animation_to_flick in R.sprite_datum.sprite_animations))
		return FALSE
	R.cut_overlays()
	R.ImmediateOverlayUpdate()
	flick("[R.sprite_datum.sprite_icon_state]-[animation_to_flick]", R)
	R.update_icon()
	. = TRUE
