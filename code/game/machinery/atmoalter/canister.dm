// The gas canister: a portable vessel of gas (code/game/machinery/atmoalter/portable_atmospherics.dm) with a release valve, a tank bay and a label.
//
// What it is: CAPABILITIES below. Its valve's work is an every() that runs while it has work (the valve open, its gas reacting, its liner exposed),
// woken by its own gas watch; the release itself is the gas domain's gas_release(). A preset is a `starts_with` table, filled when it is made.

#define CANISTER_RELEASE_LOG_MAX 50

/obj/machinery/portable_atmospherics/canister
	name = "canister"
	icon = 'icons/obj/atmos.dmi'
	icon_state = "yellow"
	density = TRUE
	max_integrity = 100
	w_class = ITEMSIZE_HUGE

	layer = TABLE_LAYER	// Above catwalks, hopefully below other things

	var/release_pressure = ONE_ATMOSPHERE
	/// The most the valve lets out per service interval, litres of the canister's gas.
	var/release_flow_rate = ATMOS_DEFAULT_VOLUME_PUMP

	var/canister_color = "yellow"
	start_pressure = 45 * ONE_ATMOSPHERE
	pressure_resistance = 7 * ONE_ATMOSPHERE
	var/temperature_resistance = 1000 + T0C
	/// Integrity of the material which actually touches the stored gas.
	var/material_liner_integrity = 100
	var/material_last_exposure = 0
	volume = 1000
	use_power = USE_POWER_OFF
	interact_offline = 1 // Allows this to be used when not in powered area.

	/// What it is filled with when it is made: gas id -> share of a full load (start_pressure at 20 C). Over 1 is more than one load.
	var/list/starts_with
	/// The temperature it is chilled to once filled (null: it stays at 20 C).
	var/chilled_to
	/// It empties itself into the room it is made in (the room filler).
	var/empties_into_room = FALSE
	/// Who opened and closed the valve: the newest CANISTER_RELEASE_LOG_MAX lines.
	var/list/release_log

	var/valve_open = FALSE
	/// It has work each service interval: the valve is open, or its gas or its liner has something left to do.
	var/working = TRUE
	/// The band of the pressure gauge (1 under 10 kPa, 2 under one atmosphere, 3 under fifteen, 4 above).
	var/gauge_band = 1

TRACKED(/obj/machinery/portable_atmospherics/canister, valve_open)
TRACKED(/obj/machinery/portable_atmospherics/canister, working)
TRACKED(/obj/machinery/portable_atmospherics/canister, gauge_band)
TRACKED(/obj/machinery/portable_atmospherics/canister, canister_color)

MSG_DEF_SELF(canister/has_liner, "It already has an engineered pressure liner.")
MSG_DEF_SELF(canister/drain_first, "Drain and restore it before installing a pressure liner.")
MSG_DEF_SELF(canister/pressurized, "Its internal pressure is too high! Empty the canister before attempting to weld it apart.")
MSG_DEF_SELF(canister/not_empty, "It can only be relabelled while it is empty.")
MSG_DEF(canister/deconstructed, "You deconstruct %T%.", "%U% deconstructs %T%.")
MSG_DEF(canister/jetpack, "You pulse-pressurize your jetpack from the tank.", "%U% pulse-pressurizes a jetpack from %T%.")

