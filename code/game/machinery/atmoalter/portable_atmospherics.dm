// A portable atmospherics machine (a canister, a portable pump or scrubber, a hydroponics tray, a distillery): its own gas, a tank bay, and the port
// under it a wrench connects it to.

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

	var/start_pressure = ONE_ATMOSPHERE
	var/maximum_pressure = 90 * ONE_ATMOSPHERE

TRACKED(/obj/machinery/portable_atmospherics, destroyed)

MSG_DEF_SELF(portable/no_port, "Nothing happens.")
MSG_DEF_SELF(portable/wrecked, "It is wrecked.")
MSG_DEF_SELF(portable/port_taken, "It failed to connect to the port.")
MSG_DEF(portable/connected, "You connect %T% to the port.", "%U% connects %T% to the port.")
MSG_DEF(portable/disconnected, "You disconnect %T% from the port.", "%U% disconnects %T% from the port.")

CAPABILITIES(/obj/machinery/portable_atmospherics)
	after_init(0, then(PROC_REF(port_after_init)))
	owns_one(nameof(air_contents), on_destroy = ON_DESTROY_PRIVATE_COPY)
	owns_one(nameof(holding), /obj/item/tank)
	ref_one(nameof(connected_port), /obj/machinery/atmospherics/portables_connector)
	tank_bay(nameof(holding), when = req(PROC_REF(not_destroyed)))
	op("port", tool(TOOL_WRENCH), label("Connect to the port"), wait(0), when(PROC_REF(port_wrench_offered)),
		needs(req(PROC_REF(not_destroyed), because = MSG(portable/wrecked)), req(PROC_REF(port_reachable), because = MSG(portable/no_port)), req(PROC_REF(port_free), because = MSG(portable/port_taken))),
		says(PROC_REF(port_message)), then(PROC_REF(port_wrenched)))
	extend(/datum/act/hit/blob, instead(then(PROC_REF(blob_bursts))))

/obj/machinery/portable_atmospherics/Initialize(mapload)
	. = ..()
	atmos_air_set(src, nameof(air_contents), new /datum/gas_mixture)
	air_contents.set_volume(volume)
	heat_set(air_contents, T20C)

/// Connects to a port on its turf, once the pipes exist.
/obj/machinery/portable_atmospherics/proc/port_after_init(datum/act/timer/A)
	var/obj/machinery/atmospherics/portables_connector/port = locate_within(loc, /obj/machinery/atmospherics/portables_connector)
	if(port)
		connect(port)

/// The machine's own gas reacts while it stands alone (a connected one's gas is the pipe network's, which reacts there). NO_REACTION when nothing did.
/obj/machinery/portable_atmospherics/proc/react_or_update()
	if(connected_port())
		return NO_REACTION
	return air_contents.react(src)

/// A blob bursts a portable canister or pump outright.
/obj/machinery/portable_atmospherics/proc/blob_bursts(datum/act/hit/blob/A)
	destroyed(src, null, "blob") // at once: expire(0) only queued it, so the blob's hit left it standing for the tick
	return TRUE

/obj/machinery/portable_atmospherics/proc/StandardAirMix()
	return list(
		GAS_O2 = O2STANDARD * MolesForPressure(),
		GAS_N2 = N2STANDARD *  MolesForPressure())

/obj/machinery/portable_atmospherics/proc/MolesForPressure(target_pressure = start_pressure)
	return (target_pressure * air_contents.return_volume()) / (R_IDEAL_GAS_EQUATION * air_contents.return_temperature())

/obj/machinery/portable_atmospherics/port_network_air()
	return air_contents

/obj/machinery/portable_atmospherics/set_port_network_air(datum/gas_mixture/new_air)
	atmos_air_set(src, nameof(air_contents), new_air)
	return TRUE

/obj/machinery/portable_atmospherics/proc/connect(obj/machinery/atmospherics/portables_connector/new_port)
	//Make sure not already connected to something else
	if(connected_port() || !new_port || new_port.connected_device)
		return 0

	//Make sure are close enough for a valid connection
	if(new_port.loc != loc)
		return 0

	//Perform the connection
	rel_set(src, nameof(connected_port), new_port)
	connected_port().connected_device = src
	connected_port().set_on(1)

	set_anchored(TRUE) //Prevent movement

	//Actually enforce the air sharing
	connected_port().rust_attach_external_device(src)
	return 1

/obj/machinery/portable_atmospherics/proc/disconnect()
	if(!connected_port())
		return 0

	connected_port().rust_detach_external_device()

	set_anchored(FALSE)

	var/obj/machinery/atmospherics/portables_connector/old_port = connected_port()
	rel_clear(old_port, nameof(old_port.connected_device))
	old_port.set_on(0)
	rel_clear(src, nameof(connected_port))
	return 1

/// Its gas was changed in place (a pump or a scrubber at work): the pipe network it shares the gas with hears it.
/obj/machinery/portable_atmospherics/proc/update_connected_network()
	if(connected_port())
		gas_touched(air_contents)

// ---- the port and the bay ----

/// Not wrecked: it takes a tank, a wrench.
/obj/machinery/portable_atmospherics/proc/not_destroyed(datum/act/A)
	return (!destroyed) ? null : MSG(portable/wrecked)

/// The wrench means the port on this machine (a tray that bolts itself down says otherwise when it has no port).
/obj/machinery/portable_atmospherics/proc/port_wrench_offered(datum/act/op/A)
	return TRUE

