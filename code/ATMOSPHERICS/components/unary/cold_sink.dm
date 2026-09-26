//TODO: Put this under a common parent type with heaters to cut down on the copypasta
#define FREEZER_PERF_MULT 2.5
#define REAGENT_COOLING_CONSUMED 0.1
#define REAGENT_COOLING_MINMOD 0.15
#define REAGENT_COOLING_MAXMOD 5

/obj/machinery/atmospherics/unary/freezer
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "gas cooling system"
	desc = "Cools gas when connected to pipe network. Can be filled by hose with coolant to increase efficiency."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "freezer_0"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_OFF
	idle_power_usage = 5			// 5 Watts for thermostat related circuitry
	circuit = /obj/item/circuitboard/unary_atmos/cooler

	var/heatsink_temperature = T20C	// The constant temperature reservoir into which the freezer pumps heat. Probably the hull of the station or something.
	var/internal_volume = 600		// L

	var/max_power_rating = 20000	// Power rating when the usage is turned up to 100
	var/power_setting = 100

	var/set_temperature = T20C		// Thermostat
	var/cooling = 0
	var/reagent_cooling = 0
	gas_dependency_mask = GAS_DEPENDENCY_ALL

/obj/machinery/atmospherics/unary/freezer/Initialize(mapload)
	. = ..()
	default_apply_parts()
	create_reagents(120)
	AddComponent(/datum/component/hose_connector/input)
	AddComponent(/datum/component/hose_connector/output)

/obj/machinery/atmospherics/unary/freezer/atmos_init()
	if(node)
		return

	var/node_connect = dir

	for(var/obj/machinery/atmospherics/target in get_step(src, node_connect))
		if(can_be_node(target, 1))
			node = target
			break

	if(check_for_obstacles())
		node = null

	if(node)
		update_icon()

/obj/machinery/atmospherics/unary/freezer/update_icon()
	if(node)
		if(use_power && cooling)
			icon_state = "freezer_1"
		else
			icon_state = "freezer"
	else
		icon_state = "freezer_0"
	return

/obj/machinery/atmospherics/unary/freezer
	silicon_use = SILICON_USE_UI

/obj/machinery/atmospherics/unary/freezer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/open_ui,
		/datum/interaction/machine_item/part_replacement,
	)
	..()

/obj/machinery/atmospherics/unary/freezer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "GasTemperatureSystem", name)
		ui.open()

/obj/machinery/atmospherics/unary/freezer/tgui_data(mob/user)
	// this is the data which will be sent to the ui
	var/data[0]
	var/air_temperature = air_contents.return_temperature()
	data["on"] = use_power ? 1 : 0
	data["gasPressure"] = round(air_contents.return_pressure())
	data["gasTemperature"] = round(air_temperature)
	data["minGasTemperature"] = 0
	data["maxGasTemperature"] = round(T20C+500)
	data["targetGasTemperature"] = round(set_temperature)
	data["powerSetting"] = power_setting

	data["reagentVolume"] = reagents.total_volume
	data["reagentMaximum"] = reagents.maximum_volume
	data["reagentPower"] = reagent_cooling

	var/temp_class = "good"
	if(air_temperature > (T0C - 20))
		temp_class = "bad"
	else if(air_temperature < (T0C - 20) && air_temperature > (T0C - 100))
		temp_class = "average"
	data["gasTemperatureClass"] = temp_class

	return data

/obj/machinery/atmospherics/unary/freezer/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	. = TRUE
	switch(action)
		if("toggleStatus")
			update_use_power(!use_power)
			update_icon()
		if("setGasTemperature")
			var/amount = text2num(params["temp"])
			if(amount > 0)
				set_temperature = min(amount, 1000)
			else
				set_temperature = max(amount, 0)
		if("setPower") //setting power to 0 is redundant anyways
			var/new_setting = between(0, text2num(params["value"]), 100)
			set_power_level(new_setting)

	add_fingerprint(ui.user)
	if(.)
		invalidate_gas_dependencies()

