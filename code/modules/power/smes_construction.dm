// BUILDABLE SMES(Superconducting Magnetic Energy Storage) UNIT
//
// Last Change 2.8.2018 by Neerti. Also signing this is still dumb.
//
// This is subtype of SMES that should be normally used. It can be constructed, deconstructed and hacked.
// It also supports RCON System which allows you to operate it remotely, if properly set.

//MAGNETIC COILS - These things actually store and transmit power within the SMES. Different types have different
/obj/item/smes_coil
	name = "superconductive magnetic coil"
	desc = "The standard superconductive magnetic coil, with average capacity and I/O rating."
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "smes_coil"			// Just few icons patched together. If someone wants to make better icon, feel free to do so!
	w_class = ITEMSIZE_LARGE 						// It's LARGE (backpack size)
	var/ChargeCapacity = 6000000		// 100 kWh
	var/IOCapacity = 250000				// 250 kW

// 20% Charge Capacity, 60% I/O Capacity. Used for substation/outpost SMESs.
/obj/item/smes_coil/weak
	name = "basic superconductive magnetic coil"
	desc = "A cheaper model of superconductive magnetic coil. Its capacity and I/O rating are considerably lower."
	icon_state = "smes_coil_weak"
	ChargeCapacity = 1200000			// 20 kWh
	IOCapacity = 150000					// 150 kW

// Capacity Coils: High Capacity, Low Flow
/obj/item/smes_coil/super_capacity
	name = "superconductive capacitance coil"
	desc = "A specialised type of superconductive magnetic coil with a significantly stronger containment field, allowing for larger power storage. Its IO rating is much lower, however."
	icon_state = "smes_coil_capacitance"
	ChargeCapacity = 60000000			// 1000 kWh
	IOCapacity = 50000					// 50 kW

/obj/item/smes_coil/super_capacity/ultra
	name = "ultraconductive capacitance coil"
	desc = "A specialised type of superconductive magnetic coil with a significantly stronger containment field, allowing for larger power storage. Its IO rating is much lower, however."
	icon_state = "smes_coil_capacitance_ultra"
	ChargeCapacity = 120000000			// 2000 kWh
	IOCapacity = 100000					// 100 kW

/obj/item/smes_coil/super_capacity/hyper
	name = "hyperconductive capacitance coil"
	desc = "A specialised type of superconductive magnetic coil with a significantly stronger containment field, allowing for larger power storage. Its IO rating is much lower, however."
	icon_state = "smes_coil_capacitance_hyper"
	ChargeCapacity = 360000000			// 6000 kWh
	IOCapacity = 200000					// 200 kW

// Flow Coils: Low Capacity, High Flow
/obj/item/smes_coil/super_io
	name = "superconductive transmission coil"
	desc = "A specialised type of superconductive magnetic coil with reduced storage capabilites but vastly improved power transmission capabilities, making it useful in systems which require large throughput."
	icon_state = "smes_coil_transmission"
	ChargeCapacity = 600000				// 10 kWh
	IOCapacity = 1000000				// 1000 kW

/obj/item/smes_coil/super_io/ultra
	name = "ultraconductive transmission coil"
	desc = "A specialised type of superconductive magnetic coil with reduced storage capabilites but vastly improved power transmission capabilities, making it useful in systems which require large throughput."
	icon_state = "smes_coil_transmission_ultra"
	ChargeCapacity = 1200000				// 20 kWh
	IOCapacity = 2000000				// 2000 kW

/obj/item/smes_coil/super_io/hyper
	name = "hyperconductive transmission coil"
	desc = "A specialised type of superconductive magnetic coil with reduced storage capabilites but vastly improved power transmission capabilities, making it useful in systems which require large throughput."
	icon_state = "smes_coil_transmission_hyper"
	ChargeCapacity = 2400000				// 40 kWh
	IOCapacity = 6000000				// 6000 kW

// SMES SUBTYPES - THESE ARE MAPPED IN AND CONTAIN DIFFERENT TYPES OF COILS

