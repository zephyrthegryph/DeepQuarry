/obj/item/tvcamera
	name = "press camera drone"
	desc = "A Ward-Takahashi EyeBuddy media streaming hovercam. Weapon of choice for war correspondents and reality show cameramen."
	icon = 'icons/obj/device.dmi'
	icon_state = "camcorder"
	item_state = "camcorder"
	w_class = ITEMSIZE_LARGE
	slot_flags = SLOT_BELT
	var/channel = "NCS Northern Star News Feed"
	var/obj/machinery/camera/network/thunder/camera
	var/obj/item/radio/radio
	var/showing_name
	/// The camera streams: what the drone shows (its camera's status, which publishes nothing, mirrored here when it is toggled).
	var/streaming = FALSE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE
TRACKED(/obj/item/tvcamera, streaming)

/// Relation view: the atom being broadcast; the feed follows it while set.
/obj/item/tvcamera/var/atom/showing
CAPABILITIES(/obj/item/tvcamera)
	ref_one(nameof(showing))
	every(2 SECONDS, then(PROC_REF(tvcamera_step)), when = nameof(showing))
	owns_one(nameof(camera), starts = /obj/machinery/camera/network/thunder)
	owns_one(nameof(radio), starts = /obj/item/radio)
	op("toggle_video", ui_act(), then(PROC_REF(ui_act_toggle_video)))
	op("toggle_audio", ui_act(), then(PROC_REF(ui_act_toggle_audio)))
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	interface("EyeBuddy", title = "Eye Buddy", state = nameof(GLOB.tgui_default_state))
	op("set_channel", ui_act("set_channel"), then(PROC_REF(ui_act_set_channel)))

DECLARE_REGISTRY(/obj/item/tvcamera, REGISTRY_LISTENING_OBJECTS)

/obj/item/tvcamera/examine()
	. = ..()
	. += "Video feed is [camera.status ? "on" : "off"]"
	. += "Audio feed is [radio.broadcasting ? "on" : "off"]"

/obj/item/tvcamera/Initialize(mapload)
	. = ..()
	camera.c_tag = channel
	camera.status = FALSE
	radio.listening = FALSE
	radio.set_frequency(ENT_FREQ)
	radio.icon = src.icon
	radio.icon_state = src.icon_state

/obj/item/tvcamera/hear_talk(mob/M, list/message_pieces, verb)
	radio.hear_talk(M, message_pieces, verb)
	. = ..()


/obj/item/tvcamera/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	user.set_machine(src)
	show_ui(user)
	return OP_OK

// show_ui body moved to code/modules/tvcamera_panel.dm (structured TGUI).

/obj/item/tvcamera/proc/channel_named(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/nc = A.answer.value
	if(nc)
		channel = nc
		camera.c_tag = channel
		to_chat(user, span_notice("New channel name - '[channel]' is set"))


/obj/item/tvcamera/proc/show_tvs(atom/thing)
	if(showing)
		hide_tvs(showing)

	rel_set(src, nameof(showing), thing)
	showing_name = "[thing]"
	for(var/obj/machinery/computer/security/telescreen/entertainment/ES as anything in REGISTRY_MEMBERS(REGISTRY_ENTERTAINMENT_SCREENS))
		ES.show_thing(thing)

/obj/item/tvcamera/proc/hide_tvs()
	if(!showing)
		return
	for(var/obj/machinery/computer/security/telescreen/entertainment/ES as anything in REGISTRY_MEMBERS(REGISTRY_ENTERTAINMENT_SCREENS))
		ES.maybe_stop_showing(showing)
	rel_clear(src, nameof(showing))
	showing_name = null

/obj/item/tvcamera/Moved(atom/old_loc, direction, forced = FALSE, movetime)
	. = ..()
	if(camera.status && loc != old_loc)
		show_tvs(loc)

/obj/item/tvcamera/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!camera)
		return
	if(camera.status && !isturf(target))
		show_tvs(target)
		act_message(user, src, MSG_SELF(span_info("You aim %T% at [target].")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " aims %T% at [target].")))
		if(user.check_current_machine(src))
			show_ui(user) // refresh the UI

