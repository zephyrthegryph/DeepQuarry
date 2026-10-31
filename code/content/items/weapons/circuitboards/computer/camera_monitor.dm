#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

/obj/item/circuitboard/security
	name = T_BOARD("security camera monitor")
	build_path = /obj/machinery/computer/security
	req_access = list(ACCESS_SECURITY)
	var/list/network
	var/locked = 1
	var/emagged = 0


MSG_DEF_SELF(camera_board/broken, "Circuit lock does not respond.")
MSG_DEF_SELF(camera_board/denied, "Access denied.")
MSG_DEF_SELF(camera_board/locked, "Circuit controls are locked.")
MSG_DEF_SELF(camera_board/already, "Circuit lock is already removed.")
MSG_DEF_SELF(camera_board/no_input, "No input found please hang up and try your call again.")
MSG_DEF_SELF(camera_board/no_network, "No network found please hang up and try your call again.")
MSG_DEF_SELF(camera_board/emagged, "You override the circuit lock and open controls.")

/// The networks the board is set to: the answer must name at least one network a board may join. A refused answer keeps the prompt open.
/datum/prompt/text/camera_networks

/datum/prompt/text/camera_networks/refusal(given)
	if(!given)
		return "No input found please hang up and try your call again."
	var/list/tempnetwork = difflist(splittext(given, ","), GLOB.restricted_camera_networks, 1)
	if(tempnetwork.len < 1)
		return "No network found please hang up and try your call again."
	return null

CAPABILITIES(/obj/item/circuitboard/security)
	op("lock", item(/obj/item/card/id), needs(req_is(nameof(emagged), FALSE, because = MSG(camera_board/broken)), req_credential_in_hand(list(/obj/item/card/id), because = MSG(camera_board/denied))), label("Lock or unlock circuit controls"), then(PROC_REF(lock_toggled)), passes())
	op("networks", tool(TOOL_MULTITOOL), needs(req_adjacent(), req_is(nameof(locked), FALSE, because = MSG(camera_board/locked))), label("Configure camera networks"), wait(0),
		asks(/datum/prompt/text, keeps = 0, fields = list("timeout" = 0, "question" = "Which networks would you like to connect this camera console circuit to? Separate networks with a comma. No Spaces!\nFor example: SS13,Security,Secret ", "title" = "Multitool-Circuitboard interface", "default" = computed(PROC_REF(networks_default))), step = "networks"),
		needs(req_answer(PROC_REF(networks_refusal), step = "networks")), then(PROC_REF(networks_entered)), passes())
	emag(then(PROC_REF(on_emag)), say = MSG(camera_board/emagged))
	extend("emag.use", needs(req_is(nameof(emagged), FALSE, because = MSG(camera_board/already))))
	extend("emag.subvert", needs(req_is(nameof(emagged), FALSE, because = MSG(camera_board/already))))

/obj/item/circuitboard/security/on_materialize()
	. = ..()
	set_network(using_map.station_networks)

/obj/item/circuitboard/security/tv
	name = T_BOARD("security camera monitor - television")
	build_path = /obj/machinery/computer/security/wooden_tv
	hidden = TRUE

/obj/item/circuitboard/security/engineering
	name = T_BOARD("engineering camera monitor")
	build_path = /obj/machinery/computer/security/engineering
	req_access = list()

/obj/item/circuitboard/security/engineering/on_materialize()
	. = ..()
	set_network(GLOB.engineering_networks)

/obj/item/circuitboard/security/mining
	name = T_BOARD("mining camera monitor")
	build_path = /obj/machinery/computer/security/mining
	network = list(NETWORK_MINE)
	req_access = list()

MATERIAL_MIX(/obj/item/circuitboard/security/telescreen/entertainment, list(MAT_STEEL = 50, MAT_GLASS = 50))
/obj/item/circuitboard/security/telescreen/entertainment
	name = T_BOARD("entertainment camera monitor")
	build_path = /obj/machinery/computer/security/telescreen/entertainment
	board_type = new /datum/frame/frame_types/display

/obj/item/circuitboard/security/telescreen/entertainment/on_materialize()
	. = ..()
	set_network(list(NETWORK_THUNDER))

MATERIAL_MIX(/obj/item/circuitboard/security/telescreen/bodycamera, list(MAT_STEEL = 50, MAT_GLASS = 50))
// Bodycam
/obj/item/circuitboard/security/telescreen/bodycamera
	name = T_BOARD("security bodycamera monitor")
	build_path = /obj/machinery/computer/security/telescreen/bodycamera
	board_type = new /datum/frame/frame_types/display

/obj/item/circuitboard/security/telescreen/bodycamera/on_materialize()
	. = ..()
	set_network(list(NETWORK_BODYCAM))

/obj/item/circuitboard/security/construct(obj/machinery/computer/security/C)
	if (..(C))
		C.set_network(network.Copy())

/obj/item/circuitboard/security/atom_deconstruct(disassembled = TRUE, obj/machinery/computer/security/C)
	if (..(C))
		set_network(C.network.Copy())

/obj/item/circuitboard/security/proc/on_emag(datum/act/op/A)
	set_emagged(TRUE)
	set_locked(FALSE)
	return OP_OK

/obj/item/circuitboard/security/proc/lock_toggled(datum/act/op/A)
	set_locked(!locked)
	to_chat(A.actor, span_notice("You [locked ? "" : "un"]lock the circuit controls."))
	return OP_OK

/obj/item/circuitboard/security/proc/networks_default(datum/act/op/A)
	return jointext(network, ",")

/// The networks an answer names: its comma-separated list without the restricted ones.
/obj/item/circuitboard/security/proc/networks_of(input)
	var/list/tempnetwork = splittext("[input]", ",")
	return difflist(tempnetwork, GLOB.restricted_camera_networks, 1)

/// An answer that names no network is refused with the line the old effect told.
/obj/item/circuitboard/security/proc/networks_refusal(datum/act/op/A)
	var/input = A.step_value("networks")
	if(!input)
		return MSG(camera_board/no_input)
	if(length(networks_of(input)) < 1)
		return MSG(camera_board/no_network)
	return null

/obj/item/circuitboard/security/proc/networks_entered(datum/act/op/A)
	set_network(networks_of(A.step_value("networks")))
	return OP_OK
