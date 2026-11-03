// A docking port (doc/rewrite/proposals/docking_port.md): one entity per docking console, holding the port's airlocks and hatches by
// relation (its console's keyed views of the map's tags) and linked to the port it docks with (`peer`). The handshake is direct calls
// between the two linked ports: nothing is broadcast, resent or filtered, so nothing can be missed.
//
//   client.initiate_docking(tag) -> server.dock_requested()  -> client.dock_accepted()   both: DOCKING, prepare
//   client ready                 -> server.peer_ready_report()
//   server ready and peer ready  -> server DOCKED, finish     -> client.dock_completed()  client: DOCKED, finish
//   client.initiate_undocking()  -> server.undock_requested()                            both: UNDOCKING, prepare
//   client ready                 -> server.peer_ready_report()
//   server ready and peer ready  -> server finish, reset      -> client.undock_completed() client: finish, reset
//   force_undock()               -> peer.dock_error()                                    both reset
//
// The client is the port that asks (the shuttle's); only it can start an undock. The server decides on a request (the docking codes)
// and says when each operation is complete. The override: while it is on, the port does nothing to its airlocks and hatches when docking
// or undocking (no doors opened, no cycle) and waits for the crew to put the port in a state it can undock from by hand.

#define DOCK_UNDOCKED	0
#define DOCK_DOCKING	1
#define DOCK_UNDOCKING	2
#define DOCK_DOCKED		3

#define DOCK_MODE_NONE		0
#define DOCK_MODE_SERVER	1
#define DOCK_MODE_CLIENT	2

/datum/docking_port
	/// The tag shuttles and landmarks name it by (its console's id_tag).
	var/id_tag
	/// The console it runs on: its machine, whose step steps the port and whose relations are the port's airlocks and hatches.
	var/obj/machinery/embedded_controller/radio/console
	/// The port it is docking, docked or undocking with.
	var/datum/docking_port/peer
	var/dock_state = DOCK_UNDOCKED
	var/control_mode = DOCK_MODE_NONE
	/// Client: its ready report went to the server for the operation in flight. Server: the client's ready report came.
	var/ready_reported = FALSE
	/// When on, docking and undocking leave the airlocks and hatches to the crew.
	var/override_enabled = FALSE
	/// A server takes only requests carrying these, when set.
	var/docking_codes
	/// The name on the docking monitor; area and coordinates when unset.
	var/display_name

CAPABILITIES(/datum/docking_port)
	ref_one(nameof(console))
	ref_one(nameof(peer))

/datum/docking_port/New(obj/machinery/embedded_controller/radio/C)
	..()
	rel_set(src, nameof(console), C)
	id_tag = C?.id_tag
	if(id_tag)
		if(SSshuttles.docking_port(id_tag))
			stack_trace("Docking port tag [id_tag] had multiple ports.")
		SSshuttles.register_docking_port(id_tag, src)

/// Phase 2: leaves the shuttle docking registry.
/datum/docking_port/lifecycle_dematerialize()
	. = ..()
	if(id_tag && SSshuttles.docking_port(id_tag) == src)
		SSshuttles.unregister_docking_port(id_tag)

// ---- what the port holds ----

/// The airlocks this port cycles and opens (its console's relations).
/datum/docking_port/proc/airlocks()
	return console ? console.port_airlocks() : list()

/// The hatch doors this port opens and bolts (its console's relations).
/datum/docking_port/proc/hatches()
	return console ? console.port_hatches() : list()

// ---- the handshake ----

/datum/docking_port/proc/set_dock_state(value)
	if(dock_state == value)
		return FALSE
	log_game("Docking [id_tag] ([get_docking_status()] -> state [value], mode [control_mode], peer [peer?.id_tag || "none"])")
	dock_state = value
	tracked_changed(src, nameof(dock_state))
	wake()
	return TRUE
SETTER(/datum/docking_port, dock_state)

/// The port's waits (ready to dock, ready to undock) run in its console's step.
/datum/docking_port/proc/wake()
	if(console)
		work_start(console)

/// Client: asks the port tagged `target` to dock.
/datum/docking_port/proc/initiate_docking(target)
	if(dock_state != DOCK_UNDOCKED || control_mode == DOCK_MODE_SERVER) // must be undocked and not serving another request
		return
	var/datum/docking_port/server = SSshuttles.docking_port(target)
	if(!server || server == src)
		log_game("Docking [id_tag] found no port tagged [target || "none"] to dock with")
		return
	control_mode = DOCK_MODE_CLIENT
	rel_set(src, nameof(peer), server)
	log_game("Docking [id_tag] requests docking with [server.id_tag]")
	server.dock_requested(src, docking_codes)

