/obj/machinery/portable_atmospherics
	material_template = /datum/material_template/pressure
	material_total = 2 * SHEET_MATERIAL_AMOUNT
	name = "atmoalter"
	use_power = USE_POWER_OFF
	layer = OBJ_LAYER // These are mobile, best not be under everything.
	var/datum/gas_mixture/air_contents

	var/obj/machinery/atmospherics/portables_connector/connected_port
	var/obj/item/tank/holding

	var/volume = 0
	var/destroyed = 0
	var/sleeping_mixture_id

	var/start_pressure = ONE_ATMOSPHERE
	var/maximum_pressure = 90 * ONE_ATMOSPHERE

/obj/machinery/portable_atmospherics/Initialize(mapload)
	..()
	air_contents = new
	air_contents.set_volume(volume)
	air_contents.set_temperature(T20C)
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/portable_atmospherics/LateInitialize()
	var/obj/machinery/atmospherics/portables_connector/port = locate() in loc
	if(port)
		connect(port)
		update_icon()

/obj/machinery/portable_atmospherics/Destroy()
	clear_gas_dependency()
	QDEL_NULL(air_contents)
	QDEL_NULL(holding)
	return ..()

/obj/machinery/portable_atmospherics/process()
	if(!connected_port) //only react when pipe_network will ont it do it for you
		//Allow for reactions
		return air_contents.react(src)
	else
		update_icon()
	return NO_REACTION

/obj/machinery/portable_atmospherics/proc/hibernate_until_gas_changes()
	var/datum/weakref/WR = WEAKREF(src)
	sleeping_mixture_id = air_contents?.arena_id()
	if(isnull(sleeping_mixture_id))
		return
	SSmachines.sleeping_gas_devices[WR.reference] = WR
	SSmachines.subscribe_gas_dependency(sleeping_mixture_id, WR)
	STOP_MACHINE_PROCESSING(src)

/obj/machinery/portable_atmospherics/proc/clear_gas_dependency()
	var/datum/weakref/WR = WEAKREF(src)
	var/ref_key = WR?.reference
	if(isnull(sleeping_mixture_id))
		if(ref_key)
			SSmachines.sleeping_gas_devices.Remove(ref_key)
		return
	if(WR)
		SSmachines.unsubscribe_gas_dependency(sleeping_mixture_id, WR)
	sleeping_mixture_id = null
	if(ref_key)
		SSmachines.sleeping_gas_devices.Remove(ref_key)

/obj/machinery/portable_atmospherics/gas_dependency_changed(mixture_id, change_mask)
	if(!(change_mask & GAS_DEPENDENCY_ALL))
		return FALSE
	// A queued notification can race an explicit wake, which clears the local
	// capture before the old subscriber entry is drained. Treat that stale entry
	// as actionable so wake_gas_subscriber can clean it; rejecting it strands the
	// portable asleep until another unrelated mutation.
	return isnull(sleeping_mixture_id) || mixture_id == sleeping_mixture_id

/obj/machinery/portable_atmospherics/blob_act()
	qdel(src)

/obj/machinery/portable_atmospherics/proc/StandardAirMix()
	return list(
		GAS_O2 = O2STANDARD * MolesForPressure(),
		GAS_N2 = N2STANDARD *  MolesForPressure())

/obj/machinery/portable_atmospherics/proc/MolesForPressure(target_pressure = start_pressure)
	return (target_pressure * air_contents.return_volume()) / (R_IDEAL_GAS_EQUATION * air_contents.return_temperature())

/obj/machinery/portable_atmospherics/port_network_air()
	return air_contents

/obj/machinery/portable_atmospherics/set_port_network_air(datum/gas_mixture/new_air)
	air_contents = new_air
	return TRUE

/obj/machinery/portable_atmospherics/update_icon()
	return null

/obj/machinery/portable_atmospherics/proc/connect(obj/machinery/atmospherics/portables_connector/new_port)
	//Make sure not already connected to something else
	if(connected_port || !new_port || new_port.connected_device)
		return 0

	//Make sure are close enough for a valid connection
	if(new_port.loc != loc)
		return 0

	//Perform the connection
	connected_port = new_port
	clear_gas_dependency()
	START_MACHINE_PROCESSING(src)
	connected_port.connected_device = src
	connected_port.on = 1 //Activate port updates
	START_MACHINE_PROCESSING(connected_port)

	anchored = TRUE //Prevent movement

	//Actually enforce the air sharing
	connected_port.rust_attach_external_device(src)

	return 1

/obj/machinery/portable_atmospherics/proc/disconnect()
	if(!connected_port)
		return 0

	connected_port.rust_detach_external_device()

	anchored = FALSE

	var/obj/machinery/atmospherics/portables_connector/old_port = connected_port
	old_port.connected_device = null
	old_port.on = 0
	STOP_MACHINE_PROCESSING(old_port)
	connected_port = null
	START_MACHINE_PROCESSING(src)

	return 1