CAPABILITIES(/obj/machinery/portable_atmospherics/canister)
	climb()
	gas_watch(air = nameof(air_contents), changed = PROC_REF(contents_changed))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(canister_step)), when = nameof(working))
	on_change(nameof(valve_open), ANY, then(PROC_REF(valve_moved)))
	op("liner", stack(/obj/item/stack/material, 2), label("Install pressure liner"), wait(0),
		needs(req(PROC_REF(no_liner), because = MSG(canister/has_liner)), req(PROC_REF(drained_for_liner), because = MSG(canister/drain_first))),
		then(PROC_REF(install_liner)))
	op("refill_jetpack", item(/obj/item/tank/jetpack), label("Pulse-pressurize jetpack"), wait(0), when(PROC_REF(actor_is_robot)),
		says(MSG(canister/jetpack)), then(PROC_REF(refill_jetpack)))
	extend("melee_hit", when(cond_not(req(/obj/item/tank))), when(cond_not(req(/obj/item/analyzer))), when(cond_not(req(/obj/item/pda))))
	op("weld_apart", tool(TOOL_WELDER), label("Deconstruct"), wait(2 SECONDS), needs(req(PROC_REF(empty_or_wrecked), because = MSG(canister/pressurized))),
		says(MSG(canister/deconstructed)), then(PROC_REF(welded_apart)))

	/// The canister's window and the buttons in it.
	section(controls, "The canister's window and the buttons in it")
	interface("Canister", state = nameof(GLOB.tgui_physical_state))
	extend("ui_open", needs(req(PROC_REF(not_destroyed), because = MSG(portable/wrecked))))
	op("relabel", ui_act("relabel"), needs(req(PROC_REF(can_relabel), because = MSG(canister/not_empty))),
		asks(/datum/prompt/choice, fields = list("title" = "Gas canister", "question" = "Choose canister label", "choices" = computed(PROC_REF(label_choices)))),
		then(PROC_REF(label_chosen)))
	op("pressure", ui_act("pressure", arg("pressure", num())), then(PROC_REF(ui_set_release_pressure)))
	op("valve", ui_act("valve"), then(PROC_REF(ui_toggle_valve)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_eject)))

/obj/machinery/portable_atmospherics/canister/nitrous_oxide
	name = "Canister: \[N2O\]"
	icon_state = "redws"
	canister_color = "redws"
	starts_with = list(GAS_N2O = 1)

/obj/machinery/portable_atmospherics/canister/nitrogen
	name = "Canister: \[N2\]"
	icon_state = "red"
	canister_color = "red"
	starts_with = list(GAS_N2 = 1)

/obj/machinery/portable_atmospherics/canister/oxygen
	name = "Canister: \[O2\]"
	icon_state = "blue"
	canister_color = "blue"
	starts_with = list(GAS_O2 = 1)

/obj/machinery/portable_atmospherics/canister/oxygen/prechilled
	name = "Canister: \[O2 (Cryo)\]"
	chilled_to = 80

/obj/machinery/portable_atmospherics/canister/phoron
	name = "Canister \[Phoron\]"
	icon_state = "orangeps"
	canister_color = "orangeps"
	starts_with = list(GAS_PHORON = 1)

/obj/machinery/portable_atmospherics/canister/carbon_dioxide
	name = "Canister \[CO2\]"
	icon_state = "black"
	canister_color = "black"
	starts_with = list(GAS_CO2 = 1)

/obj/machinery/portable_atmospherics/canister/methane
	name = "Canister: \[CH4\]"
	icon_state = "green"
	canister_color = "green"
	starts_with = list(GAS_CH4 = 1)

/obj/machinery/portable_atmospherics/canister/air
	name = "Canister \[Air\]"
	icon_state = "grey"
	canister_color = "grey"
	starts_with = list(GAS_O2 = O2STANDARD, GAS_N2 = N2STANDARD)

/obj/machinery/portable_atmospherics/canister/air/airlock
	start_pressure = 3 * ONE_ATMOSPHERE

/obj/machinery/portable_atmospherics/canister/empty/
	start_pressure = 0

/obj/machinery/portable_atmospherics/canister/empty/oxygen
	name = "Canister: \[O2\]"
	icon_state = "blue"
	canister_color = "blue"
/obj/machinery/portable_atmospherics/canister/empty/phoron
	name = "Canister \[Phoron\]"
	icon_state = "orangeps"
	canister_color = "orangeps"
/obj/machinery/portable_atmospherics/canister/empty/nitrogen
	name = "Canister \[N2\]"
	icon_state = "red"
	canister_color = "red"
/obj/machinery/portable_atmospherics/canister/empty/carbon_dioxide
	name = "Canister \[CO2\]"
	icon_state = "black"
	canister_color = "black"
/obj/machinery/portable_atmospherics/canister/empty/nitrous_oxide
	name = "Canister \[N2O\]"
	icon_state = "redws"
	canister_color = "redws"

