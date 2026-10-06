// The air alarm: the wall panel that watches a room's air and drives the room's vents and scrubbers over the radio.
//
// What it is, in its CAPABILITIES block: its maintenance panel and the five wires behind it, its ID lock, its window and the buttons in it, its
// room scan (an every() that runs only while the alarm is the area's working main alarm and has something to do: the room's air changed across one
// of its bands, or its thermostat is working) and the gas watch that wakes it. Its own code is the scan, the thermostat (a declared heat
// pump), the radio to the devices, the area's alarm and the look.
//
// The area keeps its alarms (a link: alarm_area <-> /area::air_alarms) and elects one main alarm; the devices it drives are area air devices
// (code/domains/atmos/area_air_device.dm). The remote atmospherics console works an alarm through its own panel (/datum/air_alarm_remote), whose
// window forwards to the alarm's buttons and vouches for whoever the console lets in.

#define AALARM_REPORT_TIMEOUT 100

#define MAX_TEMPERATURE 90
#define MIN_TEMPERATURE -40

MSG_DEF_SELF(alarm/unresponsive, "It does not respond.")
MSG_DEF_SELF(alarm/ai_disabled, "AI control has been disabled.")
MSG_DEF_SELF(alarm/remote_denied, "The console does not let you work this alarm.")
MSG_DEF_SELF(alarm/silicons_only, "Only a silicon can do that.")
MSG_DEF_SELF(alarm/no_such_threshold, "The alarm has no such threshold.")
MSG_DEF(alarm/cut_out, "You have cut the wires inside %T%.", "%U% has cut the wires inside %T%!")

/area
	var/obj/machinery/alarm/main_air_alarm // The air alarm currently managing the others in the area, settings changes go to this one and propogate
	/// The area's air alarms (the other end of each alarm's alarm_area link). Lazy: most areas have none. The devices they drive are the area's too
	/// (code/domains/atmos/area_air_device.dm).
	var/list/air_alarms

/// Elects a working alarm of the area its main one (the one that scans the room and drives its devices), and tells every alarm what it shows.
/area/proc/elect_main_air_alarm(obj/machinery/alarm/exclude)
	var/list/checks = list()
	for(var/obj/machinery/alarm/AA as anything in air_alarms)
		if(AA != exclude && AA.operable())
			checks += AA
	rel_set(src, nameof(main_air_alarm), length(checks) ? pick(checks) : null)
	air_alarms_refresh()

/area/proc/main_air_alarm_is_operating()
	var/obj/machinery/alarm/AM = main_air_alarm
	return AM && AM.operable()

/// Every alarm of the area takes what it shows of the area: whether it is the main one, whether the main one is down, the area's alarm level.
/area/proc/air_alarms_refresh()
	var/obj/machinery/alarm/main = main_air_alarm
	var/main_down = !main || main.shorted
	for(var/obj/machinery/alarm/AA as anything in air_alarms)
		AA.set_is_main(AA == main)
		AA.set_main_down(main_down)
		AA.set_area_alert(atmosalm)

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
	active_power_usage = 1000 //For heating/cooling rooms: the thermostat's rated energy per service interval.
	power_channel = ENVIRON
	req_one_access = list(ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)
	clicksound = SFX_BUTTON
	clickvol = 30
	blocks_emissive = NONE
	light_power = 0.25
	flags = WALL_ITEM
	circuit = /obj/item/circuitboard/airalarm
	mode = AALARM_MODE_SCRUBBING

	var/alarm_id = null
	var/breach_detection = 1 // Whether to use automatic breach detection or not
	var/frequency = PUMPS_FREQ
	var/alarm_frequency = ALERT_FREQ
	/// Remote control from the atmospherics console: RCON_NO, RCON_AUTO (in an emergency) or RCON_YES.
	var/rcon_setting = RCON_AUTO
	/// The ID lock is engaged when the alarm is made (a map clears it for the alarms it leaves open).
	var/lock_at_start = TRUE

	/// The area it serves (the other end of /area::air_alarms).
	var/tmp/area/alarm_area
	var/area_uid
	var/target_temperature = T0C+20
	var/datum/radio_frequency/radio_connection

	/// Its thresholds: env ("pressure", "temperature", a gas id, "other") -> list(red min, yellow min, yellow max, red max). Its own copy of its type's
	/// default_TLV(), made when it initializes; the area's alarms are kept in step by the threshold button.
	var/list/TLV
	var/static/list/trace_gas = list(GAS_N2O, GAS_VOLATILE_FUEL) //list of other gases that this air alarm is able to detect

	var/danger_level = 0
	var/pressure_dangerlevel = 0
	var/report_danger_level = 1
	var/alarms_hidden = FALSE //If the alarms from this machine are visible on consoles

	var/datum/looping_sound/alarm/decompression_alarm/soundloop // Looping Alarms
	var/atmoswarn = FALSE // Looping Alarms
	/// The thermostat's direction while it works (HEAT_PUMP_HEAT or HEAT_PUMP_COOL): its heat pump's mode.
	var/thermostat_mode = HEAT_PUMP_HEAT
	/// The thermostat pump's electrical rating, W (its old 1000 J per service interval).
	var/thermostat_watts = 500
	/// What the thermostat is doing: GAS_HEATER_IDLE, _COOLING or _HEATING.
	var/regulating_temperature = GAS_HEATER_IDLE
	/// What the alarm last announced of it (the click when it starts or stops).
	var/announced_regulating = GAS_HEATER_IDLE

	/// It is the area's main alarm (the area's election says).
	var/is_main = FALSE
	/// The area has no working main alarm (none, or it is shorted): the display is dark.
	var/main_down = FALSE
	/// The area's atmospherics alarm level, as it shows it.
	var/area_alert = 0
	/// Its room scan runs (every MACHINE_SERVICE_INTERVAL): set when the room changed across a band, while the thermostat works, and on every change of
	/// its own settings; the scan clears it when there is nothing left to do.
	var/scanning = TRUE
	/// The bands the last scan found the room in (room_signature()): a gas change that does not move them wakes nothing.
	var/last_signature
	/// Monotonic revision for correction-aware contract atmosphere telemetry.
	var/contract_atmos_revision = 0

