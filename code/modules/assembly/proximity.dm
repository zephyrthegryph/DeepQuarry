MATERIAL_MIX(/obj/item/assembly/prox_sensor, list(MAT_STEEL = 800, MAT_GLASS = 200))
/obj/item/assembly/prox_sensor
	name = "proximity sensor"
	desc = "Used for scanning and alerting when someone enters a certain proximity."
	icon_state = "prox"
	wires_type = WIRE_PULSE

	secured = 0

	var/scanning = 0
	var/timing = 0
	var/time = 10

	var/range = 2

/obj/item/assembly/prox_sensor/activate()
	if(!..())
		return FALSE
	timing = !timing
	update_icon()
	return FALSE

/obj/item/assembly/prox_sensor/toggle_secure()
	secured = !secured
	if(secured)
		om_task_periodic(src, PERIODIC_SLOW)
	else
		scanning = 0
		timing = 0
		om_task_periodic_stop(src)
	update_icon()
	return secured

/obj/item/assembly/prox_sensor/HasProximity(turf/T, WF, old_loc)
	if(isnull(WF))
		return
	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	if (istype(AM, /obj/effect/beam))
		return
	if (!isobserver(AM) && AM.move_speed < 12)
		sense()

/obj/item/assembly/prox_sensor/proc/sense()
	if((!holder() && !secured) || !scanning || !COOLDOWN_FINISHED(src, next_activate))
		return FALSE
	var/turf/mainloc = get_turf(src)
	pulse(0)
	if(!holder())
		mainloc.visible_message("[icon2html(src,viewers(src))] *beep* *beep*", "*beep* *beep*")

/obj/item/assembly/prox_sensor/periodic_step()
	if(scanning)
		var/turf/mainloc = get_turf(src)
		for(var/mob/living/A in range(range,mainloc))
			if (A.move_speed < 12)
				sense()

	if(timing && (time >= 0))
		time--
	if(timing && time <= 0)
		timing = 0
		toggle_scan()
		time = initial(time)

/obj/item/assembly/prox_sensor/dropped(mob/user, equipping, slot)
	..()
	sense()

/obj/item/assembly/prox_sensor/proc/toggle_scan()
	if(!secured)
		return FALSE
	scanning = !scanning
	update_icon()

/obj/item/assembly/prox_sensor/update_icon()
	cut_overlays()
	LAZYCLEARLIST(attached_overlays)
	if(timing)
		add_overlay("prox_timing")
		LAZYADD(attached_overlays, "prox_timing")
	if(scanning)
		add_overlay("prox_scanning")
		LAZYADD(attached_overlays, "prox_scanning")
	if(holder())
		holder().update_icon()
	if(holder() && istype(holder().loc,/obj/item/grenade/chem_grenade))
		var/obj/item/grenade/chem_grenade/grenade = holder().loc
		grenade.primed(scanning)

/obj/item/assembly/prox_sensor/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(isturf(old_loc))
		unsense_proximity(range = range, callback = TYPE_PROC_REF(/atom,HasProximity), center = old_loc)
	if(isturf(loc))
		sense_proximity(range = range, callback = TYPE_PROC_REF(/atom,HasProximity))
	sense()

DECLARE_UI(/obj/item/assembly/prox_sensor, "AssemblyProx")

/obj/item/assembly/prox_sensor/ui_prepare(mob/user, datum/tgui/ui)
	if(!secured)
		to_chat(user, span_warning("[src] is unsecured!"))
		return FALSE
	return TRUE

UI_DATA(/obj/item/assembly/prox_sensor, "time:num", "timing:num", "range:num", "scanning:num", "merge:ui_data_obj_item_assembly_prox_sensor{maxRange:num}")

/// The computed part of /obj/item/assembly/prox_sensor's window data (declared on its UI_DATA row).
/obj/item/assembly/prox_sensor/proc/ui_data_obj_item_assembly_prox_sensor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["maxRange"] = 5

	return data

UI_ACT(/obj/item/assembly/prox_sensor, "scanning", ui_act_scanning)
UI_ACT_PROC(/obj/item/assembly/prox_sensor, ui_act_scanning)
	toggle_scan()
	return TRUE

UI_ACT(/obj/item/assembly/prox_sensor, "timing", ui_act_timing)
UI_ACT_PROC(/obj/item/assembly/prox_sensor, ui_act_timing)
	timing = !timing
	update_icon()
	return TRUE

UI_ACT(/obj/item/assembly/prox_sensor, "set_time", ui_act_set_time, UI_ARG_NUM("time"))
UI_ACT_PROC(/obj/item/assembly/prox_sensor, ui_act_set_time)
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

UI_ACT(/obj/item/assembly/prox_sensor, "range", ui_act_range, UI_ARG_NUM("range"))
UI_ACT_PROC(/obj/item/assembly/prox_sensor, ui_act_range)
	range = clamp(params["range"], 1, 5)
	return TRUE
