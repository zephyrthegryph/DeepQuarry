/obj/item/radio/intercom
	listening = 0 //Temporary bandaid fix for comms lag.
	name = "station intercom (General)"
	desc = "Talk through this."
	icon = 'icons/obj/radio.dmi'
	icon_state = "intercom"
	layer = ABOVE_WINDOW_LAYER
	anchored = TRUE
	w_class = ITEMSIZE_LARGE
	canhear_range = 7
	flags = NOBLOODY | WALL_ITEM
	light_color = "#00ff00"
	light_power = 0.25
	blocks_emissive = NONE
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	var/circuit = /obj/item/circuitboard/intercom
	var/number = 0
	var/wiresexposed = FALSE

TYPE_TABLE_DECLARE(/obj/item/radio/intercom, intercom_channel_setup, null)

/obj/item/radio/intercom/Initialize(mapload)
	. = ..()
	var/area/A = get_area(src)
	if(A)
		observe(A, /datum/notice/observer_apc, src, then(PROC_REF(on_observer_apc)))
	update_icon()
	switch(TYPE_TABLE_GET(src, intercom_channel_setup))
		if(/obj/item/radio/intercom/department/medbay)
			internal_channels = GLOB.default_medbay_channels.Copy()
		if(/obj/item/radio/intercom/department/security)
			internal_channels = list(
				num2text(PUB_FREQ) = list(),
				num2text(SEC_I_FREQ) = list(ACCESS_SECURITY)
			)
		if(/obj/item/radio/intercom/entertainment)
			internal_channels = list(
				num2text(PUB_FREQ) = list(),
				num2text(ENT_FREQ) = list()
			)
		if(/obj/item/radio/intercom/syndicate)
			internal_channels[num2text(SYND_FREQ)] = list(ACCESS_SYNDICATE)
		if(/obj/item/radio/intercom/raider)
			internal_channels[num2text(RAID_FREQ)] = list(ACCESS_SYNDICATE)

