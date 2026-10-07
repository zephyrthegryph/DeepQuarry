MATERIAL_MIX(/obj/item/assembly/timer, list(MAT_STEEL = 500, MAT_GLASS = 50))
/obj/item/assembly/timer
	name = "timer"
	desc = "Used to time things. Works well with contraptions which has to count down. Tick tock."
	icon_state = "timer"

	wires_type = WIRE_PULSE

	secured = 0

	var/time = 10


/obj/item/assembly/timer/var/timing = FALSE
TRACKED(/obj/item/assembly/timer, timing)

/obj/item/assembly/timer/activate()
	if(!..())
		return FALSE

	set_state(!timing)

	update_icon()
	return 0

/obj/item/assembly/timer/toggle_secure()
	set_secured(!secured)
	if(!secured)
		set_timing(FALSE)
	update_icon()
	return secured

/obj/item/assembly/timer/proc/set_state(state)
	set_timing(state)

/obj/item/assembly/timer/proc/timer_end()
	if(!secured)
		return 0
	pulse(0)
	if(!holder())
		visible_message("[icon2html(src,viewers(src))] *beep* *beep*", "*beep* *beep*")

/obj/item/assembly/timer/proc/timer_step(datum/act/timer/A)
	if(timing && time-- <= 0)
		set_state(0)
		timer_end()
		time = 10

DECLARE_APPEARANCE_PROC(/obj/item/assembly/timer, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/assembly/timer/appearance_overlays()
	. = list()
	attached_overlays = list()
	if(timing)
		. += "timer_timing"
		attached_overlays += "timer_timing"
	if(holder())
		holder().update_icon()
	return .

CAPABILITIES(/obj/item/assembly/timer)
	every(2 SECONDS, then(PROC_REF(timer_step)), when = nameof(timing))
	interface("AssemblyTimer", state = nameof(GLOB.tgui_deep_inventory_state))
	without("ui_open")
	op("timing", ui_act("timing"), then(PROC_REF(ui_act_timing)))
	op("set_time", ui_act("set_time", arg("time", num())), then(PROC_REF(ui_act_set_time)))

/obj/item/assembly/timer/ui_prepare(mob/user, datum/tgui/ui)
	if(!secured)
		to_chat(user, span_warning("[src] is unsecured!"))
		return FALSE
	return TRUE

/obj/item/assembly/timer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["time"] = time
	data["timing"] = timing
	return data

/obj/item/assembly/timer/proc/ui_act_timing(datum/act/op/A)
	set_state(!timing)
	update_icon()
	return TRUE

/obj/item/assembly/timer/proc/ui_act_set_time(datum/act/op/A, time_arg)
	var/real_new_time = 0
	var/new_time = time_arg
	if(isnum(new_time))
		real_new_time = new_time
	else
		var/list/L = splittext(new_time, ":")
		for(var/i in 1 to LAZYLEN(L))
			real_new_time += text2num(L[i]) * (60 ** (LAZYLEN(L) - i))
	time = clamp(real_new_time, 0, 600)
	return TRUE
