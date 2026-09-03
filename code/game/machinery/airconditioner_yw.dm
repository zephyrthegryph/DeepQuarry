/obj/machinery/power/thermoregulator/cryogaia
	name = "Custom Thermal Regulator"
	desc = "A massive custom made Thermal regulator or CTR for short, intended to keep heat loss when going in our outside to a minimum, they are hardwired to twenty celsius"
	icon = 'icons/obj/machines/wallthermal.dmi'
	icon_state = "lasergen"
	density = 0
	anchored = 1
	//Consider making this powered by the room at some point.
	use_power = 0 //is powered directly from cables
	active_power_usage = 25 KILOWATTS  //Low Power
	idle_power_usage = 250

	circuit = null
	maintenance_flags = MACHINE_MAINT_STANDARD
	/*
	null so people can not deconstruct them and remake them to normal Regulators,
	probably should just make a circuit for it but this is pretty much just a proof of concept at the moment.
	*/

/obj/machinery/power/thermoregulator/cryogaia/wrench_act(mob/user, obj/item/I)
	anchored = !anchored
	visible_message(span_notice("\The [src] has been [anchored ? "bolted to the floor" : "unbolted from the floor"] by [user].")) //Does this not need to be disabled?
	playsound(src, I.usesound, 75, 1)
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()
		turn_off()
	return ITEM_INTERACT_SUCCESS
