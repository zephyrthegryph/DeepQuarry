MATERIAL_MIX(/obj/item/assembly/timer, list(MAT_STEEL = 500, MAT_GLASS = 50))
/obj/item/assembly/timer
	name = "timer"
	desc = "Used to time things. Works well with contraptions which has to count down. Tick tock."
	icon_state = "timer"

	wires_type = WIRE_PULSE

	secured = 0

	var/timing = 0
	var/time = 10


/obj/item/assembly/timer/activate()
	if(!..())
		return FALSE

	set_state(!timing)

	update_icon()
	return 0

/obj/item/assembly/timer/toggle_secure()
	secured = !secured
	if(secured)
		om_task_periodic(src, PERIODIC_SLOW)
	else
		timing = 0
		om_task_periodic_stop(src)
	update_icon()
	return secured

/obj/item/assembly/timer/proc/set_state(state)
	if(state && !timing) //Not running, starting though
		om_task_periodic(src, PERIODIC_SLOW)
	else if(timing && !state) //Running, stopping though
		om_task_periodic_stop(src)
	timing = state

/obj/item/assembly/timer/proc/timer_end()
	if(!secured)
		return 0
	pulse(0)
	if(!holder())
		visible_message("[icon2html(src,viewers(src))] *beep* *beep*", "*beep* *beep*")

/obj/item/assembly/timer/periodic_step()
	if(timing && time-- <= 0)
		set_state(0)
		timer_end()
		time = 10

DECLARE_APPEARANCE_PROC(/obj/item/assembly/timer, PROC_REF(appearance_overlays), list())
/obj/item/assembly/timer/appearance_overlays()
	. = list()
	attached_overlays = list()
	if(timing)
		. += "timer_timing"
		attached_overlays += "timer_timing"
	if(holder())
		holder().update_icon()
	return .

/obj/item/assembly/timer/tgui_interact(mob/user, datum/tgui/ui)
	if(!secured)
		to_chat(user, span_warning("[src] is unsecured!"))
		return FALSE
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AssemblyTimer", name)
		ui.open()

/obj/item/assembly/timer/tgui_data(mob/user)
	var/list/data = ..()
	data["time"] = time
	data["timing"] = timing
	return data

/obj/item/assembly/timer/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("timing")
			set_state(!timing)
			update_icon()
			return TRUE
		if("set_time")
			var/real_new_time = 0
			var/new_time = params["time"]
			var/list/L = splittext(new_time, ":")
			if(LAZYLEN(L))
				for(var/i in 1 to LAZYLEN(L))
					real_new_time += text2num(L[i]) * (60 ** (LAZYLEN(L) - i))
			else
				real_new_time = text2num(new_time)
			time = clamp(real_new_time, 0, 600)
			return TRUE