/obj/item/radio/intercom/proc/on_observer_apc(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	update_icon()

CAPABILITIES(/obj/item/radio/intercom)
	owns_one(nameof(circuit), starts = nameof(circuit))
	// the AI's gestures over its link: ctrl switches the microphone, alt the AI's private channel
	op("remote_microphone", remote(), gesture(GESTURE_CTRL), when(req(/mob/living/silicon/ai, of = ON_ACTOR)), label("Toggle the microphone"),
		wait(0), then(PROC_REF(remote_microphone)))
	op("remote_channel", remote(), gesture(GESTURE_ALT), when(req(/mob/living/silicon/ai, of = ON_ACTOR)), label("Toggle the AI channel"),
		wait(0), then(PROC_REF(remote_channel)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	op("use", inputs(hand(), remote()), label("Use"), then(PROC_REF(interaction_hand)))

/obj/item/radio/intercom/custom
	name = "station intercom (Custom)"
	broadcasting = FALSE
	listening = FALSE

/obj/item/radio/intercom/interrogation
	name = "station intercom (Interrogation)"
	frequency  = 1449
	broadcasting = 1
	listening = 0

/obj/item/radio/intercom/interrogation/observation
	listening = 1
	broadcasting = 0

/obj/item/radio/intercom/private
	name = "station intercom (Private)"
	frequency = AI_FREQ

/obj/item/radio/intercom/specops
	name = "\improper Spec Ops intercom"
	frequency = ERT_FREQ
	subspace_transmission = TRUE
	centComm = TRUE

/obj/item/radio/intercom/department
	canhear_range = 5
	broadcasting = FALSE
	listening = TRUE

/obj/item/radio/intercom/department/medbay
	name = "station intercom (Medbay)"
	icon_state = "medintercom"
	light_color = "#00aaff"
	frequency = MED_I_FREQ

/obj/item/radio/intercom/department/security
	name = "station intercom (Security)"
	icon_state = "secintercom"
	light_color = "#ff0000"
	frequency = SEC_I_FREQ

/obj/item/radio/intercom/entertainment
	name = "entertainment intercom"
	frequency = ENT_FREQ

/obj/item/radio/intercom/science
	name = "station intercom (Science)"
	channels=list("Science")

/obj/item/radio/intercom/omni
	name = "global announcer"
/obj/item/radio/intercom/omni/Initialize(mapload)
	channels = GLOB.radiochannels.Copy()
	return ..()

TYPE_TABLE(/obj/item/radio/intercom/department/medbay, intercom_channel_setup, /obj/item/radio/intercom/department/medbay)

TYPE_TABLE(/obj/item/radio/intercom/department/security, intercom_channel_setup, /obj/item/radio/intercom/department/security)

TYPE_TABLE(/obj/item/radio/intercom/entertainment, intercom_channel_setup, /obj/item/radio/intercom/entertainment)

/obj/item/radio/intercom/syndicate
	name = "illicit intercom"
	desc = "Talk through this. Evilly"
	frequency = SYND_FREQ
	subspace_transmission = TRUE
	syndie = TRUE

TYPE_TABLE(/obj/item/radio/intercom/syndicate, intercom_channel_setup, /obj/item/radio/intercom/syndicate)

/obj/item/radio/intercom/raider
	name = "illicit intercom"
	desc = "Pirate radio, but not in the usual sense of the word."
	frequency = RAID_FREQ
	subspace_transmission = TRUE
	syndie = TRUE

TYPE_TABLE(/obj/item/radio/intercom/raider, intercom_channel_setup, /obj/item/radio/intercom/raider)

/// Old attack_hand, and old attack_ai (the same body).
/obj/item/radio/intercom/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	src.add_fingerprint(user)
	attack_self(user)
	return OP_OK

/obj/item/radio/intercom/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	wiresexposed = !wiresexposed
	to_chat(user, "The wires have been [wiresexposed ? "exposed" : "unexposed"]")
	playsound(src, tool.usesound, 50, TRUE)
	update_icon()
	return OP_OK

/obj/item/radio/intercom/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!wiresexposed)
		return OP_OK
	act_message(user, src, MSG_SELF("You have cut the wires inside %T%."), MSG_OTHERS(span_warning("%U% has cut the wires inside %T%!")))
	playsound(src, tool.usesound, 50, TRUE)
	var/obj/structure/frame/frame = new(loc)
	var/obj/item/circuitboard/board = circuit
	rel_set(frame, nameof(frame.frame_type), frame_type_copy(board.board_type)) // the board owns its frame type; the frame takes a copy
	frame.pixel_x = pixel_x
	frame.pixel_y = pixel_y
	board.forceMove(frame)
	own_move(board, frame, nameof(frame.circuit)) // from the intercom to the frame (CONTAINED there)
	frame.set_dir(dir)
	frame.set_anchored(TRUE)
	frame.state = 2
	frame.update_icon()
	board.atom_deconstruct(TRUE, src)
	replace_with(src, /obj/item/stack/cable_coil, 5)
	return OP_OK

/obj/item/radio/intercom/receive_range(freq, level)
	if (!on)
		return -1
	if(!(0 in level))
		var/turf/position = get_turf(src)
		if(isnull(position) || !(position.z in level))
			return -1
	if (!src.listening)
		return -1
	if(freq in GLOB.antag_frequencies)
		if(!(src.syndie))
			return -1//Prevents broadcast of messages over devices lacking the encryption

	return canhear_range

DECLARE_APPEARANCE_PROC(/obj/item/radio/intercom, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/radio/intercom/appearance_overlays()
	. = list()
	var/area/A = get_area(src)
	on = A?.powered(EQUIP)


	if(!on)
		set_light(0)
		set_light_on(FALSE)
		if(wiresexposed)
			icon_state = "intercom-p_open"
		else
			icon_state = "intercom-p"
	else
		if(wiresexposed)
			icon_state = "intercom_open"
			set_light(0)
			set_light_on(FALSE)
		else
			icon_state = initial(icon_state)
			. += mutable_appearance(icon, "[icon_state]_ov")
			. += emissive_appearance(icon, "[icon_state]_ov")
			set_light(2)
			set_light_on(TRUE)

/obj/item/radio/intercom/proc/remote_microphone(datum/act/op/A)
	var/mob/user = A.actor
	ToggleBroadcast()
	to_chat(user, span_notice("\The [src]'s microphone is now <b>[broadcasting ? "enabled" : "disabled"]</b>."))
	return OP_OK

/obj/item/radio/intercom/proc/remote_channel(datum/act/op/A)
	var/mob/user = A.actor
	. = OP_OK
	if(frequency == AI_FREQ)
		set_frequency(initial(frequency))
		to_chat(user, span_notice("\The [src]'s frequency is now set to [span_green(span_bold("Default"))]."))
	else
		set_frequency(AI_FREQ)
		to_chat(user, span_notice("\The [src]'s frequency is now set to [span_pink(span_bold("AI Private"))]."))
/obj/item/radio/intercom/locked
	var/locked_frequency

/obj/item/radio/intercom/locked/set_frequency(frequency)
	if(frequency == locked_frequency)
		..(locked_frequency)

/obj/item/radio/intercom/locked/list_channels()
	return ""

/obj/item/radio/intercom/locked/ai_private
	name = "\improper AI intercom"
	frequency = AI_FREQ
	broadcasting = TRUE
	listening = TRUE

/obj/item/radio/intercom/locked/confessional
	name = "confessional intercom"
	frequency = LOCKED_COM_FREQ

/obj/item/radio/intercom/locked/entertainment
	name = "entertainment PA"
	frequency = ENT_FREQ
	broadcasting = TRUE
