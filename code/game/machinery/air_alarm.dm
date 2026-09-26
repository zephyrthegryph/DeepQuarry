#define DECLARE_TLV_VALUES var/red_min; var/yel_min; var/yel_max; var/red_max; var/tlv_comparitor;
#define LOAD_TLV_VALUES(x, y) red_min = x[1]; yel_min = x[2]; yel_max = x[3]; red_max = x[4]; tlv_comparitor = y;
#define TEST_TLV_VALUES (((tlv_comparitor > red_max && red_max > 0) || tlv_comparitor < red_min) ? 2 : ((tlv_comparitor > yel_max && yel_max > 0) || tlv_comparitor < yel_min) ? 1 : 0)

#define AALARM_MODE_SCRUBBING	1
#define AALARM_MODE_REPLACEMENT	2 //like scrubbing, but faster.
#define AALARM_MODE_PANIC		3 //constantly sucks all air
#define AALARM_MODE_CYCLE		4 //sucks off all air, then refill and switches to scrubbing
#define AALARM_MODE_FILL		5 //emergency fill
#define AALARM_MODE_OFF			6 //Shuts it all down.

#define AALARM_SCREEN_MAIN		1
#define AALARM_SCREEN_VENT		2
#define AALARM_SCREEN_SCRUB		3
#define AALARM_SCREEN_MODE		4
#define AALARM_SCREEN_SENSORS	5

#define AALARM_REPORT_TIMEOUT 100

#define MAX_TEMPERATURE 90
#define MIN_TEMPERATURE -40

//all air alarms in area are connected via freq 1439
/area
	var/datum/weakref/main_air_alarm // The air alarm currently managing the others in the area, settings changes go to this one and propogate
	// All lazy: most areas have no air alarm or vents.
	var/list/air_vent_names
	var/list/air_scrub_names
	var/list/air_vent_info
	var/list/air_scrub_info
	var/list/air_alarms

/area/proc/elect_main_air_alarm(exclude_self = FALSE)
	// loop through all sensors to update the area's sensor list as well
	main_air_alarm = null
	var/list/checks = list()
	for(var/obj/machinery/alarm/AA in air_alarms)
		if(exclude_self && AA == src)
			continue
		if(!(AA.stat & (NOPOWER|BROKEN)))
			checks += AA
	if(!checks.len)
		return
	main_air_alarm = WEAKREF(pick(checks))
	var/obj/machinery/alarm/new_main = main_air_alarm.resolve()
	for(var/obj/machinery/alarm/AA in checks)
		if(AA == new_main)
			if(AA.polls)
				START_MACHINE_PROCESSING(AA)
			else
				om_changed(AA, CHANGE_MACHINE_SETTINGS)
		else
			AA.invalidate_gas_dependencies()
		AA.update_icon()

/area/proc/main_air_alarm_is_operating()
	var/obj/machinery/alarm/AM = main_air_alarm?.resolve()
	return AM && !(AM.stat & (NOPOWER | BROKEN))



/obj/machinery/alarm

	name = "alarm"
	desc = "Used to control various station atmospheric systems. The light indicates the current air status of the area."
	icon = 'icons/obj/monitors_vr.dmi'
	icon_state = "alarm_0"
	layer = ABOVE_WINDOW_LAYER
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 80
	active_power_usage = 1000 //For heating/cooling rooms. 1000 joules equates to about 1 degree every 2 seconds for a single tile of air.
	power_channel = ENVIRON
	req_one_access = list(ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)
	clicksound = "button"
	clickvol = 30
	blocks_emissive = NONE
	light_power = 0.25
	flags = WALL_ITEM
	var/alarm_id = null
	var/breach_detection = 1 // Whether to use automatic breach detection or not
	var/frequency = PUMPS_FREQ
	//var/skipprocess = 0 //Experimenting
	var/alarm_frequency = ALERT_FREQ
	var/remote_control = 0
	var/rcon_setting = 2
	var/rcon_time = 0
	var/locked = 1
	panel_open = FALSE // If it's been screwdrivered open.
	var/aidisabled = 0
	var/shorted = 0
	polls = FALSE // runs on the OM machine pipeline (machine_pipeline.dm), not SSmachines' process() roster
	circuit = /obj/item/circuitboard/airalarm

	var/mode = AALARM_MODE_SCRUBBING
	var/screen = AALARM_SCREEN_MAIN
	var/area_uid
	var/area/alarm_area

	var/target_temperature = T0C+20
	var/regulating_temperature = 0

	var/datum/radio_frequency/radio_connection

	/// Keys are things like temperature and certain gasses. Values are lists, which contain, in order:
	/// red warning minimum value, yellow warning minimum value, yellow warning maximum value, red warning maximum value
	/// Use code\defines\gases.dm as reference for id/name. Please keep it consistent
	/// Starts as the type's shared default_TLV() table, which is read-only; call own_TLV() before editing.
	var/list/TLV
	/// TRUE once TLV is a private deep copy that this alarm may edit.
	var/TLV_owned = FALSE
	var/static/list/trace_gas = list(GAS_N2O, GAS_VOLATILE_FUEL) //list of other gases that this air alarm is able to detect

	var/danger_level = 0
	var/pressure_dangerlevel = 0

	var/report_danger_level = 1

	var/alarms_hidden = FALSE //If the alarms from this machine are visible on consoles

	var/datum/looping_sound/alarm/decompression_alarm/soundloop // Looping Alarms
	var/atmoswarn = FALSE // Looping Alarms
	var/sleeping_mixture_id
	var/sleeping_mixture_revision = -1
	/// Control-relevant atmospheric state captured when dependency sleeping begins.
	var/sleeping_alarm_signature
	/// Reused scratch output for threshold evaluation. Air alarms are numerous;
	/// allocating a list for every harmless Rust publication dominated wake scans.
	var/list/sleeping_signature_levels
	/// Monotonic revision for correction-aware contract atmosphere telemetry.
	var/contract_atmos_revision = 0

/obj/machinery/alarm/nobreach
	breach_detection = 0

/obj/machinery/alarm/monitor
	report_danger_level = 0
	breach_detection = 0

/obj/machinery/alarm/alarms_hidden
	alarms_hidden = TRUE

/obj/machinery/alarm/angled
	icon = 'icons/obj/wall_machines_angled.dmi'

/obj/machinery/alarm/angled/hidden
	alarms_hidden = TRUE