/obj/machinery/portable_atmospherics/canister/empty/methane
	name = "Canister \[CH4\]"
	icon_state = "green"
	canister_color = "green"

//R-UST port
// Special types used for engine setup admin verb, they contain double amount of that of normal canister.
/obj/machinery/portable_atmospherics/canister/nitrogen/engine_setup
	starts_with = list(GAS_N2 = 2)

/obj/machinery/portable_atmospherics/canister/carbon_dioxide/engine_setup
	starts_with = list(GAS_CO2 = 2)

/obj/machinery/portable_atmospherics/canister/phoron/engine_setup
	starts_with = list(GAS_PHORON = 2)

/// Dirty way to fill room with gas: it empties nine rooms' worth of nitrous oxide (36000 moles) into the room it is placed in. -rastaf0
/obj/machinery/portable_atmospherics/canister/nitrous_oxide/roomfiller
	start_pressure = 9 * 4000 * R_IDEAL_GAS_EQUATION * T20C / 1000
	empties_into_room = TRUE

/obj/machinery/portable_atmospherics/canister/Initialize(mapload) // ALLOW(init/INSTANCE_STATE): its gas is made by the base's init; the preset fills it, a per-instance mixture
	. = ..()
	fill_preset()

/// Its preset gas (`starts_with`, chilled to `chilled_to`), emptied into the room when it is a room filler.
/obj/machinery/portable_atmospherics/canister/proc/fill_preset()
	if(starts_with)
		gas_fill(air_contents, starts_with, start_pressure)
	if(!isnull(chilled_to))
		heat_set(air_contents, chilled_to)
	if(empties_into_room && isturf(loc))
		gas_dump(air_contents, loc)
	set_gauge_band(pressure_band())

/obj/machinery/portable_atmospherics/canister/proc/effective_maximum_pressure()
	var/internal_temperature = air_contents?.return_temperature() || T20C
	return material_environment_pressure_limit(maximum_pressure, MATERIAL_CANISTER_REFERENCE_RADIUS, MATERIAL_CANISTER_REFERENCE_THICKNESS, internal_temperature)

/// Returns TRUE while continued chemical exposure needs another sample.
/obj/machinery/portable_atmospherics/canister/proc/process_material_vessel()
	material_liner_integrity = material_assembly_view(src).liner_integrity
	return FALSE // Independent material service owns exposure and leak updates.

/obj/machinery/portable_atmospherics/canister/material_environment_begin_leak()
	if(!material_assembly_view(src).leaking)
		visible_message(span_warning("Gas begins hissing through [src]'s compromised vessel wall."))
	return ..()

/obj/machinery/portable_atmospherics/canister/material_environment_owns_leak()
	return FALSE

/obj/machinery/portable_atmospherics/canister/material_environment_rupture()
	if(!destroyed)
		atom_destruction(BOMB)

/obj/machinery/portable_atmospherics/canister/drain_power()
	return -1

/obj/machinery/portable_atmospherics/canister/return_air()
	return air_contents

/obj/machinery/portable_atmospherics/canister/proc/return_pressure()
	var/datum/gas_mixture/GM = src.return_air()
	if(GM && GM.return_volume()>0)
		return GM.return_pressure()
	return 0

/// Canisters are thick-walled: they catch half of a round.
/obj/machinery/portable_atmospherics/canister/projectile_damage(obj/item/projectile/P, def_zone)
	return receive_projectile(P, def_zone, 0.5)

// ---- its work ----

/// The pressure gauge's band for `pressure` (its own gas's when null).
/obj/machinery/portable_atmospherics/canister/proc/pressure_band(pressure = null)
	if(isnull(pressure))
		pressure = air_contents?.return_pressure() || 0
	if(pressure < 10)
		return 1
	if(pressure < ONE_ATMOSPHERE)
		return 2
	if(pressure < 15 * ONE_ATMOSPHERE)
		return 3
	return 4

/// Its gas changed (its gas watch): the gauge follows, and a canister standing alone wakes to let its gas react (a connected, closed one's gas is the
/// pipe network's).
/obj/machinery/portable_atmospherics/canister/proc/contents_changed(list/observation, index)
	set_gauge_band(pressure_band(GAS_OBSERVED(observation, index, GAS_OBS_PRESSURE)))
	if(valve_open || !connected_port())
		set_working(TRUE)

