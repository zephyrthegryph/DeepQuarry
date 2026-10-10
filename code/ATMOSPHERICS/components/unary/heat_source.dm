TRACKED(/obj/machinery/atmospherics/unary/heater, pumping)
TRACKED(/obj/machinery/atmospherics/unary/heater, heating)
TRACKED(/obj/machinery/atmospherics/unary/heater, set_temperature)

CAPABILITIES(/obj/machinery/atmospherics/unary/heater)
	silicon_ui()
	reagents(120)
	// A resistive heater on its pipeline's gas toward the thermostat: one joule of heat per joule drawn.
	when(nameof(pumping), heat_pump(HEAT_PORT(1), HEAT_AIR, nameof(power_rating), nameof(set_temperature), HEAT_PUMP_HEAT, TRUE))
	gas_watch(air = nameof(air_contents), changed = PROC_REF(gas_changed))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(service)), when = nameof(heating))
	on_change(nameof(use_power), ANY, then(PROC_REF(reconsider)))
	on_change(nameof(set_temperature), ANY, then(PROC_REF(reconsider)))
	part_replacement()
	op("toggleStatus", ui_act("toggleStatus"), then(PROC_REF(ui_act_togglestatus)))
	interface("GasTemperatureSystem")
	op("setGasTemperature", ui_act("setGasTemperature", arg("temp", num())), then(PROC_REF(ui_act_setgastemperature)))
	op("setPower", ui_act("setPower", arg("value", num())), then(PROC_REF(ui_act_setpower)))

//TODO: Put this under a common parent type with freezers to cut down on the copypasta
#define HEATER_PERF_MULT 2.5
#define REAGENT_COOLING_CONSUMED 0.1
#define REAGENT_COOLING_MINMOD 0.15
#define REAGENT_COOLING_MAXMOD 5

/obj/machinery/atmospherics/unary/heater
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "gas heating system"
	desc = "Heats gas when connected to a pipe network. Can be filled by hose with coolant to increase efficiency."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "heater_0"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_OFF
	idle_power_usage = 5			//5 Watts for thermostat related circuitry
	circuit = /obj/item/circuitboard/unary_atmos/heater

	var/max_temperature = T20C + 680
	var/internal_volume = 600	//L
	var/heating_efficiency = 1

	var/max_power_rating = 20000	//power rating when the usage is turned up to 100
	var/power_setting = 100

	var/set_temperature = T20C	//thermostat
	var/heating = 0		//mainly for icon updates
	/// TRUE while it heats: its heater exists exactly while this is set.
	var/pumping = FALSE
	var/reagent_cooling = 0


/obj/machinery/atmospherics/unary/heater/Initialize(mapload)
	. = ..()
	default_apply_parts()
	add_hose_connector(/datum/hose_connector/input)
	add_hose_connector(/datum/hose_connector/output)

/obj/machinery/atmospherics/unary/heater/atmos_init()
	if(node)
		return

	var/node_connect = dir

	//check that there is something to connect to
	for(var/obj/machinery/atmospherics/target in get_step(src, node_connect))
		if(can_be_node(target, 1))
			rel_set(src, nameof(node), target)
			break

	if(check_for_obstacles())
		rel_clear(src, nameof(node))


/// Unconnected, connected and idle, or working.
/obj/machinery/atmospherics/unary/heater/draw(datum/look/look)
	..()
	if(!node) // ALLOW(derived_reads): atmos_init() and disconnect() redraw it when its pipe comes or goes
		look.state("heater_0")
	else
		look.state((use_power && heating) ? "heater_1" : "heater")

/obj/machinery/atmospherics/unary/heater/derived()
	. = ..()
	. += drawn_from(nameof(use_power), nameof(heating))


// ---- its work: woken by its gas, its switch and its thermostat; nothing polls ----

/// Its pipe's gas changed (its gas watch): it looks again whether it has work.
/obj/machinery/atmospherics/unary/heater/proc/gas_changed(list/observation, index)
	reconsider()

/// What it does now: the heater (its CAPABILITIES entry) exists while it is switched on and works; it heats while its loop's gas is below the
/// thermostat.
/obj/machinery/atmospherics/unary/heater/proc/reconsider(datum/act/A)
	var/on = !!(operable() && use_power)
	set_pumping(on)
	set_heating(on && network && air_contents.total_moles() && air_contents.return_temperature() < set_temperature)

