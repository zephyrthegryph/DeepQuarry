// POWERNET SENSOR
//
// Last Change 31.12.2014 by Atlantis
//
// Powernet sensors are devices which relay information about connected powernet. This information may be relayed
// via two procs. Proc return_reading_text will return fully HTML styled string which contains all information. This
// may be used in PDAs or similar applications. Second proc, return_reading_data will return list containing needed data.
// This is used in NanoUI, for example.

/obj/machinery/power/sensor
	name = "Powernet Sensor"
	desc = "Small machine which transmits data about specific powernet"
	anchored = TRUE
	density = FALSE
	layer = ABOVE_UTILITY
	icon = 'icons/obj/objects.dmi'
	icon_state = "floor_beacon" // If anyone wants to make better sprite, feel free to do so without asking me.

	var/name_tag = "#UNKN#" // ID tag displayed in list of powernet sensors. Each sensor should have it's own tag!
	var/long_range = 0		// If 1, sensor reading will show on all computers, regardless of Zlevel

	var/list/history = list() // ALLOW(instance_list): the sensor's reading history: appended to on every update, always in use
	var/record_size = 60
	var/record_interval = 50
	var/next_record = 0
	var/is_secret_monitor = FALSE

// The sensor samples its network every record_interval (sensor_step()); the power monitors read its history.
CAPABILITIES(/obj/machinery/power/sensor)
	every(PROC_REF(record_delay), then(PROC_REF(sensor_step)))