/obj/machinery/portable_atmospherics/proc/update_connected_network()
	if(!connected_port)
		return

	var/datum/pipe_network/network = connected_port.return_network(src)
	if (network)
		network.mark_dirty()

/obj/machinery/portable_atmospherics/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/portable_atmos_insert_tank,
	)
	..()

/// The old attackby's tank branch: `istype(W, /obj/item/tank) && !destroyed`.
/datum/interaction/machine_item/portable_atmos_insert_tank
	id = "portable_atmos_insert_tank"
	name = "Insert tank"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item/tank
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/portable_atmospherics/proc/not_destroyed, null))
	effect = /obj/machinery/portable_atmospherics/proc/interaction_insert_tank

/obj/machinery/portable_atmospherics/proc/not_destroyed(mob/actor, atom/target, obj/item/held)
	return !destroyed

/obj/machinery/portable_atmospherics/proc/interaction_insert_tank(mob/user, obj/item/W, datum/interaction/interaction)
	if(holding)
		return TRUE
	var/obj/item/tank/T = W
	user.drop_item()
	T.loc = src
	holding = T
	update_icon()
	return TRUE

/obj/machinery/portable_atmospherics/wrench_act(mob/user, obj/item/tool)
	if(destroyed)
		return ITEM_INTERACT_BLOCKING
	if(connected_port)
		disconnect()
		to_chat(user, span_notice("You disconnect \the [src] from the port."))
		update_icon()
		playsound(src, tool.usesound, 50, TRUE)
		return ITEM_INTERACT_SUCCESS
	var/obj/machinery/atmospherics/portables_connector/possible_port = locate(/obj/machinery/atmospherics/portables_connector) in loc
	if(!possible_port)
		to_chat(user, span_notice("Nothing happens."))
		return ITEM_INTERACT_BLOCKING
	if(!connect(possible_port))
		to_chat(user, span_notice("\The [src] failed to connect to the port."))
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You connect \the [src] to the port."))
	update_icon()
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS



/obj/machinery/portable_atmospherics/powered
	material_template = /datum/material_template/pump
	material_total = 5 * SHEET_MATERIAL_AMOUNT
	var/power_rating
	var/power_losses
	var/last_power_draw = 0
	var/obj/item/cell/cell
	var/use_cell = TRUE
	var/removeable_cell = TRUE

/obj/machinery/portable_atmospherics/powered/powered()
	if(use_power) //using area power
		return ..()
	if(cell && cell.charge)
		return 1
	return 0

/obj/machinery/portable_atmospherics/powered/Initialize(mapload)
	. = ..()

/obj/machinery/portable_atmospherics/powered/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/portable_atmos_insert_cell,
	)
	..()

/// The old attackby's cell branch, before it fell to `..()` (the tank branch).
/datum/interaction/machine_item/portable_atmos_insert_cell
	id = "portable_atmos_insert_cell"
	name = "Insert power cell"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item/cell
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/portable_atmospherics/powered/proc/wants_cell, null))
	effect = /obj/machinery/portable_atmospherics/powered/proc/interaction_insert_cell

/obj/machinery/portable_atmospherics/powered/proc/wants_cell(mob/actor, atom/target, obj/item/held)
	return use_cell

/obj/machinery/portable_atmospherics/powered/proc/interaction_insert_cell(mob/user, obj/item/I, datum/interaction/interaction)
	if(cell)
		to_chat(user, "There is already a power cell installed.")
		return TRUE

	var/obj/item/cell/C = I

	user.drop_item()
	C.add_fingerprint(user)
	cell = C
	C.loc = src
	user.visible_message(span_notice("[user] opens the panel on [src] and inserts [C]."), span_notice("You open the panel on [src] and insert [C]."))
	power_change()
	return TRUE

/obj/machinery/portable_atmospherics/powered/screwdriver_act(mob/user, obj/item/tool)
	if(!removeable_cell)
		return ITEM_INTERACT_BLOCKING
	if(!cell)
		to_chat(user, span_warning("There is no power cell installed."))
		return ITEM_INTERACT_BLOCKING
	user.visible_message(span_notice("[user] opens the panel on [src] and removes [cell]."), span_notice("You open the panel on [src] and remove [cell]."))
	playsound(src, tool.usesound, 50, TRUE)
	cell.add_fingerprint(user)
	cell.forceMove(loc)
	cell = null
	power_change()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/portable_atmospherics/proc/log_open()
	// was iterating XGM `air_contents.gas` (string-id dict).
	// gas_ids() returns the same string IDs under LINDA.
	var/list/gas_id_list = air_contents.gas_ids()
	if(!length(gas_id_list))
		return

	var/gases = ""
	for(var/gas in gas_id_list)
		if(gases)
			gases += ", [gas]"
		else
			gases = gas
	log_admin("[usr] ([usr.ckey]) opened '[src.name]' containing [gases].")
	message_admins("[usr] ([usr.ckey]) opened '[src.name]' containing [gases].")
