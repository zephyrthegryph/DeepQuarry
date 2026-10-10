/obj/machinery/meter
	name = "meter"
	desc = "It measures something."
	icon = 'icons/obj/meter.dmi'
	icon_state = "meterX"
	var/obj/machinery/atmospherics/pipe/target
	var/list/pipes_on_turf
	anchored = TRUE
	power_channel = ENVIRON
	var/frequency = 0
	var/id
	var/open = FALSE
	use_power = USE_POWER_IDLE
	idle_power_usage = 15
	/// The mixture it reads (its pipe's, or a turf meter's turf's): what its gas watch is on.
	var/datum/gas_mixture/watched_air
	/// What the needle shows (an icon state of meter.dmi) and the kPa it last sent, so a change below the display's resolution is not a change.
	var/needle = "meterX"
	var/sent_kpa

TRACKED(/obj/machinery/meter, needle)
TRACKED(/obj/machinery/meter, open)
TRACKED(/obj/machinery/meter, id)

MSG_DEF(meter/unfastened, "You have unfastened %T%.", "%U% unfastens %T%.")
MSG_DEF_SELF(meter/panel_opened, "You open the maintenance panel.")
MSG_DEF_SELF(meter/panel_closed, "You close the maintenance panel.")
MSG_DEF_SELF(meter/no_pipe, "There is no pipe here to watch.")
MSG_DEF_SELF(meter/panel_shut, "Its maintenance panel is shut.")

