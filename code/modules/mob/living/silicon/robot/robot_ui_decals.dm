// Robot decal and animation control
/datum/tgui_module/robot_ui_decals
	name = "Robot Decal & Animation Control"

CAPABILITIES(/datum/tgui_module/robot_ui_decals)
	extend(TAG_UI, needs(req_bool(PROC_REF(ui_gate), silent = TRUE)))
	interface("RobotDecals", state = nameof(GLOB.tgui_self_state))
	op("toggle_decal", ui_act("toggle_decal", arg("value", schema_text(4096))), then(PROC_REF(ui_act_toggle_decal)))
	op("flick_animation", ui_act("flick_animation", arg("value", schema_text(4096))), then(PROC_REF(ui_act_flick_animation)))

/datum/tgui_module/robot_ui_decals/tgui_static_data()
	var/list/data = ..()

	var/mob/living/silicon/robot/R = host()

	if(!R.sprite_datum)
		return data

	data["all_decals"] = (R.sprite_datum.sprite_decals || list())
	data["all_animations"] = (R.sprite_datum.sprite_animations || list())

	return data

/datum/tgui_module/robot_ui_decals/ui_data(datum/act/eval/A)
	var/list/data = list()

	var/mob/living/silicon/robot/R = host()
	data["active_decals"] = (R.robotdecal_on || list())

	data["theme"] = R.get_ui_theme()

	return data

/// A robot with no sprite has no decals to work (silently).
/datum/tgui_module/robot_ui_decals/proc/ui_gate(datum/act/op/A)
	var/mob/living/silicon/robot/R = host()
	return !!R?.sprite_datum

/datum/tgui_module/robot_ui_decals/proc/ui_act_toggle_decal(datum/act/op/A, value)
	var/mob/living/silicon/robot/R = host()
	if(!LAZYLEN(R.sprite_datum.sprite_decals))
		return FALSE
	var/decal_to_toggle = lowertext(value)
	if(!(decal_to_toggle in R.sprite_datum.sprite_decals))
		return FALSE
	var/list/decals = R.robotdecal_on?.Copy()
	if(decal_to_toggle in decals)
		decals -= decal_to_toggle
	else
		LAZYADD(decals, decal_to_toggle)
	R.set_robotdecal_on(decals)
	. = TRUE

/datum/tgui_module/robot_ui_decals/proc/ui_act_flick_animation(datum/act/op/A, value)
	var/mob/living/silicon/robot/R = host()
	if(!LAZYLEN(R.sprite_datum.sprite_animations))
		return FALSE
	var/animation_to_flick = lowertext(value)
	if(!(animation_to_flick in R.sprite_datum.sprite_animations))
		return FALSE
	flick("[R.sprite_datum.sprite_icon_state]-[animation_to_flick]", R)
	. = TRUE
