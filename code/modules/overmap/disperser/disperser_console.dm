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

// The disperser window: one op per button; a setting's number is asked in its op (asks()) and applied by the handler.
CAPABILITIES(/obj/machinery/computer/ship/disperser)
	interface("OvermapDisperser")
	without("ui_open")
	op("choose", ui_act("choose", arg("dir", num())), then(PROC_REF(ui_act_choose)))
	op("calibration", ui_act("calibration", arg("calibration", num())), asks(/datum/prompt/number/disperser_setting/calibration, step = "value"), then(PROC_REF(ui_act_calibration)))
	op("skill_calibration", ui_act("skill_calibration"), then(PROC_REF(ui_act_skill_calibration)))
	op("strength", ui_act("strength"), asks(/datum/prompt/number/disperser_setting/strength, step = "value"), then(PROC_REF(ui_act_strength)))
	op("range", ui_act("range"), asks(/datum/prompt/number/disperser_setting/range, step = "value"), then(PROC_REF(ui_act_range)))
	op(BURN, ui_act(BURN), then(PROC_REF(ui_act_burn)))

/obj/machinery/computer/ship/disperser/ui_prepare(mob/user, datum/tgui/ui)
	if(!linked())
		display_reconnect_dialog(user, "disperser synchronization")
		return FALSE

	return TRUE

/obj/machinery/computer/ship/disperser/ui_title(mob/user)
	return "[linked().name] ORB control"

/// The window data.
/obj/machinery/computer/ship/disperser/ui_data(datum/act/eval/A)
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

/// The console's guard: it works a linked ship.
/obj/machinery/computer/ship/disperser/ui_gate(datum/act/op/A)
	if(!..())
		return FALSE
	return !!linked()

/obj/machinery/computer/ship/disperser/proc/ui_act_choose(datum/act/op/A, dir)
	if(!ui_gate(A))
		return FALSE
	overmapdir = sanitize_integer(dir, 0, 9, 0)
	reset_calibration()
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/disperser/proc/ui_act_calibration(datum/act/op/A, calibration_index)
	if(!ui_gate(A))
		return FALSE
	var/calnum = sanitize_integer(calibration_index, 0, caldigit)
	calibration[calnum + 1] = sanitize_integer(A.step_value("value"), 0, 9, 0)
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/disperser/proc/ui_act_skill_calibration(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	for(var/i = 1 to 2)
		calibration[i] = calexpected[i]
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/disperser/proc/ui_act_strength(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/value = A.step_value("value")
	if(value)
		strength = sanitize_integer(value, 1, 5, 1)
		middle().update_idle_power_usage(strength * range * 100)
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/disperser/proc/ui_act_range(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/value = A.step_value("value")
	if(value)
		range = sanitize_integer(value, 1, 5, 1)
		middle().update_idle_power_usage(strength * range * 100)
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/disperser/proc/ui_act_burn(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	fire(A.actor)
	terminal_typed(A.actor)
	return TRUE

/// Accessor for the middle var.
/obj/machinery/computer/ship/disperser/proc/middle() as /obj/machinery/disperser/middle
	return middle

/// Accessor for the back var.
/obj/machinery/computer/ship/disperser/proc/back() as /obj/machinery/disperser/back
	return back

/// Accessor for the front var.
/obj/machinery/computer/ship/disperser/proc/front() as /obj/machinery/disperser/front
	return front

/datum/prompt/number/disperser_setting
	timeout = 0
	var/display_min = 0
	var/display_max = 9

/datum/prompt/number/disperser_setting/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/disperser_setting/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default, display_max, display_min, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/disperser_setting/calibration
	question = "0-9"
	title = "disperser calibration"
	default = 0

/datum/prompt/number/disperser_setting/strength
	question = "1-5"
	title = "disperser strength"
	default = 1
	display_min = 1
	display_max = 5

/datum/prompt/number/disperser_setting/range
	question = "1-5"
	title = "disperser radius"
	default = 1
	display_min = 1
	display_max = 5
