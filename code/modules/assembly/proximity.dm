MATERIAL_MIX(/obj/item/assembly/prox_sensor, list(MAT_STEEL = 800, MAT_GLASS = 200))
/obj/item/assembly/prox_sensor
	name = "proximity sensor"
	desc = "Used for scanning and alerting when someone enters a certain proximity."
	icon_state = "prox"
	wires_type = WIRE_PULSE

	secured = 0

	var/scanning = 0
	var/time = 10

	var/range = 2

/obj/item/assembly/prox_sensor/var/timing = FALSE
TRACKED(/obj/item/assembly/prox_sensor, timing)

/obj/item/assembly/prox_sensor/activate()
	if(!..())
		return FALSE
	set_timing(!timing)
	return FALSE

/obj/item/assembly/prox_sensor/toggle_secure()
	set_secured(!secured)
	if(!secured)
		set_scanning(0)
		set_timing(FALSE)
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

/obj/item/assembly/prox_sensor/proc/prox_sensor_step(datum/act/timer/A)
	if(scanning)
		var/turf/mainloc = get_turf(src)
		for(var/mob/living/L in range(range,mainloc))
			if (L.move_speed < 12)
				sense()

	if(timing && (time >= 0))
		time--
	if(timing && time <= 0)
		set_timing(FALSE)
		toggle_scan()
		time = initial(time)

/obj/item/assembly/prox_sensor/dropped(mob/user, equipping, slot)
	..()
	sense()

/obj/item/assembly/prox_sensor/proc/toggle_scan()
	if(!secured)
		return FALSE
	set_scanning(!scanning)

TRACKED(/obj/item/assembly/prox_sensor, scanning)

/obj/item/assembly/prox_sensor/holder_layers()
	var/list/layers
	if(timing)
		LAZYADD(layers, "prox_timing")
	if(scanning)
		LAZYADD(layers, "prox_scanning")
	return layers

/// A grenade this sensor primes follows its scanning.
/obj/item/assembly/prox_sensor/proc/scanning_changed(datum/act/A)
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

CAPABILITIES(/obj/item/assembly/prox_sensor)
	/// Scans and counts down only while secured.
	every(2 SECONDS, then(PROC_REF(prox_sensor_step)), when = nameof(secured))
	on_change(nameof(scanning), ANY, then(PROC_REF(scanning_changed)))
	interface("AssemblyProx", state = nameof(GLOB.tgui_deep_inventory_state))
	without("ui_open")
	op("scanning", ui_act("scanning"), then(PROC_REF(ui_act_scanning)))
	op("timing", ui_act("timing"), then(PROC_REF(ui_act_timing)))
	op("set_time", ui_act("set_time", arg("time", num())), then(PROC_REF(ui_act_set_time)))
	op("range", ui_act("range", arg("range", num())), then(PROC_REF(ui_act_range)))

/obj/item/assembly/prox_sensor/ui_prepare(mob/user, datum/tgui/ui)
	if(!secured)
		to_chat(user, span_warning("[src] is unsecured!"))
		return FALSE
	return TRUE

/obj/item/assembly/prox_sensor/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["time"] = time
	data["timing"] = timing
	data["range"] = range
	data["scanning"] = scanning
	var/list/merged_1 = ui_data_obj_item_assembly_prox_sensor(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/assembly/prox_sensor's window data.
/obj/item/assembly/prox_sensor/proc/ui_data_obj_item_assembly_prox_sensor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["maxRange"] = 5

	return data

/obj/item/assembly/prox_sensor/proc/ui_act_scanning(datum/act/op/A)
	toggle_scan()
	return TRUE

/obj/item/assembly/prox_sensor/proc/ui_act_timing(datum/act/op/A)
	set_timing(!timing)
	return TRUE

/obj/item/assembly/prox_sensor/proc/ui_act_set_time(datum/act/op/A, time_arg)
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

/obj/item/assembly/prox_sensor/proc/ui_act_range(datum/act/op/A, range_arg)
	range = clamp(range_arg, 1, 5)
	return TRUE