/// One interval of heating: it pays its work and uses up coolant (the heat itself moves in Rust).
/obj/machinery/atmospherics/unary/heater/proc/service(datum/act/A)
	reagent_cooling = 1 + (reagents.machine_cooling_power(reagents) / reagents.maximum_volume)
	use_power(-heat_entries_power(src))
	reagents.remove_any(REAGENT_COOLING_CONSUMED)
	reconsider()

/obj/machinery/atmospherics/unary/heater/power_change()
	. = ..()
	if(.)
		reconsider()

/obj/machinery/atmospherics/unary/heater/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["powerSetting"] = power_setting
	data["reagentPower"] = reagent_cooling
	var/list/merged_1 = ui_data_obj_machinery_atmospherics_unary_heater(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/atmospherics/unary/heater's window data.
/obj/machinery/atmospherics/unary/heater/proc/ui_data_obj_machinery_atmospherics_unary_heater(mob/user, datum/tgui/ui, datum/tgui_state/state)
	// this is the data which will be sent to the ui
	var/list/data = list()
	data["on"] = use_power ? 1 : 0
	var/air_temperature = air_contents.return_temperature()
	data["gasPressure"] = round(air_contents.return_pressure())
	data["gasTemperature"] = round(air_temperature)
	data["minGasTemperature"] = 0
	data["maxGasTemperature"] = round(max_temperature)
	data["targetGasTemperature"] = round(set_temperature)

	data["reagentVolume"] = reagents.total_volume
	data["reagentMaximum"] = reagents.maximum_volume

	var/temp_class = "average"
	if(air_temperature > (T20C+40))
		temp_class = "bad"
	data["gasTemperatureClass"] = temp_class

	return data

/obj/machinery/atmospherics/unary/heater/proc/ui_act_togglestatus(datum/act/op/A)
	set_use_power(!use_power)
	return OP_OK

/obj/machinery/atmospherics/unary/heater/proc/ui_act_setgastemperature(datum/act/op/A, temp)
	var/mob/user = A.actor
	. = TRUE
	var/amount = temp
	if(amount > 0)
		set_set_temperature(min(amount, max_temperature))
	else
		set_set_temperature(max(amount, 0))
	reconsider()

/obj/machinery/atmospherics/unary/heater/proc/ui_act_setpower(datum/act/op/A, value)
	var/mob/user = A.actor
	. = TRUE
	var/new_setting = between(0, value, 100)
	set_power_level(new_setting)
	reconsider()

//upgrading parts
/obj/machinery/atmospherics/unary/heater/RefreshParts()
	..()
	var/cap_rating = 0
	var/bin_rating = 0
	var/laser_rating = get_part_rating(/obj/item/stock_parts/micro_laser) * 0.25
	cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)
	bin_rating = get_part_rating(/obj/item/stock_parts/matter_bin)


	max_power_rating = initial(max_power_rating) * cap_rating / 2
	max_temperature = max(initial(max_temperature) - T20C, 0) * ((bin_rating * 4 + cap_rating) / 5) + T20C
	air_contents.set_volume(max(initial(internal_volume) - 200, 0) + 200 * bin_rating)
	heating_efficiency = max(initial(heating_efficiency), (laser_rating-1))
	set_power_level(power_setting)

/obj/machinery/atmospherics/unary/heater/proc/set_power_level(new_power_setting)
	power_setting = new_power_setting
	power_rating = max_power_rating * (power_setting/100)
	heat_entries_refresh(src)

/obj/machinery/atmospherics/unary/heater/examine(mob/user)
	. = ..()
	if(panel_open)
		. += "The maintenance hatch is open."

#undef REAGENT_COOLING_MINMOD
#undef REAGENT_COOLING_MAXMOD
#undef REAGENT_COOLING_CONSUMED
#undef HEATER_PERF_MULT


/obj/machinery/atmospherics/unary/heater/sauna
	max_temperature = 331.15
	set_temperature = 313.15

/obj/machinery/atmospherics/unary/heater/cryosauna
	max_temperature = 290.15
	set_temperature = 263.15