// Proc: Initialize(mapload)
// Parameters: None
// Description: Automatically assigns name according to ID tag.
/obj/machinery/power/sensor/Initialize(mapload)
	. = ..()
	if(name_tag == "#UNKN#")
		name_tag = "Grid [z]-[x]-[y]"
	auto_set_name()
	history["supply"] = list()
	history["demand"] = list()
	for(var/obj/machinery/computer/power_monitor/PM in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		PM.power_monitor?.refresh_sensors()

// Proc: auto_set_name()
// Parameters: None
// Description: Sets name of this sensor according to the ID tag.
/obj/machinery/power/sensor/proc/auto_set_name()
	name = "[name_tag] - Powernet Sensor"

// Proc: check_grid_warning()
// Parameters: None
// Description: Checks connected powernet for warnings. If warning is found returns 1
/obj/machinery/power/sensor/proc/check_grid_warning()
	connect_to_network()
	if(power_region)
		if(power_problem(power_region))
			return 1
	return 0

/// The time between samples.
/obj/machinery/power/sensor/proc/record_delay(datum/act/A)
	return record_interval

/// One sample of its network's supply and demand, for the power monitors (unwired, it looks for a cable).
/obj/machinery/power/sensor/proc/sensor_step(datum/act/timer/A)
	if(!power_region)
		set_use_power(USE_POWER_IDLE)
		connect_to_network()
	else
		set_use_power(USE_POWER_ACTIVE)
		record()

/// What this monitor shows for the grid's load: the mean of the live ledger value and its last few history samples.
/// The grid keeps no eased copy of its own (power_grid.dm); smoothing what a reading shows is the reader's.
/obj/machinery/power/sensor/proc/shown_load()
	var/total = power_load(power_region)
	var/count = 1
	var/list/demand = history["demand"]
	for(var/i in max(length(demand) - 2, 1) to length(demand))
		total += demand[i]
		count++
	return total / count

// This tracks historical usage, for TGUI power monitors
/obj/machinery/power/sensor/proc/record()
	if(COOLDOWN_FINISHED(src, next_record))
		COOLDOWN_START(src, next_record, record_interval)


		var/list/supply = history["supply"]
		if(power_region)
			supply += power_view_avail(power_region)
		if(supply.len > record_size)
			supply.Cut(1, 2)

		var/list/demand = history["demand"]
		if(power_region)
			demand += power_view_load(power_region)
		if(demand.len > record_size)
			demand.Cut(1, 2)

/// The sensor's reading as the power monitor's window shows it (its focus): the sensor has no window of its own.
/obj/machinery/power/sensor/proc/monitor_data(mob/user)
	var/list/data = list()
	data["name"] = name_tag
	data["stored"] = record_size
	data["history"] = history
	var/list/computed = ui_data_obj_machinery_power_sensor(user, null, null)
	if(islist(computed))
		for(var/key in computed)
			data[key] = computed[key]
	return data

/// /obj/machinery/power/sensor's window data.
/obj/machinery/power/sensor/proc/ui_data_obj_machinery_power_sensor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["interval"] = record_interval / 10
	data["attached"] = !!power_region

	data["areas"] = list()
	if(power_region)
		for(var/obj/machinery/power/terminal/term in power_grid_nodes(power_region))
			if(istype(term.master(), /obj/machinery/power/apc))
				var/obj/machinery/power/apc/A = term.master()
				if(istype(A))
					var/cell_charge
					if(!A.cell)
						cell_charge = 0
					else
						cell_charge = A.cell.percent()
					// This list is sent every TGUI tick and can contain hundreds of
					// APCs. A positional tuple avoids repeating seven JSON field names
					// per row, cutting Power Monitor bridge traffic substantially.
					data["areas"] += list(list(
						A.area.name,
						cell_charge,
						DisplayPower(A.channel_load_total()),
						A.charging,
						A.equipment,
						A.lighting,
						A.environ,
					))

	return data

// Proc: reading_to_text()
// Parameters: 1 (amount - Power in Watts to be converted to W, kW or MW)
// Description: Helper proc that converts reading in Watts to kW or MW (returns string version of amount parameter)
/obj/machinery/power/sensor/proc/reading_to_text(amount = 0)
	var/units = ""
	// 10kW and less - Watts
	if(amount < 10000)
		units = "W"
	// 10MW and less - KiloWatts
	else if(amount < 10000000)
		units = "kW"
		amount = (round(amount/100) / 10)
	// More than 10MW - MegaWatts
	else
		units = "MW"
		amount = (round(amount/10000) / 100)
	if (units == "W")
		return "[amount] W"
	else
		return "~[amount] [units]" //kW and MW are only approximate readings, therefore add "~"

// Proc: find_apcs()
// Parameters: None
// Description: Searches powernet for APCs and returns them in a list.
/obj/machinery/power/sensor/proc/find_apcs()
	if(!power_region)
		return

	var/list/L = list()
	for(var/obj/machinery/power/terminal/term in power_grid_nodes(power_region))
		if(istype(term.master(), /obj/machinery/power/apc))
			var/obj/machinery/power/apc/A = term.master()
			L += A

	return L

// Proc: return_reading_text()
// Parameters: None
// Description: Generates string which contains HTML table with reading data.
/obj/machinery/power/sensor/proc/return_reading_text()
	// No powernet. Try to connect to one first.
	if(!power_region)
		connect_to_network()
	var/out = ""
	if(!power_region) // No grid.
		out = "# SYSTEM ERROR - NO POWERNET #"
		return out

	var/list/L = find_apcs()
	var/total_apc_load = 0
	if(L.len <= 0) 	// No APCs found.
		out = span_bold("No APCs located in connected powernet!")
	else			// APCs found. Create very ugly (but working!) HTML table.

		out += "<table><tr><th>Name<th>EQUIP<th>LIGHT<th>ENVIRON<th>CELL<th>LOAD"

		// These lists are used as replacement for number based APC settings
		var/static/list/S = list("M-OFF","A-OFF","M-ON", "A-ON")
		var/static/list/chg = list("N","C","F")

		// Split to multiple lines to make it more readable
		for(var/obj/machinery/power/apc/A in L)
			out += "<tr><td>\The [A.area]" 															// Add area name
			out += "<td>[S[A.equipment+1]]<td>[S[A.lighting+1]]<td>[S[A.environ+1]]" 				// Show status of channels
			if(A.cell)
				out += "<td>[round(A.cell.percent())]% - [chg[A.charging+1]]"
			else
				out += "<td>NO CELL"
			var/load = A.channel_load_total() // Load.
			total_apc_load += load
			load = reading_to_text(load)
			out += "<td>[load]"

	out += "<br><b>TOTAL AVAILABLE: [reading_to_text(power_avail(power_region))]</b>"
	out += "<br><b>APC LOAD: [reading_to_text(total_apc_load)]</b>"
	out += "<br><b>OTHER LOAD: [reading_to_text(max(power_load(power_region) - total_apc_load, 0))]</b>"
	out += "<br><b>TOTAL GRID LOAD: [reading_to_text(shown_load())] ([power_avail(power_region) ? round((shown_load() / power_avail(power_region)) * 100) : 0]%)</b>"

	if(power_problem(power_region))
		out += "<br><b>WARNING: Abnormal grid activity detected!</b>"
	return out

// Proc: return_reading_data()
// Parameters: None
// Description: Generates list containing all powernet data. Optimised for usage with NanoUI
/obj/machinery/power/sensor/proc/return_reading_data()
	// No powernet. Try to connect to one first.
	if(!power_region)
		connect_to_network()
	var/list/data = list()
	data["name"] = name_tag
	if(!power_region)
		data["error"] = "# SYSTEM ERROR - NO POWERNET #"
		data["alarm"] = 0 // Runtime Prevention
		return data

	var/list/L = find_apcs()
	var/total_apc_load = 0
	var/list/APC_data = list()
	if(L.len > 0)
		// These lists are used as replacement for number based APC settings
		var/static/list/S = list("M-OFF","A-OFF","M-ON", "A-ON")
		var/static/list/chg = list("N","C","F")

		for(var/obj/machinery/power/apc/A in L)
			var/list/APC_entry = list()
			// Channel Statuses
			APC_entry["s_equipment"] = S[A.equipment+1]
			APC_entry["s_lighting"] = S[A.lighting+1]
			APC_entry["s_environment"] = S[A.environ+1]
			// Cell Status
			APC_entry["cell_charge"] = A.cell ? round(A.cell.percent()) : "NO CELL"
			APC_entry["cell_status"] = A.cell ? chg[A.charging+1] : "N"
			// Location
			APC_entry["x"] = A.x
			APC_entry["y"] = A.y
			APC_entry["z"] = A.z
			// Other info
			APC_entry["total_load"] = reading_to_text(A.channel_load_total())
			// Hopefully removes those goddamn \improper s which are screwing up the UI
			var/N = A.area.name
			if(findtext(N, "\improper"))
				N = copytext(N, 3)
			APC_entry["name"] = N
			// Add data into main list of APC data.
			APC_data += list(APC_entry)
			// Add load of this APC to total APC load calculation
			total_apc_load += A.channel_load_total()
	data["apc_data"] = APC_data
	data["total_avail"] = reading_to_text(max(power_avail(power_region), 0))
	data["total_used_apc"] = reading_to_text(max(total_apc_load, 0))
	var/shown = shown_load()
	data["total_used_other"] = reading_to_text(max(shown - total_apc_load, 0))
	data["total_used_all"] = reading_to_text(max(shown, 0))
	// Prevents runtimes when avail is 0 (division by zero)
	if(power_avail(power_region))
		data["load_percentage"] = round((shown / power_avail(power_region)) * 100)
	else
		data["load_percentage"] = 100
	data["alarm"] = power_problem(power_region) ? 1 : 0
	return data

/// Its declared start condition (started_work(starts =)).
/obj/machinery/power/sensor/step_start_condition()
	return TRUE // schedules its history samples