/obj/item/tvcamera/proc/tvcamera_step(datum/act/timer/timer)
	var/atom/A = showing
	if(!A || QDELETED(A))
		show_tvs(loc)

	if(get_dist(get_turf(src), get_turf(A)) > 0) // No realtime updates
		show_tvs(loc)
		update_feed()

/// The look: lit while it streams; the hand or belt that carries it redraws with it (look_redraw_worn()).
/obj/item/tvcamera/draw(datum/look/look)
	..()
	look.state(streaming ? "camcorder_on" : "camcorder")
	look.held_state(streaming ? "camcorder_on" : "camcorder")

/obj/item/tvcamera/proc/update_feed()
	if(camera.status)
		PUBLISH_LEGACY(camera, /datum/notice/movable_attempted_move, null, null)

// Bodycam
// Security Bodycam

/obj/item/clothing/accessory/bodycam
	name = "Body Camera"
	desc = "A small body camera for security personnel. It can be attached to your uniform! Use in hand to configure."
	icon_state = "eshield"
	item_state = "eshield"
	w_class = ITEMSIZE_COST_TINY
	slot_flags = ACCESSORY_SLOT_DECOR
	appearance_flags = RESET_COLOR
	icon = 'icons/obj/weapons.dmi'
	var/channel = "Default Bodycamera Feed"
	var/obj/machinery/camera/network/bodycamera/bcamera
	var/obj/item/radio/bradio
	var/showing_name
	special_handling = TRUE

/// Relation view: the atom being broadcast; the feed follows it while set.
/obj/item/clothing/accessory/bodycam/var/atom/showing

CAPABILITIES(/obj/item/clothing/accessory/bodycam)
	every(2 SECONDS, then(PROC_REF(bodycam_step)), when = nameof(showing))
	owns_one(nameof(bcamera), starts = /obj/machinery/camera/network/bodycamera)
	owns_one(nameof(bradio), starts = /obj/item/radio)
	op("toggle_video", ui_act(), then(PROC_REF(ui_act_toggle_video)))
	op("toggle_audio", ui_act(), then(PROC_REF(ui_act_toggle_audio)))
	interface("EyeBuddy", title = "Eye Buddy", state = nameof(GLOB.tgui_default_state))
	op("set_channel", ui_act("set_channel"), then(PROC_REF(ui_act_set_channel)))

DECLARE_REGISTRY(/obj/item/clothing/accessory/bodycam, REGISTRY_LISTENING_OBJECTS)

/obj/item/clothing/accessory/bodycam/examine()
	. = ..()
	. += "Video feed is [bcamera.status ? "on" : "off"]"
	. += "Audio feed is [bradio.broadcasting ? "on" : "off"]"

/obj/item/clothing/accessory/bodycam/Initialize(mapload)
	. = ..()
	bcamera.c_tag = channel
	bcamera.status = FALSE
	bradio.listening = FALSE
	bradio.set_frequency(BDCM_FREQ)
	bradio.icon = src.icon
	bradio.icon_state = src.icon_state

/obj/item/clothing/accessory/bodycam/hear_talk(mob/M, list/message_pieces, verb)
	bradio.hear_talk(M, message_pieces, verb)
	. = ..()

