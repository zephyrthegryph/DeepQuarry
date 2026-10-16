/obj/machinery/exonet_node
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "exonet node"
	desc = null // Gets written in New()
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "exonet"
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

CAPABILITIES(/obj/machinery/exonet_node)
	configure(examine_text(fluff = "This is one of many nodes that make up the Exonet, which services trillions of devices across space.  This particular node \
	is referred to as a terminal node, servicing the station.<br>\
	<br>\
	In the beginning of humanity's ascend into space, the Exonet didn't exist.  Instead, the Exonet is the evolution to a network called the Interplanetary \
	Internet (sometimes referred to as the InterPlaNet), which was conceived and developed due to the limitations of the terrestrial Internet, mainly because \
	the IP protocol was unsuitable for long range communications in space, due to the massive delays associated with lightspeed being unable to overcome \
	the massive distances between planets in a timely manner.  It was a store-and-forward network of smaller internets, distributed between various nodes, \
	and was designed to be error, fault, and delay tolerant.  The first nodes were put into space around the time when colonization had begun, to service humanity's \
	close holdings, such as Luna and Mars.<br>\
	<br>\
	By 2104, the Interplanetary Internet had coverage within most of Sol, but the network of networks were limited by the speed of light, and due \
	to orbital mechanics, the delay for a request to be processed could vary.  As an example, a direct message from Mars to Earth could take anywhere \
	between three to twenty two minutes to get to Earth, and then the same amount of time to return to Mars.  Coverage was also spotty due to the \
	nature of operating at such vast distances.<br>\
	<br>\
	Fortunately, a method for traveling faster than light was discovered, which could allow data to be transmitted beyond the speed of light, \
	and thus overcome the limitations of the Interplanetary Internet.  One by one, each of the nodes were upgraded to utilize cutting edge \
	(at the time) FTL technologies to rapidly increase response time.<br>\
	<br>\
	Once humanity had send colonists out beyond Sol, to other star systems such as Sirius and Alpha Centauri, they required their own interplanetary \
	internet, so a new protocol had to be created, and another hardware upgrade for the separate interplanetary internets.  The end result allowed \
	communications between Sol and the various exosolar systems, and was dubbed the Exonet.  It remains the most common way for consumers to engage \
	in long range communications across planets and star systems.  Generally, each system has their own Exonet, which is connected to all the other \
	Exonets at the root node(s), and is typically arranged in a tree structure.  The root node(s) are generally government-owned and are very secure \
	and resilient to failure.<br>\
	<br>\
	This node is privately owned and maintained by NanoTrasen, and allows the crew of the station to have access to the Exonet.", antag = "An EMP will disable this device for a short period of time.  A longer downage can be achieved by turning it off, or rigging \
	the APC it uses to turn off remotely, such as with a signaler in the right wire."))
	default_parts()
	configure(uses_power(idle = 2500))
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition), wakes_on = list(STAT_OPERABLE), unpowered = TRUE)
	emp_disable(300 SECONDS)
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(emp_state_changed)))
	op("toggle_power", ui_act("toggle_power"), then(PROC_REF(ui_act_toggle_power)))
	op("toggle_PDA_port", ui_act("toggle_PDA_port"), then(PROC_REF(ui_act_toggle_pda_port)))
	op("toggle_communicator_port", ui_act("toggle_communicator_port"), then(PROC_REF(ui_act_toggle_communicator_port)))
	op("toggle_newscaster_port", ui_act("toggle_newscaster_port"), then(PROC_REF(ui_act_toggle_newscaster_port)))
	owns_one(nameof(soundloop), /datum/looping_sound/tcomms, starts = pick_one(list(/datum/looping_sound/tcomms = 50, /datum/looping_sound/tcomms/two = 30, /datum/looping_sound/tcomms/three = 9, /datum/looping_sound/tcomms/four = 36))) // most hum the first midloop, the rest one of three others
	interface("ExonetNode")
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

// Proc: New()
// Parameters: None
// Description: Adds components to the machine for deconstruction.
/obj/machinery/exonet_node/Initialize(mapload)
	. = ..()
	soundloop.start()
	if(mapload)
		desc = "This machine is one of many, many nodes inside [using_map.starsys_name]'s section of the Exonet, connecting the [using_map.station_short] to the rest of the system, at least \
		electronically."


/// The look (the draw sweep: from its template).
/obj/machinery/exonet_node/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][on ? "" : "_off"]")

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

/// An EMP shuts off the machine for awhile (emp_disable()); ion anomalies also pulse it to turn it off. It reconciles when that changes.
/obj/machinery/exonet_node/proc/emp_state_changed(datum/act/A)
	update_power()

// Proc: process()
// Parameters: None
// Description: Calls the procs below every tick.
/// Reconciles on/off with power and damage: every power or break change runs one step.
/obj/machinery/exonet_node/proc/work_step(datum/act/timer/A)
	update_power()
	return PROCESS_KILL

// Proc: attack_hand()
// Parameters: 1 (user - the person clicking on the machine)
// Description: Opens the TGUI interface with tgui_interact()

/obj/machinery/exonet_node/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

// Proc: tgui_interact()
// Parameters: 2 (user - person interacting with the UI, ui - the UI itself, in a refresh)
// Description: Handles opening the TGUI interface

// Proc: tgui_data()
// Parameters: 1 (user - the person using the interface)
// Description: Allows the user to turn the machine on or off, or open or close certain 'ports' for things like external PDA messages, newscasters, etc.

/obj/machinery/exonet_node/ui_data(datum/act/eval/A)
	// this is the data which will be sent to the ui
	var/list/data = list()

	data["on"] = toggle ? 1 : 0
	data["logs"] = (logs || list())

	data["allowPDAs"] = allow_external_PDAs
	data["allowCommunicators"] = allow_external_communicators
	data["allowNewscasters"] = allow_external_newscasters
	return data

// Proc: tgui_act()
// Parameters: 2 (standard tgui_act arguments)
// Description: Responds to button presses on the TGUI interface.
/obj/machinery/exonet_node/proc/ui_act_toggle_power(datum/act/op/A)
	set_toggle(!toggle)
	update_power()
	if(!toggle)
		var/msg = "[A.actor.client.key] ([A.actor]) has turned [src] off, at [x],[y],[z]."
		message_admins(msg)
		log_game(msg)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/exonet_node/proc/ui_act_toggle_pda_port(datum/act/op/A)
	set_allow_external_PDAs(!allow_external_PDAs)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/exonet_node/proc/ui_act_toggle_communicator_port(datum/act/op/A)
	set_allow_external_communicators(!allow_external_communicators)
	if(!allow_external_communicators)
		var/msg = "[A.actor.client.key] ([A.actor]) has turned [src]'s communicator port off, at [x],[y],[z]."
		message_admins(msg)
		log_game(msg)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/exonet_node/proc/ui_act_toggle_newscaster_port(datum/act/op/A)
	set_allow_external_newscasters(!allow_external_newscasters)
	if(!allow_external_newscasters)
		var/msg = "[A.actor.client.key] ([A.actor]) has turned [src]'s newscaster port off, at [x],[y],[z]."
		message_admins(msg)
		log_game(msg)
	add_fingerprint(A.actor)
	return OP_OK

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
	add_logs(msg)

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/exonet_node/step_start_condition()
	return TRUE // reconciles on/off with power
