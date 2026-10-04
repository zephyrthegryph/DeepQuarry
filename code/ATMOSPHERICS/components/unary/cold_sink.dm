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

DECLARE_REAGENTS(/obj/machinery/atmospherics/unary/freezer, 120, null)

/obj/machinery/atmospherics/unary/freezer/Initialize(mapload)
	. = ..()
	default_apply_parts()
	add_hose_connector(/datum/hose_connector/input)
	add_hose_connector(/datum/hose_connector/output)

/obj/machinery/atmospherics/unary/freezer/atmos_init()
	if(node)
		return

	var/node_connect = dir

	for(var/obj/machinery/atmospherics/target in get_step(src, node_connect))
		if(can_be_node(target, 1))
			rel_set(src, nameof(node), target)
			break

	if(check_for_obstacles())
		rel_clear(src, nameof(node))

	if(node)
		update_icon()

/// Appearance reader: 0 unconnected, 1 connected idle, 2 connected and cooling.
/obj/machinery/atmospherics/unary/freezer/proc/appearance_freezer_state()
	if(!node)
		return 0
	return (use_power && cooling) ? 2 : 1

DECLARE_APPEARANCE(/obj/machinery/atmospherics/unary/freezer, "appearance_freezer_state", list(
	"0" = list(APPEARANCE_ICON_STATE = "freezer_0"),
	"1" = list(APPEARANCE_ICON_STATE = "freezer"),
	"2" = list(APPEARANCE_ICON_STATE = "freezer_1"),
))

/obj/machinery/atmospherics/unary/freezer
	silicon_use = SILICON_USE_UI

/obj/machinery/atmospherics/unary/freezer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/open_ui,
		/datum/interaction/machine_item/part_replacement,
	)
	..()

CAPABILITIES(/obj/machinery/atmospherics/unary/freezer)
	interface("GasTemperatureSystem")
	op("toggleStatus", ui_act("toggleStatus"), then(PROC_REF(ui_act_togglestatus)))
	op("setGasTemperature", ui_act("setGasTemperature", arg("temp", num())), then(PROC_REF(ui_act_setgastemperature)))
	op("setPower", ui_act("setPower", arg("value", num())), then(PROC_REF(ui_act_setpower)))

/obj/machinery/atmospherics/unary/freezer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["powerSetting"] = power_setting
	data["reagentPower"] = reagent_cooling
	var/list/merged_1 = ui_data_obj_machinery_atmospherics_unary_freezer(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// The computed part of /obj/machinery/atmospherics/unary/freezer's window data (declared on its UI_DATA row).
/obj/machinery/atmospherics/unary/freezer/proc/ui_data_obj_machinery_atmospherics_unary_freezer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	// this is the data which will be sent to the ui
	var/list/data = list()
	var/air_temperature = air_contents.return_temperature()
	data["on"] = use_power ? 1 : 0
	data["gasPressure"] = round(air_contents.return_pressure())
	data["gasTemperature"] = round(air_temperature)
	data["minGasTemperature"] = 0
	data["maxGasTemperature"] = round(T20C+500)
	data["targetGasTemperature"] = round(set_temperature)

	data["reagentVolume"] = reagents.total_volume
	data["reagentMaximum"] = reagents.maximum_volume

	var/temp_class = "good"
	if(air_temperature > (T0C - 20))
		temp_class = "bad"
	else if(air_temperature < (T0C - 20) && air_temperature > (T0C - 100))
		temp_class = "average"
	data["gasTemperatureClass"] = temp_class

	return data

/obj/machinery/atmospherics/unary/freezer/proc/ui_act_togglestatus(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	set_use_power(!use_power)
	add_fingerprint(user)
	if(.)
		invalidate_gas_dependencies()

/obj/machinery/atmospherics/unary/freezer/proc/ui_act_setgastemperature(datum/act/op/A, temp)
	var/mob/user = A.actor
	. = TRUE
	var/amount = temp
	if(amount > 0)
		set_temperature = min(amount, 1000)
	else
		set_temperature = max(amount, 0)
	add_fingerprint(user)
	if(.)
		invalidate_gas_dependencies()

/obj/machinery/atmospherics/unary/freezer/proc/ui_act_setpower(datum/act/op/A, value)
	var/mob/user = A.actor
	. = TRUE
	var/new_setting = between(0, value, 100)
	set_power_level(new_setting)
	add_fingerprint(user)
	if(.)
		invalidate_gas_dependencies()

/obj/machinery/atmospherics/unary/freezer/machine_step()
	..()

	reagent_cooling = 1 + (reagents.machine_cooling_power(reagents) / reagents.maximum_volume)
	if(!operable() || !use_power)
		cooling = 0
		update_icon()
		register_gas_dependencies()
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
		register_gas_dependencies()
		update_icon()
		return PROCESS_KILL

	update_icon()
	return 1

/// Eligibility rule for waking from gas (unary_base.dm register_gas_dependencies()): the same
/// test process() makes before it cools anything.
/obj/machinery/atmospherics/unary/freezer/gas_wake_condition()
	return use_power && operable() && network && air_contents.total_moles() && air_contents.return_temperature() > set_temperature

/obj/machinery/atmospherics/unary/freezer/power_change()
	. = ..()
	if(.)
		// process() hibernates on NOPOWER; a power transition is a dependency change.
		invalidate_gas_dependencies()

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
