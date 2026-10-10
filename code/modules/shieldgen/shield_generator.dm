//
// This generator is for the supercool big shields intended for ships that do nice stuff with overmaps.
//
/obj/machinery/power/shield_generator
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 4 SECONDS
	name = "advanced shield generator"
	desc = "A heavy-duty shield generator and capacitor, capable of generating energy shields at large distances."
	icon = 'icons/obj/machines/shielding_vr.dmi'
	icon_state = "generator0"
	circuit = /obj/item/circuitboard/shield_generator
	density = TRUE
	var/list/field_segments    // List of all shield segments owned by this generator.
	var/list/damaged_segments  // List of shield segments that have failed and are currently regenerating (a relation view).
	var/shield_modes = 0                // Enabled shield mode flags
	var/mitigation_em = 0               // Current EM mitigation
	var/mitigation_physical = 0         // Current Physical mitigation
	var/mitigation_heat = 0             // Current Burn mitigation
	var/mitigation_max = 0              // Maximal mitigation reachable with this generator. Set by RefreshParts()
	var/max_energy = 0                  // Maximal stored energy. In joules. Depends on the type of used SMES coil when constructing this generator.
	var/current_energy = 0              // Current stored energy.
	var/field_radius = 1                // Current field radius.
	var/target_radius = 1               // Desired field radius.
	var/running = SHIELD_OFF            // Whether the generator is enabled or not.
	var/input_cap = 1 MEGAWATTS         // Currently set input limit. Set to 0 to disable limits altogether. The shield will try to input this value per tick at most
	var/upkeep_power_usage = 0          // Upkeep power usage last tick.
	var/upkeep_multiplier = 1           // Multiplier of upkeep values.
	var/power_coefficient = 1			// Multiplier of overall power usage (for mappers, subtypes, etc)
	var/power_usage = 0                 // Total power usage last tick.
	var/overloaded = 0                  // Whether the field has overloaded and shut down to regenerate.
	var/hacked = 0                      // Whether the generator has been hacked by cutting the safety wire.
	var/offline_for = 0                 // The generator will be inoperable for this duration in ticks.
	var/mode_changes_locked = 0         // Whether the control wire is cut, locking out changes.
	var/list/mode_list = null           // A list of shield_mode datums.
	var/full_shield_strength = 0        // The amount of power shields need to be at full operating strength.
	var/initial_shield_modes = MODEFLAG_HYPERKINETIC|MODEFLAG_EM|MODEFLAG_ATMOSPHERIC|MODEFLAG_HUMANOIDS

	var/idle_multiplier   = 1           // Trades off cost vs. spin-up time from idle to running
	var/idle_valid_values = list(1, 2, 5, 10)
	var/spinup_delay      = 20
	var/spinup_counter    = 0

TRACKED(/obj/machinery/power/shield_generator, mode_changes_locked)

TRACKED(/obj/machinery/power/shield_generator, offline_for)

TRACKED(/obj/machinery/power/shield_generator, running)

/// The power wire cut cuts the input (power_wires()).
STAT(/obj/machinery/power/shield_generator, input_cut, ANY)
/// The AI control wire cut locks the AI out (ai_control()).
STAT(/obj/machinery/power/shield_generator, ai_control_disabled, ANY)

