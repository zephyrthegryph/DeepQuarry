//Amazing disperser from Bxil(tm). Some icons, sounds, and some code shamelessly stolen from ParadiseSS13.

/obj/machinery/computer/ship/disperser
	name = "obstruction removal ballista control"
	icon = 'icons/obj/computer.dmi'
	icon_state = "computer"
	circuit = /obj/item/circuitboard/disperser

	icon_keyboard = "rd_key"
	icon_screen = "teleport"

	var/tmp/front_handle
	var/tmp/middle_handle
	var/tmp/back_handle
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

// ALLOW(lifecycle): releases its linked parts.
/obj/machinery/computer/ship/disperser/Destroy()
	release_links()
	. = ..()

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
		front_handle = om_handle(F)
		middle_handle = om_handle(M)
		back_handle = om_handle(B)
		// The parts are OM handles: one that is destroyed reads null, so is_valid_setup() fails
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
	front_handle = null
	middle_handle = null
	back_handle = null

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

/obj/machinery/computer/ship/disperser/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui)
	if(!linked())
		display_reconnect_dialog(user, "disperser synchronization")
		return

	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "OvermapDisperser", "[linked().name] ORB control") // 400, 550
		ui.open()

/obj/machinery/computer/ship/disperser/tgui_data(mob/user)
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

/obj/machinery/computer/ship/disperser/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	if(!linked())
		return FALSE

	switch(action)
		if("choose")
			overmapdir = sanitize_integer(text2num(params["dir"]), 0, 9, 0)
			reset_calibration()
			. = TRUE

		if("calibration")
			var/input = act_ask(ui.user, action, params, ui, "k177", /datum/om/prompt/number, message = "0-9", title = "disperser calibration", default = 0, max = 9)
			if(isnull(input))
				return
			if(!isnull(input)) //can be zero so we explicitly check for null
				var/calnum = sanitize_integer(text2num(params["calibration"]), 0, caldigit)//sanitiiiiize
				calibration[calnum + 1] = sanitize_integer(input, 0, 9, 0)//must add 1 because js indexes from 0
			. = TRUE

		if("skill_calibration")
			for(var/i = 1 to 2)
				calibration[i] = calexpected[i]
			. = TRUE

		if("strength")
			var/input = act_ask(ui.user, action, params, ui, "k189", /datum/om/prompt/number, message = "1-5", title = "disperser strength", default = 1, max = 5, min = 1)
			if(isnull(input))
				return
			if(input && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				strength = sanitize_integer(input, 1, 5, 1)
				middle().update_idle_power_usage(strength * range * 100)
			. = TRUE

		if("range")
			var/input = act_ask(ui.user, action, params, ui, "k196", /datum/om/prompt/number, message = "1-5", title = "disperser radius", default = 1, max = 5, min = 1)
			if(isnull(input))
				return
			if(input && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				range = sanitize_integer(input, 1, 5, 1)
				middle().update_idle_power_usage(strength * range * 100)
			. = TRUE

		if(BURN)
			fire(ui.user)
			. = TRUE

	if(. && !issilicon(ui.user))
		playsound(src, "terminal_type", 50, 1)

/// LC-refs: the middle this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/ship/disperser/proc/middle() as /obj/machinery/disperser/middle
	return om_resolve(middle_handle)

/// LC-refs: the back this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/ship/disperser/proc/back() as /obj/machinery/disperser/back
	return om_resolve(back_handle)

/// LC-refs: the front this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/ship/disperser/proc/front() as /obj/machinery/disperser/front
	return om_resolve(front_handle)
