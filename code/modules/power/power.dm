//////////////////////////////
// POWER MACHINERY BASE CLASS
//////////////////////////////

/////////////////////////////
// Definitions
/////////////////////////////

/obj/machinery/power
	name = null
	icon = 'icons/obj/power.dmi'
	anchored = TRUE
	/// The network this machine is on (bound by the Rust power step), or null.
	var/datum/powernet/powernet = null
	use_power = USE_POWER_OFF
	idle_power_usage = 0
	active_power_usage = 0
	/// This machine's key in the Rust power domain (0: not registered).
	var/power_key = 0
	/// Persistent supply registered with set_power_supply() (W).
	var/power_supply_rate = 0

/obj/machinery/power/Initialize(mapload)
	. = ..()
	power_autoconnect()

/// An anchored power machine joins the knot cables on its turf.
/obj/machinery/power/proc/power_autoconnect()
	if(anchored && power_turf())
		connect_to_network(FALSE)

/// The turf this machine's node sits on.
/obj/machinery/power/proc/power_turf()
	return isturf(loc) ? loc : null

/obj/machinery/power/Destroy()
	disconnect_from_network()
	if(power_key)
		power_key_free(power_key)
		power_key = 0
	return ..()

///////////////////////////////
// General procedures
//////////////////////////////

// common helper procs for all power machines
/obj/machinery/power/drain_power(drain_check, surge, amount = 0)
	if(drain_check)
		return 1

	if(powernet && powernet.avail)
		powernet.trigger_warning()
		return powernet.draw_power(amount, src)

/// Supply for the next power step only (pulse sources: coils, collectors,
/// fusion). A producer that runs every tick calls it every tick, as before.
/obj/machinery/power/proc/add_avail(amount)
	if(!powernet || amount <= 0)
		return FALSE
	SSmachines.power_queue(list(POWER_OP_PULSE, 2, power_key, amount))
	return TRUE

/// A persistent supply rate (W): it stays until changed, so a steady
/// generator can sleep. Repeating the same rate is free.
/obj/machinery/power/proc/set_power_supply(amount)
	amount = max(amount, 0)
	if(amount == power_supply_rate)
		return
	power_supply_rate = amount
	if(!power_key)
		power_key = power_key_alloc(src)
	SSmachines.power_queue(list(POWER_OP_SUPPLY, 2, power_key, amount))

/obj/machinery/power/proc/clear_power_supply()
	set_power_supply(0)

/obj/machinery/power/proc/draw_power(amount)
	if(powernet)
		return powernet.draw_power(amount, src)
	return 0

/obj/machinery/power/proc/surplus()
	if(powernet)
		return powernet.avail-powernet.load
	else
		return 0

/obj/machinery/power/proc/avail()
	if(powernet)
		return powernet.avail
	else
		return 0

/obj/machinery/power/proc/viewload()
	if(powernet)
		return powernet.viewload
	else
		return 0

/obj/machinery/power/proc/disconnect_terminal(obj/machinery/power/terminal/term) // machines without a terminal will just return, no harm no fowl.
	return

/// Registers the machine as a node on its turf; it joins every knot cable
/// there. Returns TRUE when that put it on a network. Without `bind_now` the
/// next power step binds it (map load).
/obj/machinery/power/proc/connect_to_network(bind_now = TRUE)
	if(powernet && power_key)
		return TRUE
	if(!power_send_node())
		return FALSE
	if(bind_now)
		power_bind_now()
	return !!powernet

/// Sends this machine's node (its turf) to Rust; it joins the knots there.
/obj/machinery/power/proc/power_send_node()
	var/turf/T = power_turf()
	if(!istype(T))
		return FALSE
	if(!power_key)
		power_key = power_key_alloc(src)
	SSmachines.power_queue(list(POWER_OP_MACHINE, 4, power_key, T.x, T.y, T.z))
	if(power_supply_rate)
		SSmachines.power_queue(list(POWER_OP_SUPPLY, 2, power_key, power_supply_rate))
	power_registered()
	return TRUE

/// Hook: the node was (re)sent to Rust; storage machines resend their state.
/obj/machinery/power/proc/power_registered()
	return

/// Binds to the current region at once (the step would do it anyway).
/obj/machinery/power/proc/power_bind_now()
	var/datum/powernet/network = SSmachines.power_region_of(power_key)
	power_bind(network?.region_id || 0, network ? 2 : 0)

/// Leaves the network and removes the node.
/obj/machinery/power/proc/disconnect_from_network()
	if(!power_key)
		return FALSE
	SSmachines.power_queue(list(POWER_OP_REMOVE, 1, power_key))
	var/was = !!powernet
	power_bind(0, 0)
	return was

