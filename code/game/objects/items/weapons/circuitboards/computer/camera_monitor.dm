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

TRACKED(/obj/item/circuitboard/security, network)
TRACKED(/obj/item/circuitboard/security, locked)
TRACKED(/obj/item/circuitboard/security, emagged)

MSG_DEF_SELF(camera_board/broken, "Circuit lock does not respond.")
MSG_DEF_SELF(camera_board/denied, "Access denied.")
MSG_DEF_SELF(camera_board/locked, "Circuit controls are locked.")
MSG_DEF_SELF(camera_board/already, "Circuit lock is already removed.")
MSG_DEF_SELF(camera_board/emagged, "You override the circuit lock and open controls.")

CAPABILITIES(/obj/item/circuitboard/security)
	op("lock", item(/obj/item/card/id), needs(req_is(nameof(emagged), FALSE, because = MSG(camera_board/broken)), req_credential_in_hand(list(/obj/item/card/id), because = MSG(camera_board/denied))), label("Lock or unlock circuit controls"), then(PROC_REF(lock_toggled)), passes())
	op("networks", tool(TOOL_MULTITOOL), needs(req_adjacent(), req_is(nameof(locked), FALSE, because = MSG(camera_board/locked))), label("Configure camera networks"), wait(0),
		asks(/datum/prompt/text, keeps = 0, fields = list("timeout" = 0, "question" = "Which networks would you like to connect this camera console circuit to? Separate networks with a comma. No Spaces!\nFor example: SS13,Security,Secret ", "title" = "Multitool-Circuitboard interface", "default" = computed(PROC_REF(networks_default)))), then(PROC_REF(networks_entered)), passes())
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

/obj/item/circuitboard/security/proc/networks_entered(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/input = R?.value
	if(!input)
		to_chat(A.actor, "No input found please hang up and try your call again.")
		return OP_REFUSED
	var/list/tempnetwork = splittext(input, ",")
	tempnetwork = difflist(tempnetwork, GLOB.restricted_camera_networks, 1)
	if(tempnetwork.len < 1)
		to_chat(A.actor, "No network found please hang up and try your call again.")
		return OP_REFUSED
	set_network(tempnetwork)
	return OP_OK