// These are used on individual outposts as backup should power line be cut, or engineering outpost lost power.
// 1M Charge, 150K I/O
/obj/machinery/power/smes/buildable/outpost_substation/starting_parts(datum/act/A)
	return ..() + /obj/item/smes_coil/weak

// This one is pre-installed on engineering shuttle. Allows rapid charging/discharging for easier transport of power to outpost
// 11M Charge, 2.5M I/O
/obj/machinery/power/smes/buildable/power_shuttle/starting_parts(datum/act/A)
	return ..() + list(/obj/item/smes_coil/super_io, /obj/item/smes_coil/super_io, /obj/item/smes_coil)

// Pre-installed and pre-charged SMES hidden from the station, for use in submaps: remote control off and input on from the start.
/obj/machinery/power/smes/buildable/point_of_interest
	RCon = FALSE
	input_attempt = TRUE

// ALLOW(init/INSTANCE_STATE): a point of interest's unit starts full and at its coils' caps, numbers its coils decide when it is made
/obj/machinery/power/smes/buildable/point_of_interest/Initialize(mapload)
	. = ..()
	set_stored_charge(capacity) // Should be enough for an individual POI.
	set_input_level(input_level_max)
	set_output_level(output_level_max)

// END SMES SUBTYPES

// SMES itself
/obj/machinery/power/smes/buildable
	/// 30M capacity, 1.5MW input/output when fully upgraded /w default coils.
	var/max_coils = 6
	/// The coils installed (a mapper sets it to place that many standard coils).
	var/cur_coils = 1
	/// The map placed the unit: it starts with cur_coils standard coils.
	var/tmp/placed_by_map = FALSE
	/// The failsafes: off, modifications can be done without discharging the unit, at risk of critical failure (the wire cuts it).
	var/safeties_enabled = 1
	/// A critical failure has occured and an explosion is imminent (an admin may clear it to stop the countdown).
	var/failing = 0
	/// Cut to quickly discharge, at cost of "minor" electrical issues in output grid.
	var/grounding = 1
	/// Remote (AI and RCON) control: the wire cuts it.
	var/RCon = 1
	/// The tag an RCON console lists the unit by ("NO_TAG": not listed).
	var/RCon_tag = "NO_TAG"
	initial_charge = 0

TRACKED(/obj/machinery/power/smes/buildable, failing)
TRACKED(/obj/machinery/power/smes/buildable, grounding)
TRACKED(/obj/machinery/power/smes/buildable, RCon)
TRACKED(/obj/machinery/power/smes/buildable, RCon_tag)
TRACKED(/obj/machinery/power/smes/buildable, safeties_enabled)
TRACKED(/obj/machinery/power/smes/buildable, cur_coils)

MSG_DEF_SELF(smes/rcon_cut, "Connection error: Destination Unreachable.")
MSG_DEF_SELF(smes/overloaded, "The indicator lights are flashing wildly. It seems to be overloaded! Touching it now is probably not a good idea.")
MSG_DEF_SELF(smes/safety_circuit, "The safety circuit is preventing modifications while there is charge stored.")
MSG_DEF_SELF(smes/turn_it_off, "Turn it off first.")
MSG_DEF_SELF(smes/coils_full, "You can't insert more coils into this SMES unit!")
MSG_DEF_SELF(smes/tag_taken, "That RCON tag already exists.")
MSG_DEF_SELF(smes/coil_installed, "You install the coil into the SMES unit!")