// Segments currently down and regenerating (they leave the list when they die).
CAPABILITIES(/obj/machinery/power/shield_generator)
	started_work(step = PROC_REF(work_step))
	ref_many(nameof(damaged_segments))
	owns_many(nameof(field_segments))
	owns_many(nameof(mode_list))
	space(SPACE_PANEL, door = nameof(panel_open))
	wires(name = "Shield Generator", count = 5, tools = FALSE, status_lines = PROC_REF(wire_lights))
	power_wires(stat = STAT_INPUT_CUT)
	ai_control(stat = STAT_AI_CONTROL_DISABLED, pulse_lasts = 0)
	on_wire(WIRE_CONTRABAND, cut = PROC_REF(contraband_wire_cut), pulse = PROC_REF(contraband_wire_pulsed))
	on_wire(WIRE_SHIELD_CONTROL, cut = PROC_REF(control_wire_cut))
	interface("OvermapShieldGenerator")
	op("begin_shutdown", ui_act("begin_shutdown"),
		asks(/datum/prompt/choice, fields = list("question" = "Are you sure you wish to do this? It will drain the power inside the internal storage rapidly.", "title" = "Are you sure?", "choices" = list("Yes", "No"), "buttons" = TRUE, "timeout" = 0), step = "k504", when = PROC_REF(is_running)),
		then(PROC_REF(ui_act_begin_shutdown)))
	op("start_generator", ui_act("start_generator"), then(PROC_REF(ui_act_start_generator)))
	op("toggle_idle", ui_act("toggle_idle", arg("toggle_idle", num())), then(PROC_REF(ui_act_toggle_idle)))
	op("emergency_shutdown", ui_act("emergency_shutdown"),
		asks(/datum/prompt/choice, fields = list("question" = "Are you sure that you want to initiate an emergency shield shutdown? This will instantly drop the shield, and may result in unstable release of stored electromagnetic energy. Proceed at your own risk.", "title" = "Confirmation", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "k531", when = PROC_REF(is_on)),
		then(PROC_REF(ui_act_emergency_shutdown)))
	op("set_range", ui_act("set_range"),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(range_question)), "title" = "Field Radius Control", "default" = nameof(field_radius), "max_value" = computed(PROC_REF(range_max)), "min_value" = 1, "timeout" = 0), step = "k550", when = PROC_REF(modes_unlocked)),
		then(PROC_REF(ui_act_set_range)))
	op("set_input_cap", ui_act("set_input_cap"),
		asks(/datum/prompt/number, fields = list("question" = "Enter new input cap (in kW). Enter 0 or nothing to disable input cap.", "title" = "Generator Power Control", "default" = computed(PROC_REF(input_cap_kw)), "timeout" = 0), step = "k557", when = PROC_REF(modes_unlocked)),
		then(PROC_REF(ui_act_set_input_cap)))
	op("toggle_mode", ui_act("toggle_mode", arg("toggle_mode", num())), then(PROC_REF(ui_act_toggle_mode)))
	op("switch_idle", ui_act("switch_idle", arg("switch_idle", num())), then(PROC_REF(ui_act_switch_idle)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wirecutter_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), needs(req_bool(PROC_REF(can_replace_parts_holds), because = PROC_REF(can_replace_parts_refusal))), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))
	extend("machine_anchor", needs(req_is(nameof(offline_for), FALSE, because = MSG(shield_generator/cooling)), req_is(nameof(running), FALSE, because = MSG(shield_generator/running))))
	extend("machine_unanchor", needs(req_is(nameof(offline_for), FALSE, because = MSG(shield_generator/cooling)), req_is(nameof(running), FALSE, because = MSG(shield_generator/running))))

/obj/machinery/power/shield_generator/proc/wire_lights()
	return list(
		"The orange light is [mode_changes_locked ? "on." : "off."]",
		"The blue light is [ai_control_disabled ? "off." : "blinking."]",
		"The violet light is [hacked ? "pulsing." : "steady."]",
		"The red light is [input_cut ? "off." : "on."]")

/// The contraband wire cut takes the hack off (and the modes it allowed).
/obj/machinery/power/shield_generator/proc/contraband_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(N.mended)
		return
	hacked = FALSE
	if(check_flag(MODEFLAG_BYPASS))
		toggle_flag(MODEFLAG_BYPASS)
	if(check_flag(MODEFLAG_OVERCHARGE))
		toggle_flag(MODEFLAG_OVERCHARGE)

/obj/machinery/power/shield_generator/proc/contraband_wire_pulsed(datum/act/A)
	hacked = TRUE

/obj/machinery/power/shield_generator/proc/control_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_mode_changes_locked(!N.mended)

/obj/machinery/power/shield_generator/draw(datum/look/look)
	..()
	if(running)
		look.state("generator1")
		look.light(1, 2, "#66FFFF")
	else
		look.state("generator0")
		look.light_off()

/obj/machinery/power/shield_generator/Initialize(mapload)
	. = ..()
	default_apply_parts()

	rel_take_all(src, nameof(mode_list))
	for(var/st in subtypesof(/datum/shield_mode))
		var/datum/shield_mode/SM = new st()
		rel_add(src, nameof(mode_list), SM)
	toggle_flag(initial_shield_modes)

// its field shuts down.
/obj/machinery/power/shield_generator/on_destroy(force)
	shutdown_field()
	..()

/obj/machinery/power/shield_generator/RefreshParts()
	max_energy = 0
	full_shield_strength = 0
	for(var/obj/item/smes_coil/S in slot_contents(CONTAINER_SLOT_INTERNALS))
		full_shield_strength += S.ChargeCapacity * 5
	for(var/datum/latent_entry/entry as anything in latent_entries(CONTAINER_SLOT_INTERNALS))
		if(ispath(entry.path, /obj/item/smes_coil))
			full_shield_strength += dq_type_var(entry.path, "ChargeCapacity") * entry.count * 5
	max_energy = full_shield_strength * 20
	current_energy = between(0, current_energy, max_energy)

	mitigation_max = MAX_MITIGATION_BASE + MAX_MITIGATION_RESEARCH * total_component_rating_of_type(/obj/item/stock_parts/capacitor)
	mitigation_em = between(0, mitigation_em, mitigation_max)
	mitigation_physical = between(0, mitigation_physical, mitigation_max)
	mitigation_heat = between(0, mitigation_heat, mitigation_max)
	..()