CAPABILITIES(/obj/machinery/meter)
	gas_watch(air = nameof(watched_air), changed = PROC_REF(gas_changed), mask = GAS_DEPENDENCY_PRESSURE)
	on_change(nameof(needle), ANY, then(PROC_REF(needle_moved)))
	examine_line(PROC_REF(gauge_text))
	op("read", hand(), label("Read the gauge"), wait(0), then(PROC_REF(read_gauge)))
	extend("read", inputs(remote()))
	op("unwrench", tool(TOOL_WRENCH), wait(4 SECONDS), says(MSG(meter/unfastened)), then(PROC_REF(unfastened)))
	op("panel", tool(TOOL_SCREWDRIVER), wait(0), toggles(nameof(open)), says(PROC_REF(panel_message)))
	op("set_id", tool(TOOL_MULTITOOL), wait(0), when(nameof(open)), needs(req(PROC_REF(panel_open_now))),
		asks(/datum/prompt/text, fields = list("title" = "Set ID Tag", "question" = computed(PROC_REF(id_question)), "default" = nameof(id), "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(id_entered)))
	op("retarget", tool(TOOL_MULTITOOL), wait(0), when(cond_not(nameof(open))), needs(req(PROC_REF(pipe_here), because = MSG(meter/no_pipe))), then(PROC_REF(retargeted)))

/obj/machinery/meter/Initialize(mapload)
	. = ..()
	set_target(target_ref() || select_target())

/// Points the meter at `new_target`. The meter owns its lifetime watch on a
/// pipe target: when the pipe is destroyed the meter comes off as an item.
/obj/machinery/meter/proc/set_target(new_target)
	if(istype(target_ref(), /obj/machinery/atmospherics/pipe))
		unobserve(target_ref(), /datum/notice/qdeleting, src)
	rel_set(src, nameof(target), new_target)
	if(istype(target_ref(), /obj/machinery/atmospherics/pipe))
		observe(target_ref(), /datum/notice/qdeleting, src, then(PROC_REF(on_target_deleted)))
	refresh()

/obj/machinery/meter/proc/on_target_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	rel_clear(src, nameof(target))
	if(QDELETED(src))
		return
	var/obj/item/pipe_meter/PM = new /obj/item/pipe_meter(loc)
	transfer_fingerprints_to(PM)
	replace_with(src, PM)

/obj/machinery/meter/proc/select_target()
	var/obj/machinery/atmospherics/pipe/P
	FOR_CONTENTS(P, loc)
		if(!P.hides_under_flooring())
			break
	if(!P)
		P = locate_within(loc, /obj/machinery/atmospherics/pipe)
	return P

// ---- what it shows: the gas watch moves the needle; nothing polls ----

/// The pipe's gas changed (its gas watch).
/obj/machinery/meter/proc/gas_changed(list/observation, index)
	refresh()

/// Reads its gas again: the needle, and a radio meter's report when the kPa it sends changed. Follows the pipe to a new mixture (a rebuilt network).
/obj/machinery/meter/proc/refresh()
	var/datum/gas_mixture/environment = target_ref()?.return_air()
	if(environment != watched_air)
		atmos_air_set(src, nameof(watched_air), environment)
	if(!target_ref() || !environment)
		set_needle("meterX")
		return
	if(!operable())
		set_needle("meter0")
		return
	set_needle(pressure_icon_state(environment))
	var/kpa = round(environment.return_pressure())
	if(frequency && kpa != sent_kpa)
		sent_kpa = kpa
		broadcast(kpa)

/obj/machinery/meter/power_change()
	. = ..()
	if(.)
		refresh()

/obj/machinery/meter/proc/needle_moved(datum/act/A)

/obj/machinery/meter/draw(datum/look/look)
	..()
	look.state(needle)

/obj/machinery/meter/derived()
	. = ..()
	. += drawn_from(nameof(needle))

/// Sends what it reads to its frequency.
/obj/machinery/meter/proc/broadcast(kpa)
	var/datum/radio_frequency/radio_connection = SSradio.return_frequency(frequency)
	if(!radio_connection)
		return
	var/datum/signal/signal = new
	rel_set(signal, nameof(signal.source), src)
	signal.transmission_method = TRANSMISSION_RADIO
	signal.data = list(
		"tag" = id,
		"device" = "AM",
		"pressure" = kpa,
		"sigtype" = "status"
	)
	radio_connection.post_signal(src, signal)

/obj/machinery/meter/proc/current_pressure_icon_state()
	return pressure_icon_state(target_ref()?.return_air())

/obj/machinery/meter/proc/pressure_icon_state(datum/gas_mixture/environment)
	if(!environment)
		return "meterX"
	var/env_pressure = environment.return_pressure()
	if(env_pressure <= 0.15 * ONE_ATMOSPHERE)
		return "meter0"
	if(env_pressure <= 1.8 * ONE_ATMOSPHERE)
		var/val = round(env_pressure / (ONE_ATMOSPHERE * 0.3) + 0.5)
		return "meter1_[val]"
	if(env_pressure <= 30 * ONE_ATMOSPHERE)
		var/val = round(env_pressure / (ONE_ATMOSPHERE * 5) - 0.35) + 1
		return "meter2_[val]"
	if(env_pressure <= 59 * ONE_ATMOSPHERE)
		var/val = round(env_pressure / (ONE_ATMOSPHERE * 5) - 6) + 1
		return "meter3_[val]"
	return "meter4"

/// What the gauge says to someone near enough to read it.
/obj/machinery/meter/proc/gauge_text(datum/act/eval/A)
	var/mob/user = A.actor
	if(user && get_dist(get_turf(user.client?.eye || user), src) > 3 && !isobserver(user)) // an AI reads it through its eye
		return span_warning("You are too far away to read it.")
	if(!operable())
		return span_warning("The display is off.")
	if(!target_ref())
		return "The connect error light is blinking."
	var/datum/gas_mixture/environment = target_ref().return_air()
	if(!environment)
		return "The sensor error light is blinking."
	var/environment_temperature = environment.return_temperature()
	return "The pressure gauge reads [round(environment.return_pressure(), 0.01)] kPa; [round(environment_temperature,0.01)]K ([round(environment_temperature-T0C,0.01)]&deg;C)"

/// A hand (or an AI) reads the gauge.
/obj/machinery/meter/proc/read_gauge(datum/act/op/A)
	var/mob/user = A.actor
	user.examinate(src)
	return OP_OK

/obj/machinery/meter/proc/unfastened(datum/act/op/A)
	replace_with(src, /obj/item/pipe_meter)
	return OP_OK

/obj/machinery/meter/proc/panel_message(datum/act/A)
	return open ? /datum/msg/meter/panel_opened : /datum/msg/meter/panel_closed

/obj/machinery/meter/proc/id_question(datum/act/A)
	return "Please insert an ID tag for [src], example 'exhaust_pipe'."

/// The tag is set, and a multitool keeps the meter in its buffer.
/obj/machinery/meter/proc/id_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	set_id(answer.value)
	var/obj/item/multitool/multitool = A.held?.get_multitool()
	if(multitool)
		rel_set(multitool, nameof(multitool.connectable), src)
	return OP_OK

/// Its panel is open (asked again when the tag is answered).
/obj/machinery/meter/proc/panel_open_now(datum/act/A)
	return (open) ? null : MSG(meter/panel_shut)

/obj/machinery/meter/proc/pipe_here(datum/act/A)
	return (!!locate_within(loc, /obj/machinery/atmospherics/pipe)) ? null : MSG(meter/no_pipe) // ALLOW(reads): asked when the multitool is used, never from a cached menu

/// The multitool moves the meter to the next pipe on its tile.
/obj/machinery/meter/proc/retargeted(datum/act/op/A)
	for(var/obj/machinery/atmospherics/pipe/pipe in contents_of(loc))
		rel_add(src, nameof(pipes_on_turf), pipe)
	set_target(LAZYACCESS(pipes_on_turf, 1))
	rel_remove(src, nameof(pipes_on_turf), target_ref())
	rel_add(src, nameof(pipes_on_turf), target_ref())
	to_chat(A.actor, span_notice("Pipe meter set to monitor \the [target_ref()]."))
	return OP_OK

// TURF METER - REPORTS A TILE'S AIR CONTENTS

/obj/machinery/meter/turf/select_target()
	return loc

/// A turf meter is fixed in its floor: no tool works it.
CAPABILITIES(/obj/machinery/meter/turf)
	without("unwrench")
	without("panel")
	without("set_id")
	without("retarget")

/// target (a relation view: it reads null once the target is deleted).
/obj/machinery/meter/proc/target_ref() as /obj/machinery/atmospherics/pipe
	return target
