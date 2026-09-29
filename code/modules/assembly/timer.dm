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

/obj/item/assembly/timer/update_icon()
	cut_overlays()
	attached_overlays = list()
	if(timing)
		add_overlay("timer_timing")
		attached_overlays += "timer_timing"
	if(holder())
		holder().update_icon()
	return

DECLARE_UI(/obj/item/assembly/timer, "AssemblyTimer")

/obj/item/assembly/timer/ui_prepare(mob/user, datum/tgui/ui)
	if(!secured)
		to_chat(user, span_warning("[src] is unsecured!"))
		return FALSE
	return TRUE

UI_DATA(/obj/item/assembly/timer, "time:num", "timing:num")

UI_ACT(/obj/item/assembly/timer, "timing", ui_act_timing)
UI_ACT_PROC(/obj/item/assembly/timer, ui_act_timing)
	set_state(!timing)
	update_icon()
	return TRUE

UI_ACT(/obj/item/assembly/timer, "set_time", ui_act_set_time, UI_ARG_NUM("time"))
UI_ACT_PROC(/obj/item/assembly/timer, ui_act_set_time)
	var/real_new_time = 0
	var/new_time = params["time"]
	if(isnum(new_time))
		real_new_time = new_time
	else
		var/list/L = splittext(new_time, ":")
		for(var/i in 1 to LAZYLEN(L))
			real_new_time += text2num(L[i]) * (60 ** (LAZYLEN(L) - i))
	time = clamp(real_new_time, 0, 600)
	return TRUE