CAPABILITIES(/obj/machinery/power/smes/buildable)
	owns_many(nameof(component_parts), starts = PROC_REF(starting_parts))
	wires(name = "SMES", count = 5, tools = FALSE, status_lines = PROC_REF(wire_lights))
	on_wire(WIRE_SMES_RCON, cut = PROC_REF(rcon_wire_cut), pulse = PROC_REF(rcon_wire_pulsed))
	on_wire(WIRE_SMES_INPUT, cut = PROC_REF(input_wire_cut), pulse = PROC_REF(input_wire_pulsed))
	on_wire(WIRE_SMES_OUTPUT, cut = PROC_REF(output_wire_cut), pulse = PROC_REF(output_wire_pulsed))
	on_wire(WIRE_SMES_GROUNDING, cut = PROC_REF(grounding_wire_cut), pulse = PROC_REF(grounding_wire_pulsed))
	on_wire(WIRE_SMES_FAILSAFES, cut = PROC_REF(failsafe_wire_cut), pulse = PROC_REF(failsafe_wire_pulsed))
	// A failing unit swallows whatever touches it and says why: nothing is done to it.
	op("failing", item(/obj/item), when(nameof(failing)), priority(OP_PRIORITY_PART + 2), needs(req_is(nameof(failing), FALSE, because = MSG(smes/overloaded))))
	op("install_coil", item(/obj/item/smes_coil), at(SPACE_PANEL),
		needs(req(PROC_REF(modify_refusal)), req(PROC_REF(coil_room))),
		then(PROC_REF(coil_installed)))
	op("rcon_tag", tool(TOOL_MULTITOOL), wait(0), at(SPACE_PANEL),
		needs(req_is(nameof(failing), FALSE, because = MSG(smes/overloaded))),
		asks(/datum/prompt/text/rcon_tag),
		then(PROC_REF(rcon_tag_answered)))
	extend("ui_open", needs(req_on_authority(AUTH_REMOTE_ACCESS, req_is(nameof(RCon), TRUE, because = MSG(smes/rcon_cut)))), then(PROC_REF(open_wires_beside_the_window)))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(grounding_frame)), when = cond_not(nameof(grounding)))

/// What a unit is made with: thirty lengths of cable, and, placed by a map, its standard coils (a unit built from a frame gets the frame's parts).
/obj/machinery/power/smes/buildable/proc/starting_parts(datum/act/A)
	. = list(new /obj/item/stack/cable_coil(null, 30))
	if(placed_by_map)
		. += list(/obj/item/smes_coil = cur_coils)

// ALLOW(init/INSTANCE_STATE): whether the map placed the unit (its standard coils come with it) is set before the parent makes its parts; the capacity and I/O caps are the sums of the coils it starts with
/obj/machinery/power/smes/buildable/Initialize(mapload)
	placed_by_map = mapload
	. = ..()
	if(locate_in_list(component_parts, /obj/item/smes_coil)) // a unit made bare (a frame fills it) keeps its type's numbers until its parts arrive
		recalc_coils()

/// With the grounding wire cut, sparks fly every frame and the unit discharges quickly, with a small chance of breaking lights on the APCs of its
/// powernet. It carries on until grounded or nearly empty.
/obj/machinery/power/smes/buildable/proc/grounding_frame(datum/act/timer/A)
	if(Percentage() <= 5)
		return
	fx_sparks(src, 5)
	adjust_stored_charge(-(output_level_max * SMESRATE))
	if(prob(1)) // Small chance of overload occuring since grounding is disabled.
		apcs_overload(0,10)

/// A hand on the unit with its hatch open: the wires window opens beside the unit's own window (only for someone at the unit, not over a link).
/obj/machinery/power/smes/buildable/proc/open_wires_beside_the_window(datum/act/op/A)
	if(panel_open && (A.authority & AUTH_PHYSICAL))
		wires_open(src, A.actor)
	return OP_OK

/obj/machinery/power/smes/buildable/RefreshParts()
	recalc_coils()

/// Updates the capacity and the I/O caps from the coils installed.
/obj/machinery/power/smes/buildable/proc/recalc_coils()
	if(cur_coils > max_coils || cur_coils < 1)
		return 0
	var/new_capacity = 0
	var/new_io = 0
	for(var/obj/item/smes_coil/C in component_parts)
		new_capacity += C.ChargeCapacity
		new_io += C.IOCapacity
	set_capacity(new_capacity)
	set_input_level_max(new_io)
	set_output_level_max(new_io)
	set_stored_charge(clamp(stored_charge(), 0, capacity))
	return 1

