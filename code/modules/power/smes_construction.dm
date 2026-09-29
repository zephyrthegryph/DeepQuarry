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
/obj/machinery/power/smes/buildable/outpost_substation/Initialize(mapload)
	. = ..()
	own_add(src, "component_parts", new /obj/item/smes_coil/weak(src))
	recalc_coils()

// This one is pre-installed on engineering shuttle. Allows rapid charging/discharging for easier transport of power to outpost
// 11M Charge, 2.5M I/O
/obj/machinery/power/smes/buildable/power_shuttle/Initialize(mapload)
	. = ..()
	own_add(src, "component_parts", new /obj/item/smes_coil/super_io(src))
	own_add(src, "component_parts", new /obj/item/smes_coil/super_io(src))
	own_add(src, "component_parts", new /obj/item/smes_coil(src))
	recalc_coils()

// Pre-installed and pre-charged SMES hidden from the station, for use in submaps.
/obj/machinery/power/smes/buildable/point_of_interest/Initialize(mapload)
	. = ..()
	charge = capacity // Should be enough for an individual POI.
	RCon = FALSE
	input_level = input_level_max
	output_level = output_level_max
	input_attempt = TRUE

// END SMES SUBTYPES

// SMES itself
/obj/machinery/power/smes/buildable
	var/max_coils = 6 			//30M capacity, 1.5MW input/output when fully upgraded /w default coils
	var/cur_coils = 1 			// Current amount of installed coils
	var/safeties_enabled = 1 	// If 0 modifications can be done without discharging the SMES, at risk of critical failure.
	var/failing = 0 			// If 1 critical failure has occured and SMES explosion is imminent.
	var/grounding = 1			// Cut to quickly discharge, at cost of "minor" electrical issues in output grid.
	var/RCon = 1				// Cut to disable AI and remote control.
	var/RCon_tag = "NO_TAG"		// RCON tag, change to show it on SMES Remote control console.
	charge = 0
	should_be_mapped = 1

// RCON consoles rescan without it.
/obj/machinery/power/smes/buildable/on_destroy(force)
	for(var/datum/tgui_module/rcon/R in world)
		R.FindDevices()
	..()

/// With the grounding wire cut, sparks fly every frame and the unit discharges quickly, with a
/// small chance of breaking lights on the APCs of its powernet. It stays awake until grounded or
/// nearly empty.
/obj/machinery/power/smes/buildable/power_step()
	var/needs_grounding_tick = !grounding && (Percentage() > 5)
	if(needs_grounding_tick)
		fx_sparks(src, 5)
		charge -= (output_level_max * SMESRATE)
		if(prob(1)) // Small chance of overload occuring since grounding is disabled.
			apcs_overload(0,10)
	. = ..()
	if(needs_grounding_tick)
		return null

/obj/machinery/power/smes/buildable/power_settled()
	return grounding || Percentage() <= 5

/// Old attack_ai: AI requires the RCON wire to be intact to operate the SMES (the default Use).
/// Cyborgs standing next to the SMES can also play with the wiring.
/obj/machinery/power/smes/buildable/proc/smes_buildable_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(RCon)
		actor_use_default(/datum/input_adapter/ai, user, src)
	else // RCON wire cut
		to_chat(user, span_warning("Connection error: Destination Unreachable."))

	// Cyborgs standing next to the SMES can play with the wiring.
	if(isrobot(user) && Adjacent(user) && panel_open)
		wires.Interact(user)
	return TRUE

// Proc: New()
// Parameters: None
// Description: Adds standard components for this SMES, and forces recalculation of properties.
/obj/machinery/power/smes/buildable/Initialize(mapload)
	. = ..()
	own_take_all(src, "component_parts")
	own_add(src, "component_parts", new /obj/item/stack/cable_coil(src,30))
	set_wires(new /datum/wires/smes(src))

	// Allows for mapped-in SMESs with larger capacity/IO
	if(mapload)
		for(var/i = 1, i <= cur_coils, i++)
			own_add(src, "component_parts", new /obj/item/smes_coil(src))
		recalc_coils()