/// The AI control wire locks the AI out: cut, until mended; pulsed, for ten seconds (ai_control()).
STAT(/obj/machinery/alarm, aidisabled, ANY)
/// The power wire shorts the alarm: cut, until mended; pulsed, for twenty minutes (power_wires()).
STAT(/obj/machinery/alarm, shorted, ANY)

TRACKED(/obj/machinery/alarm, danger_level)
TRACKED(/obj/machinery/alarm, regulating_temperature)
TRACKED(/obj/machinery/alarm, is_main)
TRACKED(/obj/machinery/alarm, main_down)
TRACKED(/obj/machinery/alarm, area_alert)
TRACKED(/obj/machinery/alarm, scanning)
TRACKED(/obj/machinery/alarm, target_temperature)
TRACKED(/obj/machinery/alarm, rcon_setting)
TRACKED(/obj/machinery/alarm, thermostat_mode)

CAPABILITIES(/obj/machinery/alarm)
	links(/area::air_alarms, /obj/machinery/alarm::alarm_area, a_many = TRUE)
	owns_one(nameof(soundloop), /datum/looping_sound/alarm/decompression_alarm)
	// The thermostat: a heat pump on the room's air toward the target while it works, heating resistively and cooling into the station's
	// heat-rejection loop at no better than one joule per joule (the old rate both ways).
	when(nameof(regulating_temperature), heat_pump(HEAT_AIR, HEAT_AMBIENT, nameof(thermostat_watts), nameof(target_temperature), nameof(thermostat_mode), TRUE, 0.5, 1, reads = list("target_temperature", "thermostat_mode")))
	panel()
	wires(name = "Air alarm", count = 5, tools = FALSE, by_hand = TRUE, status_lines = PROC_REF(wire_lights))
	power_wires(stat = STAT_SHORTED, pulse_lasts = 20 MINUTES, shock = 50)
	ai_control(stat = STAT_AIDISABLED, pulse_lasts = 10 SECONDS)
	lock(starts_locked = nameof(lock_at_start), powered = FALSE, guarded = FALSE, wire = WIRE_IDSCAN)
	extend(CAP_LOCK, needs(req(PROC_REF(alarm_works), because = MSG(machine/inoperable))))
	on_notice(/datum/notice/wire_cut, then(PROC_REF(wire_was_cut)))
	on_wire(WIRE_SYPHON, cut = PROC_REF(syphon_wire_cut), pulse = PROC_REF(syphon_wire_pulsed))
	on_wire(WIRE_AALARM, cut = PROC_REF(alarm_wire_cut), pulse = PROC_REF(alarm_wire_pulsed))
	op("cut_out", tool(TOOL_WIRECUTTER), label("Cut out"), at(SPACE_PANEL), wait(0), says(MSG(alarm/cut_out)), then(PROC_REF(cut_out)))
	click_order(BIND_HAND, "wires.open", "ui_open")
	gas_watch(changed = PROC_REF(room_changed))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(scan_room)), when = nameof(scanning))
	on_change(STAT_SHORTED, ANY, then(PROC_REF(shorted_changed)))
	on_change(nameof(stat), ANY, then(PROC_REF(power_changed)))
	on_change(nameof(regulating_temperature), ANY, then(PROC_REF(thermostat_changed)))
	on_change(nameof(is_main), ENTER, then(PROC_REF(became_main)))

	/// The alarm's window and the buttons in it. The lock gates every button but the remote setting and the thermostat; a shorted alarm, or one
	/// whose AI control is cut (to a silicon), or a remote console that does not let the actor in, answers none.
	section(controls, "The alarm's window and the buttons in it")
	interface("AirAlarm")
	op("rcon", ui_act("rcon", arg("rcon", enum(list(RCON_NO, RCON_AUTO, RCON_YES)))), then(PROC_REF(ui_set_rcon)))
	op("temperature", ui_act("temperature"), asks(/datum/prompt/number, fields = list(
			"title" = "Thermostat Controls",
			"question" = computed(PROC_REF(thermostat_question)),
			"default" = computed(PROC_REF(thermostat_default)),
			"min_value" = computed(PROC_REF(thermostat_min)),
			"max_value" = computed(PROC_REF(thermostat_max)))),
		then(PROC_REF(thermostat_answered)))
	op("lock", ui_act("lock"), needs(req(PROC_REF(works_lock_by_window), because = MSG(alarm/silicons_only)), req_wire(WIRE_IDSCAN)), toggles(LOCK_LOCKED))
	alarm_device_setting_ops()
	op("set_external_pressure", ui_act("set_external_pressure", arg("id_tag", schema_text(64)), arg("value", num())), then(PROC_REF(ui_set_pressure)))
	op("set_internal_pressure", ui_act("set_internal_pressure", arg("id_tag", schema_text(64)), arg("value", num())), then(PROC_REF(ui_set_pressure)))
	op("reset_external_pressure", ui_act("reset_external_pressure", arg("id_tag", schema_text(64))), then(PROC_REF(ui_reset_pressure)))
	op("reset_internal_pressure", ui_act("reset_internal_pressure", arg("id_tag", schema_text(64))), then(PROC_REF(ui_reset_pressure)))
	op("threshold", ui_act("threshold", arg("env", schema_text(64)), arg("var", int(1, 4))), needs(req(PROC_REF(threshold_known), because = MSG(alarm/no_such_threshold))),
		asks(/datum/prompt/number, fields = list(
			"title" = computed(PROC_REF(threshold_title)),
			"question" = computed(PROC_REF(threshold_question)),
			"default" = computed(PROC_REF(threshold_default)),
			"min_value" = -1)),
		then(PROC_REF(threshold_answered)))
	op("mode", ui_act("mode", arg("mode", int(AALARM_MODE_SCRUBBING, AALARM_MODE_OFF))), then(PROC_REF(ui_set_mode)))
	op("alarm", ui_act("alarm"), then(PROC_REF(ui_raise_alarm)))
	op("reset", ui_act("reset"), then(PROC_REF(ui_reset_alarm)))
	extend(TAG_UI, needs(req(PROC_REF(controls_reachable), because = PROC_REF(controls_unreachable_reason))))
	extend("ui_open", needs(req(PROC_REF(controls_reachable), because = PROC_REF(controls_unreachable_reason))))
	extend("rcon", drop = "lock")
	extend("temperature", drop = "lock")