/// The Rust step (or a connect) put this machine on region `region_id`.
/obj/machinery/power/proc/power_bind(region_id, members)
	var/datum/powernet/network = (region_id && members > 1) ? SSmachines.power_facade(region_id, power_key) : null
	if(network == powernet)
		return
	var/datum/powernet/old = powernet
	powernet = network
	old?.unbind_machine(src)
	network?.bind_machine(src)
	power_network_changed(old, network)

/// Hook: the machine moved to another network (or off one).
/obj/machinery/power/proc/power_network_changed(datum/powernet/old, datum/powernet/network)
	return

// attach a wire to a power machine - leads from the turf you are standing on
//almost never called, overwritten by all power machines but terminal and generator
/obj/machinery/power/attackby(obj/item/W, mob/user)

	if(istype(W, /obj/item/stack/cable_coil))

		var/obj/item/stack/cable_coil/coil = W

		var/turf/T = user.loc

		if(!T.is_plating() || !istype(T, /turf/simulated/floor))
			return

		if(get_dist(src, user) > 1)
			return

		coil.turf_place(T, user)
		return
	else
		..()
	return

// Power machinery should also connect/disconnect from the network.
/obj/machinery/power/wrench_act(mob/user, obj/item/W)
	if((. = ..()))
		if(anchored)
			connect_to_network()
		else
			disconnect_from_network()

// Used for power spikes by the engine, has specific effects on different machines.
/obj/machinery/power/proc/overload(obj/machinery/power/source)
	return

// Used by the grid checker upon receiving a power spike.
/obj/machinery/power/proc/do_grid_check()
	return

/obj/machinery/power/proc/power_spike()
	return

//Determines how strong could be shock, deals damage to mob, uses power.
//M is a mob who touched wire/whatever
//power_source is a source of electricity, can be powercell, area, apc, cable, powernet or null
//source is an object caused electrocuting (airlock, grille, etc)
//No animations will be performed by this proc.
/proc/electrocute_mob(mob/living/M as mob, power_source, obj/source, siemens_coeff = 1.0)
	if(istype(M.loc,/obj/mecha))	return 0	//feckin mechs are dumb
	if(issilicon(M))	return 0	//No more robot shocks from machinery
	var/area/source_area
	if(istype(power_source,/area))
		source_area = power_source
		power_source = source_area.get_apc()
	if(istype(power_source,/obj/structure/cable))
		var/obj/structure/cable/Cable = power_source
		power_source = Cable.get_powernet()

	var/datum/powernet/PN
	var/obj/item/cell/cell

	if(istype(power_source,/datum/powernet))
		PN = power_source
	else if(istype(power_source,/obj/item/cell))
		cell = power_source
	else if(istype(power_source,/obj/machinery/power/apc))
		var/obj/machinery/power/apc/apc = power_source
		cell = apc.cell
		if (apc.terminal)
			PN = apc.terminal.powernet
	else if (!power_source)
		return 0
	else
		log_admin("ERROR: /proc/electrocute_mob([M], [power_source], [source]): wrong power_source")
		return 0
	//Triggers powernet warning, but only for 5 ticks (if applicable)
	//If following checks determine user is protected we won't alarm for long.
	if(PN)
		PN.trigger_warning(5)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.species.siemens_coefficient <= 0)
			return
		if(H.get_equipped_item(SLOT_ID_GLOVES))
			var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
			if(G.siemens_coefficient == 0)	return 0		//to avoid spamming with insulated glvoes on
/*Phorochem removed.
//Phorochemistry DM: Allows chemicalresistant shocking -Radiantflash
		for(var/datum/reagent/phororeagent/R in M.reagents.reagent_list)
			if(R.id == REAGENT_ID_FULGURACIN)
				to_chat(M, span_notice("Your hairs stand up, but you resist the shock for the most part"))
				return 0 //no shock for you
*/
	//Checks again. If we are still here subject will be shocked, trigger standard 20 tick warning
	//Since this one is longer it will override the original one.
	if(PN)
		PN.trigger_warning()

	if (!cell && !PN)
		return 0
	var/PN_damage = 0
	var/cell_damage = 0
	if (PN)
		PN_damage = PN.get_electrocute_damage()
	if (cell)
		cell_damage = cell.get_electrocute_damage()
	var/shock_damage = 0
	if (PN_damage>=cell_damage)
		power_source = PN
		shock_damage = PN_damage
	else
		power_source = cell
		shock_damage = cell_damage
	var/drained_hp = M.electrocute_act(shock_damage, source, siemens_coeff) //zzzzzzap!
	var/drained_energy = drained_hp*20

	if (source_area)
		source_area.use_power_oneoff(drained_energy/CELLRATE, EQUIP)
	else if (istype(power_source,/datum/powernet))
		var/drained_power = drained_energy/CELLRATE
		drained_power = PN.draw_power(drained_power)
	else if (istype(power_source, /obj/item/cell))
		cell.use(drained_energy)
	return drained_energy