// Shuts down the shield, removing all shield segments and unlocking generator settings.
/obj/machinery/power/shield_generator/proc/shutdown_field()
	rel_clear(src, nameof(field_segments))

	set_running(SHIELD_OFF)
	current_energy = 0
	mitigation_em = 0
	mitigation_physical = 0
	mitigation_heat = 0

// Generates the field objects. Deletes existing field, if applicable.
/obj/machinery/power/shield_generator/proc/regenerate_field()
	rel_clear(src, nameof(field_segments))
	var/list/shielded_turfs

	if(check_flag(MODEFLAG_HULL))
		shielded_turfs = fieldtype_hull()
	else
		shielded_turfs = fieldtype_square()

	for(var/turf/T in shielded_turfs)
		var/obj/effect/shield/S = new(T)
		rel_set(S, nameof(S.gen), src)
		S.flags_updated()
		rel_add(src, nameof(field_segments), S)

	//Hull shield chaos icon generation
	if(check_flag(MODEFLAG_HULL))
		var/list/midsections = list()
		var/list/startends = list()
		var/list/corners = list()
		var/list/horror = list()

		for(var/obj/effect/shield/SE in field_segments)
			var/adjacent_fields = 0
			for(var/direction in GLOB.cardinal)
				var/turf/T = get_step(SE, direction)
				var/obj/effect/shield/S = locate_on(T, /obj/effect/shield)
				if(S)
					adjacent_fields |= direction

			//What?
			if(!adjacent_fields)
				horror += SE
				testing("Solo shield turf at [SE.x], [SE.y], [SE.z]")
				continue

			//Middle section or corner (multiple bits set)
			if((adjacent_fields & (adjacent_fields - 1)) != 0)
				//'Impossible' directions
				if(adjacent_fields == (NORTH|SOUTH) || adjacent_fields == (EAST|WEST))
					midsections[SE] = adjacent_fields
				//It's a simple corner
				else //if (adjacent_fields in cornerdirs)
					corners[SE] = adjacent_fields

			//Not 0, not multiple bits, it's a start or an end
			else
				startends[SE] = adjacent_fields

		//Midsections go first
		for(var/obj/effect/shield/SE in midsections)
			var/adjacent = midsections[SE]
			var/turf/L = get_step(SE, ~adjacent & (SOUTH|WEST))
			var/turf/R = get_step(SE, ~adjacent & (NORTH|EAST))
			if(!isspace(L) && !isspace(R))	// Squished in a single tile gap of space!
				switch(adjacent)
					if(NORTH|SOUTH) //Middle vertical section
						if(SE.x < src.x) //Left of generator goes north
							SE.set_dir(NORTH)
						else
							SE.set_dir(SOUTH)
					if(EAST|WEST) //Middle horizontal section
						if(SE.y < src.y) //South of generator goes left
							SE.set_dir(WEST)
						else
							SE.set_dir(EAST)
			else if(isspace(L))
				SE.set_dir(turn(~adjacent & (SOUTH|WEST), -90))
			else
				SE.set_dir(turn(~adjacent & (NORTH|EAST), -90))

			midsections -= SE

		//Some unhandled error state
		for(var/obj/effect/shield/SE in midsections)
			SE.enabled_icon_state = "arrow" //Error state/unhandled

		//Corners
		for(var/obj/effect/shield/S in corners)
			var/adjacent = corners[S]
			if(adjacent in GLOB.cornerdirs)
				do_corner_shield(S, adjacent) //Dir is adjacent fields direction
			else
				// Okay first a quick hack. If only one nonshield...
				var/nonshield = adjacent ^ (NORTH|SOUTH|EAST|WEST)
				if((nonshield & (nonshield - 1)) == 0)
					if(!isspace(get_step(S, nonshield)))
						S.set_dir(turn(nonshield, 90)) // We're basically a normal midsection just with another touching. Ignore it.
						//What's this mysterious 3rd shield touching us?
						var/dir_to_them = turn(nonshield, 180)
						var/turf/T = get_step(S, dir_to_them)
						var/obj/effect/shield/SO = locate_on(T, /obj/effect/shield)
						//They are a corner
						if((SO.dir & (SO.dir - 1)) != 0)
							continue
						else if(dir_to_them & SO.dir) //They're facing away from us, so we're their start
							S.add_overlay(image(icon, icon_state = "shield_start" , dir = SO.dir))
						else if(SO.dir & nonshield) //They're facing us (and the wall)
							S.add_overlay(image(icon, icon_state = "shield_end" , dir = SO.dir))

					else
						var/list/touchnonshield = list()
						for(var/direction in GLOB.cornerdirs)
							var/turf/T = get_step(S, direction)
							if(!isspace(T))
								touchnonshield += T
						if(touchnonshield.len == 1)
							do_corner_shield(S, get_dir(S, touchnonshield[1]))
						else
							S.enabled_icon_state = "capacitor"
				else
					// Not actually a corner... It has MULTIPLE!
					S.enabled_icon_state = "arrow" //Error state/unhandled

		for(var/obj/effect/shield/S in startends)
			var/adjacent = startends[S]
			var/turf/T = get_step(S, adjacent)
			var/obj/effect/shield/SO = locate_on(T, /obj/effect/shield)
			S.set_dir(SO.dir)
			if(S.dir == adjacent) //Flowing into them
				S.enabled_icon_state = "shield_start"
			else
				S.enabled_icon_state = "shield_end"
	else
		var/turf/gen_turf = get_turf(src)
		for(var/obj/effect/shield/SE in field_segments)
			var/new_dir = 0
			if(SE.x == gen_turf.x - field_radius)
				new_dir |= NORTH
			else if(SE.x == gen_turf.x + field_radius)
				new_dir |= SOUTH
			if(SE.y == gen_turf.y + field_radius)
				new_dir |= EAST
			else if(SE.y == gen_turf.y - field_radius)
				new_dir |= WEST
			if((new_dir & (new_dir - 1)) == 0)
				SE.set_dir(new_dir) // Only one bit set means we are an edge not corner.
			else
				do_corner_shield(SE, turn(new_dir, -90), TRUE) // All our corners are outside, don't check turf type.

	for(var/obj/effect/shield/SE in field_segments)
		SE.update_visuals()

	//Phew, update our own icon

