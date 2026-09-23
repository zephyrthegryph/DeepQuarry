/*
Overview:
	Used to create objects that need a per step proc call.  Default definition of 'New()'
	stores a reference to src machine in global 'machines list'.  Default definition
	of 'Del' removes reference to src machine in global 'machines list'.

Class Variables:

	power_init_complete (boolean)
		Indicates that we have have registered our static power usage with the area.

	use_power (num)
		current state of auto power use.
		Possible Values:
			USE_POWER_OFF:0 -- no auto power use
			USE_POWER_IDLE:1 -- machine is using power at its idle power level
			USE_POWER_ACTIVE:2 -- machine is using power at its active power level

	active_power_usage (num)
		Value for the amount of power to use when in active power mode

	idle_power_usage (num)
		Value for the amount of power to use when in idle power mode

	power_channel (num)
		What channel to draw from when drawing power for power mode
		Possible Values:
			EQUIP:0 -- Equipment Channel
			LIGHT:2 -- Lighting Channel
			ENVIRON:3 -- Environment Channel

	component_parts (list)
		A list of component parts of machine used by frame based machines.

	panel_open (num)
		Whether the panel is open

	uid (num)
		Unique id of machine across all machines.

	gl_uid (global num)
		Next uid value in sequence

	stat (bitflag)
		Machine status bit flags.
		Possible bit flags:
			BROKEN:1 -- Machine is broken
			NOPOWER:2 -- No power is being supplied to machine.
			POWEROFF:4 -- tbd
			MAINT:8 -- machine is currently under going maintenance.
			EMPED:16 -- temporary broken by EMP pulse

Class Procs:
	Initialize(mapload)                     'game/machinery/machine.dm'

	Destroy()                     'game/machinery/machine.dm'

	get_power_usage()            'game/machinery/machinery_power.dm'
		Returns the amount of power this machine uses every SSmachines cycle.
		Default definition uses 'use_power', 'active_power_usage', 'idle_power_usage'

	powered(chan = CURRENT_CHANNEL)         'game/machinery/machinery_power.dm'
		Checks to see if area that contains the object has power available for power
		channel given in 'chan'.

	use_power_oneoff(amount, chan=CURRENT_CHANNEL)   'game/machinery/machinery_power.dm'
		Deducts 'amount' from the power channel 'chan' of the area that contains the object.

	power_change()               'game/machinery/machinery_power.dm'
		Called by the area that contains the object when ever that area under goes a
		power state change (area runs out of power, or area channel is turned off).

	RefreshParts()               'game/machinery/machine.dm'
		Called to refresh the variables in the machine that are contributed to by parts
		contained in the component_parts list. (example: glass and material amounts for
		the autolathe)

		Default definition does nothing.

	assign_uid()               'game/machinery/machine.dm'
		Called by machine to assign a value to the uid variable.

	process()                  'game/machinery/machine.dm'
		Called by the 'master_controller' once per game tick for each machine that is listed in the 'machines' list.


	Compiled by Aygar
*/