/// Connected, or a port stands under it.
/obj/machinery/portable_atmospherics/proc/port_reachable(datum/act/op/A)
	return (connected_port() || locate_within(loc, /obj/machinery/atmospherics/portables_connector)) ? null : MSG(portable/no_port) // ALLOW(reads): asked when the wrench is used, never from a cached menu

/// Connected, or the port under it has no device yet.
/obj/machinery/portable_atmospherics/proc/port_free(datum/act/op/A)
	if(connected_port())
		return null
	var/obj/machinery/atmospherics/portables_connector/port = locate_within(loc, /obj/machinery/atmospherics/portables_connector) // ALLOW(reads): asked when the wrench is used, never from a cached menu
	return (port && !port.connected_device) ? null : MSG(portable/port_taken)

/obj/machinery/portable_atmospherics/proc/port_message(datum/act/A)
	return connected_port() ? /datum/msg/portable/connected : /datum/msg/portable/disconnected

/// The wrench connects it to the port under it, or disconnects it.
/obj/machinery/portable_atmospherics/proc/port_wrenched(datum/act/op/A)
	if(connected_port())
		disconnect()
	else
		connect(locate_within(loc, /obj/machinery/atmospherics/portables_connector))
	return OP_OK

/obj/machinery/portable_atmospherics/proc/log_open(mob/user)
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
	log_admin("[user] ([user.ckey]) opened '[src.name]' containing [gases].")
	message_admins("[user] ([user.ckey]) opened '[src.name]' containing [gases].")

/// connected port (a relation view: it reads null once the target is deleted).
/obj/machinery/portable_atmospherics/proc/connected_port() as /obj/machinery/atmospherics/portables_connector
	return connected_port

// ---- the powered ones (a portable pump or scrubber, a distillery): a power cell ----

/obj/machinery/portable_atmospherics/powered
	material_template = /datum/material_template/pump
	material_total = 5 * SHEET_MATERIAL_AMOUNT
	var/power_rating
	var/power_losses
	var/last_power_draw = 0
	var/obj/item/cell/cell
	var/use_cell = TRUE
	var/removeable_cell = TRUE

MSG_DEF(portable/cell_in, "You open the panel on %T% and insert %I%.", "%U% opens the panel on %T% and inserts %I%.")
MSG_DEF(portable/cell_out, "You open the panel on %T% and remove the power cell.", "%U% opens the panel on %T% and removes the power cell.")
MSG_DEF_SELF(portable/cell_present, "There is already a power cell installed.")
MSG_DEF_SELF(portable/no_cell, "There is no power cell installed.")

CAPABILITIES(/obj/machinery/portable_atmospherics/powered)
	owns_one(nameof(cell), /obj/item/cell, starts = PROC_REF(starting_cell))
	op("cell_in", item(/obj/item/cell), label("Insert power cell"), wait(0), when(nameof(use_cell)),
		needs(req_empty(nameof(cell), because = MSG(portable/cell_present))), put_in(nameof(cell)), says(MSG(portable/cell_in)), then(PROC_REF(cell_changed)))
	op("cell_out", tool(TOOL_SCREWDRIVER), label("Remove power cell"), when(nameof(removeable_cell)),
		needs(req(PROC_REF(has_cell), because = MSG(portable/no_cell))), says(MSG(portable/cell_out)), then(PROC_REF(take_cell_out)))

/// The cell it comes with (none by default).
/obj/machinery/portable_atmospherics/powered/proc/starting_cell(datum/act/A)
	return null

/obj/machinery/portable_atmospherics/powered/powered()
	if(use_power) //using area power
		return ..()
	if(cell && cell.charge)
		return 1
	return 0

/obj/machinery/portable_atmospherics/powered/proc/has_cell(datum/act/A)
	return (!isnull(cell)) ? null : MSG(portable/no_cell)

/obj/machinery/portable_atmospherics/powered/proc/take_cell_out(datum/act/op/A)
	var/obj/item/cell/C = cell
	C.add_fingerprint(A.actor)
	C.forceMove(loc)
	varslot_set(src, nameof(cell), null)
	return cell_changed(A)

/// A cell went in or came out: the machine's power follows.
/obj/machinery/portable_atmospherics/powered/proc/cell_changed(datum/act/A)
	power_change()
	return OP_OK

// air_contents is a private mixture, or a connected port network's mixture while connected (set_port_network_air()): PROTO.

// ---- a huge portable's controls (huge_portable_controls(), code/game/machinery/atmoalter/pump.dm) ----

/obj/machinery/portable_atmospherics/powered/proc/swallowed(datum/act/op/A)
	return OP_OK

/obj/machinery/portable_atmospherics/powered/proc/is_off(datum/act/A)
	return (!on) ? null : MSG(huge_portable/turn_off)

/// A requirement that never holds (a stationary one's bolts).
/obj/machinery/portable_atmospherics/powered/proc/never(datum/act/A)
	return MSG(huge_portable/bolted)

/obj/machinery/portable_atmospherics/powered/proc/anchor_toggled(datum/act/op/A)
	set_anchored(!anchored)
	return OP_OK

/obj/machinery/portable_atmospherics/powered/proc/anchor_message(datum/act/A)
	return anchored ? /datum/msg/huge_portable/anchored : /datum/msg/huge_portable/unanchored
