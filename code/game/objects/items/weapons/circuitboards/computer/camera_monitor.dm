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

/obj/item/circuitboard/security/Initialize(mapload)
	. = ..()
	network = using_map.station_networks

/obj/item/circuitboard/security/tv
	name = T_BOARD("security camera monitor - television")
	build_path = /obj/machinery/computer/security/wooden_tv
	hidden = TRUE

/obj/item/circuitboard/security/engineering
	name = T_BOARD("engineering camera monitor")
	build_path = /obj/machinery/computer/security/engineering
	req_access = list()

/obj/item/circuitboard/security/engineering/Initialize(mapload)
	. = ..()
	network = GLOB.engineering_networks

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

/obj/item/circuitboard/security/telescreen/entertainment/Initialize(mapload)
	. = ..()
	network = list(NETWORK_THUNDER)

MATERIAL_MIX(/obj/item/circuitboard/security/telescreen/bodycamera, list(MAT_STEEL = 50, MAT_GLASS = 50))
// Bodycam
/obj/item/circuitboard/security/telescreen/bodycamera
	name = T_BOARD("security bodycamera monitor")
	build_path = /obj/machinery/computer/security/telescreen/bodycamera
	board_type = new /datum/frame/frame_types/display

/obj/item/circuitboard/security/telescreen/bodycamera/Initialize(mapload)
	. = ..()
	network = list(NETWORK_BODYCAM)

/obj/item/circuitboard/security/construct(obj/machinery/computer/security/C)
	if (..(C))
		C.set_network(network.Copy())

/obj/item/circuitboard/security/atom_deconstruct(disassembled = TRUE, obj/machinery/computer/security/C)
	if (..(C))
		network = C.network.Copy()

DECLARE_EMAG(/obj/item/circuitboard/security, PROC_REF(on_emag), null, "Circuit lock is already removed.")

/obj/item/circuitboard/security/mark_emagged()
	emagged = TRUE
/obj/item/circuitboard/security/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	to_chat(user, span_notice("You override the circuit lock and open controls."))
	emagged = 1
	locked = 0
	return 1

DECLARE_INTERACTIONS(/obj/item/circuitboard/security, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/circuitboard/security/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I,/obj/item/card/id))
		if(emagged)
			to_chat(user, span_warning("Circuit lock does not respond."))
			return INTERACTION_HANDLED_PASS
		if(check_access(I))
			locked = !locked
			to_chat(user, span_notice("You [locked ? "" : "un"]lock the circuit controls."))
		else
			to_chat(user, span_warning("Access denied."))
	else if(I.has_tool_quality(TOOL_MULTITOOL))
		if(locked)
			to_chat(user, span_warning("Circuit controls are locked."))
			return INTERACTION_HANDLED_PASS
		var/existing_networks = jointext(network,",")
		open_request(src, /datum/prompt/text, PROC_REF(networks_entered), answerer = user, title = "Multitool-Circuitboard interface", question = "Which networks would you like to connect this camera console circuit to? Separate networks with a comma. No Spaces!\nFor example: SS13,Security,Secret ", default = existing_networks, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return INTERACTION_HANDLED_PASS

/obj/item/circuitboard/security/proc/networks_entered(datum/act/request/A)
	if(!A.answer)
		return
	if(locked)
		return
	var/mob/user = A.request.answerer
	var/input = A.answer.answer_value
	if(!input)
		to_chat(user, "No input found please hang up and try your call again.")
		return
	var/list/tempnetwork = splittext(input, ",")
	tempnetwork = difflist(tempnetwork, GLOB.restricted_camera_networks, 1)
	if(tempnetwork.len < 1)
		to_chat(user, "No network found please hang up and try your call again.")
		return
	network = tempnetwork
	return