/obj/machinery
	material_template = /datum/material_template/machine_part
	material_total = 5 * SHEET_MATERIAL_AMOUNT
	name = "machinery"
	silicon_use = SILICON_USE_HAND
	icon = 'icons/obj/stationobjs.dmi'
	w_class = ITEMSIZE_NO_CONTAINER
	layer = UNDER_JUNK_LAYER

	var/stat = 0
	var/emagged = 0
	var/use_power = USE_POWER_IDLE
		//0 = dont run the auto
		//1 = run auto, use idle
		//2 = run auto, use active
	var/idle_power_usage = 0
	var/active_power_usage = 0
	var/power_channel = EQUIP //EQUIP, ENVIRON or LIGHT
	var/tmp/power_init_complete = FALSE
	/// Re-checks power (power_change()) when its area's channels change.
	/// Lights listen on the reactor key instead.
	var/power_subscriber = TRUE
	var/list/component_parts = null //list of all the parts used to build it, if made from certain kinds of frames.
	var/tmp/uid
	var/panel_open = FALSE
	var/global/gl_uid = 1
	var/clicksound			// sound played on succesful interface. Just put it in the list of vars at the start.
	var/clickvol = 40		// volume
	var/interact_offline = 0 // Can the machine be interacted with while de-powered.
	var/obj/item/circuitboard/circuit = null
	/// Bitfield of MACHINE_MAINT_*: which Maintainable interactions this machine offers (machinery_maintenance.dm).
	var/maintenance_flags = NONE
	/// Time spent securing or unsecuring this machine; zero is immediate.
	var/maintenance_wrench_time = 0
	/// Time spent welding a damaged machine back to full integrity.
	var/maintenance_weld_time = 2 SECONDS
	/// Inspectable material makeup retained from the frame and installed parts.
	var/list/material_component_manifest
	/// Whole-machine EMP rejection supplied by insulating component materials.
	var/material_emp_resistance = 0
	/// Monotonic diagnostic counter for exact dependency-wake assertions.
	var/tmp/gas_dependency_wake_count = 0
	/// Slot in SSmachines.processing_machines while DF_ISPROCESSING is set; lets
	/// hibernation swap-remove in O(1).
	var/tmp/machine_processing_index = 0
	/// SSmachines pass that last handled this machine. A machine started during a
	/// pass is stamped with that pass so it waits for the next one.
	var/tmp/machine_processing_pass = 0

	var/speed_process = FALSE			//If false, SSmachines. If true, SSfastprocess.

	blocks_emissive = EMISSIVE_BLOCK_GENERIC

REGISTRY_MEMBERSHIP(/obj/machinery, REGISTRY_MACHINES)

/obj/machinery/Initialize(mapload, d=0)
	. = ..()
	if(isnum(d))
		set_dir(d)
	if(ispath(circuit))
		circuit = new circuit(src)
	if(!speed_process)
		START_MACHINE_PROCESSING(src)
	else
		START_PROCESSING(SSfastprocess, src)
	if(!mapload)
		power_change()

/obj/machinery/Destroy()
	cancel_sleep_keys()
	if(!speed_process)
		STOP_MACHINE_PROCESSING(src)
	else
		STOP_PROCESSING(SSfastprocess, src)
	// Constructed machinery owns its installed board. Clear the typed reference
	// immediately when destruction starts; otherwise the board spends an extra GC
	// generation retained by an already-deleting machine (and reference tracking
	// turns thousands of those harmless delays into multi-second world freezes).
	if(circuit)
		if(circuit.loc == src && !QDELETED(circuit))
			qdel(circuit)
		circuit = null
	if(component_parts)
		for(var/atom/A in component_parts)
			if(A.loc == src) // If the components are inside the machine, delete them.
				qdel(A)
			else // Otherwise we assume they were dropped to the ground during deconstruction, and were not removed from the component_parts list by deconstruction code.
				WARNING("[A] was still in [src]'s component_parts when it was Destroy()'d")
		component_parts.Cut()
		component_parts = null
	if(contents) // The same for contents.
		for(var/atom/A in contents)
			if(ishuman(A))
				var/mob/living/carbon/human/H = A
				H.forceMove(loc)
				H.reset_perspective()
			else
				qdel(A)
	return ..()

/obj/machinery/process() // Steady power usage is handled separately. If you dont use process why are you here?
	return PROCESS_KILL

/// Whether a dirty gas notification makes a sleeping machine actionable.
/// Gas-dependent subtypes override this; the conservative default preserves
/// correctness for newly subscribed machinery until it supplies a filter.
/obj/machinery/proc/gas_dependency_changed(mixture_id, change_mask)
	return TRUE

/// Change classes this machine can act on while sleeping. Rust uses the
/// aggregate mask to avoid publishing irrelevant notifications into DM.
/obj/machinery/proc/gas_dependency_interest_mask()
	return GAS_DEPENDENCY_ALL

/obj/machinery/emp_act(severity, recursive)
	if(material_emp_resistance && prob(material_emp_resistance))
		return EMP_PROTECT_ALL
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(use_power && stat == 0)
		use_power(7500/severity)

		var/obj/effect/overlay/pulse2 = new /obj/effect/overlay(src.loc)
		pulse2.icon = 'icons/effects/effects.dmi'
		pulse2.icon_state = "empdisable"
		pulse2.name = "emp sparks"
		pulse2.anchored = TRUE
		pulse2.set_dir(pick(GLOB.cardinal))
		QDEL_IN(pulse2, 1 SECOND)


