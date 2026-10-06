/obj/machinery/mech_sensor
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "airlock_sensor_off"
	name = "mechatronic sensor"
	desc = "Regulates mech movement."
	anchored = TRUE
	density = TRUE
	throwpass = 1
	use_power = USE_POWER_IDLE
	layer = ON_WINDOW_LAYER
	power_channel = EQUIP
	on = 0
	var/id_tag = null

	var/frequency = AIRLOCK_FREQ
	var/datum/radio_frequency/radio_connection
	/// Without it the feedback becomes horribly spammy.
	COOLDOWN_DECLARE(feedback_cooldown)

/obj/machinery/mech_sensor/CanPass(atom/movable/mover, turf/target)
	if(!enabled())
		return TRUE

	if((get_dir(loc, target) & dir) && src.is_blocked(mover))
		src.give_feedback(mover)
		return FALSE
	return TRUE

/obj/machinery/mech_sensor/proc/is_blocked(O as obj)
	if(istype(O, /obj/mecha/medical/odysseus))
		var/obj/mecha/medical/odysseus/M = O
		for(var/obj/item/mecha_parts/mecha_equipment/ME in M.equipment)
			if(istype(ME, /obj/item/mecha_parts/mecha_equipment/tool/sleeper))
				var/obj/item/mecha_parts/mecha_equipment/tool/sleeper/S = ME
				if(S?.slot_item(MECHA_SLOT_PILOT) != null)
					return 0

	return istype(O, /obj/mecha) || istype(O, /obj/vehicle)

/obj/machinery/mech_sensor/proc/give_feedback(O as obj)
	var/block_message = span_warning("Movement control overridden. Area denial active.")
	if(!COOLDOWN_FINISHED(src, feedback_cooldown))
		return

	if(istype(O, /obj/mecha))
		var/obj/mecha/R = O
		if(R && R?.slot_item(MECHA_SLOT_PILOT))
			to_chat(R?.slot_item(MECHA_SLOT_PILOT),block_message)
	else if(istype(O, /obj/vehicle/train/engine))
		var/obj/vehicle/train/engine/E = O
		if(E && E.load && E.is_train_head())
			to_chat(E.load,block_message)

	COOLDOWN_START(src, feedback_cooldown, 5 SECONDS)

/obj/machinery/mech_sensor/proc/enabled()
	return on && !has_stat(NOPOWER)

/// The look (the draw sweep: from its template).
/obj/machinery/mech_sensor/draw(datum/look/look)
	..()
	look.state("airlock_sensor_[enabled() ? "standby" : "off"]")

/obj/machinery/mech_sensor/Initialize(mapload)
	. = ..()
	set_frequency(frequency)

/obj/machinery/mech_sensor/proc/set_frequency(new_frequency)
	if(radio_connection())
		SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency))

/obj/machinery/mech_sensor/receive_signal(datum/signal/signal)
	if(has_stat(NOPOWER))
		return

	if(!signal.data["tag"] || (signal.data["tag"] != id_tag))
		return

	if(signal.data["command"] == "enable")
		set_on(1)
	else if (signal.data["command"] == "disable")
		set_on(0)


/// radio connection
/obj/machinery/mech_sensor/proc/radio_connection() as /datum/radio_frequency
	return radio_connection