/obj/machinery/alarm/angled/offset_airalarm()
	pixel_x = (dir & 3) ? 0 : (dir == 4 ? -21 : 21)
	pixel_y = (dir & 3) ? (dir == 1 ? -18 : 20) : 0

/obj/machinery/alarm/Initialize(mapload)
	. = ..()
	update_area()
	set_frequency(frequency)
	if(!pixel_x && !pixel_y)
		offset_airalarm()
	set_wires(new /datum/wires/alarm(src))
	LAZYADD(alarm_area.air_alarms, src)
	if(!alarm_area.main_air_alarm_is_operating()) // select main alarm
		alarm_area.elect_main_air_alarm()
	set_initial_TLV()
	soundloop = new(list(src), FALSE)

/obj/machinery/alarm/Destroy()
	SSmachines.wake_gas_subscriber(WEAKREF(src))
	unregister_radio(src, frequency)
	qdel(wires)
	wires = null
	LAZYREMOVE(alarm_area.air_alarms, src)
	if(alarm_area.main_air_alarm?.resolve() == src)
		alarm_area.elect_main_air_alarm(TRUE)
	alarm_area = null
	QDEL_NULL(soundloop) // Looping Alarms
	. = ..()

/obj/machinery/alarm/proc/offset_airalarm()
	pixel_x = (dir & 3) ? 0 : (dir == 4 ? -26 : 26)
	pixel_y = (dir & 3) ? (dir == 1 ? -26 : 26) : 0

/obj/machinery/alarm/proc/set_initial_TLV()
	invalidate_gas_dependencies()
	TLV = default_TLV()
	TLV_owned = FALSE
	update_icon()

/// The shared, read-only threshold table for this alarm type. Subtypes override
/// this with their own proc-local static table built from a copy of the parent's.
/obj/machinery/alarm/proc/default_TLV()
	var/static/list/table
	if(!table)
		table = list()
		// breathable air according to human/Life()
		table[GAS_O2] =			list(16, 19, 135, 140) // Partial pressure, kpa
		table[GAS_N2] =			list(0, 0, 135, 140) // Partial pressure, kpa
		table[GAS_CO2] =		list(-1.0, -1.0, 5, 10) // Partial pressure, kpa
		table[GAS_PHORON] =		list(-1.0, -1.0, 0, 0.5) // Partial pressure, kpa
		table[GAS_CH4] =		list(-1.0, -1.0, 0, 0.5) // Partial pressure, kpa
		table["other"] =		list(-1.0, -1.0, 0.5, 1.0) // Partial pressure, kpa
		table["pressure"] =		list(ONE_ATMOSPHERE * 0.80, ONE_ATMOSPHERE * 0.90, ONE_ATMOSPHERE * 1.10, ONE_ATMOSPHERE * 1.20) /* kpa */
		table["temperature"] =	list(T0C - 26, T0C, T0C + 40, T0C + 66) // K
	return table

/proc/copy_air_alarm_TLV(list/table)
	var/list/copy = list()
	for(var/key in table)
		var/list/row = table[key]
		copy[key] = row.Copy()
	return copy

/// Copy-on-write: give this alarm a private TLV table before editing it.
/obj/machinery/alarm/proc/own_TLV()
	if(TLV_owned)
		return
	TLV = copy_air_alarm_TLV(TLV)
	TLV_owned = TRUE

/obj/machinery/alarm/proc/update_area()
	invalidate_gas_dependencies()
	alarm_area = get_area(src)
	area_uid = "\ref[alarm_area]"
	if(name == "alarm")
		name = "[alarm_area.name] Air Alarm \[[rand(9999)]\]" // random number id to help with players locating alarms, cosmetic

/obj/machinery/alarm/proc/scan_atmo()
	var/turf/simulated/location = src.loc
	if(!istype(location))	return//returns if loc is not simulated

	var/datum/gas_mixture/environment = location.return_air()

	//Handle temperature adjustment here.
	handle_heating_cooling(environment)

	var/old_level = danger_level
	var/old_pressurelevel = pressure_dangerlevel
	danger_level = overall_danger_level(environment)

	if(old_level != danger_level)
		apply_danger_level(danger_level)

	if(old_pressurelevel != pressure_dangerlevel)
		if(breach_detected())
			mode = AALARM_MODE_OFF
			apply_mode()

	if(SScontracts && (old_level != danger_level || old_pressurelevel != pressure_dangerlevel))
		contract_atmos_revision++
		var/current_pressure = environment.return_pressure()
		var/current_temperature = environment.return_temperature()
		emit_contract_event(CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, list(
			"department" = DEPARTMENT_ENGINEERING,
			"fact_id" = "atmos-service:[REF(src)]",
			"fact_revision" = contract_atmos_revision,
			"service_id" = REF(src),
			"danger_level" = danger_level,
			"metrics" = list(
				"pressure" = current_pressure,
				"temperature" = current_temperature,
			),
			"detail" = "[alarm_area] atmospheric service reports danger level [danger_level], [round(current_pressure, 0.1)] kPa, and [round(current_temperature, 0.1)] K.",
		), "atmos-service:[REF(src)]:[contract_atmos_revision]", src)
	if(mode == AALARM_MODE_CYCLE && environment.return_pressure() < ONE_ATMOSPHERE * 0.05)
		mode = AALARM_MODE_FILL
		apply_mode()

	if(alarm_area?.atmosalm || danger_level > 0)  // Looping Alarms (Trigger Decompression alarm here, on detection of any breach in the area)
		soundloop.start()
		atmoswarn = TRUE
	else if(danger_level == 0 && alarm_area?.atmosalm == 0)  // Looping Alarms (Cancel Decompression alarm here)
		soundloop.stop()
		atmoswarn = FALSE

	//atmos computer remote controll stuff
	switch(rcon_setting)
		if(RCON_NO)
			remote_control = 0
		if(RCON_AUTO)
			if(danger_level == 2)
				remote_control = 1
			else
				remote_control = 0
		if(RCON_YES)
			remote_control = 1

// Machine pipeline (code/game/machinery/machine_pipeline.dm, "air alarms" section): `polls =
// FALSE` (declared with the other vars below) moves this off SSmachines' process() roster onto
// the OM machine pipeline. The scan/regulate/election logic that used to live in process() is
// unchanged, just relocated to /datum/om/stage/machine/power/alarm/perform().