/// Detects new coils placed by mappers: they replace the standard ones.
/obj/machinery/power/smes/buildable/apply_mapped_upgrades()
	var/list/parts_found = turf_contents_of_type(get_turf(src), /obj/item/smes_coil)
	if(!length(parts_found))
		return
	for(var/obj/item/smes_coil/C in component_parts.Copy())
		rel_remove(src, nameof(component_parts), C) // an owned part removed is disposed of
		set_cur_coils(cur_coils - 1)
	for(var/obj/item/W as anything in parts_found)
		if(cur_coils >= max_coils)
			break
		rel_add(src, nameof(component_parts), W)
		W.forceMove(src)
		set_cur_coils(cur_coils + 1)
	RefreshParts()

// Proc: total_system_failure()
// Parameters: 2 (intensity - how strong the failure is, user - person which caused the failure)
// Description: Checks the sensors for alerts. If change (alerts cleared or detected) occurs, calls for icon update.
/obj/machinery/power/smes/buildable/proc/total_system_failure(intensity = 0, mob/user)
	// SMESs store very large amount of power. If someone screws up (ie: Disables safeties and attempts to modify the SMES) very bad things happen.
	// Bad things are based on charge percentage.
	// Possible effects:
	// Sparks - Lets out few sparks, mostly fire hazard if phoron present. Otherwise purely aesthetic.
	// Shock - Depending on intensity harms the user. Insultated Gloves protect against weaker shocks, but strong shock bypasses them.
	// EMP Pulse - Lets out EMP pulse discharge which screws up nearby electronics.
	// Light Overload - X% chance to overload each lighting circuit in connected powernet. APC based.
	// APC Failure - X% chance to destroy APC causing very weak explosion too. Won't cause hull breach or serious harm.
	// SMES Explosion - X% chance to destroy the SMES, in moderate explosion. May cause small hull breach.

	if (!intensity)
		return

	var/mob/living/carbon/human/h_user = user
	if (!istype(h_user))
		return

	// Preparations
	var/spark_amount = 3
	// Check if user has protected gloves.
	var/user_protected = 0
	if(h_user.get_equipped_item(SLOT_ID_GLOVES))
		var/obj/item/clothing/gloves/G = h_user.get_equipped_item(SLOT_ID_GLOVES)
		if(G.siemens_coefficient == 0)
			user_protected = 1
	log_game("SMES FAILURE: <b>[src.x]X [src.y]Y [src.z]Z</b> User: [h_user.ckey], Intensity: [intensity]/100")
	message_admins("SMES FAILURE: <b>[src.x]X [src.y]Y [src.z]Z</b> User: [h_user.ckey], Intensity: [intensity]/100 - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[src.x];Y=[src.y];Z=[src.z]'>JMP</a>")

	var/used_hand = h_user.hand?BP_L_HAND:BP_R_HAND

	switch (intensity)
		if (0 to 15)
			// Small overcharge
			// Sparks, Weak shock
			spark_amount = 2
			if (user_protected && prob(80))
				to_chat(h_user, "A small electrical arc almost burns your hand. Luckily you had your gloves on!")
			else
				to_chat(h_user, "A small electrical arc sparks and burns your hand as you touch the [src]!")
				h_user.injure(INJURY_ELECTRIC, rand(5,10), used_hand, src)
				h_user.status_at_least(STAT_WEAKENED, 2)

		if (16 to 35)
			// Medium overcharge
			// Sparks, Medium shock, Weak EMP
			spark_amount = 4
			if (user_protected && prob(25))
				to_chat(h_user, "A medium electrical arc sparks and almost burns your hand. Luckily you had your gloves on!")
			else
				to_chat(h_user, "A medium electrical arc sparks as you touch the [src], severely burning your hand!")
				h_user.injure(INJURY_ELECTRIC, rand(10,25), used_hand, src)
				h_user.status_at_least(STAT_WEAKENED, 5)
			empulse(get_turf(src), 1, 2, 3, 4)

		if (36 to 60)
			// Strong overcharge
			// Sparks, Strong shock, Strong EMP, 10% light overload. 1% APC failure
			spark_amount = 7
			if (user_protected)
				to_chat(h_user, "A strong electrical arc sparks between you and [src], ignoring your gloves and burning your hand!")
				h_user.injure(INJURY_ELECTRIC, rand(25,60), used_hand, src)
				h_user.status_at_least(STAT_WEAKENED, 8)
			else
				to_chat(h_user, "A strong electrical arc sparks between you and [src], knocking you out for a while!")
				h_user.electrocute_act(rand(35,75), src, def_zone = BP_TORSO)
			empulse(get_turf(src), 6, 8, 12, 16)
			apcs_overload(1, 10)
			ping("Caution. Output regulator malfunction. Uncontrolled discharge detected.")

		if (61 to INFINITY)
			// Massive overcharge
			// Sparks, Near - instantkill shock, Strong EMP, 25% light overload, 5% APC failure. 50% of SMES explosion. This is bad.
			spark_amount = 10
			to_chat(h_user, "A massive electrical arc sparks between you and [src]. The last thing you can think about is \"Oh shit...\"")
			// Remember, we have few gigajoules of electricity here.. Turn them into crispy toast.
			h_user.electrocute_act(rand(150,195), src, def_zone = BP_TORSO)
			empulse(get_turf(src), 32, 64)
			apcs_overload(5, 25)
			ping("Caution. Output regulator malfunction. Significant uncontrolled discharge detected.")

			if (prob(50))
				// Added admin-notifications so they can stop it when griffed.
				log_game("SMES explosion imminent.")
				message_admins("SMES explosion imminent.")
				ping("DANGER! Magnetic containment field unstable! Containment field failure imminent!")
				set_failing(1)
				// 30 - 60 seconds and then BAM!
				after(src, rand(30 SECONDS, 60 SECONDS), PROC_REF(containment_failure), key = "containment_failure")

	fx_sparks(src, spark_amount)
	set_stored_charge(0)

