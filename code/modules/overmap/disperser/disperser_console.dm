//Amazing disperser from Bxil(tm). Some icons, sounds, and some code shamelessly stolen from ParadiseSS13.

/obj/machinery/computer/ship/disperser
	name = "obstruction removal ballista control"
	icon = 'icons/obj/computer.dmi'
	icon_state = "computer"
	circuit = /obj/item/circuitboard/disperser

	icon_keyboard = "rd_key"
	icon_screen = "teleport"

	var/tmp/obj/machinery/disperser/front/front
	var/tmp/obj/machinery/disperser/middle/middle
	var/tmp/obj/machinery/disperser/back/back
	var/const/link_range = 16 //How far can the above stuff be maximum before we start complaining

	var/overmapdir = 0

	var/caldigit = 4 //number of digits that needs calibration
	var/list/calibration //what it is
	var/list/calexpected //what is should be

	var/range = 1 //range of the explosion
	var/strength = 1 //strength of the explosion
	var/next_shot = 0 //round time where the next shot can start from
	var/const/coolinterval = 2 MINUTES //time to wait between safe shots in deciseconds

/obj/machinery/computer/ship/disperser/Initialize(mapload)
	. = ..()
	link_parts()
	reset_calibration()

// releases its linked parts.
/obj/machinery/computer/ship/disperser/on_destroy(force)
	release_links()
	..()

