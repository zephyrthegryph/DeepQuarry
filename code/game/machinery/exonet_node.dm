/obj/machinery/exonet_node
	step_on_power_change = TRUE
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "exonet node"
	desc = null // Gets written in New()
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "exonet"
	idle_power_usage = 2500
	density = TRUE
	on = 1
	var/toggle = 1

	var/allow_external_PDAs = 1
	var/allow_external_communicators = 1
	var/allow_external_newscasters = 1

	var/opened = 0

	var/list/logs // Gets written to by exonet's send_message() function.

	circuit = /obj/item/circuitboard/telecomms/exonet_node

	var/datum/looping_sound/tcomms/soundloop
	var/noisy = TRUE
	/// Until when an EMP keeps the node down (EMP_DISABLE).
	EXPIRY_DECLARE(emp_until)

// Proc: New()
// Parameters: None
// Description: Adds components to the machine for deconstruction.
/obj/machinery/exonet_node/Initialize(mapload)
	own_set(src, "soundloop", new /datum/looping_sound/tcomms(list(src), FALSE))
	if(prob(60)) // 60% chance to change the midloop
		if(prob(40))
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_02.ogg' = 1)
			soundloop.mid_length = 40
		else if(prob(20))
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_03.ogg' = 1)
			soundloop.mid_length = 10
		else
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_04.ogg' = 1)
			soundloop.mid_length = 30
	soundloop.start()
	. = ..()
	default_apply_parts()
	if(mapload)
		desc = "This machine is one of many, many nodes inside [using_map.starsys_name]'s section of the Exonet, connecting the [using_map.station_short] to the rest of the system, at least \
		electronically."


APPEARANCE_TEMPLATE(/obj/machinery/exonet_node, "{initial(icon_state)}{on?:_off}")

// Proc: update_power()
// Parameters: None
// Description: Sets the device on/off and adjusts power draw based on stat and toggle variables.
/obj/machinery/exonet_node/proc/update_power()
	if(toggle)
		if(!operable())
			set_on(0)
			update_idle_power_usage(0)
			soundloop.stop()
			noisy = FALSE
		else
			set_on(1)
			update_idle_power_usage(2500)
	else
		set_on(0)
		update_idle_power_usage(0)
		soundloop.stop()
		noisy = FALSE
	if(!noisy && on)
		soundloop.start()
		noisy = TRUE
	update_icon()

// An EMP shuts off the machine for awhile.  Ion anomalies also pulse it to turn it off.
EMP_DISABLE(/obj/machinery/exonet_node, 300 SECONDS, "emp_until")

/obj/machinery/exonet_node/emp_disable_changed(disabled)
	..()
	update_power()

// Proc: process()
// Parameters: None
// Description: Calls the procs below every tick.
/// Reconciles on/off with power and damage: every power or break change runs one step.
/obj/machinery/exonet_node/machine_step()
	update_power()
	return PROCESS_KILL

// Proc: attack_hand()
// Parameters: 1 (user - the person clicking on the machine)
// Description: Opens the TGUI interface with tgui_interact()
/obj/machinery/exonet_node/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/exonet_open_ui,
	)
	..()

/// Old attack_hand, which never called ..(): no gate.
/datum/interaction/machine_hand/ungated/exonet_open_ui
	id = "exonet_open_ui"
	name = "Use"
	effect = /obj/machinery/exonet_node/proc/interaction_open_ui_impl

/obj/machinery/exonet_node/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

// Proc: tgui_interact()
// Parameters: 2 (user - person interacting with the UI, ui - the UI itself, in a refresh)
// Description: Handles opening the TGUI interface
/obj/machinery/exonet_node/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ExonetNode", src)
		ui.open()

// Proc: tgui_data()
// Parameters: 1 (user - the person using the interface)
// Description: Allows the user to turn the machine on or off, or open or close certain 'ports' for things like external PDA messages, newscasters, etc.
/obj/machinery/exonet_node/tgui_data(mob/user)
	// this is the data which will be sent to the ui
	var/list/data = list()

	data["on"] = toggle ? 1 : 0
	data["allowPDAs"] = allow_external_PDAs
	data["allowCommunicators"] = allow_external_communicators
	data["allowNewscasters"] = allow_external_newscasters
	data["logs"] = (logs || list())

	return data

// Proc: tgui_act()
// Parameters: 2 (standard tgui_act arguments)
// Description: Responds to button presses on the TGUI interface.
/obj/machinery/exonet_node/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("toggle_power")
			. = TRUE
			toggle = !toggle
			update_power()
			if(!toggle)
				var/msg = "[ui.user.client.key] ([ui.user]) has turned [src] off, at [x],[y],[z]."
				message_admins(msg)
				log_game(msg)

		if("toggle_PDA_port")
			. = TRUE
			allow_external_PDAs = !allow_external_PDAs

		if("toggle_communicator_port")
			. = TRUE
			allow_external_communicators = !allow_external_communicators
			if(!allow_external_communicators)
				var/msg = "[ui.user.client.key] ([ui.user]) has turned [src]'s communicator port off, at [x],[y],[z]."
				message_admins(msg)
				log_game(msg)

		if("toggle_newscaster_port")
			. = TRUE
			allow_external_newscasters = !allow_external_newscasters
			if(!allow_external_newscasters)
				var/msg = "[ui.user.client.key] ([ui.user]) has turned [src]'s newscaster port off, at [x],[y],[z]."
				message_admins(msg)
				log_game(msg)

	update_icon()
	add_fingerprint(ui.user)

// Proc: get_exonet_node()
// Parameters: None
// Description: Helper proc to get a reference to an Exonet node.
/proc/get_exonet_node()
	for(var/obj/machinery/exonet_node/E in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(E.on)
			return E

// Proc: write_log()
// Parameters: 4 (origin_address - Where the message is from, target_address - Where the message is going, data_type - Instructions on how to interpet content,
// 		content - The actual message.
// Description: This writes to the logs list, so that people can see what people are doing on the Exonet ingame.  Note that this is not an admin logging function.
// 		Communicators are already logged seperately.
/obj/machinery/exonet_node/proc/write_log(origin_address, target_address, data_type, content)
	var/timestamp = "[stationdate2text()] [stationtime2text()]"
	var/msg = "[timestamp] | FROM [origin_address] TO [target_address] | TYPE: [data_type] | CONTENT: [content]"
	LAZYADD(logs, msg)

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/exonet_node/step_start_condition()
	return TRUE // reconciles on/off with power
