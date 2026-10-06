/obj/machinery/power/generator/oldteg
	name = "old thermoelectric generator"
	desc = "It's a 'high efficiency' thermoelectric generator, though this one seems a bit old and worn out. Are the turbines squeeking?"
	max_power = 500000
	thermal_efficiency = 0.40 // 25% less effective around 1400 kw with 24 shots

/obj/machinery/power/generator
	name = "thermoelectric generator"
	desc = "It's a high efficiency thermoelectric generator."
	icon_state = "teg-unassembled"
	density = TRUE
	anchored = FALSE
	unacidable = TRUE

	use_power = USE_POWER_IDLE
	idle_power_usage = 100 //Watts, I hope.  Just enough to do the computer and display things.

	var/max_power = 500000
	var/thermal_efficiency = 0.65

	var/tmp/obj/machinery/atmospherics/binary/circulator/circ1
	var/tmp/obj/machinery/atmospherics/binary/circulator/circ2

	var/last_circ1_gen = 0
	var/last_circ2_gen = 0
	var/last_thermal_gen = 0
	var/stored_energy = 0
	var/lastgen1 = 0
	var/lastgen2 = 0
	var/effective_gen = 0
	var/lastgenlev = 0
	var/datum/looping_sound/generator/soundloop
	/// It has work each service interval: bolted, working, both circulators found and a pressure head (or energy) to turn (reconsider()).
	var/generating = FALSE
	/// The watches it sleeps on: its circulators' four mixtures.
	var/list/datum/native_watch/gas/loop_watches

TRACKED(/obj/machinery/power/generator, generating)
TRACKED(/obj/machinery/power/generator, lastgenlev)

MSG_DEF(teg/secured, "You secure the bolts holding %T% to the floor.", "%U% secures the bolts holding %T% to the floor.")
MSG_DEF(teg/unsecured, "You unsecure the bolts holding %T% to the floor.", "%U% unsecures the bolts holding %T% to the floor.")
MSG_DEF_SELF(teg/not_ready, "It isn't bolted down and working.")

CAPABILITIES(/obj/machinery/power/generator)
	after_init(0, then(PROC_REF(connect_circulators)))
	owns_one(nameof(soundloop), /datum/looping_sound/generator)
	owns_many(nameof(loop_watches), /datum/native_watch/gas)
	membership(joins = REGISTRY_TURBINES)
	interface("TEGenerator")
	extend("ui_open", needs(req(PROC_REF(ready), because = MSG(teg/not_ready))))
	ui_shape(totalOutput = num(), maxTotalOutput = num(), thermalOutput = num(), primary = list_of(), secondary = list_of())
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(teg_step)), when = nameof(generating))
	op("anchor", tool(TOOL_WRENCH), label("Wrench"), wait(0), says(PROC_REF(anchor_message)), then(PROC_REF(anchor_toggled)))

/obj/machinery/power/generator/Initialize(mapload)
	rel_set(src, nameof(soundloop), new /datum/looping_sound/generator(list(src), FALSE))
	desc = initial(desc) + " Rated for [round(max_power/1000)] kW."
	make_rotatable()
	. = ..()

/// Connects its circulators, once they exist.
/obj/machinery/power/generator/proc/connect_circulators(datum/act/timer/A)
	reconnect()


//generators connect in dir and GLOB.reverse_dir(dir) directions
//mnemonic to determine circulator/generator directions: the cirulators orbit clockwise around the generator
//so a circulator to the NORTH of the generator connects first to the EAST, then to the WEST
//and a circulator to the WEST of the generator connects first to the NORTH, then to the SOUTH
//note that the circulator's outlet dir is it's always facing dir, and it's inlet is always the reverse
/obj/machinery/power/generator/proc/reconnect()
	rel_clear(src, nameof(circ1))
	rel_clear(src, nameof(circ2))
	if(src.loc && anchored)
		if(src.dir & (EAST|WEST))
			rel_set(src, nameof(circ1), locate_within(get_step(src,WEST), /obj/machinery/atmospherics/binary/circulator))
			rel_set(src, nameof(circ2), locate_within(get_step(src,EAST), /obj/machinery/atmospherics/binary/circulator))

			if(circ1() && circ2())
				if(circ1().dir != NORTH || circ2().dir != SOUTH)
					rel_clear(src, nameof(circ1))
					rel_clear(src, nameof(circ2))

		else if(src.dir & (NORTH|SOUTH))
			rel_set(src, nameof(circ1), locate_within(get_step(src,NORTH), /obj/machinery/atmospherics/binary/circulator))
			rel_set(src, nameof(circ2), locate_within(get_step(src,SOUTH), /obj/machinery/atmospherics/binary/circulator))

			if(circ1() && circ2() && (circ1().dir != EAST || circ2().dir != WEST))
				rel_clear(src, nameof(circ1))
				rel_clear(src, nameof(circ2))

	reconsider()