/// The valve opened or closed: the work follows.
/obj/machinery/portable_atmospherics/canister/proc/valve_moved(datum/act/A)
	set_working(TRUE)

/// One service interval: the liner's exposure, the gas's reactions, the valve's release into the held tank or the room. It parks once nothing is left.
/obj/machinery/portable_atmospherics/canister/proc/canister_step(datum/act/A)
	if(destroyed)
		set_working(FALSE)
		return
	var/turf/canister_turf = get_turf(src)
	material_observe_gases(air_contents, canister_turf?.return_air())
	var/reaction_result = react_or_update()
	var/material_active = process_material_vessel()
	if(destroyed)
		set_working(FALSE)
		return
	if(valve_open)
		gas_release(air_contents, holding ? holding.air_contents : loc, release_pressure, release_flow_rate)
	set_gauge_band(pressure_band())
	set_working(valve_open || reaction_result != NO_REACTION || material_active)

// ---- the look ----

/obj/machinery/portable_atmospherics/canister/draw(datum/look/look)
	..()
	if(destroyed)
		look.state("[canister_color]-1")
		return
	look.state(canister_color)
	look.overlay("can-open", when = !!holding)
	look.overlay("can-connector", when = !!connected_port())
	switch(gauge_band)
		if(1)
			look.overlay("can-o0")
		if(2)
			look.overlay("can-o1")
		if(3)
			look.overlay("can-o2")
		if(4)
			look.overlay("can-o3")

// ---- wrecked ----

// At zero integrity the canister ruptures: it dumps its gas into the room, frees its port, drops its tank and becomes a wreck you can walk through (it
// is not deleted).
/obj/machinery/portable_atmospherics/canister/atom_destruction(damage_flag)
	if(!destroyed && isturf(loc))
		disconnect()
		gas_dump(air_contents, loc) // before the machine's own destruction lets go of its gas
	. = ..()
	if(destroyed)
		return
	set_destroyed(1)
	play_sfx(src, SFX_EFFECTS_SPRAY)
	set_density(FALSE)
	tank_bay_eject(src, nameof(holding))
	set_working(FALSE)

// ---- ops ----

/obj/machinery/portable_atmospherics/canister/proc/no_liner(datum/act/A)
	return !pressure_liner_material_id // ALLOW(reads): asked when the sheets are used, never from a cached menu

/obj/machinery/portable_atmospherics/canister/proc/drained_for_liner(datum/act/A)
	return !destroyed && gas_pressure_of(air_contents) <= ONE_ATMOSPHERE * 0.1

/obj/machinery/portable_atmospherics/canister/proc/install_liner(datum/act/op/A)
	var/obj/item/stack/material/stock = A.held
	var/datum/material/liner = stock.material
	pressure_liner_material_id = liner.name
	set_construction_material(MATERIAL_ROLE_LINER, liner.name)
	material_liner_integrity = 100
	material_assembly(src).liner_integrity = 100
	name = "[liner.display_name]-lined [initial(name)]"
	color = liner.icon_colour
	to_chat(A.actor, span_notice("You install a [liner.display_name] pressure liner in [src]."))
	return OP_OK

/// A cyborg's module (its input carries its link's authority beside the gripper's).
/obj/machinery/portable_atmospherics/canister/proc/actor_is_robot(datum/act/op/A)
	return !!(A.authority & AUTH_REMOTE_ACCESS)

/// A cyborg's jetpack takes half the pressure difference, up to ten atmospheres.
/obj/machinery/portable_atmospherics/canister/proc/refill_jetpack(datum/act/op/A)
	var/obj/item/tank/jetpack/J = A.held
	var/datum/gas_mixture/jetpack_air = J.air_contents
	gas_release(air_contents, jetpack_air, min(10 * ONE_ATMOSPHERE, (air_contents.return_pressure() + jetpack_air.return_pressure()) / 2))
	return OP_OK

