TRACKED(/obj/machinery/atmospherics/unary/freezer, pumping)
TRACKED(/obj/machinery/atmospherics/unary/freezer, cooling)
TRACKED(/obj/machinery/atmospherics/unary/freezer, set_temperature)

CAPABILITIES(/obj/machinery/atmospherics/unary/freezer)
	reagents(120)
	// A heat pump from its pipeline's gas into the room around it, toward the thermostat: the room takes the heat plus the work, at a
	// Carnot-bounded COP that better parts and coolant raise.
	when(nameof(pumping), heat_pump(HEAT_PORT(1), HEAT_AIR, nameof(power_rating), nameof(set_temperature), HEAT_PUMP_COOL, FALSE, nameof(carnot_fraction), nameof(max_cop)))
	gas_watch(air = nameof(air_contents), changed = PROC_REF(gas_changed))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(service)), when = nameof(cooling))
	on_change(nameof(use_power), ANY, then(PROC_REF(reconsider)))
	on_change(nameof(set_temperature), ANY, then(PROC_REF(reconsider)))
	part_replacement()
	op("toggleStatus", ui_act("toggleStatus"), then(PROC_REF(ui_act_togglestatus)))
	interface("GasTemperatureSystem")
	op("setGasTemperature", ui_act("setGasTemperature", arg("temp", num())), then(PROC_REF(ui_act_setgastemperature)))
	op("setPower", ui_act("setPower", arg("value", num())), then(PROC_REF(ui_act_setpower)))

//TODO: Put this under a common parent type with heaters to cut down on the copypasta
/// The share of the Carnot COP stock parts achieve; each part tier above the first adds to it (RefreshParts()).
#define FREEZER_CARNOT_FRACTION 0.4
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

	/// The share of the Carnot COP its pump achieves (parts and coolant raise it).
	var/carnot_fraction = FREEZER_CARNOT_FRACTION
	/// Upper bound on its COP.
	var/max_cop = 10
	/// TRUE while it pumps: its heat pump exists exactly while this is set.
	var/pumping = FALSE
	var/internal_volume = 600		// L

	var/max_power_rating = 20000	// Power rating when the usage is turned up to 100
	var/power_setting = 100

	var/set_temperature = T20C		// Thermostat
	var/cooling = 0
	var/reagent_cooling = 0


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

/// Unconnected, connected and idle, or working.
/obj/machinery/atmospherics/unary/freezer/draw(datum/look/look)
	..()
	if(!node) // ALLOW(derived_reads): atmos_init() and disconnect() redraw it when its pipe comes or goes
		look.state("freezer_0")
	else
		look.state((use_power && cooling) ? "freezer_1" : "freezer")

/obj/machinery/atmospherics/unary/freezer/derived()
	. = ..()
	. += drawn_from(nameof(use_power), nameof(cooling))

/obj/machinery/atmospherics/unary/freezer
	silicon_use = SILICON_USE_UI

/obj/machinery/atmospherics/unary/freezer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["powerSetting"] = power_setting
	data["reagentPower"] = reagent_cooling
	var/list/merged_1 = ui_data_obj_machinery_atmospherics_unary_freezer(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/atmospherics/unary/freezer's window data.
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
	set_use_power(!use_power)
	return OP_OK

/obj/machinery/atmospherics/unary/freezer/proc/ui_act_setgastemperature(datum/act/op/A, temp)
	var/mob/user = A.actor
	. = TRUE
	var/amount = temp
	if(amount > 0)
		set_set_temperature(min(amount, 1000))
	else
		set_set_temperature(max(amount, 0))
	heat_entries_refresh(src)
	reconsider()

/obj/machinery/atmospherics/unary/freezer/proc/ui_act_setpower(datum/act/op/A, value)
	var/mob/user = A.actor
	. = TRUE
	var/new_setting = between(0, value, 100)
	set_power_level(new_setting)
	reconsider()

// ---- its work: woken by its gas, its switch and its thermostat; nothing polls ----

/// Its pipe's gas changed (its gas watch): it looks again whether it has work.
/obj/machinery/atmospherics/unary/freezer/proc/gas_changed(list/observation, index)
	reconsider()

/// What it does now: the heat pump (its CAPABILITIES entry) exists while it is switched on and works; it cools while its loop's gas is above the
/// thermostat.
/obj/machinery/atmospherics/unary/freezer/proc/reconsider(datum/act/A)
	var/on = !!(operable() && use_power)
	set_pumping(on)
	set_cooling(on && network && air_contents.total_moles() && air_contents.return_temperature() > set_temperature)
	update_icon()

/// One interval of cooling: coolant and parts set the pump's share of Carnot, it pays its work and uses up coolant (the heat moves in Rust).
/obj/machinery/atmospherics/unary/freezer/proc/service(datum/act/A)
	reagent_cooling = 1 + (reagents.machine_cooling_power(reagents) / reagents.maximum_volume)
	var/coolant_fraction = clamp(FREEZER_CARNOT_FRACTION * get_part_bonus() * CLAMP(reagent_cooling, REAGENT_COOLING_MINMOD, REAGENT_COOLING_MAXMOD), 0.05, 1)
	if(abs(coolant_fraction - carnot_fraction) > 0.01)
		carnot_fraction = coolant_fraction
		heat_entries_refresh(src)
	use_power(-heat_entries_power(src))
	reagents.remove_any(REAGENT_COOLING_CONSUMED)
	reconsider()

/// How much better than stock its parts make the pump (1: stock).
/obj/machinery/atmospherics/unary/freezer/proc/get_part_bonus()
	return max(1, (get_part_rating(/obj/item/stock_parts/manipulator) + get_part_rating(/obj/item/stock_parts/matter_bin)) / 2)

/obj/machinery/atmospherics/unary/freezer/power_change()
	. = ..()
	if(.)
		reconsider()

//upgrading parts
/obj/machinery/atmospherics/unary/freezer/RefreshParts()
	..()
	var/cap_rating = 0
	var/manip_rating = 0
	var/bin_rating = get_part_rating(/obj/item/stock_parts/matter_bin)
	cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)
	manip_rating = get_part_rating(/obj/item/stock_parts/manipulator)

	max_power_rating = initial(max_power_rating) * cap_rating / 2			//more powerful
	carnot_fraction = clamp(FREEZER_CARNOT_FRACTION * max(1, (manip_rating + bin_rating) / 2), 0.05, 1)	//more efficient
	air_contents.set_volume(max(initial(internal_volume) - 200, 0) + 200 * bin_rating)
	set_power_level(power_setting)

/obj/machinery/atmospherics/unary/freezer/proc/set_power_level(new_power_setting)
	power_setting = new_power_setting
	power_rating = max_power_rating * (power_setting/100)
	heat_entries_refresh(src)

/obj/machinery/atmospherics/unary/freezer/examine(mob/user)
	. = ..()
	if(panel_open)
		. += "The maintenance hatch is open."

#undef REAGENT_COOLING_MINMOD
#undef REAGENT_COOLING_MAXMOD
#undef REAGENT_COOLING_CONSUMED
#undef FREEZER_CARNOT_FRACTION