/obj/machinery/vv_edit_var(var_name, new_value)
	if(var_name == NAMEOF(src, use_power))
		update_use_power(new_value)
		return TRUE
	else if(var_name == NAMEOF(src, power_channel))
		update_power_channel(new_value)
		return TRUE
	else if(var_name == NAMEOF(src, idle_power_usage))
		update_idle_power_usage(new_value)
		return TRUE
	else if(var_name == NAMEOF(src, active_power_usage))
		update_active_power_usage(new_value)
		return TRUE
	return ..()

/// Returns the sum of the rating values of all component_parts entries that are instances of part_type.
/obj/machinery/proc/total_component_rating_of_type(part_type)
	. = 0
	for(var/thing in component_parts)
		if(istype(thing, part_type))
			var/obj/item/stock_parts/part = thing
			. += part.rating

/obj/machinery/proc/operable(additional_flags = 0)
	return !inoperable(additional_flags)

/obj/machinery/proc/inoperable(additional_flags = 0)
	return (stat & (NOPOWER | BROKEN | additional_flags))

// Duplicate of below because we don't want to fuck around with CanUseTopic in TGUI
// TODO: Replace this with can_interact from /tg/
/obj/machinery/tgui_status(mob/user)
	if(!interact_offline && (stat & (NOPOWER | BROKEN)))
		return STATUS_CLOSE
	return ..()

/obj/machinery/CanUseTopic(mob/user)
	if(!interact_offline && (stat & (NOPOWER | BROKEN)))
		return STATUS_CLOSE
	return ..()

////////////////////////////////////////////////////////////////////////////////////////////

/// Machines take the AI's Use as a hand's (silicon_use), but a cyborg looking
/// through a camera can't remotely control them.
/obj/machinery/attack_ai(mob/user as mob)
	if(isrobot(user) && (!user.client || user.is_remote_viewing()))
		return
	return ..()

/obj/machinery/attack_hand(mob/user as mob)

	if(inoperable(MAINT))
		return 1
	if(user.lying || user.stat)
		return 1
	if(!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return 1
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.injury_load(INJURY_CATEGORY_NEURAL) >= 55)
			visible_message(span_warning("[H] stares cluelessly at [src]."))
			return 1
		else if(prob(H.injury_load(INJURY_CATEGORY_NEURAL)))
			to_chat(user, span_warning("You momentarily forget how to use [src]."))
			return 1

	if(clicksound && istype(user, /mob/living/carbon))
		playsound(src, clicksound, clickvol)

	add_fingerprint(user)

	return ..()

/obj/machinery/proc/RefreshParts() //Placeholder proc for machines that are built using frames.
	return

/// Finalize the physical machine from its real installed parts. Individual
/// machines still calculate functional ratings in RefreshParts(); this common
/// pass retains their materials and supplies chassis/EMP behavior.
/obj/machinery/proc/finalize_material_assembly()
	material_component_manifest = list()
	var/total_integrity = 0
	var/total_dielectric = 0
	var/part_count = 0
	for(var/obj/item/part as anything in component_parts)
		var/datum/material/material = part.primary_construction_material() || part.get_material()
		if(!material)
			continue
		part_count++
		total_integrity += material.integrity
		total_dielectric += material.dielectric_strength
		material_component_manifest += "[part.name]: [material.display_name]"
	if(!part_count)
		return FALSE
	var/integrity_factor = clamp((total_integrity / part_count) / 150, 0.5, 2.5)
	max_integrity = max(1, round(initial(max_integrity) * integrity_factor))
	if(uses_integrity)
		update_integrity(max_integrity)
	material_emp_resistance = clamp(round(total_dielectric / part_count * 0.6), 0, 75)
	return TRUE

/obj/machinery/examine(mob/user)
	. = ..()
	if(length(material_component_manifest))
		. += span_notice("Installed material parts: [jointext(material_component_manifest, "; ")].")

/obj/machinery/proc/assign_uid()
	uid = gl_uid
	gl_uid++

/obj/machinery/proc/state(msg)
	for(var/mob/O in hearers(src, null))
		O.show_message("[icon2html(src,O.client)] " + span_notice("[msg]"), 2)