// Proc: apcs_overload()
// Parameters: 2 (failure_chance - chance to actually break the APC, overload_chance - Chance of breaking lights)
// Description: Damages output powernet by power surge. Destroys few APCs and lights, depending on parameters.
/obj/machinery/power/smes/buildable/proc/apcs_overload(failure_chance, overload_chance)
	if (!power_region)
		return

	for(var/obj/machinery/power/terminal/T in power_grid_nodes(power_region))
		if(istype(T.master(), /obj/machinery/power/apc))
			var/obj/machinery/power/apc/A = T.master()
			if (prob(overload_chance))
				A.overload_lighting()
			if (prob(failure_chance))
				A.atom_break()

// A critical unit shows only the smes-crit overlay.
/obj/machinery/power/smes/buildable/draw_status(datum/look/look)
	if(failing)
		look.overlay("smes-crit")
		return
	..()

// ---- the coils ----

/// Why the unit cannot be modified now, or null: charged above 1% with the safeties on, or a switch on.
/obj/machinery/power/smes/buildable/proc/modify_refusal(datum/act/op/A)
	if((stored_charge() > (capacity/100)) && safeties_enabled)
		return /datum/msg/smes/safety_circuit
	if(output_attempt || input_attempt)
		return /datum/msg/smes/turn_it_off
	return null

/// There is room for another coil.
/obj/machinery/power/smes/buildable/proc/coil_room(datum/act/A)
	return cur_coils < max_coils ? null : MSG(smes/coils_full)

