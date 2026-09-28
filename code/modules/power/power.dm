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
	/// The Rust power region this machine's node is on (polled, not pushed;
	/// power_grid.dm), or 0.
	var/power_region = 0
	use_power = USE_POWER_OFF
	idle_power_usage = 0
	active_power_usage = 0
	/// Persistent supply registered with set_power_supply() (W). Every
	/// `/obj/machinery/power` is a `Producer` (verdigris/domains/power);
	/// most never set a nonzero supply, which costs nothing.
	var/power_supply_rate = 0

REGISTRY_MEMBERSHIP(/obj/machinery/power, REGISTRY_POWER_MACHINES)

/obj/machinery/power/Initialize(mapload)
	. = ..()

/// `on_materialize()` (not `Initialize()`): joining the knot cables on this
/// machine's turf is a world registration (a network join, exactly the
/// class `atom_materialize.dm` documents), and needs `vg_entity` bound --
/// `vg_bind()` runs earlier in the same `on_materialize()` chain
/// (`/atom/movable/on_materialize()`, `code/game/atoms_movable.dm`),
/// `Initialize()` runs strictly before either. Calling this from
/// `Initialize()` sent every anchored power machine's node with
/// `vg_entity` still `0` -- `vg_power_bind_machine` correctly refused it
/// (`entity handle 0 is not bound`), so the node was silently never placed.
/obj/machinery/power/on_materialize()
	. = ..()
	power_autoconnect()

/// An anchored power machine joins the knot cables on its turf.
/obj/machinery/power/proc/power_autoconnect()
	if(anchored && power_turf())
		connect_to_network(FALSE)

/// The turf this machine's node sits on.
/obj/machinery/power/proc/power_turf()
	return isturf(loc) ? loc : null

/// Phase 1 (unbind): the machine's power node leaves its network.
/obj/machinery/power/lifecycle_unbind()
	. = ..()
	disconnect_from_network()

///////////////////////////////
// General procedures
//////////////////////////////

// common helper procs for all power machines
/obj/machinery/power/drain_power(drain_check, surge, amount = 0)
	if(drain_check)
		return 1

	if(power_region && power_avail(power_region))
		power_warn(power_region)
		return power_draw(power_region, amount, src)

/// Supply for the next power step only (pulse sources: coils, collectors,
/// fusion). A producer that runs every tick calls it every tick, as before.
/obj/machinery/power/proc/add_avail(amount)
	if(!power_region || amount <= 0 || !vg_entity)
		return FALSE
	set_pulse(amount)
	return TRUE

/// A persistent supply rate (W): it stays until changed, so a steady
/// generator can sleep. Repeating the same rate is free.
/obj/machinery/power/proc/set_power_supply(amount)
	amount = max(amount, 0)
	if(amount == power_supply_rate)
		return
	power_supply_rate = amount
	if(vg_entity)
		set_supply(amount)

/obj/machinery/power/proc/clear_power_supply()
	set_power_supply(0)

/obj/machinery/power/proc/draw_power(amount)
	return power_draw(power_region, amount, src)

/obj/machinery/power/proc/surplus()
	return power_netexcess(power_region)

/obj/machinery/power/proc/avail()
	return power_avail(power_region)

/obj/machinery/power/proc/viewload()
	return power_view_load(power_region)

/obj/machinery/power/proc/disconnect_terminal(obj/machinery/power/terminal/term) // machines without a terminal will just return, no harm no fowl.
	return

/// Registers the machine as a node on its turf; it joins every knot cable
/// there. Returns TRUE when that put it on a network. Without `bind_now` the
/// next power step binds it (map load).
/obj/machinery/power/proc/connect_to_network(bind_now = TRUE)
	if(power_region && vg_entity)
		return TRUE
	if(!power_send_node())
		return FALSE
	if(bind_now)
		power_bind_now()
	return !!power_region

/// Sends this machine's node (its turf) to Rust; it joins the knots there.
/// A no-op (not an error) before `vg_entity` exists: several subtypes call
/// `connect_to_network()` straight from their own `Initialize()`, which
/// runs before `on_materialize()`'s `vg_bind()` mints it (`rust_
/// architecture.md`'s Initialize/on_materialize split, this proc's own
/// base-class docs). The base class's `on_materialize()` calls
/// `power_autoconnect()` after `vg_bind()` regardless, so every anchored
/// machine still gets its node sent once `vg_entity` is real -- an early
/// call here just has nothing to do yet.
/obj/machinery/power/proc/power_send_node()
	var/turf/T = power_turf()
	if(!istype(T))
		return FALSE
	if(!vg_entity)
		return FALSE
	vg_power_bind_machine(vg_entity, T.x, T.y, T.z)
	if(power_supply_rate)
		set_supply(power_supply_rate)
	power_registered()
	return TRUE

/// Hook: the node was (re)sent to Rust; storage machines resend their state.
/obj/machinery/power/proc/power_registered()
	return