/obj/machinery/proc/ping(text=null)
	if(!text)
		text = "\The [src] pings."

	state(text, "blue")
	playsound(src, 'sound/machines/ping.ogg', 50, 0)

/obj/machinery/proc/shock(mob/user, prb)
	if(inoperable())
		return 0
	if(!prob(prb))
		return 0
	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(5, 1, src)
	s.start()
	if(electrocute_mob(user, get_area(src), src, 0.7))
		var/area/temp_area = get_area(src)
		if(temp_area)
			var/obj/machinery/power/apc/temp_apc = temp_area.get_apc()

			if(temp_apc && temp_apc.terminal && temp_apc.terminal.powernet)
				temp_apc.terminal.powernet.trigger_warning()
		if(user.stunned)
			return 1
	return 0

/obj/machinery/proc/default_apply_parts()
	var/obj/item/circuitboard/CB = circuit
	if(!istype(CB))
		return
	CB.apply_default_parts(src)
	RefreshParts()

/obj/machinery/proc/default_use_hicell()
	var/obj/item/cell/C = locate(/obj/item/cell) in component_parts
	if(C)
		component_parts -= C
		qdel(C)
		C = new /obj/item/cell/high(src)
		component_parts += C
		RefreshParts()
		return C

/obj/machinery/proc/default_part_replacement(mob/user, obj/item/storage/part_replacer/R)
	var/parts_replaced = FALSE
	if(!istype(R))
		return 0
	if(!component_parts)
		return 0
	to_chat(user, span_notice("Following parts detected in [src]:"))
	for(var/obj/item/C in component_parts)
		to_chat(user, span_notice("    [C.name]"))
	if(panel_open || !R.panel_req)
		var/obj/item/circuitboard/CB = circuit
		var/P
		for(var/obj/item/A in component_parts)
			for(var/T in CB.req_components)
				if(ispath(A.type, T))
					P = T
					break
			for(var/obj/item/B in R.contents)
				if(istype(B, P) && istype(A, P))
					if(B.get_rating() > A.get_rating())
						R.remove_from_storage(B, src)
						R.handle_item_insertion(A, 1)
						component_parts -= A
						component_parts += B
						B.loc = null
						to_chat(user, span_notice("[A.name] replaced with [B.name]."))
						parts_replaced = TRUE
						break
			update_icon()
			RefreshParts()
			if(parts_replaced)
				R.play_rped_sound()
	return 1

// This is it's own proc so it can be more easily found when looking for machines that can upgrade themselves from mapped parts
// Should be called from LateInitialize()
/obj/machinery/proc/apply_mapped_upgrades()
	return

/// Focused-hook implementation for monitor-style machines that dismantle directly
/// rather than exposing a maintenance panel.
/obj/machinery/proc/deconstruct_display(mob/user, obj/item/tool)
	if(!circuit)
		return ITEM_INTERACT_BLOCKING
	if(!use_tool(user, tool, src, delay = 2 SECONDS, volume = 50, message_self = "You start disconnecting the monitor."))
		return ITEM_INTERACT_BLOCKING
	if(stat & BROKEN)
		to_chat(user, span_notice("The broken glass falls out."))
		new /obj/item/material/shard(loc)
	else
		to_chat(user, span_notice("You disconnect the monitor."))
	return dismantle() ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING

/obj/machinery/proc/dismantle()
	SEND_SIGNAL(src, COMSIG_OBJ_DECONSTRUCT, FALSE)
	playsound(src, 'sound/items/Crowbar.ogg', 50, 1)
	for(var/obj/I in contents)
		if(istype(I,/obj/item/card/id))
			I.forceMove(src.loc)

	if(!circuit)
		return 0
	var/obj/structure/frame/A = new /obj/structure/frame(src.loc)
	var/obj/item/circuitboard/M = circuit
	A.circuit = M
	A.anchored = TRUE
	A.frame_type = M.board_type
	if(A.frame_type.circuit)
		A.need_circuit = 0

	if(A.frame_type.frame_class == FRAME_CLASS_ALARM || A.frame_type.frame_class == FRAME_CLASS_DISPLAY)
		A.density = FALSE
	else
		A.density = TRUE

	if(A.frame_type.frame_class == FRAME_CLASS_MACHINE)
		for(var/obj/D in component_parts)
			D.forceMove(src.loc)
		if(A.components)
			A.components.Cut()
		else
			A.components = list()
		component_parts = list()
		A.check_components()

	if(A.frame_type.frame_class == FRAME_CLASS_ALARM)
		A.state = FRAME_FASTENED
	else if(A.frame_type.frame_class == FRAME_CLASS_COMPUTER || A.frame_type.frame_class == FRAME_CLASS_DISPLAY)
		if(stat & BROKEN)
			A.state = FRAME_WIRED
		else
			A.state = FRAME_PANELED
	else
		A.state = FRAME_WIRED

	A.set_dir(dir)
	A.pixel_x = pixel_x
	A.pixel_y = pixel_y
	A.update_desc()
	A.update_icon()
	M.loc = null
	M.atom_deconstruct(TRUE, src)
	qdel(src)
	return 1