/obj/machinery/portable_atmospherics/canister/proc/empty_or_wrecked(datum/act/A)
	return destroyed || gas_pressure_of(air_contents) <= 1

/obj/machinery/portable_atmospherics/canister/proc/welded_apart(datum/act/op/A)
	disconnect()
	replace_with(src, /obj/item/stack/material/steel, 10)
	return OP_OK

// ---- the window ----

/obj/machinery/portable_atmospherics/canister/ui_data(datum/act/eval/A)
	var/pressure = air_contents.return_pressure()
	var/list/data = list(
		"can_relabel" = can_relabel(A) ? 1 : 0,
		"connected" = connected_port() ? 1 : 0,
		"pressure" = round(pressure || 0),
		"releasePressure" = round(release_pressure || 0),
		"defaultReleasePressure" = round(initial(release_pressure)),
		"minReleasePressure" = round(ONE_ATMOSPHERE/10),
		"maxReleasePressure" = round(10*ONE_ATMOSPHERE),
		"valveOpen" = valve_open ? 1 : 0,
		"holding" = null,
	)
	if(holding)
		data["holding"] = list("name" = holding.name, "pressure" = round(holding.air_contents.return_pressure()))
	return data

/// It can be relabelled while it is empty (under one kilopascal).
/obj/machinery/portable_atmospherics/canister/proc/can_relabel(datum/act/A)
	return !destroyed && gas_pressure_of(air_contents) < 1

/// The labels a canister can be given, each with the colour it paints the canister.
GLOBAL_LIST_INIT(canister_label_colors, list(
	"\[N2O\]" = "redws",
	"\[N2\]" = "red",
	"\[O2\]" = "blue",
	"\[Phoron\]" = "orangeps",
	"\[CO2\]" = "black",
	"\[CH4\]" = "green",
	"\[Air\]" = "grey",
	"\[CAUTION\]" = "yellow",
))

/obj/machinery/portable_atmospherics/canister/proc/label_colors()
	return GLOB.canister_label_colors

/obj/machinery/portable_atmospherics/canister/proc/label_choices(datum/act/A)
	return label_colors()

/obj/machinery/portable_atmospherics/canister/proc/label_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/label = R?.value
	var/list/colors = label_colors()
	if(label && colors[label])
		set_canister_color(colors[label])
		name = "Canister: [label]"
	return OP_OK

/obj/machinery/portable_atmospherics/canister/proc/ui_set_release_pressure(datum/act/op/A, pressure)
	release_pressure = clamp(round(pressure), ONE_ATMOSPHERE/10, 10*ONE_ATMOSPHERE)
	add_fingerprint(A.actor)
	return OP_OK

/// A line of the release log, the oldest dropped beyond CANISTER_RELEASE_LOG_MAX.
/obj/machinery/portable_atmospherics/canister/proc/log_release(text)
	LAZYADD(release_log, text)
	if(length(release_log) > CANISTER_RELEASE_LOG_MAX)
		release_log.Cut(1, length(release_log) - CANISTER_RELEASE_LOG_MAX + 1)

/obj/machinery/portable_atmospherics/canister/proc/ui_toggle_valve(datum/act/op/A)
	var/mob/user = A.actor
	var/into = holding ? "the [holding]" : "the air"
	if(valve_open)
		log_release("Valve was closed by [user] ([user.ckey]), stopping the transfer into [into]")
	else
		log_release("Valve was opened by [user] ([user.ckey]), starting the transfer into [into]")
		if(!holding)
			log_open(user)
	set_valve_open(!valve_open)
	add_fingerprint(user)
	return OP_OK

/// The tank comes out onto the floor; an open valve closes first.
/obj/machinery/portable_atmospherics/canister/proc/ui_eject(datum/act/op/A)
	var/mob/user = A.actor
	if(holding)
		if(valve_open)
			set_valve_open(FALSE)
			log_release("Valve was closed by [user] ([user.ckey]), stopping the transfer into the [holding]")
		holding.manipulated_by = user.real_name
		tank_bay_eject(src, nameof(holding))
	add_fingerprint(user)
	return OP_OK

#undef CANISTER_RELEASE_LOG_MAX