/obj/machinery/power/shield_generator/proc/do_corner_shield(obj/effect/shield/S, new_dir, force_outside)
	S.enabled_icon_state = "blank"
	S.set_dir(new_dir)
	var/inside = force_outside ? FALSE : isspace(get_step(S, new_dir))
	// TODO - Obviously this can be more elegant
	if(inside)
		switch(new_dir)
			if(NORTHEAST)
				S.add_overlay(image(S.icon, icon_state = "shield_end", dir = SOUTH))
				S.add_overlay(image(S.icon, icon_state = "shield_start", dir = EAST))
			if(NORTHWEST)
				S.add_overlay(image(S.icon, icon_state = "shield_end", dir = EAST))
				S.add_overlay(image(S.icon, icon_state = "shield_start", dir = NORTH))
			if(SOUTHEAST)
				S.add_overlay(image(S.icon, icon_state = "shield_end", dir = WEST))
				S.add_overlay(image(S.icon, icon_state = "shield_start", dir = SOUTH))
			if(SOUTHWEST)
				S.add_overlay(image(S.icon, icon_state = "shield_end", dir = NORTH))
				S.add_overlay(image(S.icon, icon_state = "shield_start", dir = WEST))
	else
		switch(new_dir)
			if(NORTHEAST)
				S.add_overlay(image(S.icon, icon_state = "shield_end", dir = WEST))
				S.add_overlay(image(S.icon, icon_state = "shield_start", dir = NORTH))
			if(NORTHWEST)
				S.add_overlay(image(S.icon, icon_state = "shield_end", dir = SOUTH))
				S.add_overlay(image(S.icon, icon_state = "shield_start", dir = WEST))
			if(SOUTHEAST)
				S.add_overlay(image(S.icon, icon_state = "shield_end", dir = NORTH))
				S.add_overlay(image(S.icon, icon_state = "shield_start", dir = EAST))
			if(SOUTHWEST)
				S.add_overlay(image(S.icon, icon_state = "shield_end", dir = EAST))
				S.add_overlay(image(S.icon, icon_state = "shield_start", dir = SOUTH))

// Recalculates and updates the upkeep multiplier
/obj/machinery/power/shield_generator/proc/update_upkeep_multiplier()
	var/new_upkeep = 1.0
	for(var/datum/shield_mode/SM in mode_list)
		if(check_flag(SM.mode_flag))
			new_upkeep *= SM.multiplier

	upkeep_multiplier = new_upkeep * power_coefficient