/**
 * Machinery contents are the deterministic salvage from structural destruction.
 * /obj/deconstruct() moves those contents to the turf after this hook. Detach the
 * bookkeeping references first so Destroy() neither deletes the salvaged parts
 * nor reports them as stale component_parts.
 */
/obj/machinery/atom_deconstruct(disassembled = TRUE)
	component_parts = null
	circuit = null
	return ..()

/obj/machinery/atom_destruction(damage_flag)
	playsound(src, 'sound/machines/machine_die_short.ogg', 50, TRUE)
	var/datum/effect/effect/system/spark_spread/sparks = new
	sparks.set_up(5, 0, src)
	sparks.start()
	qdel(sparks)
	return ..()

/**
 * The one machinery break (damage.md §6). Sets BROKEN, sends COMSIG_MACHINERY_BROKEN
 * and publishes REACT_KEY_MACHINE_BROKEN. Returns TRUE if the machine was not
 * already broken. Subtypes with real behaviour call this first and act on the
 * result; an override that only sets flags is forbidden (tools/ci/check_breakpoints.sh).
 */
/obj/machinery/atom_break(damage_flag)
	. = ..()
	if(stat & BROKEN)
		return FALSE
	stat |= BROKEN
	SEND_SIGNAL(src, COMSIG_MACHINERY_BROKEN, damage_flag)
	REACT_PUBLISH_OWN(src, REACT_KEY_MACHINE_BROKEN, REACT_KEY_CHANGED)
	update_icon()
	return TRUE

/// The inverse of atom_break(). Returns TRUE if the machine was broken.
/obj/machinery/atom_fix()
	. = ..()
	if(!(stat & BROKEN))
		return FALSE
	stat &= ~BROKEN
	REACT_PUBLISH_OWN(src, REACT_KEY_MACHINE_BROKEN, REACT_KEY_CHANGED)
	update_icon()
	return TRUE

// --- Sleeping on DM-owned keys (reactor.md §4, S2) ----------------------------------------------

/obj/machinery
	/// While asleep on keys: the (token, kind) pairs from SSreactor.sleep_on_keys().
	var/tmp/list/react_sleep_tokens

/**
 * Stops polling until any key in `keys` (a flat list of (kind, id, mask) triples) is published.
 * Replaces any keys the machine already slept on. The wake arrives through on_react() at the
 * next reactor step, so a publication after this call (even in the same tick) is never missed.
 */
/obj/machinery/proc/sleep_until_keys(list/keys)
	cancel_sleep_keys()
	if(QDELETED(src) || !length(keys))
		return FALSE
	react_sleep_tokens = SSreactor.sleep_on_keys(src, keys)
	STOP_MACHINE_PROCESSING(src)
	return TRUE

/obj/machinery/proc/cancel_sleep_keys()
	if(react_sleep_tokens)
		SSreactor.cancel_keys(src, react_sleep_tokens)
		react_sleep_tokens = null

/// TRUE while the machine sleeps on keys and is not polled.
/obj/machinery/proc/asleep_on_keys()
	return react_sleep_tokens && !(datum_flags & DF_ISPROCESSING)

/obj/machinery/on_react(reason, source, source_kind)
	if((reason & REACT_REASON_KEY) && react_sleep_tokens)
		cancel_sleep_keys()
		START_MACHINE_PROCESSING(src)