/obj/machinery/alarm/proc/register_gas_dependencies(datum/weakref/WR)
	var/datum/gas_mixture/environment = return_air()
	var/new_mixture_id = environment?.arena_id()
	if(sleeping_mixture_id != new_mixture_id)
		SSmachines.unsubscribe_gas_dependency(sleeping_mixture_id, WR)
		sleeping_mixture_id = new_mixture_id
	// Hibernation is also the idempotent repair path after a wake. The mixture
	// may be unchanged while the scheduler-side subscription was removed, so
	// always ensure the registration exists.
	SSmachines.subscribe_gas_dependency(sleeping_mixture_id, WR)
	sleeping_mixture_revision = environment ? environment.revision() : -1
	sleeping_alarm_signature = environment ? atmospheric_control_signature(environment) : null

/obj/machinery/alarm/proc/unregister_gas_dependencies(datum/weakref/WR)
	SSmachines.unsubscribe_gas_dependency(sleeping_mixture_id, WR)
	sleeping_mixture_id = null
	sleeping_mixture_revision = -1
	sleeping_alarm_signature = null

/obj/machinery/alarm/gas_dependency_changed(mixture_id, change_mask, list/observation, observation_index)
	if(!(change_mask & GAS_DEPENDENCY_ALL) || mixture_id != sleeping_mixture_id)
		return FALSE
	// Composition is only actionable when it crosses one of the alarm's TLV
	// bands. The Rust observation below contains every gas this controller can
	// display, so unconditional composition wakes merely turned harmless room-air
	// diffusion into six full alarm scans per Machines fire.
	if(observation && observation_index)
		var/current_revision = observation[observation_index + 2]
		if(current_revision == sleeping_mixture_revision)
			return FALSE
		var/current_signature = atmospheric_control_signature_observation(observation, observation_index)
		if(current_signature != sleeping_alarm_signature)
			return TRUE
		sleeping_mixture_revision = current_revision
		return FALSE
	var/datum/gas_mixture/environment = return_air()
	if(!environment || environment.arena_id() != sleeping_mixture_id)
		return TRUE
	var/current_revision = environment.revision()
	if(current_revision == sleeping_mixture_revision)
		return FALSE
	var/current_signature = atmospheric_control_signature(environment)
	if(current_signature != sleeping_alarm_signature)
		return TRUE
	// Harmless diffusion changed the mixture without crossing a gameplay or
	// control threshold. Advance the captured revision and remain asleep.
	sleeping_mixture_revision = current_revision
	return FALSE

/obj/machinery/alarm/proc/atmospheric_control_signature(datum/gas_mixture/environment)
	LAZYINITLIST(sleeping_signature_levels)
	var/current_danger = overall_danger_level(environment, sleeping_signature_levels, FALSE)
	var/current_pressure = sleeping_signature_levels["raw_pressure"]
	var/temperature_action = 0
	if(current_pressure >= 1)
		var/current_temperature = sleeping_signature_levels["raw_temperature"]
		if(abs(current_temperature - target_temperature) > 2.0)
			temperature_action = current_temperature > target_temperature ? 1 : 2
	var/cycle_ready = mode == AALARM_MODE_CYCLE && current_pressure < ONE_ATMOSPHERE * 0.05
	// Four tiny enums fit losslessly in one number. This avoids constructing and
	// comparing a temporary string on every dirty-gas notification.
	return current_danger | (sleeping_signature_levels["pressure"] << 2) | (temperature_action << 4) | (cycle_ready << 6)

/// Evaluate the same TLVs as overall_danger_level() from the atomic Rust
/// observation attached to a dirty publication. No gas datum lookup or FFI call
/// occurs in this path.
/obj/machinery/alarm/proc/atmospheric_control_signature_observation(list/observation, observation_index)
	var/environment_pressure = observation[observation_index + 3]
	var/environment_temperature = observation[observation_index + 4]
	var/environment_volume = observation[observation_index + 5]
	var/partial_pressure = environment_volume > 0 ? R_IDEAL_GAS_EQUATION * environment_temperature / environment_volume : 0
	DECLARE_TLV_VALUES
	LOAD_TLV_VALUES(TLV["pressure"], environment_pressure)
	var/calculated_pressure_level = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV[GAS_O2], observation[observation_index + 6] * partial_pressure)
	var/oxygen_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV[GAS_CO2], observation[observation_index + 7] * partial_pressure)
	var/co2_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV[GAS_PHORON], observation[observation_index + 8] * partial_pressure)
	var/phoron_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV[GAS_CH4], observation[observation_index + 9] * partial_pressure)
	var/methane_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV["temperature"], environment_temperature)
	var/temperature_dangerlevel = TEST_TLV_VALUES
	var/other_moles = observation[observation_index + 10] + observation[observation_index + 11]
	LOAD_TLV_VALUES(TLV["other"], other_moles * partial_pressure)
	var/other_dangerlevel = TEST_TLV_VALUES
	var/current_danger = max(calculated_pressure_level, oxygen_dangerlevel, co2_dangerlevel, phoron_dangerlevel, methane_dangerlevel, temperature_dangerlevel, other_dangerlevel)
	var/temperature_action = 0
	if(environment_pressure >= 1 && abs(environment_temperature - target_temperature) > 2.0)
		temperature_action = environment_temperature > target_temperature ? 1 : 2
	var/cycle_ready = mode == AALARM_MODE_CYCLE && environment_pressure < ONE_ATMOSPHERE * 0.05
	return current_danger | (calculated_pressure_level << 2) | (temperature_action << 4) | (cycle_ready << 6)

/obj/machinery/alarm/proc/invalidate_gas_dependencies()
	SSmachines.wake_gas_subscriber(WEAKREF(src))

/obj/machinery/alarm/update_use_power(new_use_power)
	if(use_power == new_use_power)
		return
	invalidate_gas_dependencies()
	return ..()

/obj/machinery/alarm/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	invalidate_gas_dependencies()