/obj/item/clothing/accessory/bodycam/proc/configure_bodycam(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	show_bodycam_ui(user)
	return OP_OK

// show_bodycam_ui body moved to code/modules/tvcamera_panel.dm (structured TGUI).

/obj/item/clothing/accessory/bodycam/proc/channel_named(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/nc = sanitize(A.answer.value, MAX_NAME_LEN)
	if(nc)
		channel = nc
		bcamera.c_tag = channel
		to_chat(user, span_notice("New channel name - '[channel]' is set"))


/obj/item/clothing/accessory/bodycam/proc/show_bodycamera_tvs(atom/thing)
	if(showing)
		hide_bodycamera_tvs(showing)

	rel_set(src, nameof(showing), thing)
	showing_name = "[thing]"
	for(var/obj/machinery/computer/security/telescreen/bodycamera/ES as anything in REGISTRY_MEMBERS(REGISTRY_BODYCAMERA_SCREENS))
		ES.show_thing(thing, src)

/obj/item/clothing/accessory/bodycam/proc/hide_bodycamera_tvs()
	if(!showing)
		return
	for(var/obj/machinery/computer/security/telescreen/bodycamera/ES as anything in REGISTRY_MEMBERS(REGISTRY_BODYCAMERA_SCREENS))
		ES.maybe_stop_showing(showing)
	rel_clear(src, nameof(showing))
	showing_name = null

/obj/item/clothing/accessory/bodycam/Moved(atom/old_loc, direction, forced = FALSE, movetime)
	. = ..()
	if(bcamera.status && loc != old_loc)
		show_bodycamera_tvs(loc)

/obj/item/clothing/accessory/bodycam/proc/bodycam_step(datum/act/timer/timer)
	var/atom/A = showing
	if(!A || QDELETED(A))
		show_bodycamera_tvs(loc)

	if(get_dist(get_turf(src), get_turf(A)) > 0) // No realtime updates
		update_feed()

/obj/item/clothing/accessory/bodycam/proc/update_feed()
	if(bcamera.status)
		PUBLISH_LEGACY(bcamera, /datum/notice/movable_attempted_move, null, null)

/obj/item/clothing/accessory/bodycam/draw(datum/look/look)
	..()

//Assembly by roboticist

/// An infrared sensor turns the head into a TV camera assembly.
/obj/item/robot_parts/head/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/assembly/S = A.held
	var/obj/item/TVAssembly/TV = new(user)
	consume(S, user)
	user.put_in_hands(TV)
	to_chat(user, span_notice("You add the infrared sensor to the robot head."))
	consume(src, user)
	return OP_OK

/obj/item/TVAssembly
	name = "\improper TV Camera Assembly"
	desc = "A robotic head with an infrared sensor inside."
	icon = 'icons/obj/robot_parts.dmi'
	icon_state = "head"
	item_state = "head"
	var/buildstep = 0
	w_class = ITEMSIZE_LARGE

TRACKED(/obj/item/TVAssembly, buildstep)

CAPABILITIES(/obj/item/TVAssembly)
	// the old attackby: the construction steps (a camera module or tape recorder must be free to take)
	op("build", item(/obj/item), label("Build"), needs(req(PROC_REF(can_insert_device), because = PROC_REF(insert_device_refusal))), then(PROC_REF(interaction_item)))

/// Requirement: a matching construction ingredient can be taken from where it is.
/obj/item/TVAssembly/proc/can_insert_device(datum/act/op/A)
	return isnull(insert_device_refusal(A))

/obj/item/TVAssembly/proc/insert_device_refusal(datum/act/op/A)
	var/obj/item/held = A.held
	if((buildstep == 0 && istype(held, /obj/item/robot_parts/robot_component/camera)) || (buildstep == 1 && istype(held, /obj/item/taperecorder)))
		return A.actor.release_refusal(held, A.actor)
	return null

/// Old attackby: a construction step machine. Faithfully preserved, including that a
/// successful buildstep 0/1 match still falls through to ..() afterward (no early return there).
/obj/item/TVAssembly/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	switch(buildstep)
		if(0)
			if(istype(W, /obj/item/robot_parts/robot_component/camera))
				var/obj/item/robot_parts/robot_component/camera/CA = W
				if(!consume(CA, user))
					return OP_DECLINE
				to_chat(user, span_notice("You add the camera module to [src]"))
				desc = "This TV camera assembly has a camera module."
				set_buildstep(buildstep + 1)
		if(1)
			if(istype(W, /obj/item/taperecorder))
				var/obj/item/taperecorder/T = W
				if(!consume(T, user))
					return OP_DECLINE
				set_buildstep(buildstep + 1)
				to_chat(user, span_notice("You add the tape recorder to [src]"))
		if(2)
			if(istype(W, /obj/item/stack/cable_coil))
				var/obj/item/stack/cable_coil/C = W
				if(C.get_amount() < 6)
					to_chat(user, span_notice("You need six cable coils to wire the devices."))
					return OP_DECLINE
				C.use(6)
				set_buildstep(buildstep + 1)
				to_chat(user, span_notice("You wire the assembly"))
				desc = "This TV camera assembly has wires sticking out"
				return OP_OK
		if(3)
			if(W.has_tool_quality(TOOL_WIRECUTTER))
				to_chat(user, span_notice(" You trim the wires."))
				set_buildstep(buildstep + 1)
				desc = "This TV camera assembly needs casing."
				return OP_OK
		if(4)
			if(istype(W, /obj/item/stack/material/steel))
				var/obj/item/stack/material/steel/S = W
				set_buildstep(buildstep + 1)
				S.use(1)
				to_chat(user, span_notice("You encase the assembly in a Ward-Takeshi casing."))
				var/turf/T = get_turf(src)
				new /obj/item/tvcamera(T)
				consume(src, user)
				return OP_OK

	return OP_DECLINE

/obj/item/tvcamera/proc/camera_set_channel(mob/user)
	open_request(src, /datum/prompt/text, PROC_REF(channel_named), answerer = user, title = "Select new channel name", question = "Channel name", default = channel, max_len = MAX_NAME_LEN, usable_state = "physical", name_text = TRUE, timeout = 0)

/obj/item/tvcamera/proc/camera_toggle_video(mob/user)
	camera.set_status(!camera.status)
	set_streaming(camera.status)
	if(camera.status)
		to_chat(user,span_notice("Video streaming activated. Broadcasting on channel '[channel]'"))
		show_tvs(loc)
	else
		to_chat(user,span_notice("Video streaming deactivated."))
		hide_tvs()
		for(var/obj/machinery/computer/security/telescreen/entertainment/ES as anything in REGISTRY_MEMBERS(REGISTRY_ENTERTAINMENT_SCREENS))
			ES.stop_showing()

/obj/item/tvcamera/proc/camera_toggle_audio(mob/user)
	radio.ToggleBroadcast()
	if(radio.broadcasting)
		to_chat(user,span_notice("Audio streaming activated. Broadcasting on frequency [format_frequency(radio.frequency)]."))
	else
		to_chat(user,span_notice("Audio streaming deactivated."))

/obj/item/clothing/accessory/bodycam/proc/camera_set_channel(mob/user)
	open_request(src, /datum/prompt/text, PROC_REF(channel_named), answerer = user, title = "Select new channel name", question = "Channel name", default = channel, max_len = MAX_NAME_LEN, usable_state = "physical", name_text = TRUE, timeout = 0)

/obj/item/clothing/accessory/bodycam/proc/camera_toggle_video(mob/user)
	bcamera.set_status(!bcamera.status)
	var/turf/here = get_turf(user)
	if(bcamera.status)
		to_chat(user,span_notice("Video streaming activated. Broadcasting on channel '[channel]'"))
		if(here)
			act_message(user, here, others = span_notice("%U% turns on their body camera."))
		show_bodycamera_tvs(loc)
	else
		to_chat(user,span_notice("Video streaming deactivated."))
		if(here)
			act_message(user, here, others = span_warning("%U% turns off their body camera!"))
		hide_bodycamera_tvs()
		for(var/obj/machinery/computer/security/telescreen/bodycamera/ES as anything in REGISTRY_MEMBERS(REGISTRY_BODYCAMERA_SCREENS))
			ES.stop_showing()

/obj/item/clothing/accessory/bodycam/proc/camera_toggle_audio(mob/user)
	bradio.ToggleBroadcast()
	if(bradio.broadcasting)
		to_chat(user,span_notice("Audio streaming activated. Broadcasting on frequency [format_frequency(bradio.frequency)]."))
	else
		to_chat(user,span_notice("Audio streaming deactivated."))