/// The switches of the area's devices in the window: one button each, all sent to the device named by id_tag.
/proc/alarm_device_setting_ops()
	. = list()
	for(var/action in list("power", "o2_scrub", "n2_scrub", "co2_scrub", "tox_scrub", "n2o_scrub", "fuel_scrub", "ch4_scrub", "panic_siphon", "scrubbing", "direction", "excheck", "incheck"))
		. += op(action, ui_act(action, arg("id_tag", schema_text(64)), arg("val", num())), then(TYPE_PROC_REF(/obj/machinery/alarm, ui_device_setting)))

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

/obj/machinery/alarm/server
	req_access = list(ACCESS_RD, ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)
	target_temperature = 90

/obj/machinery/alarm/server/default_TLV()
	. = ..()
	.[GAS_O2] =			list(-1.0, -1.0,-1.0,-1.0) // Partial pressure, kpa
	.[GAS_CO2] =		list(-1.0, -1.0,   5,  10) // Partial pressure, kpa
	.[GAS_PHORON] =		list(-1.0, -1.0, 0, 0.5) // Partial pressure, kpa
	.[GAS_CH4] =		list(-1.0, -1.0, 0, 0.5) // Partial pressure, kpa
	.["other"] =		list(-1.0, -1.0, 0.5, 1.0) // Partial pressure, kpa
	.["pressure"] =		list(0,ONE_ATMOSPHERE*0.10,ONE_ATMOSPHERE*1.40,ONE_ATMOSPHERE*1.60) /* kpa */
	.["temperature"] =	list(20, 40, 140, 160) // K

/obj/machinery/alarm/freezer
	target_temperature = T0C - 13.15 // Chilly freezer room

/obj/machinery/alarm/freezer/default_TLV()
	. = ..()
	.["temperature"] =	list(T0C - 40, T0C - 20, T0C + 40, T0C + 66) // K, lower temperature for freezer air alarms

/obj/machinery/alarm/sifwilderness
	breach_detection = 0
	report_danger_level = 0

/obj/machinery/alarm/sifwilderness/default_TLV()
	. = ..()
	.[GAS_O2] =			list(16, 17, 135, 140)
	.["pressure"] =		list(0,ONE_ATMOSPHERE*0.10,ONE_ATMOSPHERE*1.50,ONE_ATMOSPHERE*1.60)
	.["temperature"] =	list(T0C - 40, T0C - 31, T0C + 40, T0C + 120)

/obj/machinery/alarm/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(alarm_area), get_area(src)) // paired: the area's air_alarms lists it
	area_uid = alarm_area?.air_uid()
	if(name == "alarm")
		name = "[alarm_area?.name] Air Alarm \[[rand(9999)]\]" // random number id to help with players locating alarms, cosmetic
	set_frequency(frequency)
	if(!pixel_x && !pixel_y)
		offset_airalarm()
	TLV = default_TLV()
	rel_set(src, nameof(soundloop), new /datum/looping_sound/alarm/decompression_alarm(list(src), FALSE))
	if(!alarm_area?.main_air_alarm_is_operating()) // select main alarm
		alarm_area?.elect_main_air_alarm()
	else
		alarm_area.air_alarms_refresh()

/// It goes: its area elects another main alarm.
/obj/machinery/alarm/on_destroy(force)
	var/area/served = alarm_area
	if(served)
		rel_set(src, nameof(alarm_area), null) // paired: the area no longer lists it
		if(served.main_air_alarm == src)
			served.elect_main_air_alarm(src)
	..()

/obj/machinery/alarm/proc/offset_airalarm()
	pixel_x = (dir & 3) ? 0 : (dir == 4 ? -26 : 26)
	pixel_y = (dir & 3) ? (dir == 1 ? -26 : 26) : 0

/// The thresholds a new alarm of this type starts with (a fresh table: each alarm keeps its own). Subtypes edit their parent's.
/obj/machinery/alarm/proc/default_TLV()
	. = list()
	// breathable air according to human/Life()
	.[GAS_O2] =			list(16, 19, 135, 140) // Partial pressure, kpa
	.[GAS_N2] =			list(0, 0, 135, 140) // Partial pressure, kpa
	.[GAS_CO2] =		list(-1.0, -1.0, 5, 10) // Partial pressure, kpa
	.[GAS_PHORON] =		list(-1.0, -1.0, 0, 0.5) // Partial pressure, kpa
	.[GAS_CH4] =		list(-1.0, -1.0, 0, 0.5) // Partial pressure, kpa
	.["other"] =		list(-1.0, -1.0, 0.5, 1.0) // Partial pressure, kpa
	.["pressure"] =		list(ONE_ATMOSPHERE * 0.80, ONE_ATMOSPHERE * 0.90, ONE_ATMOSPHERE * 1.10, ONE_ATMOSPHERE * 1.20) /* kpa */
	.["temperature"] =	list(T0C - 26, T0C, T0C + 40, T0C + 66) // K

/// How far outside its band `env` (a TLV key) the reading `value` is: 0 safe, 1 yellow, 2 red. A negative bound is off. The one band test.
/obj/machinery/alarm/proc/tlv_level(env, value)
	var/list/band = TLV[env]
	if(!band)
		return 0
	if((value > band[4] && band[4] > 0) || value < band[1])
		return 2
	if((value > band[3] && band[3] > 0) || value < band[2])
		return 1
	return 0

/// The area's alarm (a location).
/obj/machinery/alarm/proc/alarm_area_ref() as /area
	return alarm_area