/obj/machinery/computer/ship/disperser/proc/link_parts()
	if(is_valid_setup())
		return TRUE

	for(var/obj/machinery/disperser/front/F in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(get_dist(src, F) >= link_range)
			continue
		var/backwards = turn(F.dir, 180)
		var/obj/machinery/disperser/middle/M = locate_within(get_step(F, backwards), /obj/machinery/disperser/middle)
		if(!M || get_dist(src, M) >= link_range)
			continue
		var/obj/machinery/disperser/back/B = locate_within(get_step(M, backwards), /obj/machinery/disperser/back)
		if(!B || get_dist(src, B) >= link_range)
			continue
		rel_set(src, nameof(front), F)
		rel_set(src, nameof(middle), M)
		rel_set(src, nameof(back), B)
		// The parts are relation views: one that is destroyed reads null, so is_valid_setup() fails
		// without a destruction signal on each.
		if(is_valid_setup())
			return TRUE
	return FALSE

/obj/machinery/computer/ship/disperser/proc/is_valid_setup()
	if(front() && middle() && back())
		var/everything_in_range = (get_dist(src, front()) < link_range) && (get_dist(src, middle()) < link_range) && (get_dist(src, back()) < link_range)
		var/everything_in_order = (middle().Adjacent(front()) && middle().Adjacent(back())) && (front().dir == middle().dir && middle().dir == back().dir)
		return everything_in_order && everything_in_range
	return FALSE

/obj/machinery/computer/ship/disperser/proc/release_links()
	rel_clear(src, nameof(front))
	rel_clear(src, nameof(middle))
	rel_clear(src, nameof(back))

/obj/machinery/computer/ship/disperser/proc/get_calibration()
	var/list/calresult[caldigit]
	for(var/i = 1 to caldigit)
		if(calibration[i] == calexpected[i])
			calresult[i] = 2
		else if(calibration[i] in calexpected)
			calresult[i] = 1
		else
			calresult[i] = 0
	return calresult

/obj/machinery/computer/ship/disperser/proc/reset_calibration()
	calexpected = new /list(caldigit)
	calibration = new /list(caldigit)
	for(var/i = 1 to caldigit)
		calexpected[i] = rand(0,9)
		calibration[i] = 0

/obj/machinery/computer/ship/disperser/proc/cal_accuracy()
	var/top = 0
	var/divisor = caldigit * 2 //maximum possible value, aka 100% accuracy
	for(var/i in get_calibration())
		top += i
	return round(top * 100 / divisor)

/obj/machinery/computer/ship/disperser/proc/get_next_shot_seconds()
	return max(0, (next_shot - world.time) / 10)

/obj/machinery/computer/ship/disperser/proc/cool_failchance()
	return get_next_shot_seconds() * 1000 / coolinterval

/obj/machinery/computer/ship/disperser/proc/get_charge_type()
	var/obj/structure/ship_munition/disperser_charge/B = locate_within(get_turf(back()), /obj/structure/ship_munition/disperser_charge)
	if(B)
		return B.chargetype
	return OVERMAP_WEAKNESS_NONE

/obj/machinery/computer/ship/disperser/proc/get_charge()
	var/obj/structure/ship_munition/disperser_charge/B = locate_within(get_turf(back()), /obj/structure/ship_munition/disperser_charge)
	if(B)
		return B

DECLARE_UI(/obj/machinery/computer/ship/disperser, "OvermapDisperser")

/obj/machinery/computer/ship/disperser/ui_prepare(mob/user, datum/tgui/ui)
	if(!linked())
		display_reconnect_dialog(user, "disperser synchronization")
		return FALSE

	return TRUE

/obj/machinery/computer/ship/disperser/ui_title(mob/user)
	return "[linked().name] ORB control"

UI_DATA_REPLACE(/obj/machinery/computer/ship/disperser, "merge:ui_data_obj_machinery_computer_ship_disperser{faillink:bool,calibration:list,overmapdir:num,cal_accuracy:unknown,strength:num,range:num,next_shot:num,nopower:bool,skill:bool,chargeload:text}")

/// The computed part of /obj/machinery/computer/ship/disperser's window data (declared on its UI_DATA row).
/obj/machinery/computer/ship/disperser/proc/ui_data_obj_machinery_computer_ship_disperser(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["faillink"] = FALSE
	data["calibration"] = null
	data["overmapdir"] = null
	data["cal_accuracy"] = 0
	data["strength"] = 0
	data["range"] = 0
	data["next_shot"] = -1
	data["nopower"] = TRUE
	data["skill"] = FALSE
	data["chargeload"] = null

	if(!link_parts())
		data["faillink"] = TRUE
	else
		data["calibration"] = calibration
		data["overmapdir"] = overmapdir
		data["cal_accuracy"] = cal_accuracy()
		data["strength"] = strength
		data["range"] = range
		data["next_shot"] = round(get_next_shot_seconds())
		data["nopower"] = !data["faillink"] && (!front().powered() || !middle().powered() || !back().powered())

		var/charge = "UNKNOWN ERROR"
		if(get_charge_type() == OVERMAP_WEAKNESS_NONE)
			charge = "ERROR: No valid charge detected."
		else
			var/obj/structure/ship_munition/disperser_charge/B = get_charge()
			charge = B.chargedesc
		data["chargeload"] = charge

	return data

/obj/machinery/computer/ship/disperser/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!linked())
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/computer/ship/disperser, "choose", ui_act_choose, UI_ARG_NUM("dir"))
UI_ACT_PROC(/obj/machinery/computer/ship/disperser, ui_act_choose)
	overmapdir = sanitize_integer(params["dir"], 0, 9, 0)
	reset_calibration()
	. = TRUE
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/disperser, "calibration", ui_act_calibration, UI_ARG_NUM("calibration"))
UI_ACT_PROC(/obj/machinery/computer/ship/disperser, ui_act_calibration)
	if(!istype(ui) || QDELETED(ui) || !ismob(ui.user) || QDELETED(ui.user))
		return
	open_request(ui, /datum/prompt/number/disperser_setting/calibration, TYPE_PROC_REF(/datum/tgui, disperser_setting_answered), answerer = ui.user, calibration_index = params["calibration"])