/obj/machinery/power/shield_generator/proc/work_step(datum/act/timer/A)
	upkeep_power_usage = 0
	power_usage = 0

	if(offline_for)
		set_offline_for(max(0, offline_for - 1))
	// We're turned off: nothing left to do once any shutdown cooldown has run out. Starting it
	// (its UI, set_idle()) wakes it.
	if(running == SHIELD_OFF)
		if(!offline_for)
			return PROCESS_KILL
		return

	if(target_radius != field_radius && running != SHIELD_RUNNING) // Do not recalculate the field while it's running; that's extremely laggy.
		field_radius += (target_radius > field_radius) ? 1 : -1

	// We are shutting down, therefore our stored energy disperses faster than usual.
	else if(running == SHIELD_DISCHARGING)
		current_energy -= SHIELD_SHUTDOWN_DISPERSION_RATE
	else if(running == SHIELD_SPINNING_UP)
		spinup_counter--
		if(spinup_counter <= 0)
			set_running(SHIELD_RUNNING)
			regenerate_field()

	mitigation_em = between(0, mitigation_em - MITIGATION_LOSS_PASSIVE, mitigation_max)
	mitigation_heat = between(0, mitigation_heat - MITIGATION_LOSS_PASSIVE, mitigation_max)
	mitigation_physical = between(0, mitigation_physical - MITIGATION_LOSS_PASSIVE, mitigation_max)

	if(running == SHIELD_RUNNING)
		upkeep_power_usage = round((length(field_segments) - length(damaged_segments)) * ENERGY_UPKEEP_PER_TILE * upkeep_multiplier)
	else if(running > SHIELD_RUNNING)
		upkeep_power_usage = round(ENERGY_UPKEEP_IDLE * idle_multiplier * (field_radius * 8) * upkeep_multiplier) // Approximates number of turfs.

	if(power_region && (running >= SHIELD_RUNNING) && !input_cut)
		var/energy_buffer = 0
		energy_buffer = draw_power(min(upkeep_power_usage, input_cap))
		power_usage += round(energy_buffer)

		if(energy_buffer < upkeep_power_usage)
			current_energy -= round(upkeep_power_usage - energy_buffer)	// If we don't have enough energy from the grid, take it from the internal battery instead.

		// Now try to recharge our internal energy.
		var/energy_to_demand
		if(input_cap)
			energy_to_demand = between(0, max_energy - current_energy, input_cap - energy_buffer)
		else
			energy_to_demand = max(0, max_energy - current_energy)
		energy_buffer = draw_power(energy_to_demand)
		power_usage += energy_buffer
		current_energy += round(energy_buffer)
	else
		current_energy -= round(upkeep_power_usage)	// We are shutting down, or we lack external power connection. Use energy from internal source instead.

	if(current_energy <= 0)
		energy_failure()

	if(!overloaded)
		for(var/obj/effect/shield/S in damaged_segments)
			S.regenerate()
	else if (field_integrity() > 25)
		overloaded = 0

/// Requirement (was REQ_* can_replace_parts): the legacy check answers TRUE to pass.
/obj/machinery/power/shield_generator/proc/can_replace_parts_holds(datum/act/op/A)
	var/answer = can_replace_parts(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_replace_parts_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/power/shield_generator/proc/can_replace_parts_refusal(datum/act/op/A)
	var/answer = can_replace_parts(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/power/shield_generator/proc/can_replace_parts(mob/actor, atom/target, obj/item/held)
	if(offline_for)
		return "wait until it cools down from emergency shutdown first"
	if(running)
		return "turn it off first"
	return TRUE

/obj/machinery/power/shield_generator/proc/screwdriver_used(datum/act/op/A)
	return OP_DECLINE

/obj/machinery/power/shield_generator/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!panel_open)
		return OP_OK
	wires_open(src, user)
	return OP_OK

/obj/machinery/power/shield_generator/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!panel_open)
		return OP_OK
	wires_open(src, user)
	return OP_OK

/obj/machinery/power/shield_generator/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(offline_for)
		to_chat(user, span_warning("Wait until \the [src] cools down from emergency shutdown first!"))
		return OP_OK
	if(running)
		to_chat(user, span_notice("Turn off \the [src] first!"))
		return OP_OK
	return OP_DECLINE

MSG_DEF_SELF(shield_generator/cooling, "Wait until %T% cools down from emergency shutdown first!")
MSG_DEF_SELF(shield_generator/running, "Turn off %T% first!")

/obj/machinery/power/shield_generator/proc/energy_failure()
	if(running == SHIELD_DISCHARGING)
		shutdown_field()
	else
		current_energy = 0
		overloaded = 1
		for(var/obj/effect/shield/S in field_segments)
			S.fail(1)

