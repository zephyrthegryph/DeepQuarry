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
	blocks_emissive = NONE
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	var/circuit = /obj/item/circuitboard/intercom
	var/number = 0
	var/wiresexposed = FALSE

/obj/item/radio/intercom/Initialize(mapload)
	. = ..()
	var/area/A = get_area(src)
	if(A)
		observe(A, /datum/notice/observer_apc, src, then(PROC_REF(on_observer_apc)))
	set_on(A?.powered(EQUIP))

/obj/item/radio/intercom/proc/on_observer_apc(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/area/A = get_area(src)
	set_on(A?.powered(EQUIP))

CAPABILITIES(/obj/item/radio/intercom)
	configure(light_glow(color = "#00ff00", power = 0.25))
	owns_one(nameof(circuit), starts = nameof(circuit))
	// the AI's gestures over its link: ctrl switches the microphone, alt the AI's private channel
	op("remote_microphone", remote(), gesture(GESTURE_CTRL), when(req_actor_kind(/mob/living/silicon/ai)), label("Toggle the microphone"),
		wait(0), then(PROC_REF(remote_microphone)))
	op("remote_channel", remote(), gesture(GESTURE_ALT), when(req_actor_kind(/mob/living/silicon/ai)), label("Toggle the AI channel"),
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
	frequency = MED_I_FREQ

CAPABILITIES(/obj/item/radio/intercom/department/medbay)
	configure(light_glow(color = "#00aaff"))

/obj/item/radio/intercom/department/security
	name = "station intercom (Security)"
	icon_state = "secintercom"
	frequency = SEC_I_FREQ

CAPABILITIES(/obj/item/radio/intercom/department/security)
	configure(light_glow(color = "#ff0000"))

/obj/item/radio/intercom/entertainment
	name = "entertainment intercom"
	frequency = ENT_FREQ

/obj/item/radio/intercom/science
	name = "station intercom (Science)"
	channels=list("Science")

/obj/item/radio/intercom/omni
	name = "global announcer"

CAPABILITIES(/obj/item/radio/intercom/omni)
	derives(nameof(channels), PROC_REF(all_channels))

/// The global announcer speaks on every channel (derives(), at init).
/obj/item/radio/intercom/omni/proc/all_channels()
	return GLOB.radiochannels.Copy()

/obj/item/radio/intercom/department/medbay/starting_channels()
	return GLOB.default_medbay_channels.Copy()

/obj/item/radio/intercom/department/security/starting_channels()
	return list(
		num2text(PUB_FREQ) = list(),
		num2text(SEC_I_FREQ) = list(ACCESS_SECURITY))

/obj/item/radio/intercom/entertainment/starting_channels()
	return list(
		num2text(PUB_FREQ) = list(),
		num2text(ENT_FREQ) = list())

/obj/item/radio/intercom/syndicate
	name = "illicit intercom"
	desc = "Talk through this. Evilly"
	frequency = SYND_FREQ
	subspace_transmission = TRUE
	syndie = TRUE

/obj/item/radio/intercom/syndicate/starting_channels()
	. = ..()
	.[num2text(SYND_FREQ)] = list(ACCESS_SYNDICATE)

/obj/item/radio/intercom/raider
	name = "illicit intercom"
	desc = "Pirate radio, but not in the usual sense of the word."
	frequency = RAID_FREQ
	subspace_transmission = TRUE
	syndie = TRUE

/obj/item/radio/intercom/raider/starting_channels()
	. = ..()
	.[num2text(RAID_FREQ)] = list(ACCESS_SYNDICATE)

/// Old attack_hand, and old attack_ai (the same body).
/obj/item/radio/intercom/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	src.add_fingerprint(user)
	attack_self(user)
	return OP_OK

/obj/item/radio/intercom/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	set_wiresexposed(!wiresexposed)
	to_chat(user, "The wires have been [wiresexposed ? "exposed" : "unexposed"]")
	playsound(src, sounds_of(tool).use, 50, TRUE)
	return OP_OK

/obj/item/radio/intercom/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!wiresexposed)
		return OP_OK
	act_message(user, src, MSG_SELF("You have cut the wires inside %T%."), MSG_OTHERS(span_warning("%U% has cut the wires inside %T%!")))
	playsound(src, sounds_of(tool).use, 50, TRUE)
	var/obj/structure/frame/frame = new(loc)
	var/obj/item/circuitboard/board = circuit
	rel_set(frame, nameof(frame.frame_type), frame_type_copy(board.board_type)) // the board owns its frame type; the frame takes a copy
	frame.pixel_x = pixel_x
	frame.pixel_y = pixel_y
	board.forceMove(frame)
	own_move(board, frame, nameof(frame.circuit)) // from the intercom to the frame (CONTAINED there)
	frame.set_dir(dir)
	frame.set_anchored(TRUE)
	frame.set_state(2)
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

/obj/item/radio/intercom/draw(datum/look/look)
	..()
	var/stem = initial(icon_state)
	if(!on)
		look.glow(GLOW_OFF)
		look.state(wiresexposed ? "intercom-p_open" : "intercom-p")
	else if(wiresexposed)
		look.state("intercom_open")
		look.glow(GLOW_OFF)
	else
		look.overlay(mutable_appearance(icon, "[stem]_ov"))
		look.overlay(emissive_appearance(icon, "[stem]_ov"))
		look.glow(2, glow_of_type(type).power, glow_of_type(type).color)

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
