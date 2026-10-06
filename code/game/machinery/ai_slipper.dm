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
	req_access = list(ACCESS_AI_UPLOAD)

OM_FIELD(/obj/machinery/ai_slipper, cooldown_on, 0, CHANGE_MACHINE_SETTINGS)
DECLARE_REPEAT(/obj/machinery/ai_slipper, 0.5 SECONDS, slip_process, "cooldown_on")

/obj/machinery/ai_slipper/proc/appearance_on()
	return (!has_stat(NOPOWER) && !has_stat(BROKEN) && !disabled) ? 1 : 0

/// The look (the draw sweep: from its template).
/obj/machinery/ai_slipper/draw(datum/look/look)
	..()
	look.state("liquid_dispenser[appearance_on() ? "_on" : ""]")

/obj/machinery/ai_slipper/proc/setState(enabled, uses)
	disabled = !enabled
	src.uses = uses
	power_change()

// TGUI migration. The old attack_hand opened AiSlipper.tsx; the
// Topic-driven toggle/fire actions move to tgui_act. The old attackby kept the
// ID-swipe lock/unlock behavior and just closed the UI on lock.

/obj/machinery/ai_slipper/proc/interaction_toggle_lock(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return OP_OK
	if(istype(user, /mob/living/silicon))
		attack_hand(user)
		return OP_OK
	if(allowed(user))
		set_locked(!locked)
		to_chat(user, "You [ locked ? "lock" : "unlock"] the device.")
		if(locked)
			SStgui.close_uis(src)
		else if(user.check_current_machine(src))
			attack_hand(user)
	else
		to_chat(user, span_warning("Access denied."))
	return OP_OK

/obj/machinery/ai_slipper/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return OP_OK
	if(get_dist(src, user) > 1 && !istype(user, /mob/living/silicon))
		to_chat(user, "Too far away.")
		user.unset_machine()
		SStgui.close_uis(src)
		return OP_OK
	tgui_interact(user)
	return OP_OK

CAPABILITIES(/obj/machinery/ai_slipper)
	interface("AiSlipper", title = "AI Liquid Dispenser")
	op("toggle_on", ui_act("toggle_on"), then(PROC_REF(ui_act_toggle_on)))
	op("toggle_use", ui_act("toggle_use"), then(PROC_REF(ui_act_toggle_use)))
	extend(TAG_UI, needs(req(PROC_REF(panel_unlocked), because = MSG(ai_slipper/panel_locked))))
	op("ai_slipper_toggle_lock", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Swipe ID"), then(PROC_REF(interaction_toggle_lock)))
	op("ai_slipper_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))

MSG_DEF_SELF(ai_slipper/panel_locked, "Control panel is locked!")

/// A locked panel answers only a silicon.
/obj/machinery/ai_slipper/proc/panel_unlocked(datum/act/op/A)
	return !locked || issilicon(A.actor)

/obj/machinery/ai_slipper/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	var/area/here = get_area(src)
	data["area_name"] = here?.name || "Unknown"
	data["locked"] = !!locked
	data["is_silicon"] = istype(user, /mob/living/silicon)
	data["disabled"] = !!disabled
	data["cooldown_on"] = !!cooldown_on
	data["uses"] = uses
	data["cooldown_timeleft"] = cooldown_timeleft
	return data

/obj/machinery/ai_slipper/proc/ui_act_toggle_on(datum/act/op/A)
	disabled = !disabled
	return TRUE

/obj/machinery/ai_slipper/proc/ui_act_toggle_use(datum/act/op/A)
	if(cooldown_on || disabled || uses <= 0)
		return TRUE
	new /obj/effect/effect/foam(src.loc)
	uses--
	cooldown_time = world.timeofday + 10 SECONDS
	set_cooldown_on(1)
	return TRUE

/obj/machinery/ai_slipper/proc/slip_process()
	var/ticksleft = cooldown_time - world.timeofday
	if(ticksleft > 0)
		if(ticksleft > 1e5)
			cooldown_time = world.timeofday + 10	// midnight rollover
		cooldown_timeleft = (ticksleft / 10)
		return
	if(uses <= 0)
		return REPEAT_STOP
	set_cooldown_on(0)
	power_change()