/// The radio connection (a relation view).
/obj/machinery/alarm/proc/radio_connection() as /datum/radio_frequency
	return radio_connection

// ---- the room ----

/// The bands the room's air is in, as one number: the overall danger, the pressure's danger, what the thermostat would do and whether a cycle is
/// ready to fill. Two readings in the same bands are the same number. `partials` is gas id -> kPa.
/obj/machinery/alarm/proc/room_signature(pressure, temperature, list/partials)
	var/danger = room_danger(pressure, temperature, partials)
	var/temperature_action = 0
	if(pressure >= 1 && abs(temperature - target_temperature) > 2)
		temperature_action = temperature > target_temperature ? 1 : 2
	var/cycle_ready = mode == AALARM_MODE_CYCLE && pressure < ONE_ATMOSPHERE * 0.05
	return danger | (tlv_level("pressure", pressure) << 2) | (temperature_action << 4) | (cycle_ready << 6)

/// The worst band of the room's readings.
/obj/machinery/alarm/proc/room_danger(pressure, temperature, list/partials)
	. = max(tlv_level("pressure", pressure), tlv_level("temperature", temperature))
	for(var/gas in list(GAS_O2, GAS_CO2, GAS_PHORON, GAS_CH4))
		. = max(., tlv_level(gas, partials[gas]))
	var/other = 0
	for(var/gas in trace_gas)
		other += partials[gas]
	. = max(., tlv_level("other", other))

/// The partial pressures (kPa) the bands read, from a sample.
/obj/machinery/alarm/proc/sample_partials(datum/gas_sample/S)
	. = list()
	for(var/gas in list(GAS_O2, GAS_CO2, GAS_PHORON, GAS_CH4) + trace_gas)
		.[gas] = S.partial_pressure(gas)

/// The room's air changed (its gas watch): a main alarm wakes its scan when the change crossed one of its bands. Read from the change's own
/// record, so a harmless drift costs no read of the air.
/obj/machinery/alarm/proc/room_changed(list/observation, index)
	if(!is_main || scanning)
		return
	if(observed_signature(observation, index) != last_signature)
		set_scanning(TRUE)

/// room_signature() of the air a gas watch's observation record describes.
/obj/machinery/alarm/proc/observed_signature(list/observation, index)
	var/pressure = GAS_OBSERVED(observation, index, GAS_OBS_PRESSURE)
	var/temperature = GAS_OBSERVED(observation, index, GAS_OBS_TEMPERATURE)
	var/volume = GAS_OBSERVED(observation, index, GAS_OBS_VOLUME)
	var/per_mole = volume > 0 ? R_IDEAL_GAS_EQUATION * temperature / volume : 0
	var/list/partials = list(
		GAS_O2 = GAS_OBSERVED(observation, index, GAS_OBS_OXYGEN) * per_mole,
		GAS_CO2 = GAS_OBSERVED(observation, index, GAS_OBS_CARBON_DIOXIDE) * per_mole,
		GAS_PHORON = GAS_OBSERVED(observation, index, GAS_OBS_PLASMA) * per_mole,
		GAS_CH4 = GAS_OBSERVED(observation, index, GAS_OBS_METHANE) * per_mole,
		GAS_N2O = GAS_OBSERVED(observation, index, GAS_OBS_NITROUS_OXIDE) * per_mole,
		GAS_VOLATILE_FUEL = GAS_OBSERVED(observation, index, GAS_OBS_VOLATILE_FUEL) * per_mole)
	return room_signature(pressure, temperature, partials)

/// Something the scan reads changed (a setting, the power, the election): the next interval scans.
/obj/machinery/alarm/proc/rescan()
	last_signature = null
	set_scanning(TRUE)

/// It works the room: the area's working main alarm, on a turf.
/obj/machinery/alarm/proc/controls_room()
	return is_main && operable() && !shorted && !main_down && isturf(loc)

/// One scan of the room (every MACHINE_SERVICE_INTERVAL while `scanning`): the thermostat, the danger level and the area's alarm, breach detection,
/// the cycle's fill and the looping alarm. It stops once there is nothing left to do.
/obj/machinery/alarm/proc/scan_room(datum/act/A)
	if(!controls_room())
		set_scanning(FALSE)
		return
	var/datum/gas_mixture/environment = loc.return_air()
	var/datum/gas_sample/S = gas_sample(environment)
	var/list/partials = sample_partials(S)

	if(target_temperature > T0C + MAX_TEMPERATURE)
		set_target_temperature(T0C + MAX_TEMPERATURE)
	if(target_temperature < T0C + MIN_TEMPERATURE)
		set_target_temperature(T0C + MIN_TEMPERATURE)
	var/state = thermostat_state(S, !tlv_level("temperature", target_temperature))
	if(state != GAS_HEATER_IDLE)
		set_thermostat_mode(state == GAS_HEATER_COOLING ? HEAT_PUMP_COOL : HEAT_PUMP_HEAT)
	set_regulating_temperature(state)

	var/old_level = danger_level
	var/old_pressurelevel = pressure_dangerlevel
	set_danger_level(room_danger(S.pressure, S.temperature, partials))
	pressure_dangerlevel = tlv_level("pressure", S.pressure)
	if(old_level != danger_level)
		apply_danger_level(danger_level)
	if(old_pressurelevel != pressure_dangerlevel && breach_detected(S.pressure))
		set_mode(AALARM_MODE_OFF)
		apply_mode()
	if(SScontracts && (old_level != danger_level || old_pressurelevel != pressure_dangerlevel))
		contract_atmos_revision++
		emit_contract_event(CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, list(
			"department" = DEPARTMENT_ENGINEERING,
			"fact_id" = "atmos-service:[REF(src)]",
			"fact_revision" = contract_atmos_revision,
			"service_id" = REF(src),
			"danger_level" = danger_level,
			"metrics" = list(
				"pressure" = S.pressure,
				"temperature" = S.temperature,
			),
			"detail" = "[alarm_area] atmospheric service reports danger level [danger_level], [round(S.pressure, 0.1)] kPa, and [round(S.temperature, 0.1)] K.",
		), "atmos-service:[REF(src)]:[contract_atmos_revision]", src)
	if(mode == AALARM_MODE_CYCLE && S.pressure < ONE_ATMOSPHERE * 0.05)
		set_mode(AALARM_MODE_FILL)
		apply_mode()
	update_soundloop()
	last_signature = room_signature(S.pressure, S.temperature, partials)
	set_scanning(state != GAS_HEATER_IDLE)