/obj/machinery/alarm/proc/handle_heating_cooling(datum/gas_mixture/environment)
	DECLARE_TLV_VALUES
	LOAD_TLV_VALUES(TLV["temperature"], target_temperature)
	if(!regulating_temperature)
		//check for when we should start adjusting temperature
		if(!TEST_TLV_VALUES && abs(environment.return_temperature() - target_temperature) > 2.0 && environment.return_pressure() >= 1)
			update_use_power(USE_POWER_ACTIVE)
			regulating_temperature = (environment.return_temperature() > target_temperature ? 1 : 2)
			audible_message("\The [src] clicks as it starts [regulating_temperature == 1 ? "cooling" : "heating"] the room.",\
			"You hear a click and a faint electronic hum.", runemessage = "* click *")
			playsound(src, 'sound/machines/click.ogg', 50, 1)
	else
		//check for when we should stop adjusting temperature
		if(TEST_TLV_VALUES || abs(environment.return_temperature() - target_temperature) <= 0.5 || environment.return_pressure() < 1)
			update_use_power(USE_POWER_IDLE)
			audible_message("\The [src] clicks quietly as it stops [regulating_temperature == 1 ? "cooling" : "heating"] the room.",\
			"You hear a click as a faint electronic humming stops.", runemessage = "* click *")
			regulating_temperature = 0
			playsound(src, 'sound/machines/click.ogg', 50, 1)

	if(regulating_temperature)
		if(target_temperature > T0C + MAX_TEMPERATURE)
			target_temperature = T0C + MAX_TEMPERATURE

		if(target_temperature < T0C + MIN_TEMPERATURE)
			target_temperature = T0C + MIN_TEMPERATURE

		var/datum/gas_mixture/gas
		gas = environment.remove(0.25 * environment.total_moles())
		if(gas)

			if(gas.return_temperature() <= target_temperature)	//gas heating
				var/energy_used = min(gas.get_thermal_energy_change(target_temperature) , active_power_usage)

				gas.add_thermal_energy(energy_used)
				//use_power(energy_used, ENVIRON) //handle by update_use_power instead
			else	//gas cooling
				var/heat_transfer = min(abs(gas.get_thermal_energy_change(target_temperature)), active_power_usage)

				//Assume the heat is being pumped into the hull which is fixed at 20 C
				//none of this is really proper thermodynamics but whatever

				var/cop = gas.return_temperature() / T20C	//coefficient of performance -> power used = heat_transfer/cop

				heat_transfer = min(heat_transfer, cop * active_power_usage)	//this ensures that we don't use more than active_power_usage amount of power

				heat_transfer = -gas.add_thermal_energy(-heat_transfer)	//get the actual heat transfer

				//use_power(heat_transfer / cop, ENVIRON)	//handle by update_use_power instead

			environment.merge(gas)

/obj/machinery/alarm/proc/overall_danger_level(datum/gas_mixture/environment, list/calculated_levels, update_pressure_level = TRUE)
	var/environment_temperature = environment.return_temperature()
	var/partial_pressure = R_IDEAL_GAS_EQUATION * environment_temperature/environment.return_volume()
	var/environment_pressure = environment.return_pressure()

	var/other_moles = 0
	for(var/g in trace_gas)
		other_moles += LINDA_GAS_AMT(environment, g) //this is only going to be used in a partial pressure calc, so we don't need to worry about group_multiplier here.

	DECLARE_TLV_VALUES
	LOAD_TLV_VALUES(TLV["pressure"], environment_pressure)
	var/calculated_pressure_level = TEST_TLV_VALUES
	if(update_pressure_level)
		pressure_dangerlevel = calculated_pressure_level // not local because it's used in process()
	LOAD_TLV_VALUES(TLV[GAS_O2], LINDA_GAS_AMT(environment, GAS_O2)*partial_pressure)
	var/oxygen_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV[GAS_CO2], LINDA_GAS_AMT(environment, GAS_CO2)*partial_pressure)
	var/co2_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV[GAS_PHORON], LINDA_GAS_AMT(environment, GAS_PHORON)*partial_pressure)
	var/phoron_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV[GAS_CH4], LINDA_GAS_AMT(environment, GAS_CH4)*partial_pressure)
	var/methane_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV["temperature"], environment_temperature)
	var/temperature_dangerlevel = TEST_TLV_VALUES
	LOAD_TLV_VALUES(TLV["other"], other_moles*partial_pressure)
	var/other_dangerlevel = TEST_TLV_VALUES

	var/calculated_danger_level = max(
		calculated_pressure_level,
		oxygen_dangerlevel,
		co2_dangerlevel,
		phoron_dangerlevel,
		methane_dangerlevel,
		other_dangerlevel,
		temperature_dangerlevel
		)
	if(calculated_levels)
		calculated_levels["pressure"] = calculated_pressure_level
		calculated_levels["raw_pressure"] = environment_pressure
		calculated_levels["raw_temperature"] = environment_temperature
	return calculated_danger_level

// Returns whether this air alarm thinks there is a breach, given the sensors that are available to it.
/obj/machinery/alarm/proc/breach_detected()
	var/turf/simulated/location = src.loc

	if(!istype(location))
		return 0

	if(breach_detection	== 0)
		return 0

	var/datum/gas_mixture/environment = location.return_air()
	var/environment_pressure = environment.return_pressure()
	var/pressure_levels = TLV["pressure"]

	if(environment_pressure <= pressure_levels[1])		//low pressures
		if(!(mode == AALARM_MODE_PANIC || mode == AALARM_MODE_CYCLE))
			return 1

	return 0

/obj/machinery/alarm/update_icon()
	// start actual update!
	cut_overlays()

	if(panel_open)
		icon_state = "alarmx"
		set_light(0)
		set_light_on(FALSE)
		return
	if(!alarm_area || (stat & (NOPOWER|BROKEN)) || shorted)
		icon_state = "alarmp"
		set_light(0)
		set_light_on(FALSE)
		return

	// sub light!
	var/obj/machinery/alarm/MA = alarm_area.main_air_alarm?.resolve()
	if(MA == src)
		// I am the main alarm
		add_overlay(mutable_appearance(icon, "alarm_Mmode"))
		add_overlay(emissive_appearance(icon, "alarm_Mmode"))
	if(!MA || MA.shorted)
		// main alarm is out! don't show display!
		icon_state = "alarmp"
		add_overlay(mutable_appearance(icon, "alarm_Xmode"))
		add_overlay(emissive_appearance(icon, "alarm_Xmode"))
		set_light(0)
		set_light_on(FALSE)
		return
	// passive light on
	add_overlay(mutable_appearance(icon, "alarm_Pmode"))
	add_overlay(emissive_appearance(icon, "alarm_Pmode"))

	var/icon_level = danger_level
	if(alarm_area.atmosalm)
		icon_level = max(icon_level, 1)	//if there's an atmos alarm but everything is okay locally, no need to go past yellow

	var/new_color = null
	switch(icon_level)
		if(0)
			icon_state = "alarm_0"
			if(alarm_area.main_air_alarm?.resolve() == src)
				// active controller
				add_overlay(mutable_appearance(icon, "alarm_ov0"))
				add_overlay(emissive_appearance(icon, "alarm_ov0"))
				new_color = "#03A728"
			else
				// passive mode
				add_overlay(mutable_appearance(icon, "alarm_ovP"))
				add_overlay(emissive_appearance(icon, "alarm_ovP"))
				new_color = "#0033FF"
		if(1)
			icon_state = "alarm_2" //yes, alarm2 is yellow alarm
			add_overlay(mutable_appearance(icon, "alarm_ov2"))
			add_overlay(emissive_appearance(icon, "alarm_ov2"))
			new_color = "#EC8B2F"
		if(2)
			icon_state = "alarm_1"
			add_overlay(mutable_appearance(icon, "alarm_ov1"))
			add_overlay(emissive_appearance(icon, "alarm_ov1"))
			new_color = "#DA0205"

	set_light(l_range = 2, l_power = 0.25, l_color = new_color)
	set_light_on(TRUE)

