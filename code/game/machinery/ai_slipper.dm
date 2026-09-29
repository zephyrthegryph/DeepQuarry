/obj/machinery/ai_slipper
	name = "\improper AI Liquid Dispenser"
	icon = 'icons/obj/device.dmi'
	icon_state = "liquid_dispenser"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	var/uses = 20
	var/disabled = 1
	var/lethal = 0
	locked = 1
	var/cooldown_time = 0
	var/cooldown_timeleft = 0
	var/cooldown_on = 0
	req_access = list(ACCESS_AI_UPLOAD)

/obj/machinery/ai_slipper/Initialize(mapload)
	. = ..()
	update_icon()

/obj/machinery/ai_slipper/power_change()
	. = ..()
	update_icon()

/obj/machinery/ai_slipper/update_icon()
	if(has_stat(NOPOWER) || has_stat(BROKEN))
		icon_state = "liquid_dispenser"
	else
		icon_state = disabled ? "liquid_dispenser" : "liquid_dispenser_on"

/obj/machinery/ai_slipper/proc/setState(enabled, uses)
	disabled = !enabled
	src.uses = uses
	power_change()

// TGUI migration. The old attack_hand opened AiSlipper.tsx; the
// Topic-driven toggle/fire actions move to tgui_act. The old attackby kept the
// ID-swipe lock/unlock behavior and just closed the UI on lock.
/obj/machinery/ai_slipper/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/ai_slipper_toggle_lock,
		/datum/interaction/machine_hand/ungated/ai_slipper_use,
	)
	..()

/datum/interaction/machine_item/ai_slipper_toggle_lock
	id = "ai_slipper_toggle_lock"
	name = "Swipe ID"
	effect = /obj/machinery/ai_slipper/proc/interaction_toggle_lock

/obj/machinery/ai_slipper/proc/interaction_toggle_lock(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	if(istype(user, /mob/living/silicon))
		attack_hand(user)
		return TRUE
	if(allowed(user))
		set_locked(!locked)
		to_chat(user, "You [ locked ? "lock" : "unlock"] the device.")
		if(locked)
			SStgui.close_uis(src)
		else if(user.check_current_machine(src))
			attack_hand(user)
	else
		to_chat(user, span_warning("Access denied."))
	return TRUE

/datum/interaction/machine_hand/ungated/ai_slipper_use
	id = "ai_slipper_use"
	name = "Use"
	requires = list()
	effect = /obj/machinery/ai_slipper/proc/interaction_use

/obj/machinery/ai_slipper/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	if(get_dist(src, user) > 1 && !istype(user, /mob/living/silicon))
		to_chat(user, "Too far away.")
		user.unset_machine()
		SStgui.close_uis(src)
		return TRUE
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/ai_slipper, "AiSlipper", UI_TITLE("AI Liquid Dispenser"))

UI_DATA_REPLACE(/obj/machinery/ai_slipper, "uses:num", "cooldown_timeleft:num", "merge:ui_data_obj_machinery_ai_slipper{area_name:unknown,locked:bool,is_silicon:num,disabled:bool,cooldown_on:bool}")

/// The computed part of /obj/machinery/ai_slipper's window data (declared on its UI_DATA row).
/obj/machinery/ai_slipper/proc/ui_data_obj_machinery_ai_slipper(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/area/A = get_area(src)
	data["area_name"] = A?.name || "Unknown"
	data["locked"] = !!locked
	data["is_silicon"] = istype(user, /mob/living/silicon)
	data["disabled"] = !!disabled
	data["cooldown_on"] = !!cooldown_on
	return data

/obj/machinery/ai_slipper/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(locked && !istype(usr, /mob/living/silicon))
		to_chat(usr, "Control panel is locked!")
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/ai_slipper, "toggle_on", ui_act_toggle_on)
UI_ACT_PROC(/obj/machinery/ai_slipper, ui_act_toggle_on)
	disabled = !disabled
	update_icon()
	return TRUE

UI_ACT(/obj/machinery/ai_slipper, "toggle_use", ui_act_toggle_use)
UI_ACT_PROC(/obj/machinery/ai_slipper, ui_act_toggle_use)
	if(cooldown_on || disabled || uses <= 0)
		return TRUE
	new /obj/effect/effect/foam(src.loc)
	uses--
	cooldown_on = 1
	cooldown_time = world.timeofday + 100
	slip_process()
	return TRUE

/obj/machinery/ai_slipper/proc/slip_process()
	var/ticksleft = cooldown_time - world.timeofday
	if(ticksleft > 0)
		if(ticksleft > 1e5)
			cooldown_time = world.timeofday + 10	// midnight rollover
		cooldown_timeleft = (ticksleft / 10)
		om_after(src, 5, PROC_REF(slip_process))
		return
	if(uses <= 0)
		return
	if(uses >= 0)
		cooldown_on = 0
	power_change()
	return