// ---- its work: woken by its loops' gas, its bolts, its power; nothing polls ----

/// Whether it has work, and the watches it sleeps on: its circulators' four mixtures, re-armed each time (a rebuilt loop is a new mixture).
/obj/machinery/power/generator/proc/reconsider(datum/act/A)
	gas_watch_many_clear(src, nameof(loop_watches))
	if(!anchored || !circ1() || !circ2() || !operable())
		set_generating(FALSE)
		return
	if(gas_wake_condition() || stored_energy >= 0.01 || effective_gen >= 0.01)
		set_generating(TRUE)
		return
	set_generating(FALSE)
	gas_watch_many(src, nameof(loop_watches), list(circ1().air1, circ1().air2, circ2().air1, circ2().air2), GAS_DEPENDENCY_PRESSURE, PROC_REF(loop_heard))

/// Rust reported a change of one of its loops while it slept.
/obj/machinery/power/generator/proc/loop_heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	if(gas_wake_condition())
		reconsider()

/// Bolted down and working: its window opens.
/obj/machinery/power/generator/proc/ready(datum/act/A)
	return anchored && operable()

/obj/machinery/power/generator/proc/gas_wake_condition()
	if(!circ1() || !circ2())
		return FALSE
	return (circ1().air1.return_pressure() - circ1().air2.return_pressure() > 10) || (circ2().air1.return_pressure() - circ2().air2.return_pressure() > 10)

/obj/machinery/power/generator/draw(datum/look/look)
	..()
	look.state(anchored ? "teg-assembled" : "teg-unassembled")
	if(operable() && lastgenlev != 0)
		look.overlay("teg-op[lastgenlev]")

/obj/machinery/power/generator/derived()
	. = ..()
	. += drawn_from(nameof(lastgenlev), nameof(anchored))

/// Its circulators show which side runs hot while it generates.
/obj/machinery/power/generator/proc/update_circulator_temperatures()
	var/obj/machinery/atmospherics/binary/circulator/one = circ1()
	var/obj/machinery/atmospherics/binary/circulator/two = circ2()
	if(!one || !two)
		return
	if(!operable() || lastgenlev == 0)
		one.set_temperature_overlay(null)
		two.set_temperature_overlay(null)
		return
	var/extreme = (lastgenlev > 9) ? "ex" : ""
	var/one_cold = one.last_temperature < two.last_temperature
	one.set_temperature_overlay("circ-[extreme][one_cold ? "cold" : "hot"]")
	two.set_temperature_overlay("circ-[extreme][one_cold ? "hot" : "cold"]")

/// One service interval of generating (its every(), while it has work).
/obj/machinery/power/generator/proc/teg_step(datum/act/A)
	if(!circ1() || !circ2() || !operable())
		stored_energy = 0
		set_power_supply(0)
		reconsider()
		return

	var/datum/gas_mixture/air1 = circ1().return_transfer_air()
	var/datum/gas_mixture/air2 = circ2().return_transfer_air()

	lastgen2 = lastgen1
	lastgen1 = 0
	last_thermal_gen = 0
	last_circ1_gen = 0
	last_circ2_gen = 0

	if(air1 && air2)
		// The circulators' gas meets across the junction: the hot side's heat flows to the cold side and thermal_efficiency of it, never
		// more than Carnot allows, leaves as electricity (Rust books it).
		last_thermal_gen = heat_engine_once(air1, air2, thermal_efficiency)

	//Transfer the air
	if (air1)
		circ1().air2.merge(air1)
	if (air2)
		circ2().air2.merge(air2)

	//Update the gas networks
	gas_touched(circ1().air2)
	gas_touched(circ2().air2)

	//Exceeding maximum power leads to some power loss
	if(effective_gen > max_power && prob(5))
		fx_sparks(src, 3)
		stored_energy *= 0.5

	//Power
	last_circ1_gen = circ1().return_stored_energy()
	last_circ2_gen = circ2().return_stored_energy()
	stored_energy += last_thermal_gen + last_circ1_gen + last_circ2_gen
	lastgen1 = stored_energy*0.4 //smoothened power generation to prevent slingshotting as pressure is equalized, then restored by pumps
	stored_energy -= lastgen1
	effective_gen = (lastgen1 + lastgen2) / 2

	// Sounds.
	if(effective_gen > (max_power * 0.05)) // More than 5% and sounds start.
		soundloop.start()
		soundloop.volume = LERP(1, 40, effective_gen / max_power)
	else
		soundloop.stop()

	// update icon overlays and power usage only if displayed level has changed
	var/genlev = max(0, min( round(11*effective_gen / max_power), 11))
	if(effective_gen > 100 && genlev == 0)
		genlev = 1
	if(genlev != lastgenlev)
		set_lastgenlev(genlev)
		update_circulator_temperatures()
	// A supply rate, not a per-tick pulse: the TEG is a steady generator (M3).
	set_power_supply(effective_gen)
	if(!air1 && !air2 && stored_energy < 0.01 && effective_gen < 0.01)
		set_power_supply(0)
		reconsider()