/// Binds to the current region at once (the step would do it anyway).
/obj/machinery/power/proc/power_bind_now()
	vg_power_commit()
	power_refresh_network()

/// Re-reads which region (if any) this machine's node is on right now and
/// updates `power_region` if it changed. A machine alone on its own singleton
/// region (no cable reached it) reads as unconnected, as before.
/obj/machinery/power/proc/power_refresh_network()
	var/id = vg_entity ? vg_power_region_of(vg_entity) : 0
	var/connected = id && length(vg_power_region_members(id)) > 1
	power_bind(connected ? id : 0)

/// Leaves the network and removes the node.
/obj/machinery/power/proc/disconnect_from_network()
	if(!vg_entity)
		return FALSE
	vg_power_unbind_node(vg_entity)
	var/was = !!power_region
	power_bind(0)
	return was

/// The machine's node is (or isn't) on region `region_id` now.
/obj/machinery/power/proc/power_bind(region_id)
	if(region_id == power_region)
		// Still re-join a grid list reset under us (admin re-register).
		if(region_id && !(src in power_grid_nodes(region_id)))
			power_grid_move_node(src, 0, region_id)
		return
	var/old = power_region
	power_region = region_id
	power_grid_move_node(src, old, region_id)
	power_network_changed(old, region_id)

/// Hook: the machine moved to another network (or off one).
/obj/machinery/power/proc/power_network_changed(old_region, new_region)
	return

// attach a wire to a power machine - leads from the turf you are standing on
//almost never called, overwritten by all power machines but terminal and generator
/obj/machinery/power/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/power_cable_place,
	)
	..()

/datum/interaction/machine_item/power_cable_place
	id = "power_cable_place"
	name = "Lay cable"
	held_type = /obj/item/stack/cable_coil
	effect = /obj/machinery/power/proc/interaction_cable_place

/obj/machinery/power/proc/interaction_cable_place(mob/user, obj/item/stack/cable_coil/coil, datum/interaction/interaction)
	var/turf/T = user.loc

	if(!T.is_plating() || !istype(T, /turf/simulated/floor))
		return TRUE

	if(get_dist(src, user) > 1)
		return TRUE

	coil.turf_place(T, user)
	return TRUE

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
//power_source is a source of electricity, can be powercell, area, apc, cable, a power machine, a power region id or null
//source is an object caused electrocuting (airlock, grille, etc)
//No animations will be performed by this proc.
/proc/electrocute_mob(mob/living/M as mob, power_source, obj/source, siemens_coeff = 1.0)
	if(istype(M.loc,/obj/mecha))	return 0	//feckin mechs are dumb
	if(issilicon(M))	return 0	//No more robot shocks from machinery
	var/area/source_area
	if(istype(power_source,/area))
		source_area = power_source
		power_source = source_area.get_apc()
	var/region = 0
	var/obj/item/cell/cell
	if(istype(power_source,/obj/structure/cable))
		var/obj/structure/cable/Cable = power_source
		region = Cable.get_power_region()
	else if(istype(power_source,/obj/machinery/power))
		var/obj/machinery/power/P = power_source
		if(istype(P, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/apc = P
			cell = apc.cell
			region = apc.terminal?.power_region
		else
			region = P.power_region
	else if(istype(power_source,/obj/item/cell))
		cell = power_source
	else if(isnum(power_source))
		region = power_source
	else if (!power_source)
		return 0
	else
		log_admin("ERROR: /proc/electrocute_mob([M], [power_source], [source]): wrong power_source")
		return 0
	//Triggers a grid warning, but only for 5 ticks (if applicable)
	//If following checks determine user is protected we won't alarm for long.
	if(region)
		power_warn(region, 5)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.species.siemens_coefficient <= 0)
			return
		if(H.get_equipped_item(SLOT_ID_GLOVES))
			var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
			if(G.siemens_coefficient == 0)	return 0		//to avoid spamming with insulated glvoes on
	//Checks again. If we are still here subject will be shocked, trigger standard 20 tick warning
	//Since this one is longer it will override the original one.
	if(region)
		power_warn(region)

	if (!cell && !region)
		return 0
	var/PN_damage = region ? power_electrocute_damage(region) : 0
	var/cell_damage = cell ? cell.get_electrocute_damage() : 0
	var/shock_damage = 0
	var/from_grid = FALSE
	if (PN_damage>=cell_damage)
		from_grid = TRUE
		shock_damage = PN_damage
	else
		shock_damage = cell_damage
	var/drained_hp = M.electrocute_act(shock_damage, source, siemens_coeff) //zzzzzzap!
	var/drained_energy = drained_hp*20

	if (source_area)
		source_area.use_power_oneoff(drained_energy/CELLRATE, EQUIP)
	else if (from_grid && region)
		power_draw(region, drained_energy/CELLRATE)
	else if (cell)
		cell.use(drained_energy)
	return drained_energy