// Proc: attack_hand()
// Parameters: None
// Description: Opens the UI as usual, and if cover is removed opens the wiring panel.
/obj/machinery/power/smes/buildable/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_SILICON("Use", PROC_REF(smes_buildable_silicon_use)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
	into += list(
		/datum/interaction/machine_hand/smes_buildable_wires,
	)
	..()

/// Approximation: the old attack_hand unconditionally called ..() (the ancestor SMES's own
/// attack_hand, out of this file's scope) and then always opened the wire panel if open.
/// The ancestor call can't be replayed from here, so this declines (FALSE) to let the entry
/// fall through to whatever the ancestor/base machinery attack_hand still provides; the wire
/// panel now opens before that fallback runs rather than after, an order approximation - see report.
/datum/interaction/machine_hand/smes_buildable_wires
	id = "smes_buildable_wires"
	name = "Use"
	effect = /obj/machinery/power/smes/buildable/proc/interaction_wires

/obj/machinery/power/smes/buildable/proc/interaction_wires(mob/user, obj/item/held, datum/interaction/interaction)
	if(panel_open)
		wires.Interact(user)
	return FALSE

/obj/machinery/power/smes/buildable/RefreshParts()
	recalc_coils()

// Proc: recalc_coils()
// Parameters: None
// Description: Updates properties (IO, capacity, etc.) of this SMES by checking internal components.
/obj/machinery/power/smes/buildable/proc/recalc_coils()
	if ((cur_coils <= max_coils) && (cur_coils >= 1))
		capacity = 0
		input_level_max = 0
		output_level_max = 0
		for(var/obj/item/smes_coil/C in component_parts)
			capacity += C.ChargeCapacity
			input_level_max += C.IOCapacity
			output_level_max += C.IOCapacity
		charge = between(0, charge, capacity)
		power_sync()
		return 1
	return 0

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
				h_user.status_at_least(EFFECT_WEAKENED, 2)

		if (16 to 35)
			// Medium overcharge
			// Sparks, Medium shock, Weak EMP
			spark_amount = 4
			if (user_protected && prob(25))
				to_chat(h_user, "A medium electrical arc sparks and almost burns your hand. Luckily you had your gloves on!")
			else
				to_chat(h_user, "A medium electrical arc sparks as you touch the [src], severely burning your hand!")
				h_user.injure(INJURY_ELECTRIC, rand(10,25), used_hand, src)
				h_user.status_at_least(EFFECT_WEAKENED, 5)
			empulse(get_turf(src), 1, 2, 3, 4)

		if (36 to 60)
			// Strong overcharge
			// Sparks, Strong shock, Strong EMP, 10% light overload. 1% APC failure
			spark_amount = 7
			if (user_protected)
				to_chat(h_user, "A strong electrical arc sparks between you and [src], ignoring your gloves and burning your hand!")
				h_user.injure(INJURY_ELECTRIC, rand(25,60), used_hand, src)
				h_user.status_at_least(EFFECT_WEAKENED, 8)
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
				failing = 1
				update_icon()
				// 30 - 60 seconds and then BAM!
				om_after(src, rand(300,600), PROC_REF(containment_failure))

	fx_sparks(src, spark_amount)
	charge = 0

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

// Proc: update_icon()
// Parameters: None
// Description: Allows us to use special icon overlay for critical SMESs
/obj/machinery/power/smes/buildable/update_icon()
	if (failing)
		cut_overlays()
		add_overlay("smes-crit")
	else
		..()

// Proc: attackby()
// Parameters: 2 (W - object that was used on this machine, user - person which used the object)
// Description: Handles tool interaction. Allows deconstruction/upgrading/fixing.
/obj/machinery/power/smes/buildable/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/smes_buildable_failing_block,
		/datum/interaction/machine_item/smes_buildable_install_coil,
	)
	..()

// No more disassembling of overloaded SMESs. You broke it, now enjoy the consequences.
/datum/interaction/machine_item/smes_buildable_failing_block
	id = "smes_buildable_failing_block"
	name = "Use"
	held_type = /obj/item
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/power/smes/buildable/proc/is_failing, null))
	effect = /obj/machinery/power/smes/buildable/proc/interaction_failing_block

/obj/machinery/power/smes/buildable/proc/is_failing(mob/actor, atom/target, obj/item/held)
	return failing

/obj/machinery/power/smes/buildable/proc/interaction_failing_block(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_warning("The [src]'s indicator lights are flashing wildly. It seems to be overloaded! Touching it now is probably not a good idea."))
	return TRUE

/**
 * Approximation: the old attackby gated everything below on `if(..())` - the ancestor SMES's
 * own attackby (out of this file's scope), which per the comment returns truthy only when
 * the maintenance hatch is open and it took no action itself (terminal de/construction).
 * That can't be replayed from here, so this is offered only when the panel is open (see
 * report); when not offered, the entry falls through to the base/ancestor attackby, matching
 * the old "..() returned falsy, nothing else happens" path.
 */
/datum/interaction/machine_item/smes_buildable_install_coil
	id = "smes_buildable_install_coil"
	name = "Install coil"
	held_type = /obj/item/smes_coil
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/power/smes/buildable/proc/panel_is_open_impl, null))
	effect = /obj/machinery/power/smes/buildable/proc/interaction_install_coil
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/power/smes/buildable/proc/can_modify))

/obj/machinery/power/smes/buildable/proc/panel_is_open_impl(mob/actor, atom/target, obj/item/held)
	return panel_open