/obj/machinery/alarm/receive_signal(datum/signal/signal)
	if(stat & (NOPOWER|BROKEN))
		return
	if(!signal || signal.encryption)
		return
	var/id_tag = signal.data["tag"]
	if(!id_tag)
		return
	if(signal.data["area"] != area_uid)
		return
	if(signal.data["sigtype"] != "status")
		return

	var/dev_type = signal.data["device"]
	if(!(id_tag in alarm_area.air_scrub_names) && !(id_tag in alarm_area.air_vent_names))
		register_env_machine(id_tag, dev_type)
	if(dev_type == "AScr")
		LAZYSET(alarm_area.air_scrub_info, id_tag, signal.data)
	else if(dev_type == "AVP")
		LAZYSET(alarm_area.air_vent_info, id_tag, signal.data)

/obj/machinery/alarm/proc/register_env_machine(m_id, device_type)
	var/new_name
	if(device_type == "AVP")
		new_name = "[alarm_area.name] Vent Pump #[length(alarm_area.air_vent_names)+1]"
		LAZYSET(alarm_area.air_vent_names, m_id, new_name)
	else if(device_type == "AScr")
		new_name = "[alarm_area.name] Air Scrubber #[length(alarm_area.air_scrub_names)+1]"
		LAZYSET(alarm_area.air_scrub_names, m_id, new_name)
	else
		return
	addtimer(CALLBACK(src, PROC_REF(send_signal),m_id, list("init" = new_name)), 10, TIMER_DELETE_ME)

/obj/machinery/alarm/proc/refresh_all()
	for(var/id_tag in alarm_area.air_vent_names)
		var/list/I = LAZYACCESS(alarm_area.air_vent_info, id_tag)
		if(I && I["timestamp"] + AALARM_REPORT_TIMEOUT / 2 > world.time)
			continue
		send_signal(id_tag, list("status"))
	for(var/id_tag in alarm_area.air_scrub_names)
		var/list/I = LAZYACCESS(alarm_area.air_scrub_info, id_tag)
		if(I && I["timestamp"] + AALARM_REPORT_TIMEOUT / 2 > world.time)
			continue
		send_signal(id_tag, list("status"))

/obj/machinery/alarm/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, AIRALARM_AREA_FILTER(RADIO_TO_AIRALARM, area_uid))

/obj/machinery/alarm/proc/send_signal(target, list/command)//sends signal 'command' to 'target'. Returns 0 if no radio connection, 1 otherwise
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.source = src

	signal.data = command
	signal.data["tag"] = target
	signal.data["sigtype"] = "command"

	radio_connection.post_signal(src, signal, AIRALARM_AREA_FILTER(RADIO_FROM_AIRALARM, area_uid))
//			to_world("Signal [command] Broadcasted to [target]")

	return 1

/obj/machinery/alarm/proc/apply_mode()
	for(var/obj/machinery/alarm/AA in alarm_area.air_alarms)
		AA.mode = mode //propagate mode to other air alarms in the area

	switch(mode)
		if(AALARM_MODE_SCRUBBING)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list("power"= 1, "co2_scrub"= 1, "scrubbing"= 1, "panic_siphon"= 0))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list("power"= 1, "checks"= "default", "set_external_pressure"= "default"))

		if(AALARM_MODE_PANIC, AALARM_MODE_CYCLE)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list("power"= 1, "panic_siphon"= 1))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list("power"= 0))

		if(AALARM_MODE_REPLACEMENT)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list("power"= 1, "panic_siphon"= 1))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list("power"= 1, "checks"= "default", "set_external_pressure"= "default"))

		if(AALARM_MODE_FILL)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list("power"= 0))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list("power"= 1, "checks"= "default", "set_external_pressure"= "default"))

		if(AALARM_MODE_OFF)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list("power"= 0))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list("power"= 0))

/obj/machinery/alarm/proc/apply_danger_level(new_danger_level)
	if(report_danger_level && alarm_area.atmosalert(new_danger_level, src))
		post_alert(new_danger_level)
	for(var/obj/machinery/alarm/AA in alarm_area.air_alarms)
		AA.update_icon()

/obj/machinery/alarm/proc/post_alert(alert_level)
	var/datum/radio_frequency/frequency = SSradio.return_frequency(alarm_frequency)
	if(!frequency)
		return

	var/datum/signal/alert_signal = new
	alert_signal.source = src
	alert_signal.transmission_method = TRANSMISSION_RADIO
	alert_signal.data["zone"] = alarm_area.name
	alert_signal.data["type"] = "Atmospheric"

	if(alert_level==2)
		alert_signal.data["alert"] = "severe"
	else if(alert_level==1)
		alert_signal.data["alert"] = "minor"
	else if(alert_level==0)
		alert_signal.data["alert"] = "clear"

	frequency.post_signal(src, alert_signal)

/obj/machinery/alarm
	silicon_use = SILICON_USE_UI

/obj/machinery/alarm/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/alarm_unlock,
		/datum/interaction/machine_alt/alarm_toggle_lock,
		/datum/interaction/machine_hand/interact,
	)
	..()

/// Any item used on the alarm invalidates gas dependencies and adds a fingerprint;
/// an ID card or PDA also toggles the lock. Always falls through afterward (the
/// old attackby's trailing `return ..()`), so the resolver moves on to whatever
/// the parent type offers (part replacement, deconstruction, etc).
/datum/interaction/machine_item/alarm_unlock
	id = "alarm_unlock"
	name = "Swipe ID"
	category = INTERACTION_CAT_LOCK
	held_type = /obj/item
	consumes_input = FALSE
	effect = /obj/machinery/alarm/proc/interaction_swipe