/// What the thermostat does now: it starts once the air is 2 K off the target, stops within half a kelvin of it, and never works a near vacuum
/// or an unsafe target (`allowed`). Its heat pump (CAPABILITIES) moves the heat.
/obj/machinery/alarm/proc/thermostat_state(datum/gas_sample/S, allowed)
	var/gap = target_temperature - S.temperature
	if(regulating_temperature == GAS_HEATER_IDLE)
		if(allowed && abs(gap) > 2 && S.pressure >= 1)
			return gap < 0 ? GAS_HEATER_COOLING : GAS_HEATER_HEATING
		return GAS_HEATER_IDLE
	if(!allowed || abs(gap) <= 0.5 || S.pressure < 1)
		return GAS_HEATER_IDLE
	return gap < 0 ? GAS_HEATER_COOLING : GAS_HEATER_HEATING

/// The looping alarm sounds while the room or the area is in danger and the alarm works.
/obj/machinery/alarm/proc/update_soundloop()
	atmoswarn = danger_level > 0 || alarm_area?.atmosalm
	if(operable() && atmoswarn)
		soundloop.start()
	else
		soundloop.stop()

/// The thermostat starts or stops: it draws its power and clicks.
/obj/machinery/alarm/proc/thermostat_changed(datum/act/A)
	var/old_state = announced_regulating
	announced_regulating = regulating_temperature
	if(old_state == regulating_temperature)
		return
	var/working = regulating_temperature != GAS_HEATER_IDLE
	set_use_power(working ? USE_POWER_ACTIVE : USE_POWER_IDLE)
	var/doing = (working ? regulating_temperature : old_state) == GAS_HEATER_COOLING ? "cooling" : "heating"
	if(working)
		audible_message("\The [src] clicks as it starts [doing] the room.", "You hear a click and a faint electronic hum.", runemessage = "* click *")
	else
		audible_message("\The [src] clicks quietly as it stops [doing] the room.", "You hear a click as a faint electronic humming stops.", runemessage = "* click *")
	play_sfx(src, SFX_MACHINES_CLICK)

/// Whether this alarm thinks the room is breached: the pressure fell into the red, and nothing here is siphoning on purpose.
/obj/machinery/alarm/proc/breach_detected(pressure)
	if(!breach_detection)
		return FALSE
	var/list/band = TLV["pressure"]
	return pressure <= band[1] && !(mode == AALARM_MODE_PANIC || mode == AALARM_MODE_CYCLE)

// ---- what it shows ----

/obj/machinery/alarm/draw(datum/look/look)
	..()
	if(panel_open(src))
		look.state("alarmx")
		return
	if(!alarm_area || !operable() || shorted)
		look.state("alarmp")
		return
	if(is_main)
		look.glow("alarm_Mmode")
	if(main_down)
		look.state("alarmp")
		look.glow("alarm_Xmode")
		return
	look.glow("alarm_Pmode")
	var/icon_level = danger_level
	if(area_alert)
		icon_level = max(icon_level, 1) //if there's an atmos alarm but everything is okay locally, no need to go past yellow
	switch(icon_level)
		if(0)
			look.state("alarm_0")
			look.glow(is_main ? "alarm_ov0" : "alarm_ovP")
			look.light(2, 0.25, is_main ? "#03A728" : "#0033FF")
		if(1)
			look.state("alarm_2") //yes, alarm2 is yellow alarm
			look.glow("alarm_ov2")
			look.light(2, 0.25, "#EC8B2F")
		if(2)
			look.state("alarm_1")
			look.glow("alarm_ov1")
			look.light(2, 0.25, "#DA0205")

/// Its power or condition changed: the area may need another main alarm, its scan its first look, its loop its silence.
/obj/machinery/alarm/proc/power_changed(datum/act/A)
	if(!alarm_area)
		return
	if(!alarm_area.main_air_alarm_is_operating())
		alarm_area.elect_main_air_alarm()
	rescan()
	update_soundloop()

/// The power wires shorted the alarm or gave it back: the area's alarms show it.
/obj/machinery/alarm/proc/shorted_changed(datum/act/A)
	alarm_area?.air_alarms_refresh()
	rescan()

/// Elected the area's main alarm: it scans the room.
/obj/machinery/alarm/proc/became_main(datum/act/A)
	rescan()

// ---- the radio ----

/obj/machinery/alarm/receive_signal(datum/signal/signal)
	if(!operable())
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
	if(dev_type != AREA_AIR_VENT && dev_type != AREA_AIR_SCRUBBER)
		return
	alarm_area.air_device_register(dev_type, id_tag) // the area names it (a device registers itself; one from elsewhere joins here)
	alarm_area.air_device_report(dev_type, id_tag, signal.data)

/// Asks the devices whose status is stale for a fresh one.
/obj/machinery/alarm/proc/refresh_all()
	for(var/kind in list(AREA_AIR_VENT, AREA_AIR_SCRUBBER))
		var/list/info = alarm_area.air_device_info(kind)
		for(var/id_tag in alarm_area.air_device_names(kind))
			var/list/I = LAZYACCESS(info, id_tag)
			if(I && ELAPSED_SINCE(src, I["timestamp"], CLOCK_WORLD) < AALARM_REPORT_TIMEOUT / 2)
				continue
			send_signal(id_tag, list("status" = TRUE))

/obj/machinery/alarm/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, AIRALARM_AREA_FILTER(RADIO_TO_AIRALARM, area_uid)))