/// Requirement: TRUE, or why the SMES can't be modified now.
/obj/machinery/power/smes/buildable/proc/can_modify(mob/user, atom/target, obj/item/held)
	// Charged above 1% and safeties are enabled.
	if((charge > (capacity/100)) && safeties_enabled)
		return "the safety circuit is preventing modifications while there is charge stored"
	if(output_attempt || input_attempt)
		return "turn it off first"
	return TRUE

/obj/machinery/power/smes/buildable/proc/interaction_install_coil(mob/user, obj/item/W, datum/interaction/interaction)
	// Probability of failure if safety circuit is disabled (in %)
	var/failure_probability = round((charge / capacity) * 100)

	// If failure probability is below 5% it's usually safe to do modifications
	if (failure_probability < 5)
		failure_probability = 0

	// Superconducting Magnetic Coil - Upgrade the SMES
	if (cur_coils < max_coils)

		if (failure_probability && prob(failure_probability))
			total_system_failure(failure_probability, user)
			return TRUE

		to_chat(user, "You install the coil into the SMES unit!")
		user.drop_item()
		cur_coils ++
		own_add(src, "component_parts", W)
		W.forceMove(src)
		recalc_coils()
	else
		to_chat(user, span_red("You can't insert more coils into this SMES unit!"))
	return TRUE

/obj/machinery/power/smes/buildable/multitool_act(mob/user, obj/item/tool)
	if(failing || !panel_open)
		if(failing)
			to_chat(user, span_warning("The [src]'s indicator lights are flashing wildly. It seems to be overloaded! Touching it now is probably not a good idea."))
		return ITEM_INTERACT_BLOCKING
	var/new_tag = rerun_ask(user, "k418", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/text, message = "Enter new RCON tag. Use \"NO_TAG\" to disable RCON or leave empty to cancel.", title = "SMES RCON system", max_length = MAX_NAME_LEN)
	if(isnull(new_tag))
		return ITEM_INTERACT_BLOCKING
	if(!new_tag)
		return ITEM_INTERACT_BLOCKING
	for(var/obj/machinery/power/smes/buildable/smes in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(smes.RCon_tag == new_tag)
			to_chat(user, span_warning("The entered RCON tag [new_tag] already exists. Aborting."))
			return ITEM_INTERACT_BLOCKING
	RCon_tag = new_tag
	to_chat(user, span_notice("You changed the RCON tag to: [new_tag]"))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/smes/buildable/crowbar_act(mob/user, obj/item/tool)
	if(failing || !panel_open)
		if(failing)
			to_chat(user, span_warning("The [src]'s indicator lights are flashing wildly. It seems to be overloaded! Touching it now is probably not a good idea."))
		return ITEM_INTERACT_BLOCKING
	if((charge > capacity / 100) && safeties_enabled)
		to_chat(user, span_warning("The safety circuit of [src] is preventing modifications while there is charge stored!"))
		return ITEM_INTERACT_BLOCKING
	if(output_attempt || input_attempt)
		to_chat(user, span_warning("Turn off [src] first!"))
		return ITEM_INTERACT_BLOCKING
	if(length(terminals))
		to_chat(user, span_warning("You have to disassemble the terminal first!"))
		return ITEM_INTERACT_BLOCKING
	var/failure_probability = round(charge / capacity * 100)
	if(failure_probability < 5)
		failure_probability = 0
	use_tool(user, tool, src, delay = 10 SECONDS * cur_coils, volume = 50, start_self = "You begin to disassemble [src]!", receiver = src, on_done = PROC_REF(crowbar_act_tool_done), done_args = list(user, failure_probability))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/smes/buildable/proc/containment_failure()
	if(!failing) // Admin can manually set this var back to 0 to stop overload, for use when griffed.
		update_icon()
		ping("Magnetic containment stabilised.")
		return
	ping("DANGER! Magnetic containment field failure in 3 ... 2 ... 1 ...")
	explosion(get_turf(src),1,2,4,8)
	// Not sure if this is necessary, but just in case the SMES *somehow* survived..
	qdel(src)
/obj/machinery/power/smes/buildable/proc/crowbar_act_tool_done(mob/user, failure_probability)
	if(failure_probability && prob(failure_probability))
		total_system_failure(failure_probability, user)
		return ITEM_INTERACT_SUCCESS
	to_chat(user, span_red("You have disassembled the SMES cell!"))
	dismantle()

/// Remote (AI and RCON) control on or off.
/obj/machinery/power/smes/buildable/proc/set_rcon(state)
	RCon = state
	om_changed(src, CHANGE_MACHINE_SETTINGS)

/// The failsafes on or off.
/obj/machinery/power/smes/buildable/proc/set_safeties(state)
	safeties_enabled = state
	om_changed(src, CHANGE_MACHINE_SETTINGS)