/obj/machinery/alarm/proc/interaction_swipe(mob/user, obj/item/W, datum/interaction/interaction)
	invalidate_gas_dependencies()
	add_fingerprint(user)
	if(istype(W, /obj/item/card/id) || istype(W, /obj/item/pda))// trying to unlock the interface with an ID card
		togglelock(user)
	return FALSE

/// Alt-click toggles the interface lock.
/datum/interaction/machine_alt/alarm_toggle_lock
	id = "alarm_toggle_lock"
	name = "Toggle lock"
	category = INTERACTION_CAT_LOCK
	consumes_input = FALSE
	effect = /obj/machinery/alarm/proc/interaction_toggle_lock

/obj/machinery/alarm/proc/interaction_toggle_lock(mob/user, obj/item/held, datum/interaction/interaction)
	togglelock(user)
	return TRUE

/obj/machinery/alarm/interact(mob/user)
	tgui_interact(user)
	wires.Interact(user)

/obj/machinery/alarm/tgui_status(mob/user)
	if(isAI(user) && aidisabled)
		to_chat(user, "AI control has been disabled.")
	else if(!shorted)
		return ..()
	return STATUS_CLOSE

/obj/machinery/alarm/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, datum/tgui_state/state)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AirAlarm", name, parent_ui)
		if(state)
			ui.set_state(state)
		ui.open()

/obj/machinery/alarm/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list(
		"locked" = locked,
		"siliconUser" = siliconaccess(user) || (isobserver(user) && is_admin(user)),
		"remoteUser" = !!ui.parent_ui,
		"danger_level" = danger_level,
		"target_temperature" = "[target_temperature - T0C]C",
		"rcon" = rcon_setting,
	)

	var/area/A = get_area(src)
	data["atmos_alarm"] = A?.atmosalm
	data["fire_alarm"] = A?.fire

	var/turf/T = get_turf(src)
	var/datum/gas_mixture/environment = T.return_air()

	var/list/list/environment_data = list()
	data["environment_data"] = environment_data

	DECLARE_TLV_VALUES

	var/pressure = environment.return_pressure()
	LOAD_TLV_VALUES(TLV["pressure"], pressure)
	environment_data.Add(list(list(
		"name" = "Pressure",
		"value" = pressure,
		"unit" = "kPa",
		"danger_level" = TEST_TLV_VALUES
	)))

	var/temperature = environment.return_temperature()
	LOAD_TLV_VALUES(TLV["temperature"], temperature)
	environment_data.Add(list(list(
		"name" = "Temperature",
		"value" = temperature,
		"unit" = "K ([round(temperature - T0C, 0.1)]C)",
		"danger_level" = TEST_TLV_VALUES
	)))

	var/total_moles = environment.total_moles()
	var/partial_pressure = R_IDEAL_GAS_EQUATION * temperature / environment.return_volume()
	for(var/gas_id in environment.gas_ids()) // environment.gas (XGM) → environment.gas_ids()
		if(!(gas_id in TLV))
			continue
		LOAD_TLV_VALUES(TLV[gas_id], LINDA_GAS_AMT(environment, gas_id) * partial_pressure)
		environment_data.Add(list(list(
			"name" = gas_id,
			"value" = LINDA_GAS_AMT(environment, gas_id) / total_moles * 100,
			"unit" = "%",
			"danger_level" = TEST_TLV_VALUES
		)))

	if(!locked || siliconaccess(user) || data["remoteUser"] || (isobserver(user) && is_admin(user)))
		var/list/list/vents = list()
		data["vents"] = vents
		for(var/id_tag in A.air_vent_names)
			var/long_name = A.air_vent_names[id_tag]
			var/list/info = LAZYACCESS(A.air_vent_info, id_tag)
			if(!info)
				continue
			vents.Add(list(list(
				"id_tag"	= id_tag,
				"long_name" = sanitize(long_name),
				"power"		= info["power"],
				"checks"	= info["checks"],
				"excheck"	= info["checks"]&1,
				"incheck"	= info["checks"]&2,
				"direction"	= info["direction"],
				"external"	= info["external"],
				"internal"	= info["internal"],
				"extdefault"= (info["external"] == ONE_ATMOSPHERE),
				"intdefault"= (info["internal"] == 0),
			)))


		var/list/list/scrubbers = list()
		data["scrubbers"] = scrubbers
		for(var/id_tag in alarm_area.air_scrub_names)
			var/long_name = alarm_area.air_scrub_names[id_tag]
			var/list/info = LAZYACCESS(alarm_area.air_scrub_info, id_tag)
			if(!info)
				continue
			scrubbers += list(list(
				"id_tag"	= id_tag,
				"long_name" = sanitize(long_name),
				"power"		= info["power"],
				"scrubbing"	= info["scrubbing"],
				"panic"		= info["panic"],
				"filters"   = list(
					list("name" = GASNAME_O2,			"command" = "o2_scrub",	"val" = info["filter_o2"]),
					list("name" = GASNAME_N2,			"command" = "n2_scrub",	"val" = info["filter_n2"]),
					list("name" = GASNAME_CO2, 			"command" = "co2_scrub", "val" = info["filter_co2"]),
					list("name" = GASNAME_PHORON, 		"command" = "tox_scrub", "val" = info["filter_phoron"]),
					list("name" = GASNAME_CH4, 			"command" = "ch4_scrub", "val" = info["filter_ch4"]),
					list("name" = GASNAME_N2O,			"command" = "n2o_scrub", "val" = info["filter_n2o"]),
					list("name" = GASNAME_VOLATILE_FUEL,"command" = "fuel_scrub", "val" = info["filter_fuel"])
				)
			))
		data["scrubbers"] = scrubbers

		data["mode"] = mode

		var/list/list/modes = list()
		data["modes"] = modes
		modes[++modes.len] = list("name" = "Filtering - Scrubs out contaminants", 			"mode" = AALARM_MODE_SCRUBBING,		"selected" = mode == AALARM_MODE_SCRUBBING, 	"danger" = 0)
		modes[++modes.len] = list("name" = "Replace Air - Siphons out air while replacing", "mode" = AALARM_MODE_REPLACEMENT,	"selected" = mode == AALARM_MODE_REPLACEMENT,	"danger" = 0)
		modes[++modes.len] = list("name" = "Panic - Siphons air out of the room", 			"mode" = AALARM_MODE_PANIC,			"selected" = mode == AALARM_MODE_PANIC, 		"danger" = 1)
		modes[++modes.len] = list("name" = "Cycle - Siphons air before replacing", 			"mode" = AALARM_MODE_CYCLE,			"selected" = mode == AALARM_MODE_CYCLE, 		"danger" = 1)
		modes[++modes.len] = list("name" = "Fill - Shuts off scrubbers and opens vents", 	"mode" = AALARM_MODE_FILL,			"selected" = mode == AALARM_MODE_FILL, 			"danger" = 0)
		modes[++modes.len] = list("name" = "Off - Shuts off vents and scrubbers", 			"mode" = AALARM_MODE_OFF,			"selected" = mode == AALARM_MODE_OFF, 			"danger" = 0)

		var/list/selected
		var/list/thresholds = list()

		var/list/gas_names = list(GAS_O2, GAS_CO2, GAS_PHORON, GAS_CH4, "other")	//Gas ids made to match code\defines\gases.dm
		for(var/g in gas_names)
			thresholds[++thresholds.len] = list("name" = g, "settings" = list())
			selected = TLV[g]
			for(var/i = 1, i <= 4, i++)
				thresholds[thresholds.len]["settings"] += list(list("env" = g, "val" = i, "selected" = selected[i]))

		selected = TLV["pressure"]
		thresholds[++thresholds.len] = list("name" = "Pressure", "settings" = list())
		for(var/i = 1, i <= 4, i++)
			thresholds[thresholds.len]["settings"] += list(list("env" = "pressure", "val" = i, "selected" = selected[i]))

		selected = TLV["temperature"]
		thresholds[++thresholds.len] = list("name" = "Temperature", "settings" = list())
		for(var/i = 1, i <= 4, i++)
			thresholds[thresholds.len]["settings"] += list(list("env" = "temperature", "val" = i, "selected" = selected[i]))

		data["thresholds"] = thresholds
	return data