/obj/machinery/atmospherics/unary/freezer/process()
	..()

	reagent_cooling = 1 + (reagents.machine_cooling_power(reagents) / reagents.maximum_volume)
	if(stat & (NOPOWER|BROKEN) || !use_power)
		cooling = 0
		update_icon()
		SSmachines.hibernate_vent(src)
		return PROCESS_KILL

	var/air_temperature = air_contents.return_temperature()
	if(network && air_contents.total_moles() && air_temperature > set_temperature)
		cooling = 1

		var/heat_transfer = max( -air_contents.get_thermal_energy_change(set_temperature - 5), 0 )

		//Assume the heat is being pumped into the hull which is fixed at heatsink_temperature
		//not /really/ proper thermodynamics but whatever
		var/cop = FREEZER_PERF_MULT * air_temperature/heatsink_temperature	//heatpump coefficient of performance from thermodynamics -> power used = heat_transfer/cop
		heat_transfer = min(heat_transfer, cop * power_rating)	//limit heat transfer by available power

		// Process coolant
		heat_transfer *= CLAMP(reagent_cooling,REAGENT_COOLING_MINMOD,REAGENT_COOLING_MAXMOD)
		reagents.remove_any(REAGENT_COOLING_CONSUMED)

		var/removed = -air_contents.add_thermal_energy(-heat_transfer)		//remove the heat
		if(debug)
			visible_message("[src]: Removing [removed] W.")

		use_power(power_rating)
		// Heat pump: the room around the machine is the hot side. It receives
		// the heat taken from the loop plus the electrical work.
		var/datum/gas_mixture/environment = loc?.return_air()
		environment?.add_thermal_energy(removed + power_rating)

		network.mark_dirty()
	else
		cooling = 0
		SSmachines.hibernate_vent(src)
		update_icon()
		return PROCESS_KILL

	update_icon()
	return 1

/// A band watch (code/datums/om/watch.dm, "any gas quantity" generalization) on its own pipe
/// contents' temperature crossing set_temperature, in place of the base unary "wake on any
/// change" revision watch: the freezer only ever has work to do once the gas it's cooling warms
/// back past its thermostat, so this skips every harmless composition/pressure wake in between.
/obj/machinery/atmospherics/unary/freezer/register_gas_dependencies()
	var/mixture_id = air_contents?.arena_id()
	if(isnull(mixture_id))
		return
	var/list/datum/om_watch_band/bands = list(new /datum/om_watch_band("temperature", TRUE, set_temperature, 2))
	om_watch_arm_bands(src, "pipe", mixture_id, bands, wake_callback = CALLBACK(src, PROC_REF(wake_from_gas)))

/obj/machinery/atmospherics/unary/freezer/unregister_gas_dependencies()
	om_watch_disarm(src, "pipe")

//upgrading parts
/obj/machinery/atmospherics/unary/freezer/RefreshParts()
	..()
	var/cap_rating = 0
	var/manip_rating = 0
	var/bin_rating = get_part_rating(/obj/item/stock_parts/matter_bin)
	cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)
	manip_rating = get_part_rating(/obj/item/stock_parts/manipulator)

	max_power_rating = initial(max_power_rating) * cap_rating / 2			//more powerful
	heatsink_temperature = initial(heatsink_temperature) / ((manip_rating + bin_rating) / 2)	//more efficient
	air_contents.set_volume(max(initial(internal_volume) - 200, 0) + 200 * bin_rating)
	set_power_level(power_setting)

/obj/machinery/atmospherics/unary/freezer/proc/set_power_level(new_power_setting)
	power_setting = new_power_setting
	power_rating = max_power_rating * (power_setting/100)

/obj/machinery/atmospherics/unary/freezer/examine(mob/user)
	. = ..()
	if(panel_open)
		. += "The maintenance hatch is open."

#undef REAGENT_COOLING_MINMOD
#undef REAGENT_COOLING_MAXMOD
#undef REAGENT_COOLING_CONSUMED
#undef FREEZER_PERF_MULT