UI_ACT(/obj/machinery/computer/ship/disperser, "skill_calibration", ui_act_skill_calibration)
UI_ACT_PROC(/obj/machinery/computer/ship/disperser, ui_act_skill_calibration)
	for(var/i = 1 to 2)
		calibration[i] = calexpected[i]
	. = TRUE
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/disperser, "strength", ui_act_strength)
UI_ACT_PROC(/obj/machinery/computer/ship/disperser, ui_act_strength)
	if(!istype(ui) || QDELETED(ui) || !ismob(ui.user) || QDELETED(ui.user))
		return
	open_request(ui, /datum/prompt/number/disperser_setting/strength, TYPE_PROC_REF(/datum/tgui, disperser_setting_answered), answerer = ui.user)

UI_ACT(/obj/machinery/computer/ship/disperser, "range", ui_act_range)
UI_ACT_PROC(/obj/machinery/computer/ship/disperser, ui_act_range)
	if(!istype(ui) || QDELETED(ui) || !ismob(ui.user) || QDELETED(ui.user))
		return
	open_request(ui, /datum/prompt/number/disperser_setting/range, TYPE_PROC_REF(/datum/tgui, disperser_setting_answered), answerer = ui.user)

UI_ACT(/obj/machinery/computer/ship/disperser, BURN, ui_act_burn)
UI_ACT_PROC(/obj/machinery/computer/ship/disperser, ui_act_burn)
	fire(ui.user)
	. = TRUE
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

/// Accessor for the middle var.
/obj/machinery/computer/ship/disperser/proc/middle() as /obj/machinery/disperser/middle
	return middle

/// Accessor for the back var.
/obj/machinery/computer/ship/disperser/proc/back() as /obj/machinery/disperser/back
	return back

/// Accessor for the front var.
/obj/machinery/computer/ship/disperser/proc/front() as /obj/machinery/disperser/front
	return front

/datum/tgui/proc/disperser_setting_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/disperser_setting/ask = context.answer
	var/obj/machinery/computer/ship/disperser/console = src_object()
	console.apply_disperser_setting(user, state(), ask.setting_action, ask.answer_value, ask.calibration_index)
	SStgui.update_uis(console)

/obj/machinery/computer/ship/disperser/proc/apply_disperser_setting(mob/user, datum/tgui_state/state, setting_action, value, calibration_index)
	switch(setting_action)
		if("calibration")
			var/calnum = sanitize_integer(calibration_index, 0, caldigit)
			calibration[calnum + 1] = sanitize_integer(value, 0, 9, 0)
		if("strength")
			if(value && tgui_status(user, state) == STATUS_INTERACTIVE)
				strength = sanitize_integer(value, 1, 5, 1)
				middle().update_idle_power_usage(strength * range * 100)
		if("range")
			if(value && tgui_status(user, state) == STATUS_INTERACTIVE)
				range = sanitize_integer(value, 1, 5, 1)
				middle().update_idle_power_usage(strength * range * 100)
	if(!issilicon(user))
		play_sfx(src, SFX_TERMINAL_TYPE)

/datum/prompt/number/disperser_setting
	timeout = 0
	recheck_on_open = TRUE
	var/setting_action
	var/calibration_index
	var/display_min = 0
	var/display_max = 9

/datum/prompt/number/disperser_setting/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/disperser_setting/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default, display_max, display_min, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/disperser_setting/recheck_extra()
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui) || QDELETED(answerer))
		return "gone"
	var/obj/machinery/computer/ship/disperser/console = original_ui.src_object()
	if(!istype(console) || QDELETED(console))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	if(!console.ui_act_allowed(original_ui.user, setting_action, original_ui, original_ui.state()))
		return "the disperser setting is unavailable"
	return null

/datum/prompt/number/disperser_setting/calibration
	question = "0-9"
	title = "disperser calibration"
	default = 0
	setting_action = "calibration"

/datum/prompt/number/disperser_setting/strength
	question = "1-5"
	title = "disperser strength"
	default = 1
	display_min = 1
	display_max = 5
	setting_action = "strength"

/datum/prompt/number/disperser_setting/range
	question = "1-5"
	title = "disperser radius"
	default = 1
	display_min = 1
	display_max = 5
	setting_action = "range"