/obj/machinery/alarm/tgui_act(action, params, datum/tgui/ui, datum/tgui_state/state)
	invalidate_gas_dependencies()
	if(..())
		return TRUE

	if(action == "rcon")
		var/attempted_rcon_setting = text2num(params["rcon"])

		switch(attempted_rcon_setting)
			if(RCON_NO)
				rcon_setting = RCON_NO
			if(RCON_AUTO)
				rcon_setting = RCON_AUTO
			if(RCON_YES)
				rcon_setting = RCON_YES

		for(var/obj/machinery/alarm/AA in alarm_area.air_alarms)
			AA.rcon_setting = rcon_setting
		return TRUE

	if(action == "temperature")
		var/list/selected = TLV["temperature"]
		var/max_temperature = min(selected[3] - T0C, MAX_TEMPERATURE)
		var/min_temperature = max(selected[2] - T0C, MIN_TEMPERATURE)
		var/input_temperature = tgui_input_number(ui.user, "What temperature would you like the system to mantain? (Capped between [min_temperature] and [max_temperature]C)", "Thermostat Controls", target_temperature - T0C, max_temperature, min_temperature, round_value = FALSE)
		if(isnum(input_temperature))
			if(input_temperature > max_temperature || input_temperature < min_temperature)
				to_chat(ui.user, "Temperature must be between [min_temperature]C and [max_temperature]C")
			else
				for(var/obj/machinery/alarm/AA in alarm_area.air_alarms)
					AA.target_temperature = input_temperature + T0C
					AA.invalidate_gas_dependencies()
		return TRUE

	// Account for remote users here.
	// Yes, this is kinda snowflaky; however, I would argue it would be far more snowflakey
	// to include "custom hrefs" and all the other bullshit that nano states have just for the
	// like, two UIs, that want remote access to other UIs.
	if((locked && !(siliconaccess(ui.user) || (isobserver(ui.user) && is_admin(ui.user))) && !istype(state, /datum/tgui_state/air_alarm_remote)) || (issilicon(ui.user) && aidisabled))
		return

	var/device_id = params["id_tag"]
	switch(action)
		if("lock")
			if((siliconaccess(ui.user) && !wires.is_cut(WIRE_IDSCAN)) || (isobserver(ui.user) && is_admin(ui.user)))
				locked = !locked
				. = TRUE
		if( "power",
			"o2_scrub",
			"n2_scrub",
			"co2_scrub",
			"tox_scrub",
			"n2o_scrub",
			"fuel_scrub",
			"ch4_scrub",
			"panic_siphon",
			"scrubbing",
			"direction")
			send_signal(device_id, list("[action]" = text2num(params["val"])), ui.user)
			. = TRUE
		if("excheck")
			send_signal(device_id, list("checks" = text2num(params["val"])^1), ui.user)
			. = TRUE
		if("incheck")
			send_signal(device_id, list("checks" = text2num(params["val"])^2), ui.user)
			. = TRUE
		if("set_external_pressure", "set_internal_pressure")
			var/target = params["value"]
			if(!isnull(target))
				send_signal(device_id, list("[action]" = target), ui.user)
				. = TRUE
		if("reset_external_pressure")
			send_signal(device_id, list("reset_external_pressure"), ui.user)
			. = TRUE
		if("reset_internal_pressure")
			send_signal(device_id, list("reset_internal_pressure"), ui.user)
			. = TRUE
		if("threshold")
			var/env = params["env"]

			var/name = params["var"]
			var/value = tgui_input_number(ui.user, "New [name] for [env]:", name, TLV[env][name], min_value=-1, round_value = FALSE)
			if(!isnull(value) && !..())
				own_TLV()
				if(value < 0)
					TLV[env][name] = -1
				else
					TLV[env][name] = round(value, 0.01)
				clamp_tlv_values(env, name)
				// investigate_log(" treshold value for [env]:[name] was set to [value] by [key_name(ui.user)]",INVESTIGATE_ATMOS)
				for(var/obj/machinery/alarm/AA in alarm_area.air_alarms)
					AA.own_TLV()
					AA.TLV[env][name] = TLV[env][name]
					AA.invalidate_gas_dependencies()
				. = TRUE
		if("mode")
			mode = text2num(params["mode"])
			// investigate_log("was turned to [get_mode_name(mode)] mode by [key_name(ui.user)]",INVESTIGATE_ATMOS)
			apply_mode(ui.user)
			. = TRUE
		if("alarm")
			if(alarm_area.atmosalert(2, src))
				apply_danger_level(2)
			. = TRUE
		if("reset")
			atmos_reset()
			. = TRUE
	for(var/obj/machinery/alarm/AA in alarm_area.air_alarms)
		AA.update_icon()