/// Sends `command` to the device tagged `target`. FALSE with no radio.
/obj/machinery/alarm/proc/send_signal(target, list/command)
	if(!radio_connection())
		return FALSE
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(signal.source), src)
	signal.data = command
	signal.data["tag"] = target
	signal.data["sigtype"] = "command"
	radio_connection().post_signal(src, signal, AIRALARM_AREA_FILTER(RADIO_FROM_AIRALARM, area_uid))
	return TRUE

/// Every alarm of the area takes this one's mode, and the area's devices are commanded for it.
/obj/machinery/alarm/proc/apply_mode()
	for(var/obj/machinery/alarm/AA as anything in alarm_area.air_alarms)
		AA.set_mode(mode)
	var/list/scrubbers = alarm_area.air_device_names(AREA_AIR_SCRUBBER)
	var/list/vents = alarm_area.air_device_names(AREA_AIR_VENT)
	switch(mode)
		if(AALARM_MODE_SCRUBBING)
			for(var/device_id in scrubbers)
				send_signal(device_id, list("power" = 1, "co2_scrub" = 1, "scrubbing" = 1, "panic_siphon" = 0))
			for(var/device_id in vents)
				send_signal(device_id, list("power" = 1, "checks" = "default", "set_external_pressure" = "default"))
		if(AALARM_MODE_PANIC, AALARM_MODE_CYCLE)
			for(var/device_id in scrubbers)
				send_signal(device_id, list("power" = 1, "panic_siphon" = 1))
			for(var/device_id in vents)
				send_signal(device_id, list("power" = 0))
		if(AALARM_MODE_REPLACEMENT)
			for(var/device_id in scrubbers)
				send_signal(device_id, list("power" = 1, "panic_siphon" = 1))
			for(var/device_id in vents)
				send_signal(device_id, list("power" = 1, "checks" = "default", "set_external_pressure" = "default"))
		if(AALARM_MODE_FILL)
			for(var/device_id in scrubbers)
				send_signal(device_id, list("power" = 0))
			for(var/device_id in vents)
				send_signal(device_id, list("power" = 1, "checks" = "default", "set_external_pressure" = "default"))
		if(AALARM_MODE_OFF)
			for(var/device_id in scrubbers)
				send_signal(device_id, list("power" = 0))
			for(var/device_id in vents)
				send_signal(device_id, list("power" = 0))

/// The room's danger changed: the area's alarm follows (unless this alarm only monitors).
/obj/machinery/alarm/proc/apply_danger_level(new_danger_level)
	if(report_danger_level && alarm_area.atmosalert(new_danger_level, src))
		post_alert(new_danger_level)

/obj/machinery/alarm/proc/post_alert(alert_level)
	var/datum/radio_frequency/frequency = SSradio.return_frequency(alarm_frequency)
	if(!frequency)
		return
	var/datum/signal/alert_signal = new
	rel_set(alert_signal, nameof(alert_signal.source), src)
	alert_signal.transmission_method = TRANSMISSION_RADIO
	alert_signal.data["zone"] = alarm_area.name
	alert_signal.data["type"] = "Atmospheric"
	if(alert_level == 2)
		alert_signal.data["alert"] = "severe"
	else if(alert_level == 1)
		alert_signal.data["alert"] = "minor"
	else if(alert_level == 0)
		alert_signal.data["alert"] = "clear"
	frequency.post_signal(src, alert_signal)

/obj/machinery/alarm/proc/atmos_reset()
	if(alarm_area.atmosalert(0, src))
		apply_danger_level(0)

// ---- the window ----

/// It works: not broken, powered.
/obj/machinery/alarm/proc/alarm_works(datum/act/A)
	return operable()

/// The window's buttons answer: the alarm is not shorted, a silicon's AI control is not cut, and a remote console lets the actor in.
/obj/machinery/alarm/proc/controls_reachable(datum/act/op/A)
	return isnull(controls_unreachable_reason(A))

/obj/machinery/alarm/proc/controls_unreachable_reason(datum/act/op/A)
	if(shorted)
		return /datum/msg/alarm/unresponsive
	if(aidisabled && (A.authority & AUTH_REMOTE_ACCESS))
		return /datum/msg/alarm/ai_disabled
	var/datum/air_alarm_remote/panel = A.window_forwarder()
	if(istype(panel) && !panel.allows(A))
		return /datum/msg/alarm/remote_denied
	return null

/// The window's lock button is a silicon's (over a link the alarm lets in) or an admin ghost's.
/obj/machinery/alarm/proc/works_lock_by_window(datum/act/op/A)
	var/mob/user = A.actor
	if(remote_link_allowed(A))
		return TRUE
	var/mob/observer/dead/ghost = user
	return istype(ghost) && ghost.can_admin_interact()