/// The coil goes in: with the safety circuit off and charge held, the modification can fail badly (the coil stays in hand and the unit discharges
/// into whoever touched it).
/obj/machinery/power/smes/buildable/proc/coil_installed(datum/act/op/A)
	var/mob/user = A.actor
	// Probability of failure if safety circuit is disabled (in %); below 5% it is safe.
	var/failure_probability = round((stored_charge() / capacity) * 100)
	if (failure_probability >= 5 && prob(failure_probability))
		total_system_failure(failure_probability, user)
		return OP_OK
	if(!move_into(src, nameof(src.component_parts), A.held, user))
		return OP_REFUSED
	set_cur_coils(cur_coils + 1) // counted once the coil is in, not before
	recalc_coils()
	act_message_t(user, src, /datum/msg/smes/coil_installed)
	return OP_OK

/// An RCON tag typed at the unit: NO_TAG takes it off the consoles, an empty answer changes nothing, a tag another unit carries is refused and asked again.
/datum/prompt/text/rcon_tag
	question = "Enter new RCON tag. Use \"NO_TAG\" to disable RCON or leave empty to cancel."
	max_len = MAX_NAME_LEN

/datum/prompt/text/rcon_tag/refusal(given)
	if(!given || given == "NO_TAG")
		return null
	for(var/obj/machinery/power/smes/buildable/smes in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(smes.RCon_tag == given)
			return /datum/msg/smes/tag_taken
	return null

/// The RCON tag was typed in (a taken one was refused at the prompt).
/obj/machinery/power/smes/buildable/proc/rcon_tag_answered(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/new_tag = R?.value
	if(!new_tag)
		return OP_OK
	set_RCon_tag(new_tag)
	to_chat(A.actor, span_notice("You changed the RCON tag to: [new_tag]"))
	return OP_OK

/// The countdown of a containment failure ran out: unless an admin cleared `failing`, the field fails, the unit explodes and is destroyed.
/obj/machinery/power/smes/buildable/proc/containment_failure()
	if(!failing) // Admin can manually set this var back to 0 to stop overload, for use when griffed.
		ping("Magnetic containment stabilised.")
		return
	ping("DANGER! Magnetic containment field failure in 3 ... 2 ... 1 ...")
	explosion(get_turf(src),1,2,4,8)
	// The blast takes the unit with it; one it somehow left standing is destroyed the way damage destroys it.
	if(!QDELETED(src))
		atom_destruction(BOMB)

// ---- the wires ----

/obj/machinery/power/smes/buildable/proc/wire_lights()
	return list(
		"The green light is [(input_cut || output_cut) ? "off" : "on"].",
		"The red light is [(safeties_enabled || grounding) ? "off" : "blinking"].",
		"The blue light is [RCon ? "on" : "off"].")

/obj/machinery/power/smes/buildable/proc/rcon_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_RCon(N.mended)

/// The remote wire pulsed drops remote control for a second (a second pulse inside that second changes nothing).
/obj/machinery/power/smes/buildable/proc/rcon_wire_pulsed(datum/act/A)
	if(RCon)
		set_RCon(FALSE)
		after(src, 1 SECOND, PROC_REF(set_RCon), key = "rcon_pulse", with = list(TRUE))

/obj/machinery/power/smes/buildable/proc/input_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_input_cut(!N.mended)

/obj/machinery/power/smes/buildable/proc/input_wire_pulsed(datum/act/A)
	toggle_input()

/obj/machinery/power/smes/buildable/proc/output_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_output_cut(!N.mended)

/obj/machinery/power/smes/buildable/proc/output_wire_pulsed(datum/act/A)
	toggle_output()

/obj/machinery/power/smes/buildable/proc/grounding_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_grounding(N.mended)

/obj/machinery/power/smes/buildable/proc/grounding_wire_pulsed(datum/act/A)
	set_grounding(0)

/obj/machinery/power/smes/buildable/proc/failsafe_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_safeties_enabled(N.mended)

/// The failsafe wire pulsed drops the safeties for a second (a second pulse inside that second changes nothing).
/obj/machinery/power/smes/buildable/proc/failsafe_wire_pulsed(datum/act/A)
	if(safeties_enabled)
		set_safeties_enabled(FALSE)
		after(src, 1 SECOND, PROC_REF(set_safeties_enabled), key = "failsafe_pulse", with = list(TRUE))