// This big ol' mess just ensures that TLV always makes sense. If you set the max value below the min value,
// it'll automatically update all the other values to keep it sane.
/obj/machinery/alarm/proc/clamp_tlv_values(env, changed_threshold)
	own_TLV()
	var/list/selected = TLV[env]
	switch(changed_threshold)
		if(1)
			if(selected[1] > selected[2])
				selected[2] = selected[1]
			if(selected[1] > selected[3])
				selected[3] = selected[1]
			if(selected[1] > selected[4])
				selected[4] = selected[1]
		if(2)
			if(selected[1] > selected[2])
				selected[1] = selected[2]
			if(selected[2] > selected[3])
				selected[3] = selected[2]
			if(selected[2] > selected[4])
				selected[4] = selected[2]
		if(3)
			if(selected[1] > selected[3])
				selected[1] = selected[3]
			if(selected[2] > selected[3])
				selected[2] = selected[3]
			if(selected[3] > selected[4])
				selected[4] = selected[3]
		if(4)
			if(selected[1] > selected[4])
				selected[1] = selected[4]
			if(selected[2] > selected[4])
				selected[2] = selected[4]
			if(selected[3] > selected[4])
				selected[3] = selected[4]




/obj/machinery/alarm/proc/atmos_reset()
	if(alarm_area.atmosalert(0, src))
		apply_danger_level(0)
	for(var/obj/machinery/alarm/AA in alarm_area.air_alarms)
		AA.update_icon()

/obj/machinery/alarm/screwdriver_act(mob/user, obj/item/tool)
	invalidate_gas_dependencies()
	add_fingerprint(user)
	playsound(src, tool.usesound, 50, TRUE)
	panel_open = !panel_open
	to_chat(user, "The wires have been [panel_open ? "exposed" : "unexposed"]")
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/alarm/wirecutter_act(mob/user, obj/item/tool)
	invalidate_gas_dependencies()
	add_fingerprint(user)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	user.visible_message(span_warning("[user] has cut the wires inside \the [src]!"), "You have cut the wires inside \the [src].")
	playsound(src, tool.usesound, 50, TRUE)
	new /obj/item/stack/cable_coil(get_turf(src), 5)
	return dismantle() ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING

/obj/machinery/alarm/proc/togglelock(mob/user)
	if(stat & (NOPOWER|BROKEN))
		to_chat(user, "It does nothing.")
		return
	else
		if(allowed(user) && !wires.is_cut(WIRE_IDSCAN))
			locked = !locked
			to_chat(user, span_notice("You [locked ? "lock" : "unlock"] the Air Alarm interface."))
		else
			to_chat(user, span_warning("Access denied."))
		return

/obj/machinery/alarm/power_change()
	invalidate_gas_dependencies()
	..()
	var/delay_time = rand(0,15)
	if(delay_time)
		addtimer(CALLBACK(src, PROC_REF(process_power_change)), delay_time, TIMER_DELETE_ME)
		return
	process_power_change()

/obj/machinery/alarm/proc/process_power_change()
	update_icon()
	if(!soundloop)
		return
	if(stat & (NOPOWER | BROKEN))
		soundloop.stop()
	else if(atmoswarn)
		soundloop.start()

/obj/machinery/alarm/server/Initialize(mapload)
	. = ..()
	req_access = list(ACCESS_RD, ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)
	target_temperature = 90

/obj/machinery/alarm/server/default_TLV()
	var/static/list/table
	if(!table)
		table = copy_air_alarm_TLV(..())
		table[GAS_O2] =			list(-1.0, -1.0,-1.0,-1.0) // Partial pressure, kpa
		table[GAS_CO2] =		list(-1.0, -1.0,   5,  10) // Partial pressure, kpa
		table[GAS_PHORON] =		list(-1.0, -1.0, 0, 0.5) // Partial pressure, kpa
		table[GAS_CH4] =		list(-1.0, -1.0, 0, 0.5) // Partial pressure, kpa
		table["other"] =		list(-1.0, -1.0, 0.5, 1.0) // Partial pressure, kpa
		table["pressure"] =		list(0,ONE_ATMOSPHERE*0.10,ONE_ATMOSPHERE*1.40,ONE_ATMOSPHERE*1.60) /* kpa */
		table["temperature"] =	list(20, 40, 140, 160) // K
	return table

/obj/machinery/alarm/freezer
	target_temperature = T0C - 13.15 // Chilly freezer room

/obj/machinery/alarm/freezer/default_TLV()
	var/static/list/table
	if(!table)
		table = copy_air_alarm_TLV(..())
		table["temperature"] =	list(T0C - 40, T0C - 20, T0C + 40, T0C + 66) // K, lower temperature for freezer air alarms
	return table

/obj/machinery/alarm/sifwilderness
	breach_detection = 0
	report_danger_level = 0

/obj/machinery/alarm/sifwilderness/default_TLV()
	var/static/list/table
	if(!table)
		table = copy_air_alarm_TLV(..())
		table["oxygen"] =		list(16, 17, 135, 140)
		table["pressure"] =		list(0,ONE_ATMOSPHERE*0.10,ONE_ATMOSPHERE*1.50,ONE_ATMOSPHERE*1.60)
		table["temperature"] =	list(T0C - 40, T0C - 31, T0C + 40, T0C + 120)
	return table

#undef LOAD_TLV_VALUES
#undef TEST_TLV_VALUES
#undef DECLARE_TLV_VALUES

#undef AALARM_MODE_SCRUBBING
#undef AALARM_MODE_REPLACEMENT
#undef AALARM_MODE_PANIC
#undef AALARM_MODE_CYCLE
#undef AALARM_MODE_FILL
#undef AALARM_MODE_OFF

#undef AALARM_SCREEN_MAIN
#undef AALARM_SCREEN_VENT
#undef AALARM_SCREEN_SCRUB
#undef AALARM_SCREEN_MODE
#undef AALARM_SCREEN_SENSORS

#undef AALARM_REPORT_TIMEOUT

#undef MAX_TEMPERATURE
#undef MIN_TEMPERATURE