/// Server: `client` asks to dock. A busy port, or a wrong code, leaves the client waiting (it may ask again).
/datum/docking_port/proc/dock_requested(datum/docking_port/client, code)
	if(control_mode != DOCK_MODE_NONE || dock_state != DOCK_UNDOCKED)
		return
	if(docking_codes && code != docking_codes)
		log_game("Docking [id_tag] refuses [client.id_tag]: wrong docking codes")
		return
	control_mode = DOCK_MODE_SERVER
	ready_reported = FALSE
	rel_set(src, nameof(peer), client)
	set_dock_state(DOCK_DOCKING)
	if(!override_enabled)
		prepare_for_docking()
	client.dock_accepted(src)

/// Client: the server took the request.
/datum/docking_port/proc/dock_accepted(datum/docking_port/server)
	if(control_mode != DOCK_MODE_CLIENT || dock_state != DOCK_UNDOCKED || peer != server)
		return
	ready_reported = FALSE
	set_dock_state(DOCK_DOCKING)
	if(!override_enabled)
		prepare_for_docking()

/// Server: the client is ready for the operation in flight.
/datum/docking_port/proc/peer_ready_report(datum/docking_port/client)
	if(control_mode != DOCK_MODE_SERVER || peer != client || (dock_state != DOCK_DOCKING && dock_state != DOCK_UNDOCKING))
		return
	ready_reported = TRUE
	wake()

/// Client: the server finished docking.
/datum/docking_port/proc/dock_completed(datum/docking_port/server)
	if(control_mode != DOCK_MODE_CLIENT || dock_state != DOCK_DOCKING || peer != server)
		return
	set_dock_state(DOCK_DOCKED)
	if(!override_enabled)
		finish_docking()
	ready_reported = FALSE

/// Client: starts undocking (only the client can).
/datum/docking_port/proc/initiate_undocking()
	if(dock_state != DOCK_DOCKED || control_mode != DOCK_MODE_CLIENT)
		return
	ready_reported = FALSE
	set_dock_state(DOCK_UNDOCKING)
	if(!override_enabled)
		prepare_for_undocking()
	peer?.undock_requested(src)

/// Server: the client is undocking.
/datum/docking_port/proc/undock_requested(datum/docking_port/client)
	if(control_mode != DOCK_MODE_SERVER || dock_state != DOCK_DOCKED || peer != client)
		return
	ready_reported = FALSE
	set_dock_state(DOCK_UNDOCKING)
	if(!override_enabled)
		prepare_for_undocking()

/// Client: the server finished undocking.
/datum/docking_port/proc/undock_completed(datum/docking_port/server)
	if(control_mode != DOCK_MODE_CLIENT || dock_state != DOCK_UNDOCKING || peer != server)
		return
	if(!override_enabled)
		finish_undocking()
	reset()

/// The peer gave up (forced undock, or it found itself in a state it cannot be in).
/datum/docking_port/proc/dock_error(datum/docking_port/from)
	if(peer == from)
		reset()

/// The console's step: the waits of the operation in flight.
/datum/docking_port/proc/handshake_step()
	switch(dock_state)
		if(DOCK_DOCKING)
			if(ready_for_docking())
				if(control_mode == DOCK_MODE_CLIENT)
					if(!ready_reported)
						ready_reported = TRUE
						peer?.peer_ready_report(src)
				else if(control_mode == DOCK_MODE_SERVER && ready_reported)
					ready_reported = FALSE
					set_dock_state(DOCK_DOCKED)
					if(!override_enabled)
						finish_docking()
					peer?.dock_completed(src)
		if(DOCK_UNDOCKING)
			if(!override_enabled)
				keep_hatches_closing()
			if(ready_for_undocking())
				if(control_mode == DOCK_MODE_CLIENT)
					if(!ready_reported)
						ready_reported = TRUE
						peer?.peer_ready_report(src)
				else if(control_mode == DOCK_MODE_SERVER && ready_reported)
					if(!override_enabled)
						finish_undocking()
					var/datum/docking_port/client = peer
					reset()
					client?.undock_completed(src)
	// states it cannot be in: a port with no mode or no peer that is not undocked gives up; an undocked server has no mode
	if(dock_state != DOCK_UNDOCKED && (control_mode == DOCK_MODE_NONE || !peer))
		force_undock()
	if(control_mode == DOCK_MODE_SERVER && dock_state == DOCK_UNDOCKED)
		control_mode = DOCK_MODE_NONE

/// Whether the console keeps stepping for the port: while an operation is in flight.
/datum/docking_port/proc/needs_step()
	return dock_state == DOCK_DOCKING || dock_state == DOCK_UNDOCKING

/datum/docking_port/proc/reset()
	set_dock_state(DOCK_UNDOCKED)
	control_mode = DOCK_MODE_NONE
	rel_set(src, nameof(peer), null)
	ready_reported = FALSE
	for(var/obj/machinery/embedded_controller/radio/airlock/A as anything in airlocks())
		A.undock_finish()

