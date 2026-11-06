/obj/item/integrated_circuit/input/EPv2
	name = "\improper EPv2 circuit"
	desc = "Enables the sending and receiving of messages on the Exonet with the EPv2 protocol."
	extended_desc = "An EPv2 address is a string with the format of XXXX:XXXX:XXXX:XXXX.  Data can be send or received using the \
	second pin on each side, with additonal data reserved for the third pin.  When a message is received, the second activation pin \
	will pulse whatever's connected to it.  Pulsing the first activation pin will send a message.\
	\
	When messaging Communicators, you must set data to send to the string `text` to avoid errors in reception."
	icon_state = "signal"
	complexity = 4
	inputs = list(
		"target EPv2 address"	= IC_PINTYPE_STRING,
		"data to send"			= IC_PINTYPE_STRING,
		"secondary text"		= IC_PINTYPE_STRING
		)
	outputs = list(
		"address received"			= IC_PINTYPE_STRING,
		"data received"				= IC_PINTYPE_STRING,
		"secondary text received"	= IC_PINTYPE_STRING,
		"self address"				= IC_PINTYPE_STRING
		)
	activators = list("send data" = IC_PINTYPE_PULSE_IN, "on data received" = IC_PINTYPE_PULSE_OUT, "on data sent" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 50
	var/datum/exonet_protocol/exonet = null
	var/obj/machinery/exonet_node/node = null

/obj/item/integrated_circuit/input/EPv2/proc/get_connection_to_tcomms()
	if(node && node.on)
		return can_telecomm(src,node)
	return 0

CAPABILITIES(/obj/item/integrated_circuit/input/EPv2)
	setup(PROC_REF(prepare_exonet_address))
	ref_one(nameof(node), /obj/machinery/exonet_node)
	owns_one(nameof(exonet), /datum/exonet_protocol, starts = /datum/exonet_protocol)

/obj/item/integrated_circuit/input/EPv2/proc/prepare_exonet_address()
	exonet.make_address("EPv2_circuit-[ref_token(src)]")
	desc += "<br>This circuit's EPv2 address is: [exonet.address]"
	rel_set(src, nameof(node), get_exonet_node())

/obj/item/integrated_circuit/input/EPv2/do_work()
	var/target_address = get_pin_data(IC_INPUT, 1)
	var/message = get_pin_data(IC_INPUT, 2)
	var/text = get_pin_data(IC_INPUT, 3)
	set_pin_data(IC_OUTPUT, 4, exonet.address)

	var/is_communicator = FALSE // improved communicator support
	for(var/obj/item/communicator/comm in REGISTRY_MEMBERS(REGISTRY_COMMUNICATORS))
		if(comm.exonet && comm.exonet.address == target_address)
			is_communicator = TRUE
			break

	if(target_address && istext(target_address))
		if(!get_connection_to_tcomms())
			set_pin_data(IC_OUTPUT, 1, null)
			set_pin_data(IC_OUTPUT, 2, "Error: Cannot connect to Exonet node.")
			set_pin_data(IC_OUTPUT, 3, "error")

			push_data()
			activate_pin(2)
		else
			if(is_communicator)
				text = message // For communicators, we need to set the text to the message.
				message = "text"
			exonet.send_message(target_address, message, text)