/obj/machinery/power/shield_generator/proc/set_idle(new_state)
	if(new_state)
		if(running == SHIELD_IDLE)
			return
		set_running(SHIELD_IDLE)
		rel_clear(src, nameof(field_segments))
	else
		if(running != SHIELD_IDLE)
			return
		set_running(SHIELD_SPINNING_UP)
		spinup_counter = round(spinup_delay / idle_multiplier)
	work_start(src)

/// The window's data.
/obj/machinery/power/shield_generator/ui_data(datum/act/eval/A)
	. = list()
	.["running"] = running
	.["overloaded"] = overloaded
	.["mitigation_max"] = mitigation_max
	.["field_radius"] = field_radius
	.["target_radius"] = target_radius
	.["hacked"] = hacked
	.["idle_multiplier"] = idle_multiplier
	.["idle_valid_values"] = idle_valid_values
	.["spinup_counter"] = spinup_counter
	var/list/part = ui_data_part_shield_generator(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/power/shield_generator/proc/ui_data_part_shield_generator(datum/act/eval/A)
	var/list/data = list()

	data["modes"] = get_flag_descriptions()
	data["mitigation_physical"] = round(mitigation_physical, 0.1)
	data["mitigation_em"] = round(mitigation_em, 0.1)
	data["mitigation_heat"] = round(mitigation_heat, 0.1)
	data["field_integrity"] = field_integrity()
	data["max_energy"] = round(max_energy / 1000000, 0.1)
	data["current_energy"] = round(current_energy / 1000000, 0.1)
	data["percentage_energy"] = round(data["current_energy"] / data["max_energy"] * 100)
	data["total_segments"] = field_segments ? field_segments.len : 0
	data["functional_segments"] = damaged_segments ? data["total_segments"] - damaged_segments.len : data["total_segments"]
	data["input_cap_kw"] = round(input_cap / 1000)
	data["upkeep_power_usage"] = round(upkeep_power_usage / 1000, 0.1)
	data["power_usage"] = round(power_usage / 1000)
	data["offline_for"] = offline_for * 2

	return data

/obj/machinery/power/shield_generator/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(panel_open && Adjacent(user))
		wires_open(src, user)
	else
		tgui_interact(user)
	return TRUE

/obj/machinery/power/shield_generator/tgui_status(mob/user)
	if(issilicon(user) && !Adjacent(user) && ai_control_disabled)
		return STATUS_UPDATE
	if(panel_open)
		return min(..(), STATUS_DISABLED)
	return ..()

/// The shutdown question is asked only of a running generator.
/obj/machinery/power/shield_generator/proc/is_running(datum/act/op/A)
	return running >= SHIELD_RUNNING

/obj/machinery/power/shield_generator/proc/is_on(datum/act/op/A)
	return !!running

/// The range and input-cap questions are asked only while the modes are not locked.
/obj/machinery/power/shield_generator/proc/modes_unlocked(datum/act/op/A)
	return !mode_changes_locked

/obj/machinery/power/shield_generator/proc/range_question(datum/act/op/A)
	return "Enter new field range (1-[world.maxx]). Leave blank to cancel."

/obj/machinery/power/shield_generator/proc/range_max(datum/act/op/A)
	return world.maxx

/obj/machinery/power/shield_generator/proc/input_cap_kw(datum/act/op/A)
	return round(input_cap / 1000)

/obj/machinery/power/shield_generator/proc/ui_act_begin_shutdown(datum/act/op/A)
	var/mob/user = A.actor
	if(running < SHIELD_RUNNING) // Discharging or off
		return
	var/alert = A.step_value("k504")
	if(running < SHIELD_RUNNING)
		return
	if(alert == "Yes")
		set_idle(TRUE) // do this first to clear the field
		set_running(SHIELD_DISCHARGING)
	return TRUE

/obj/machinery/power/shield_generator/proc/ui_act_start_generator(datum/act/op/A)
	if(offline_for)
		return
	set_idle(TRUE)
	return TRUE

/obj/machinery/power/shield_generator/proc/ui_act_toggle_idle(datum/act/op/A, toggle_idle)
	if(running < SHIELD_RUNNING)
		return TRUE
	set_idle(toggle_idle)
	return TRUE

// Instantly drops the shield, but causes a cooldown before it may be started again. Also carries a risk of EMP at high charge.

/obj/machinery/power/shield_generator/proc/ui_act_emergency_shutdown(datum/act/op/A)
	var/mob/user = A.actor
	if(!running)
		return TRUE

	var/choice = A.step_value("k531")
	if((choice != "Yes") || !running)
		return TRUE

	// If the shield would take 5 minutes to disperse and shut down using regular methods, it will take x1.5 (7 minutes and 30 seconds) of this time to cool down after emergency shutdown
	set_offline_for(round(current_energy / (SHIELD_SHUTDOWN_DISPERSION_RATE / 1.5)))
	var/old_energy = current_energy
	shutdown_field()
	log_and_message_admins("has triggered \the [src]'s emergency shutdown!", user)
	empulse(src, old_energy / 60000000, old_energy / 32000000, 1) // If shields are charged at 450 MJ, the EMP will be 7.5, 14.0625. 90 MJ, 1.5, 2.8125
	old_energy = 0

	return TRUE

/obj/machinery/power/shield_generator/proc/ui_act_set_range(datum/act/op/A)
	var/mob/user = A.actor
	if(mode_changes_locked)
		return TRUE
	var/new_range = A.step_value("k550")
	if(!new_range)
		return TRUE
	target_radius = between(1, new_range, world.maxx)
	return TRUE

/obj/machinery/power/shield_generator/proc/ui_act_set_input_cap(datum/act/op/A)
	var/mob/user = A.actor
	if(mode_changes_locked)
		return TRUE
	var/_answer_k557 = A.step_value("k557")
	var/new_cap = round(_answer_k557)
	if(!new_cap)
		input_cap = 0
		return
	input_cap = max(0, new_cap) * 1000
	return TRUE

/obj/machinery/power/shield_generator/proc/ui_act_toggle_mode(datum/act/op/A, toggle_mode)
	if(mode_changes_locked)
		return TRUE
	// Toggling hacked-only modes requires the hacked var to be set to 1
	if((toggle_mode & (MODEFLAG_BYPASS | MODEFLAG_OVERCHARGE)) && !hacked)
		return TRUE

	toggle_flag(toggle_mode)
	return TRUE

/obj/machinery/power/shield_generator/proc/ui_act_switch_idle(datum/act/op/A, switch_idle)
	if(mode_changes_locked)
		return TRUE
	if(running == SHIELD_SPINNING_UP)
		return TRUE
	var/new_idle = switch_idle
	if(new_idle in idle_valid_values)
		idle_multiplier = new_idle
	return TRUE

/obj/machinery/power/shield_generator/proc/field_integrity()
	if(full_shield_strength)
		return round(CLAMP01(current_energy / full_shield_strength) * 100)
	return 0

// Takes specific amount of damage
/obj/machinery/power/shield_generator/proc/deal_shield_damage(damage, shield_damtype)
	var/energy_to_use = damage * ENERGY_PER_HP
	if(check_flag(MODEFLAG_MODULATE))
		mitigation_em -= MITIGATION_HIT_LOSS
		mitigation_heat -= MITIGATION_HIT_LOSS
		mitigation_physical -= MITIGATION_HIT_LOSS

		switch(shield_damtype)
			if(SHIELD_DAMTYPE_PHYSICAL)
				mitigation_physical += MITIGATION_HIT_LOSS + MITIGATION_HIT_GAIN
				energy_to_use *= 1 - (mitigation_physical / 100)
			if(SHIELD_DAMTYPE_EM)
				mitigation_em += MITIGATION_HIT_LOSS + MITIGATION_HIT_GAIN
				energy_to_use *= 1 - (mitigation_em / 100)
			if(SHIELD_DAMTYPE_HEAT)
				mitigation_heat += MITIGATION_HIT_LOSS + MITIGATION_HIT_GAIN
				energy_to_use *= 1 - (mitigation_heat / 100)

		mitigation_em = between(0, mitigation_em, mitigation_max)
		mitigation_heat = between(0, mitigation_heat, mitigation_max)
		mitigation_physical = between(0, mitigation_physical, mitigation_max)

	current_energy -= energy_to_use

	// Overload the shield, which will shut it down until we recharge above 25% again
	if(current_energy < 0)
		energy_failure()
		return SHIELD_BREACHED_FAILURE

	if(prob(10 - field_integrity()))
		return SHIELD_BREACHED_CRITICAL
	if(prob(20 - field_integrity()))
		return SHIELD_BREACHED_MAJOR
	if(prob(35 - field_integrity()))
		return SHIELD_BREACHED_MINOR
	return SHIELD_ABSORBED

// Checks whether specific flags are enabled
/obj/machinery/power/shield_generator/proc/check_flag(flag)
	return (shield_modes & flag)

/obj/machinery/power/shield_generator/proc/toggle_flag(flag)
	shield_modes ^= flag
	update_upkeep_multiplier()
	for(var/obj/effect/shield/S in field_segments)
		S.flags_updated()

	if((flag & (MODEFLAG_HULL|MODEFLAG_MULTIZ)) && (running == SHIELD_RUNNING))
		regenerate_field()

	if(flag & MODEFLAG_MODULATE)
		mitigation_em = 0
		mitigation_physical = 0
		mitigation_heat = 0

/obj/machinery/power/shield_generator/proc/get_flag_descriptions()
	var/list/all_flags = list()
	for(var/datum/shield_mode/SM in mode_list)
		if(SM.hacked_only && !hacked)
			continue
		all_flags.Add(list(list(
			"name" = SM.mode_name,
			"desc" = SM.mode_desc,
			"flag" = SM.mode_flag,
			"status" = check_flag(SM.mode_flag),
			"hacked" = SM.hacked_only,
			"multiplier" = SM.multiplier
		)))
	return all_flags

// These two procs determine tiles that should be shielded given the field range. They are quite CPU intensive and may trigger BYOND infinite loop checks, therefore they are set
// as background procs to prevent locking up the server. They are only called when the field is generated, or when hull mode is toggled on/off.
/obj/machinery/power/shield_generator/proc/fieldtype_square()
	set background = 1
	var/list/out = list()
	var/list/base_turfs = get_base_turfs()

	for(var/turf/gen_turf in base_turfs)
		var/turf/T
		for (var/x_offset = -field_radius; x_offset <= field_radius; x_offset++)
			T = locate(gen_turf.x + x_offset, gen_turf.y - field_radius, gen_turf.z)
			if(T)
				out += T
			T = locate(gen_turf.x + x_offset, gen_turf.y + field_radius, gen_turf.z)
			if(T)
				out += T

		for (var/y_offset = -field_radius+1; y_offset < field_radius; y_offset++)
			T = locate(gen_turf.x - field_radius, gen_turf.y + y_offset, gen_turf.z)
			if(T)
				out += T
			T = locate(gen_turf.x + field_radius, gen_turf.y + y_offset, gen_turf.z)
			if(T)
				out += T
	return out

/obj/machinery/power/shield_generator/proc/fieldtype_hull()
	set background = 1
	. = list()
	var/list/base_turfs = get_base_turfs()

	// Old code found all space turfs and added them if it had a non-space neighbor.
	// This one finds all non-space turfs and adds all its non-space neighbors.
	for(var/turf/gen_turf in base_turfs)
		var/area/TA = null // Variable for area checking. Defining it here so memory does not have to be allocated repeatedly.
		for(var/turf/T in trange(field_radius, gen_turf))
			// Don't expand to space or on shuttle areas.
			if(isopenturf(T))
				continue

			// Find adjacent space/shuttle tiles and cover them. Shuttles won't be blocked if shield diffuser is mapped in and turned on.
			for(var/turf/TN in orange(1, T))
				TA = get_area(TN)
				if((istype(TN, /turf/space) || (istype(TN, /turf/simulated/open) && (istype(TA, /area/space)))))
					. |= TN
					continue

// Returns a list of turfs from which a field will propagate. If multi-Z mode is enabled, this will return a "column" of turfs above and below the generator.
/obj/machinery/power/shield_generator/proc/get_base_turfs()
	var/list/turfs = list()
	var/turf/T = get_turf(src)

	if(!istype(T))
		return

	turfs.Add(T)

	// Multi-Z mode is disabled
	if(!check_flag(MODEFLAG_MULTIZ))
		return turfs

	while(HasAbove(T.z))
		T = GetAbove(T)
		if(istype(T))
			turfs.Add(T)

	T = get_turf(src)

	while(HasBelow(T.z))
		T = GetBelow(T)
		if(istype(T))
			turfs.Add(T)

	return turfs

// Starts fully charged
/obj/machinery/power/shield_generator/charged/Initialize(mapload)
	. = ..()
	current_energy = max_energy

// Best coil and capacitor, as data (roadmap C6) -- no eager objects.
// `list(circuit = 1, ...)` would use the literal identifier "circuit" as the
// key (DM's named-argument list syntax), not circuit's value -- the key
// must be set by index instead to be the board's actual type path.
/obj/machinery/power/shield_generator/upgraded/latent_generator()
	var/list/gen = list(
		/obj/item/stock_parts/capacitor = 1,
		/obj/item/smes_coil/super_capacity = 1,
	)
	gen[circuit] = 1
	return gen

// Starts with the best SMES coil and capacitor (and fully charged)
/obj/machinery/power/shield_generator/upgraded/Initialize(mapload)
	. = ..()
	RefreshParts()
	current_energy = max_energy

// Only uses 20% as much power (and starts upgraded and charged and hacked)
/obj/machinery/power/shield_generator/upgraded/admin
	name = "experimental shield generator"
	power_coefficient = 0.2
	hacked = TRUE