/obj/machinery/power/generator/proc/anchor_message(datum/act/A)
	return anchored ? /datum/msg/teg/secured : /datum/msg/teg/unsecured

/// The wrench bolts it down onto the grid, or frees it.
/obj/machinery/power/generator/proc/anchor_toggled(datum/act/op/A)
	set_anchored(!anchored)
	set_use_power(anchored ? USE_POWER_IDLE : USE_POWER_ACTIVE)
	if(anchored)
		connect_to_network()
	else
		stored_energy = 0
		set_power_supply(0)
		disconnect_from_network()
	set_lastgenlev(0)
	effective_gen = 0
	reconnect()
	return OP_OK

/obj/machinery/power/generator/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["totalOutput"] = effective_gen
	data["maxTotalOutput"] = max_power
	data["thermalOutput"] = last_thermal_gen
	var/list/merged_1 = ui_data_obj_machinery_power_generator(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/power/generator's window data.
/obj/machinery/power/generator/proc/ui_data_obj_machinery_power_generator(mob/user, datum/tgui/ui, datum/tgui_state/state)
	// this is the data which will be sent to the ui
	var/vertical = 0
	if (dir == NORTH || dir == SOUTH)
		vertical = 1

	var/list/data = list()

	data["primary"] = null
	if(circ1())
		//The one on the left (or top)
		data["primary"] = list()
		data["primary"]["dir"] = vertical ? "top" : "left"
		data["primary"]["output"] = last_circ1_gen
		data["primary"]["flowCapacity"] = circ1().volume_capacity_used*100
		data["primary"]["inletPressure"] = circ1().air1.return_pressure()
		data["primary"]["inletTemperature"] = circ1().air1.return_temperature()
		data["primary"]["outletPressure"] = circ1().air2.return_pressure()
		data["primary"]["outletTemperature"] = circ1().air2.return_temperature()

	data["secondary"] = null
	if(circ2())
		//Now for the one on the right (or bottom)
		data["secondary"] = list()
		data["secondary"]["dir"] = vertical ? "bottom" : "right"
		data["secondary"]["output"] = last_circ2_gen
		data["secondary"]["flowCapacity"] = circ2().volume_capacity_used*100
		data["secondary"]["inletPressure"] = circ2().air1.return_pressure()
		data["secondary"]["inletTemperature"] = circ2().air1.return_temperature()
		data["secondary"]["outletPressure"] = circ2().air2.return_pressure()
		data["secondary"]["outletTemperature"] = circ2().air2.return_temperature()

	return data

/obj/machinery/power/generator/power_change()
	. = ..()
	reconsider()

/obj/machinery/power/generator/power_spike(announce_prob = 30)
	if(!(effective_gen >= max_power / 2 && power_region)) // Don't make a spike if we're not making a whole lot of power.
		return

	var/list/powernet_union = LAZYCOPY(power_grid_nodes(power_region))
	for(var/obj/machinery/power/terminal/T in power_grid_nodes(power_region))
		if(T.master() && istype(T.master(), /obj/machinery/power/smes))
			var/obj/machinery/power/smes/S = T.master()
			if(length(power_grid_nodes(S.power_region))) powernet_union |= power_grid_nodes(S.power_region)

	var/found_grid_checker = FALSE
	for(var/obj/machinery/power/grid_checker/G in powernet_union)
		G.power_failure(announce_prob) // If we found a grid checker, then all is well.
		found_grid_checker = TRUE
	if(!found_grid_checker) // Otherwise lets break some stuff.
		after(src, 1, PROC_REF(announce_power_spike))
		// The overloads roll through the network a machine a tick, each on the machine's clock.
		var/i = 0
		var/limit = rand(30, 50)
		for(var/obj/machinery/power/P in powernet_union)
			i++
			after(P, i, TYPE_PROC_REF(/obj/machinery/power, overload), with = list(src))
			if(i >= limit)
				break

/obj/machinery/power/generator/proc/announce_power_spike()
	GLOB.command_announcement.Announce("Dangerous power spike detected in the power network.  Please check machinery \
	for electrical damage.",
	"Critical Power Overload",
	ANNOUNCER_MSG_POWERSPIKE)

/// the circ1 this refers to: a relation view, null once that is deleted.
/obj/machinery/power/generator/proc/circ1() as /obj/machinery/atmospherics/binary/circulator
	return circ1

/// the circ2 this refers to: a relation view, null once that is deleted.
/obj/machinery/power/generator/proc/circ2() as /obj/machinery/atmospherics/binary/circulator
	return circ2