/obj/machinery/alarm/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/remote = istype(A.holder, /datum/air_alarm_remote)
	var/list/data = list(
		"locked" = lock_locked(src),
		"siliconUser" = !!(user?.remote_link_allows(src) || (isobserver(user) && is_admin(user))),
		"remoteUser" = remote,
		"danger_level" = danger_level,
		"target_temperature" = "[target_temperature - T0C]C",
		"rcon" = rcon_setting,
		"atmos_alarm" = alarm_area?.atmosalm,
		"fire_alarm" = alarm_area?.fire,
	)
	var/list/list/environment_data = list()
	data["environment_data"] = environment_data
	var/turf/T = get_turf(src)
	var/datum/gas_sample/S = gas_sample(T?.return_air())
	environment_data.Add(list(list("name" = "Pressure", "value" = S.pressure, "unit" = "kPa", "danger_level" = tlv_level("pressure", S.pressure))))
	environment_data.Add(list(list("name" = "Temperature", "value" = S.temperature, "unit" = "K ([round(S.temperature - T0C, 0.1)]C)", "danger_level" = tlv_level("temperature", S.temperature))))
	for(var/gas_id in S.gas_ids())
		if(!(gas_id in TLV))
			continue
		environment_data.Add(list(list("name" = gas_id, "value" = S.share(gas_id) * 100, "unit" = "%", "danger_level" = tlv_level(gas_id, S.partial_pressure(gas_id)))))

	if(lock_locked(src) && !data["siliconUser"] && !remote)
		return data
	var/list/list/vents = list()
	data["vents"] = vents
	var/list/vent_info = alarm_area?.air_device_info(AREA_AIR_VENT)
	for(var/id_tag in alarm_area?.air_device_names(AREA_AIR_VENT))
		var/list/info = LAZYACCESS(vent_info, id_tag)
		if(!info)
			continue
		vents.Add(list(list(
			"id_tag"	= id_tag,
			"long_name" = sanitize(alarm_area.air_vent_names[id_tag]),
			"power"		= info["power"],
			"checks"	= info["checks"],
			"excheck"	= info["checks"] & VENT_CHECK_EXTERNAL,
			"incheck"	= info["checks"] & VENT_CHECK_INTERNAL,
			"direction"	= info["direction"],
			"external"	= info["external"],
			"internal"	= info["internal"],
			"extdefault"= (info["external"] == ONE_ATMOSPHERE),
			"intdefault"= (info["internal"] == 0),
		)))
	var/list/list/scrubbers = list()
	data["scrubbers"] = scrubbers
	var/list/scrub_info = alarm_area?.air_device_info(AREA_AIR_SCRUBBER)
	for(var/id_tag in alarm_area?.air_device_names(AREA_AIR_SCRUBBER))
		var/list/info = LAZYACCESS(scrub_info, id_tag)
		if(!info)
			continue
		scrubbers += list(list(
			"id_tag"	= id_tag,
			"long_name" = sanitize(alarm_area.air_scrub_names[id_tag]),
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
	data["mode"] = mode
	var/list/list/modes = list()
	data["modes"] = modes
	modes[++modes.len] = list("name" = "Filtering - Scrubs out contaminants", 			"mode" = AALARM_MODE_SCRUBBING,		"selected" = mode == AALARM_MODE_SCRUBBING, 	"danger" = 0)
	modes[++modes.len] = list("name" = "Replace Air - Siphons out air while replacing", "mode" = AALARM_MODE_REPLACEMENT,	"selected" = mode == AALARM_MODE_REPLACEMENT,	"danger" = 0)
	modes[++modes.len] = list("name" = "Panic - Siphons air out of the room", 			"mode" = AALARM_MODE_PANIC,			"selected" = mode == AALARM_MODE_PANIC, 		"danger" = 1)
	modes[++modes.len] = list("name" = "Cycle - Siphons air before replacing", 			"mode" = AALARM_MODE_CYCLE,			"selected" = mode == AALARM_MODE_CYCLE, 		"danger" = 1)
	modes[++modes.len] = list("name" = "Fill - Shuts off scrubbers and opens vents", 	"mode" = AALARM_MODE_FILL,			"selected" = mode == AALARM_MODE_FILL, 			"danger" = 0)
	modes[++modes.len] = list("name" = "Off - Shuts off vents and scrubbers", 			"mode" = AALARM_MODE_OFF,			"selected" = mode == AALARM_MODE_OFF, 			"danger" = 0)
	var/list/thresholds = list()
	var/static/list/gas_names = list(GAS_O2, GAS_CO2, GAS_PHORON, GAS_CH4, "other")	//Gas ids made to match code\defines\gases.dm
	for(var/env in gas_names + list("pressure", "temperature"))
		var/list/settings = list()
		var/list/band = TLV[env]
		for(var/i in 1 to 4)
			settings += list(list("env" = env, "val" = i, "selected" = band[i]))
		thresholds += list(list("name" = env == "pressure" ? "Pressure" : (env == "temperature" ? "Temperature" : env), "settings" = settings))
	data["thresholds"] = thresholds
	return data

/obj/machinery/alarm/proc/ui_set_rcon(datum/act/op/A, rcon)
	for(var/obj/machinery/alarm/AA as anything in alarm_area.air_alarms)
		AA.set_rcon_setting(rcon)
	return OP_OK

/obj/machinery/alarm/proc/thermostat_max(datum/act/A)
	var/list/band = TLV["temperature"]
	return min(band[3] - T0C, MAX_TEMPERATURE)

/obj/machinery/alarm/proc/thermostat_min(datum/act/A)
	var/list/band = TLV["temperature"]
	return max(band[2] - T0C, MIN_TEMPERATURE)

/obj/machinery/alarm/proc/thermostat_default(datum/act/A)
	return target_temperature - T0C

/obj/machinery/alarm/proc/thermostat_question(datum/act/A)
	return "What temperature would you like the system to mantain? (Capped between [thermostat_min(A)] and [thermostat_max(A)]C)"

/// The thermostat's answer (clamped to the safe band by the question) sets every alarm of the area.
/obj/machinery/alarm/proc/thermostat_answered(datum/act/op/A)
	var/datum/prompt/number/R = A.answer
	if(!isnum(R?.value))
		return OP_OK
	for(var/obj/machinery/alarm/AA as anything in alarm_area.air_alarms)
		AA.set_target_temperature(R.value + T0C)
		AA.rescan()
	return OP_OK

/// A switch of one of the area's devices: sent to it as the radio command of the button's name.
/obj/machinery/alarm/proc/ui_device_setting(datum/act/op/A, id_tag, val)
	var/action = A.window_action()
	switch(action)
		if("excheck")
			send_signal(id_tag, list("checks" = val ^ VENT_CHECK_EXTERNAL))
		if("incheck")
			send_signal(id_tag, list("checks" = val ^ VENT_CHECK_INTERNAL))
		else
			send_signal(id_tag, list("[action]" = val))
	return OP_OK

/obj/machinery/alarm/proc/ui_set_pressure(datum/act/op/A, id_tag, value)
	if(!isnull(value))
		send_signal(id_tag, list("[A.window_action()]" = value))
	return OP_OK

/obj/machinery/alarm/proc/ui_reset_pressure(datum/act/op/A, id_tag)
	send_signal(id_tag, list("[A.window_action()]" = TRUE))
	return OP_OK

/// The threshold button names a band the alarm has.
/obj/machinery/alarm/proc/threshold_known(datum/act/op/A)
	return islist(TLV[A.args?["env"]]) // ALLOW(reads): asked when the threshold button is pressed, never from a cached menu

/obj/machinery/alarm/proc/threshold_title(datum/act/op/A)
	return "[A.args?["var"]]"

/obj/machinery/alarm/proc/threshold_question(datum/act/op/A)
	return "New [A.args?["var"]] for [A.args?["env"]]:"

/obj/machinery/alarm/proc/threshold_default(datum/act/op/A)
	var/list/band = TLV[A.args?["env"]]
	return band?[A.args?["var"]]

/// The answered threshold (negative: off) is set, its band kept in order, and the band copied to every alarm of the area.
/obj/machinery/alarm/proc/threshold_answered(datum/act/op/A, env, index)
	var/datum/prompt/number/R = A.answer
	if(!isnum(R?.value) || !islist(TLV[env]))
		return OP_OK
	var/list/band = TLV[env]
	band[index] = R.value < 0 ? -1 : round(R.value, 0.01)
	clamp_tlv_values(env, index)
	for(var/obj/machinery/alarm/AA as anything in alarm_area.air_alarms)
		AA.TLV[env] = band.Copy()
		AA.rescan()
	return OP_OK

/// Keeps the band `env` in order after `changed_threshold` moved: the others follow it.
/obj/machinery/alarm/proc/clamp_tlv_values(env, changed_threshold)
	var/list/selected = TLV[env]
	var/value = selected[changed_threshold]
	for(var/i in 1 to 4)
		if(i < changed_threshold && selected[i] > value)
			selected[i] = value
		else if(i > changed_threshold && selected[i] < value)
			selected[i] = value

/obj/machinery/alarm/proc/ui_set_mode(datum/act/op/A, new_mode)
	set_mode(new_mode)
	apply_mode()
	rescan()
	return OP_OK

/obj/machinery/alarm/proc/ui_raise_alarm(datum/act/op/A)
	if(alarm_area.atmosalert(2, src))
		apply_danger_level(2)
	return OP_OK

/obj/machinery/alarm/proc/ui_reset_alarm(datum/act/op/A)
	atmos_reset()
	return OP_OK

// ---- the panel and the wires ----

/// The wirecutters at the open panel cut the alarm out of the wall: its frame and board stay, with five lengths of cable.
/obj/machinery/alarm/proc/cut_out(datum/act/op/A)
	new /obj/item/stack/cable_coil(get_turf(src), 5)
	dismantle()
	return OP_OK

/obj/machinery/alarm/proc/wire_lights()
	return list(
		"The Air Alarm is [lock_locked(src) ? "locked." : "unlocked."]",
		"The Air Alarm is [(shorted || (has_stat(NOPOWER|BROKEN))) ? "offline." : "working properly!"]",
		"The 'AI control allowed' light is [aidisabled ? "off" : "on"].")

/// The ID wire cut locks the interface.
/obj/machinery/alarm/proc/wire_was_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(N.wire == WIRE_IDSCAN && !N.mended)
		cap_key_set(src, LOCK_LOCKED, TRUE, null)

/// The syphon wire cut panics the vents.
/obj/machinery/alarm/proc/syphon_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(!N.mended)
		set_mode(AALARM_MODE_PANIC)
		apply_mode()

/// The syphon wire pulsed swaps scrubbing and panic.
/obj/machinery/alarm/proc/syphon_wire_pulsed(datum/act/A)
	set_mode(mode == AALARM_MODE_SCRUBBING ? AALARM_MODE_PANIC : AALARM_MODE_SCRUBBING)
	apply_mode()

/// The alarm wire cut raises the area's atmos alarm.
/obj/machinery/alarm/proc/alarm_wire_cut(datum/act/A)
	if(alarm_area.atmosalert(2, src))
		post_alert(2)

/// The alarm wire pulsed clears it.
/obj/machinery/alarm/proc/alarm_wire_pulsed(datum/act/A)
	if(alarm_area.atmosalert(0, src))
		post_alert(0)

// ---- the remote atmospherics console's panel ----

/// The window a remote atmospherics console shows of one alarm: the alarm's own window, its buttons forwarded to the alarm, which takes them past its
/// lock from whoever the console lets in (window_vouches()).
/datum/air_alarm_remote
	var/obj/machinery/alarm/alarm
	var/datum/tgui_module/atmos_control/console

CAPABILITIES(/datum/air_alarm_remote)
	ref_one(nameof(alarm), /obj/machinery/alarm)
	ref_one(nameof(console), /datum/tgui_module/atmos_control)
	interface("AirAlarm", forwards = nameof(alarm))

/datum/air_alarm_remote/New(datum/tgui_module/atmos_control/console, obj/machinery/alarm/alarm)
	..()
	rel_set(src, nameof(src.console), console)
	rel_set(src, nameof(src.alarm), alarm)

/// The console lets the actor of `A` work the alarm: a silicon's link the alarm lets in, the console's own access, an emagged console, remote
/// control always on (or on in an emergency), or the chief engineer's access.
/datum/air_alarm_remote/proc/allows(datum/act/op/A)
	var/mob/user = A?.actor
	if(!user || !alarm || !console)
		return FALSE
	if(alarm.remote_link_allowed(A) || console.emagged || console.access.allowed(user) || (ACCESS_CE in user.GetAccess()))
		return TRUE
	return alarm.rcon_setting == RCON_YES || (alarm.rcon_setting == RCON_AUTO && alarm.alarm_area?.atmosalm)

/datum/air_alarm_remote/window_vouches(datum/act/op/A)
	return allows(A)

/datum/air_alarm_remote/ui_data(datum/act/eval/A)
	return alarm ? alarm.ui_data(A) : list()

#undef AALARM_REPORT_TIMEOUT
#undef MAX_TEMPERATURE
#undef MIN_TEMPERATURE