/datum/docking_port/proc/force_undock()
	var/datum/docking_port/was = peer
	reset()
	was?.dock_error(src)

// ---- what docking does to the port's airlocks and hatches ----

/// Getting ready to dock: each airlock cycles in.
/datum/docking_port/proc/prepare_for_docking()
	for(var/obj/machinery/embedded_controller/radio/airlock/A as anything in airlocks())
		A.dock_prepare(src)

/datum/docking_port/proc/ready_for_docking()
	for(var/obj/machinery/embedded_controller/radio/airlock/A as anything in airlocks())
		if(!A.dock_ready())
			return FALSE
	return TRUE

/// Docked: the airlocks open both doors, the hatches open and bolt.
/datum/docking_port/proc/finish_docking()
	for(var/obj/machinery/embedded_controller/radio/airlock/A as anything in airlocks())
		A.dock_finish()
	open_hatches()

/// Getting ready to undock: the airlocks shut and bolt their doors, the hatches close.
/datum/docking_port/proc/prepare_for_undocking()
	for(var/obj/machinery/embedded_controller/radio/airlock/A as anything in airlocks())
		A.undock_prepare()
	close_hatches()

/// Ready to undock: every airlock has a door shut and bolted, every hatch is shut and bolted.
/datum/docking_port/proc/ready_for_undocking()
	for(var/obj/machinery/embedded_controller/radio/airlock/A as anything in airlocks())
		if(!A.undock_ready())
			return FALSE
	return hatches_secured()

/datum/docking_port/proc/finish_undocking()
	for(var/obj/machinery/embedded_controller/radio/airlock/A as anything in airlocks())
		A.undock_finish()

/// An undock asked while a hatch was still swinging open (a pilot launching right after docking) must not wait for a shut hatch forever:
/// while undocking, an open hatch is closed again each step. It is read from the door itself, so it is never a stale report.
/datum/docking_port/proc/keep_hatches_closing()
	for(var/obj/machinery/door/airlock/D as anything in hatches())
		if(!D.density)
			D.airlock_command("secure_close")

/datum/docking_port/proc/open_hatches()
	for(var/obj/machinery/door/airlock/D as anything in hatches())
		if(D.density)
			D.airlock_command("secure_open")
		else if(!is_bolted(D))
			D.airlock_command("lock")

/datum/docking_port/proc/close_hatches()
	for(var/obj/machinery/door/airlock/D as anything in hatches())
		if(!D.density)
			D.airlock_command("secure_close")
		else if(!is_bolted(D))
			D.airlock_command("lock")

/datum/docking_port/proc/hatches_secured()
	for(var/obj/machinery/door/airlock/D as anything in hatches())
		if(!D.density || !is_bolted(D))
			return FALSE
	return TRUE

/// The window's hatch status: list(state = "open"|"closed", lock = "locked"|"unlocked") of its first hatch (closed and locked with none).
/datum/docking_port/proc/hatch_status()
	var/list/doors = hatches()
	var/obj/machinery/door/airlock/D = length(doors) ? doors[1] : null
	if(!D)
		return list("state" = "closed", "lock" = "locked")
	return list("state" = D.density ? "closed" : "open", "lock" = is_bolted(D) ? "locked" : "unlocked")

// ---- the console's commands ----

/// A command from the console's window: TRUE when the port took it.
/datum/docking_port/proc/user_command(command)
	switch(command)
		if("toggle_override")
			set_override_enabled(!override_enabled)
			return TRUE
		if("force_door")
			if(override_enabled)
				if(hatch_status()["state"] == "open")
					close_hatches()
				else
					open_hatches()
			return TRUE
	return FALSE

// ---- reads ----

/datum/docking_port/proc/docked()
	return dock_state == DOCK_DOCKED

/datum/docking_port/proc/undocked()
	return dock_state == DOCK_UNDOCKED

/// Safely undocked: the shuttle can leave.
/datum/docking_port/proc/can_launch()
	return undocked()

/datum/docking_port/proc/get_docking_status()
	switch(dock_state)
		if(DOCK_UNDOCKED)
			return "undocked"
		if(DOCK_DOCKING)
			return "docking"
		if(DOCK_UNDOCKING)
			return "undocking"
		if(DOCK_DOCKED)
			return "docked"

/datum/docking_port/proc/get_name()
	return display_name ? display_name : "[get_area(console)] ([console?.x], [console?.y])"

#undef DOCK_UNDOCKED
#undef DOCK_DOCKING
#undef DOCK_UNDOCKING
#undef DOCK_DOCKED

#undef DOCK_MODE_NONE
#undef DOCK_MODE_SERVER
#undef DOCK_MODE_CLIENT
