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
	var/locked = 1
	var/cooldown_time = 0
	var/cooldown_timeleft = 0
	var/cooldown_on = 0
	req_access = list(ACCESS_AI_UPLOAD)

/obj/machinery/ai_slipper/Initialize(mapload)
	. = ..()
	update_icon()

/obj/machinery/ai_slipper/power_change()
	..()
	update_icon()

/obj/machinery/ai_slipper/update_icon()
	if(stat & NOPOWER || stat & BROKEN)
		icon_state = "liquid_dispenser"
	else
		icon_state = disabled ? "liquid_dispenser" : "liquid_dispenser_on"

/obj/machinery/ai_slipper/proc/setState(enabled, uses)
	disabled = disabled
	uses = uses
	power_change()

/obj/machinery/ai_slipper/attackby(obj/item/W, mob/user)
	if(stat & (NOPOWER|BROKEN))
		return
	if(istype(user, /mob/living/silicon))
		return attack_hand(user)
	if(allowed(user))
		locked = !locked
		to_chat(user, "You [ locked ? "lock" : "unlock"] the device.")
		if(locked)
			SStgui.close_uis(src)
		else if(user.check_current_machine(src))
			attack_hand(user)
	else
		to_chat(user, span_warning("Access denied."))
	return

/obj/machinery/ai_slipper/attack_ai(mob/user as mob)
	return attack_hand(user)

/obj/machinery/ai_slipper/attack_hand(mob/user as mob)
	if(stat & (NOPOWER|BROKEN))
		return
	if(get_dist(src, user) > 1 && !istype(user, /mob/living/silicon))
		to_chat(user, "Too far away.")
		user.unset_machine()
		SStgui.close_uis(src)
		return
	tgui_interact(user)

/obj/machinery/ai_slipper/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AiSlipper", "AI Liquid Dispenser")
		ui.open()

/obj/machinery/ai_slipper/tgui_data(mob/user)
	var/list/data = list()
	var/area/A = get_area(src)
	data["area_name"] = A?.name || "Unknown"
	data["locked"] = !!locked
	data["is_silicon"] = istype(user, /mob/living/silicon)
	data["disabled"] = !!disabled
	data["uses"] = uses
	data["cooldown_on"] = !!cooldown_on
	data["cooldown_timeleft"] = cooldown_timeleft
	return data

/obj/machinery/ai_slipper/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(locked && !istype(usr, /mob/living/silicon))
		to_chat(usr, "Control panel is locked!")
		return TRUE
	switch(action)
		if("toggle_on")
			disabled = !disabled
			update_icon()
			return TRUE
		if("toggle_use")
			if(cooldown_on || disabled || uses <= 0)
				return TRUE
			new /obj/effect/effect/foam(src.loc)
			uses--
			cooldown_on = 1
			cooldown_time = world.timeofday + 100
			slip_process()
			return TRUE

/obj/machinery/ai_slipper/proc/slip_process()
	while(cooldown_time - world.timeofday > 0)
		var/ticksleft = cooldown_time - world.timeofday

		if(ticksleft > 1e5)
			cooldown_time = world.timeofday + 10	// midnight rollover


		cooldown_timeleft = (ticksleft / 10)
		sleep(5)
	if(uses <= 0)
		return
	if(uses >= 0)
		cooldown_on = 0
	power_change()
	return
